import SwiftUI
import PhotosUI
import SwiftData

struct PaletteLabView: View {
    // Data
    @Query(sort: \Book.lastAccessed, order: .reverse) private var books: [Book]
    @State private var image: PlatformImage? = nil
    @State private var isLoading = false
    @State private var imageURLString: String = ""
    @State private var clusters: Int = 5
    @State private var seeds: [SeedColor] = []
    @State private var roles: [PaletteRole] = []
    @State private var exportJSON: String = ""
    @State private var selection: PhotosPickerItem? = nil
    @State private var monochromeRoles: [PaletteRole] = ExperimentsPaletteStore.defaultMonochromeRoles
    @State private var monochromeJSON: String = ExperimentsPaletteStore.defaultMonochromeJSON

    enum Source { case currentBook, url, photos }
    @State private var source: Source = .currentBook

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Source selector
                Picker("Source", selection: $source) {
                    Text("Current Book").tag(Source.currentBook)
                    Text("URL").tag(Source.url)
                    Text("Photos").tag(Source.photos)
                }
                .pickerStyle(.segmented)

                if source == .url {
                    HStack(spacing: 8) {
                        TextField("https://...", text: $imageURLString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .dsTextField()
                        Button("Load") { Task { await loadFromURL() } }
                            .dsSmallButton()
                    }
                } else if source == .photos {
                    PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                        Label("Pick Photo", systemImage: "photo")
                    }
                    .onChange(of: selection) { _, new in
                        if let item = new { Task { await loadFromPhotos(item) } }
                    }
                } else {
                    Button("Use Current Book Cover") { Task { await loadFromCurrentBook() } }
                        .dsSmallButton()
                }

                if let img = image {
                    #if canImport(UIKit)
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 220).cornerRadius(8)
                    #elseif canImport(AppKit)
                    Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 220).cornerRadius(8)
                    #endif
                } else if isLoading {
                    ProgressView().frame(height: 120)
                }

                // Controls
                HStack {
                    Text("k = \(clusters)").font(DS.Typography.caption)
                    Slider(value: Binding(get: { Double(clusters) }, set: { clusters = Int($0) }), in: 3...7, step: 1)
                }

                HStack(spacing: 12) {
                    Button("Extract Palette") { extractPalette() }
                        .dsSecondaryButton()
                    Button("Copy JSON") { copyJSON() }
                        .dsSmallButton()
                        .disabled(exportJSON.isEmpty)
                }

                if !seeds.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seeds").font(DS.Typography.subheadline)
                        HStack(spacing: 8) {
                            ForEach(0..<min(seeds.count, 5), id: \.self) { i in
                                let seed = seeds[i]
                                Swatch(color: seed.color, label: seed.color.toHexString() ?? "—")
                            }
                        }
                    }
                }

                ForEach(roles, id: \.name) { role in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(role.name).font(DS.Typography.subheadline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(role.tones, id: \.tone) { tone in
                                    Swatch(color: tone.color, label: "T\(tone.tone)")
                                }
                            }
                        }
                    }
                }

                if !monochromeRoles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Default Monochrome Palette")
                                .font(DS.Typography.subheadline)
                            Spacer()
                            Button("Copy JSON") { copyToPasteboard(monochromeJSON) }
                                .dsSmallButton()
                        }

                        ForEach(monochromeRoles, id: \.name) { role in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(role.name).font(DS.Typography.captionEmphasized)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(role.tones, id: \.tone) { tone in
                                            Swatch(color: tone.color, label: "T\(tone.tone)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 16)
                }
            }
            .padding(16)
        }
        .navigationTitle("Palette Lab")
        .onAppear {
            if image == nil { Task { await loadFromCurrentBook() } }
        }
    }

    // MARK: - Loaders

    private func loadFromCurrentBook() async {
        guard let book = books.first, let urlStr = (book.coverImageUrl ?? book.thumbnailUrl), let url = URL(string: urlStr) else { return }
        await load(url: url)
    }

    private func loadFromURL() async { guard let url = URL(string: imageURLString) else { return }; await load(url: url) }

    private func load(url: URL) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            #if canImport(UIKit)
            if let img = UIImage(data: data) { image = img }
            #elseif canImport(AppKit)
            if let img = NSImage(data: data) { image = img }
            #endif
        } catch {
            print("PaletteLab load error: \(error)")
        }
    }

    private func loadFromPhotos(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                #if canImport(UIKit)
                if let img = UIImage(data: data) { image = img }
                #elseif canImport(AppKit)
                if let img = NSImage(data: data) { image = img }
                #endif
            }
        } catch {
            print("Photos load error: \(error)")
        }
    }

    // MARK: - Extraction pipeline

    private func extractPalette() {
        guard let image = image, let cg = ImageSampler.downsampleToCGImage(image, maxDimension: 64) else { return }
        let pixels = ImageSampler.extractRGBAPixels(cg)
        var labPoints: [LabPoint] = []
        labPoints.reserveCapacity(pixels.count/4)
        var i = 0
        while i < pixels.count {
            let r = Double(pixels[i]) / 255.0
            let g = Double(pixels[i+1]) / 255.0
            let b = Double(pixels[i+2]) / 255.0
            let a = Double(pixels[i+3]) / 255.0
            if a > 0.5 { // ignore transparent
                let lab = rgbToOKLab(r: r, g: g, b: b)
                labPoints.append(LabPoint(L: lab.L, a: lab.a, b: lab.b))
            }
            i += 4
        }

        let clustersRes = KMeansQuantizer.quantize(labPoints: labPoints, k: clusters, maxIterations: 10)
        let seedList = PaletteGenerator.scoreSeeds(clustersRes)
        self.seeds = seedList
        self.roles = PaletteGenerator.generateRoles(from: seedList)
        self.exportJSON = PaletteGenerator.serializeRolesToJSON(self.roles)
    }

    private func copyJSON() {
        copyToPasteboard(exportJSON)
    }

    private func copyToPasteboard(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

private struct Swatch: View {
    let color: Color
    let label: String
    var body: some View {
        VStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 56, height: 40).overlay(
                RoundedRectangle(cornerRadius: 2).stroke(DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.hairline)
            )
            Text(label).font(DS.Typography.micro).foregroundColor(DS.Colors.secondaryText)
                .lineLimit(1).frame(width: 56)
        }
    }
}
