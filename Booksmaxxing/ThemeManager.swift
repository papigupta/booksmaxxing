import SwiftUI
import SwiftData

@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var tokensLight: ThemeTokens = ThemeTokens(
        background: DS.Colors.primaryBackground,
        surface: DS.Colors.primaryBackground,
        surfaceVariant: DS.Colors.secondaryBackground,
        onSurface: DS.Colors.primaryText,
        primary: DS.Colors.black,
        onPrimary: DS.Colors.white,
        primaryContainer: DS.Colors.gray100,
        onPrimaryContainer: DS.Colors.primaryText,
        secondary: DS.Colors.gray800,
        onSecondary: DS.Colors.white,
        secondaryContainer: DS.Colors.gray100,
        onSecondaryContainer: DS.Colors.primaryText,
        tertiary: DS.Colors.gray700,
        onTertiary: DS.Colors.white,
        tertiaryContainer: DS.Colors.gray100,
        onTertiaryContainer: DS.Colors.primaryText,
        outline: DS.Colors.subtleBorder,
        divider: DS.Colors.divider,
        success: Color.green,
        error: DS.Colors.destructive
    )

    @Published private(set) var tokensDark: ThemeTokens? = nil
    @Published private(set) var activeRoles: [PaletteRole] = PaletteGenerator.generateMonochromeRoles()
    @Published private(set) var activeSeedHexes: [String] = []
    @Published private(set) var usingBookPalette: Bool = false

    private var modelContext: ModelContext?
    func attachModelContext(_ ctx: ModelContext) { self.modelContext = ctx }

    func currentTokens(for scheme: ColorScheme) -> ThemeTokens {
        if scheme == .dark, let d = tokensDark { return d }
        return tokensLight
    }

    func activateTheme(for book: Book) async {
        guard let mc = modelContext else { return }
        // Try fetch existing (fetch all and filter to avoid predicate compile constraints)
        let descriptor = FetchDescriptor<BookTheme>()
        if let existing = try? mc.fetch(descriptor).first(where: { $0.bookId == book.id }) {
            if let roles = try? JSONDecoder().decode([PaletteRoleDTO].self, from: existing.rolesJSON) {
                let rolesModels = roles.map { $0.model }
                applyRoles(rolesModels, seeds: nil)
                activeSeedHexes = existing.seedHex.isEmpty ? [] : [existing.seedHex]
                usingBookPalette = true
                return
            }
        }
        // No existing: attempt to download cover and compute
        guard let urlStr = (book.coverImageUrl ?? book.thumbnailUrl), let url = URL(string: urlStr) else { return }

        // Heavy work (network + quantization) off the main actor to avoid UI jank
        let generated: (roleDTOs: [PaletteRoleDTO], seedHexes: [String])? = await Task.detached(priority: .utility) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                #if canImport(UIKit)
                guard let img = UIImage(data: data) else { return nil }
                #elseif canImport(AppKit)
                guard let img = NSImage(data: data) else { return nil }
                #endif
                guard let cg = ImageSampler.downsampleToCGImage(img, maxDimension: 64) else { return nil }
                let px = ImageSampler.extractRGBAPixels(cg)
                var labs: [LabPoint] = []
                labs.reserveCapacity(px.count/4)
                var i = 0
                while i < px.count { // ignore transparent
                    if px[i+3] > 127 {
                        let r = Double(px[i]) / 255.0
                        let g = Double(px[i+1]) / 255.0
                        let b = Double(px[i+2]) / 255.0
                        let lab = rgbToOKLab(r: r, g: g, b: b)
                        labs.append(LabPoint(L: lab.L, a: lab.a, b: lab.b))
                    }
                    i += 4
                }
                let clusters = KMeansQuantizer.quantize(labPoints: labs, k: 5, maxIterations: 10)
                let seeds = PaletteGenerator.scoreSeeds(clusters)
                let roles = PaletteGenerator.generateRoles(from: seeds)
                let dto: [PaletteRoleDTO] = roles.map { role in
                    let dict = Dictionary(uniqueKeysWithValues: role.tones.map { ($0.tone, $0.color.toHexString() ?? "#000000") })
                    return PaletteRoleDTO(name: role.name, tones: dict)
                }
                let seedHexes = seeds.compactMap { $0.color.toHexString() }
                return (dto, seedHexes)
            } catch {
                print("ThemeManager error (background): \(error)")
                return nil
            }
        }.value

        guard let generated = generated else { return }
        let roles = generated.roleDTOs.map { $0.model }
        applyRoles(roles, seeds: nil)
        activeSeedHexes = generated.seedHexes
        usingBookPalette = true

        // Persist on main actor
        if let data = try? JSONEncoder().encode(generated.roleDTOs) {
            let seedHex = generated.seedHexes.first ?? "#000000"
            let theme = BookTheme(bookId: book.id, seedHex: seedHex, rolesJSON: data)
            mc.insert(theme)
            try? mc.save()
        }
    }

    private func applyRoles(_ roles: [PaletteRole], seeds: [SeedColor]?) {
        let light = ThemeEngine.resolveTokens(roles: roles, mode: .light)
        let dark = ThemeEngine.resolveTokens(roles: roles, mode: .dark)
        self.tokensLight = light
        self.tokensDark = dark
        self.activeRoles = roles
        if let seeds {
            self.activeSeedHexes = seeds.compactMap { $0.color.toHexString() }
        } else {
            self.activeSeedHexes = []
        }
    }

    func seedColor(at index: Int) -> Color? {
        guard index >= 0, index < activeSeedHexes.count else { return nil }
        return Color(hex: activeSeedHexes[index])
    }

    func resetToDefaultPalette() {
        let roles = PaletteGenerator.generateMonochromeRoles()
        applyRoles(roles, seeds: nil)
        usingBookPalette = false
    }

    func resetForNewSession() {
        modelContext = nil
        resetToDefaultPalette()
    }

    func previewRoles(_ roles: [PaletteRole], seeds: [SeedColor]) {
        applyRoles(roles, seeds: seeds)
        usingBookPalette = true
    }
}

// Codable DTO for persistence (PaletteRole isn’t Codable)
private struct PaletteRoleDTO: Codable {
    let name: String
    let tones: [Int: String]
    var model: PaletteRole {
        let arr = tones.map { (tone: $0.key, color: Color(hex: $0.value.replacingOccurrences(of: "#", with: ""))) }
        let sorted = arr.sorted { $0.tone < $1.tone }
        return PaletteRole(name: name, tones: sorted)
    }
}
