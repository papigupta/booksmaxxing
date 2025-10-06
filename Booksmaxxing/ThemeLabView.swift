import SwiftUI

struct ThemeLabView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case bookSearch = "Book Search"
        case presets = "Presets"
        case palettes = "Palettes"

        var id: String { rawValue }
    }
    @Binding var preset: ThemePreset
    @State private var mode: Mode = .bookSearch
    @State private var lastSelectedTitle: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                switch mode {
                case .bookSearch:
                    VStack(spacing: 12) {
                        BookSearchView(
                            title: "Google Books Auto-fill",
                            description: "Prototype auto-complete hooked to Google Books. Suggestions update after three characters.",
                            placeholder: "Start typing a title…",
                            minimumCharacters: 3,
                            selectionHint: "Tap a result to simulate filling the Add Book form.",
                            clearOnSelect: false
                        ) { metadata in
                            lastSelectedTitle = metadata.title
                            print("DEBUG: Experiments selection → \(metadata.title) by \(metadata.authors.first ?? "Unknown")")
                        }

                        if let lastSelectedTitle {
                            Text("Selected: \(lastSelectedTitle)")
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.secondaryText)
                                .padding(.horizontal)
                        }
                    }
                case .presets:
                    PresetsContent(preset: $preset)
                        .applyTheme(preset)
                case .palettes:
                    PaletteLabView()
                }
            }
            .navigationTitle("Experiments")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(preset.preferredColorScheme)
    }
}

private struct PresetsContent: View {
    @Binding var preset: ThemePreset
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme Preset").font(DS.Typography.subheadline).foregroundColor(DS.Colors.primaryText)
                    Picker("Theme Preset", selection: $preset) {
                        ForEach(ThemePreset.allCases) { theme in Text(theme.rawValue).tag(theme) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .dsCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Components Sampler").font(DS.Typography.subheadline).foregroundColor(DS.Colors.primaryText)
                    VStack(spacing: 12) {
                        Button("Primary Action") {}.dsPrimaryButton()
                        Button("Secondary Action") {}.dsSecondaryButton()
                        HStack(spacing: 12) { Button("Small") {}.dsSmallButton(); Button("Tertiary") {}.dsTertiaryButton() }
                    }
                    DSDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Heading / Title").font(DS.Typography.title2).foregroundColor(DS.Colors.primaryText)
                        Text("Body copy — a short paragraph to judge readability under the selected theme. The quick brown fox jumps over the lazy dog.")
                            .font(DS.Typography.body).foregroundColor(DS.Colors.secondaryText).lineSpacing(4)
                    }
                    DSDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Input").font(DS.Typography.captionEmphasized).foregroundColor(DS.Colors.primaryText)
                        TextField("Type here…", text: .constant(""))
                            .dsTextField()
                    }
                }
                .padding()
                .dsCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Palette-aware Primary Button")
                        .font(DS.Typography.subheadline)
                        .foregroundColor(DS.Colors.primaryText)
                    PalettePrimaryButtonSample()
                }
                .padding()
                .dsCard()

                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Card").font(DS.Typography.captionEmphasized)
                            Text("Neutral container for content.").font(DS.Typography.caption).foregroundColor(DS.Colors.secondaryText)
                        }
                        .padding()
                        .dsCard()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Subtle Card").font(DS.Typography.captionEmphasized)
                            Text("Light emphasis background.").font(DS.Typography.caption).foregroundColor(DS.Colors.secondaryText)
                        }
                        .padding()
                        .dsSubtleCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accent Card").font(DS.Typography.captionEmphasized).foregroundColor(DS.Colors.white)
                        Text("High contrast container.").font(DS.Typography.caption).foregroundColor(DS.Colors.gray200)
                    }
                    .padding()
                    .dsAccentCard()
                }
                .padding()

                Spacer(minLength: 12)
            }
            .padding(16)
            .background(DS.Colors.secondaryBackground)
        }
    }
}
