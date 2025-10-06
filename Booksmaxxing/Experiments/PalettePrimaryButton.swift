import SwiftUI

struct PaletteAwarePrimaryButtonStyle: ButtonStyle {
    @EnvironmentObject private var themeManager: ThemeManager
    private static let defaultPalette = PaletteGenerator.generateMonochromeRoles()

    func makeBody(configuration: Configuration) -> some View {
        let palette = themeManager.usingBookPalette ? themeManager.activeRoles : Self.defaultPalette
        let colors = PaletteAwarePrimaryButtonStyle.resolveColors(palette: palette, themeManager: themeManager)

        return configuration.label
            .foregroundColor(colors.text)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(minHeight: 52)
            .background(
                PalettePrimaryButtonBackground(
                    background: colors.background,
                    stroke: colors.stroke,
                    bigShadow: colors.bigShadow,
                    smallShadow: colors.smallShadow,
                    innerBright: colors.innerBright,
                    innerDark: colors.innerDark
                )
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(DS.Animation.spring, value: configuration.isPressed)
    }

    private static func resolveColors(palette: [PaletteRole], themeManager: ThemeManager) -> PaletteButtonColors {
        let background = palette.color(role: .primary, tone: 90) ?? DS.Colors.gray100
        let stroke = palette.color(role: .primary, tone: 80) ?? DS.Colors.gray200
        let bigShadow = palette.color(role: .primary, tone: 80) ?? DS.Colors.gray300
        let smallShadow = palette.color(role: .primary, tone: 70) ?? DS.Colors.gray400
        let innerBright = palette.color(role: .neutral, tone: 90) ?? DS.Colors.gray100
        let innerDark = palette.color(role: .tertiary, tone: 70) ?? DS.Colors.gray500

        let seedColor = themeManager.seedColor(at: 2)
        let text = seedColor ?? palette.color(role: .primary, tone: 30) ?? DS.Colors.primaryText

        return PaletteButtonColors(
            background: background,
            text: text,
            stroke: stroke,
            bigShadow: bigShadow,
            smallShadow: smallShadow,
            innerBright: innerBright,
            innerDark: innerDark
        )
    }
}

private struct PaletteButtonColors {
    let background: Color
    let text: Color
    let stroke: Color
    let bigShadow: Color
    let smallShadow: Color
    let innerBright: Color
    let innerDark: Color
}

private struct PalettePrimaryButtonBackground: View {
    let background: Color
    let stroke: Color
    let bigShadow: Color
    let smallShadow: Color
    let innerBright: Color
    let innerDark: Color

    var body: some View {
        Capsule()
            .fill(background)
            .overlay(
                Capsule()
                    .strokeBorder(stroke, lineWidth: 3)
            )
            .shadow(color: bigShadow.opacity(1.0), radius: 24, x: 0, y: 0)
            .shadow(color: smallShadow.opacity(0.2), radius: 3, x: 2, y: 2)
            .overlay(innerBrightOverlay)
            .overlay(innerDarkOverlay)
    }

    private var innerBrightOverlay: some View {
        Capsule()
            .stroke(
                LinearGradient(
                    colors: [innerBright.opacity(0.95), innerBright.opacity(0.3), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5
            )
            .blur(radius: 2)
            .offset(x: -3, y: -4)
            .mask(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .compositingGroup()
    }

    private var innerDarkOverlay: some View {
        Capsule()
            .stroke(
                LinearGradient(
                    colors: [.clear, innerDark.opacity(0.6), innerDark.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5
            )
            .blur(radius: 4)
            .offset(x: 3, y: 4)
            .mask(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .blendMode(.multiply)
            .compositingGroup()
    }
}

struct PalettePrimaryButtonSample: View {
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .regular))
                Text("Add a new book")
                    .font(DS.Typography.fraunces(size: 16, weight: .regular))
                    .tracking(DS.Typography.tightTracking(for: 16))
            }
        }
        .buttonStyle(PaletteAwarePrimaryButtonStyle())
    }
}

#Preview("Palette Primary Button") {
    PalettePrimaryButtonSample()
        .padding()
        .environmentObject(ThemeManager())
}
