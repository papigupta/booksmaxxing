import SwiftUI
import SwiftData

struct ThemeScheme: Codable {
    struct Role: Codable { let name: String; let tones: [Int:String] }
    let roles: [Role]
}

// Contrast utilities
private func relativeLuminance(_ color: Color) -> Double {
    #if canImport(UIKit)
    let ui = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    #elseif canImport(AppKit)
    let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.white
    let r = ns.redComponent, g = ns.greenComponent, b = ns.blueComponent
    #endif
    func comp(_ c: Double) -> Double {
        let c = c <= 0.03928 ? c/12.92 : pow((c+0.055)/1.055, 2.4)
        return c
    }
    return 0.2126*comp(Double(r)) + 0.7152*comp(Double(g)) + 0.0722*comp(Double(b))
}

func contrastRatio(_ c1: Color, _ c2: Color) -> Double {
    let L1 = relativeLuminance(c1)
    let L2 = relativeLuminance(c2)
    let (light, dark) = (max(L1, L2), min(L1, L2))
    return (light + 0.05) / (dark + 0.05)
}

// Resolve the nearest tone in ladder that meets contrast
private func pickPassingTone(target: Double, ladder: [(Int, Color)], against bg: Color, preferLight: Bool) -> Color {
    // sort ladder by distance from prefered direction
    let sorted = ladder.sorted { a, b in
        return preferLight ? a.0 > b.0 : a.0 < b.0
    }
    for (_, c) in sorted {
        if contrastRatio(c, bg) >= target { return c }
    }
    // if none pass, return the one with max contrast
    return sorted.max(by: { contrastRatio($0.1, bg) < contrastRatio($1.1, bg) })?.1 ?? ladder.first!.1
}

struct ThemeEngine {
    static func generateScheme(from roles: [PaletteRole]) -> ThemeScheme {
        let mapped: [ThemeScheme.Role] = roles.map { role in
            let tones = Dictionary(uniqueKeysWithValues: role.tones.map { ($0.tone, $0.color.toHexString() ?? "#000000") })
            return .init(name: role.name, tones: tones)
        }
        return ThemeScheme(roles: mapped)
    }

    static func resolveTokens(roles: [PaletteRole], mode: ColorScheme) -> ThemeTokens {
        func color(of roleName: String, tone: Int) -> Color {
            guard let role = roles.first(where: { $0.name == roleName }) else { return Color.gray }
            guard let c = role.tones.first(where: { $0.tone == tone })?.color else { return Color.gray }
            return c
        }
        let neutral = roles.first(where: { $0.name == "Neutral" })!

        let isLight = (mode == .light)
        func accentColor(hue: Double, fallback: Color) -> Color {
            let referenceTone = isLight ? color(of: "Primary", tone: 50) : color(of: "Primary", tone: 60)
            if let base = referenceTone.toOKLCH() {
                let lightness = min(max(base.L, 0.35), 0.85)
                let chroma = min(max(base.C * 1.25, 0.12), 0.22)
                return oklchToSRGBClamped(OKLCH(L: lightness, C: chroma, h: hue))
            }
            return fallback
        }
        let bg = isLight ? color(of: "Neutral", tone: 98) : color(of: "Neutral", tone: 8)
        let surface = bg
        let surfaceVariant = isLight ? color(of: "Neutral", tone: 94) : color(of: "Neutral", tone: 14)
        let onSurface = pickPassingTone(target: 4.5, ladder: neutral.tones.map { ($0.tone, $0.color) }, against: bg, preferLight: !isLight)

        // Primary
        let primary = isLight ? color(of: "Primary", tone: 40) : color(of: "Primary", tone: 80)
        let onPrimary = pickPassingTone(target: 4.5, ladder: neutral.tones.map { ($0.tone, $0.color) }, against: primary, preferLight: isLight)
        let primaryContainer = isLight ? color(of: "Primary", tone: 90) : color(of: "Primary", tone: 30)
        let onPrimaryContainer = pickPassingTone(target: 4.5, ladder: neutral.tones.map { ($0.tone, $0.color) }, against: primaryContainer, preferLight: !isLight)

        // Secondary
        let secondary = isLight ? color(of: "Secondary", tone: 40) : color(of: "Secondary", tone: 80)
        let onSecondary = pickPassingTone(target: 4.5, ladder: neutral.tones.map { ($0.tone, $0.color) }, against: secondary, preferLight: isLight)
        let secondaryContainer = isLight ? color(of: "Secondary", tone: 90) : color(of: "Secondary", tone: 30)
        let onSecondaryContainer = pickPassingTone(target: 4.5, ladder: neutral.tones.map { ($0.tone, $0.color) }, against: secondaryContainer, preferLight: !isLight)

        // Tertiary
        let tertiary = isLight ? color(of: "Tertiary", tone: 40) : color(of: "Tertiary", tone: 80)
        let onTertiary = pickPassingTone(target: 4.5, ladder: neutral.tones.map { ($0.tone, $0.color) }, against: tertiary, preferLight: isLight)
        let tertiaryContainer = isLight ? color(of: "Tertiary", tone: 90) : color(of: "Tertiary", tone: 30)
        let onTertiaryContainer = pickPassingTone(target: 4.5, ladder: neutral.tones.map { ($0.tone, $0.color) }, against: tertiaryContainer, preferLight: !isLight)

        // Outlines/Dividers
        let outline = isLight ? color(of: "Neutral Variant", tone: 50) : color(of: "Neutral Variant", tone: 60)
        let divider = isLight ? color(of: "Neutral Variant", tone: 90) : color(of: "Neutral Variant", tone: 20)
        let success = accentColor(hue: 135, fallback: Color.green)
        let error = accentColor(hue: 25, fallback: Color.red)

        return ThemeTokens(
            background: bg,
            surface: surface,
            surfaceVariant: surfaceVariant,
            onSurface: onSurface,
            primary: primary,
            onPrimary: onPrimary,
            primaryContainer: primaryContainer,
            onPrimaryContainer: onPrimaryContainer,
            secondary: secondary,
            onSecondary: onSecondary,
            secondaryContainer: secondaryContainer,
            onSecondaryContainer: onSecondaryContainer,
            tertiary: tertiary,
            onTertiary: onTertiary,
            tertiaryContainer: tertiaryContainer,
            onTertiaryContainer: onTertiaryContainer,
            outline: outline,
            divider: divider,
            success: success,
            error: error
        )
    }
}
