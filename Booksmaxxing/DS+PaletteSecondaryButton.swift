import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Palette-aware secondary button for the design system
// Same behavior as primary (ripple, haptics, text styling), but:
// - No outer shadows
// - Inner shadow treatments are size-halved (line widths, blurs, offsets), colors/opacity unchanged
struct DSPaletteSecondaryButtonStyle: ButtonStyle {
    @EnvironmentObject private var themeManager: ThemeManager
    private static let defaultPalette = PaletteGenerator.generateMonochromeRoles()

    struct Layout {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
    }

    private enum Variant {
        case text(Layout)
        case icon(diameter: CGFloat)
    }

    private let variant: Variant
    private let controlHeight: CGFloat = 36

    init(horizontalPadding: CGFloat = 12, verticalPadding: CGFloat = 4) {
        let layout = Layout(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
        self.variant = .text(layout)
    }

    init(iconDiameter: CGFloat) {
        self.variant = .icon(diameter: iconDiameter)
    }

    func makeBody(configuration: Configuration) -> some View {
        let palette = themeManager.usingBookPalette ? themeManager.activeRoles : Self.defaultPalette
        let colors = Self.resolveColors(palette: palette)
        return makeContent(configuration: configuration, colors: colors)
    }

    @ViewBuilder
    private func makeContent(configuration: Configuration, colors: SecondaryPaletteButtonColors) -> some View {
        switch variant {
        case .text(let layout):
            SecondaryStyledContent(
                configuration: configuration,
                colors: colors,
                layout: layout,
                height: controlHeight,
                isIcon: false
            )
        case .icon:
            let layout = Layout(horizontalPadding: 0, verticalPadding: 0)
            SecondaryStyledContent(
                configuration: configuration,
                colors: colors,
                layout: layout,
                height: controlHeight,
                isIcon: true
            )
        }
    }

    private static func resolveColors(palette: [PaletteRole]) -> SecondaryPaletteButtonColors {
        let background = palette.color(role: .primary, tone: 90) ?? DS.Colors.gray100
        let stroke = palette.color(role: .primary, tone: 80) ?? DS.Colors.gray200
        let bigShadow = palette.color(role: .primary, tone: 80) ?? DS.Colors.gray300 // unused but kept for parity
        let smallShadow = palette.color(role: .primary, tone: 70) ?? DS.Colors.gray400 // unused but kept for parity
        let innerBright = palette.color(role: .primary, tone: 95) ?? DS.Colors.gray100
        let innerDark = palette.color(role: .primary, tone: 70) ?? DS.Colors.gray400
        let text = palette.color(role: .primary, tone: 30) ?? DS.Colors.primaryText

        return SecondaryPaletteButtonColors(
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

// MARK: - Internal Styled Content + Effects (secondary-specific names to avoid clashes)

private struct SecondaryStyledContent: View {
    let configuration: ButtonStyle.Configuration
    let colors: SecondaryPaletteButtonColors
    let layout: DSPaletteSecondaryButtonStyle.Layout
    let height: CGFloat
    let isIcon: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var ripples: [SecondaryRippleItem] = []
    @State private var buttonSize: CGSize = .zero
    @State private var pressProgress: CGFloat = 0

    private let rippleDuration: Double = 0.4
    private let rippleIntensity: Double = 0.125
    private let pressInAnimation: Animation = .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.2)
    private let pressOutAnimation: Animation = .interactiveSpring(response: 0.32, dampingFraction: 0.68, blendDuration: 0.12)
    private let bounceReleaseDelay: Double = 0.1
    private let defaultMinHeight: CGFloat = 36 // unified control height

    var body: some View { content }

    private var content: some View {
        let minHeight: CGFloat = height
        let cornerRadius = height / 2
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return configuration.label
            .font(DS.Typography.fraunces(size: 14, weight: .regular))
            .tracking(DS.Typography.tightTracking(for: 14))
            .foregroundColor(isEnabled ? colors.text : colors.text.opacity(0.45))
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
            .frame(width: isIcon ? height : nil, height: height)
            .background(
                SecondaryButtonBackground(
                    background: colors.background,
                    stroke: colors.stroke,
                    innerBright: colors.innerBright,
                    innerDark: colors.innerDark,
                    pressProgress: pressProgress,
                    cornerRadius: cornerRadius
                )
            )
            .overlay(
                SecondaryRippleLayer(
                    ripples: $ripples,
                    size: effectiveSize,
                    duration: rippleDuration,
                    intensity: rippleIntensity,
                    shape: shape
                )
            )
            .overlay(
                GeometryReader { proxy in
                    Color.clear.preference(key: SecondaryButtonSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(SecondaryButtonSizePreferenceKey.self) { buttonSize = $0 }
            .contentShape(shape)
            .scaleEffect(1.0 - (0.14 * pressProgress))
            .onAppear(perform: prepareSoftHaptic)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    withAnimation(pressInAnimation) { pressProgress = 1.0 }
                    addRipple(at: CGPoint(x: effectiveSize.width / 2, y: effectiveSize.height / 2))
                    triggerSoftHaptic()
                } else {
                    triggerBounceSequence()
                }
            }
    }

    private var effectiveSize: CGSize {
        if buttonSize == .zero {
            if isIcon { return CGSize(width: height, height: height) }
            return CGSize(width: 280, height: height)
        }
        return buttonSize
    }

    private func addRipple(at point: CGPoint) { ripples.append(SecondaryRippleItem(center: point)) }

    private func triggerSoftHaptic() {
        #if canImport(UIKit)
        SecondaryButtonHaptics.shared.fire()
        #endif
    }

    private func prepareSoftHaptic() {
        #if canImport(UIKit)
        SecondaryButtonHaptics.shared.prepare()
        #endif
    }

    private func triggerBounceSequence() {
        if pressProgress < 1.0 {
            withAnimation(pressInAnimation) { pressProgress = 1.0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + bounceReleaseDelay) {
            withAnimation(pressOutAnimation) { pressProgress = 0.0 }
        }
    }
}

private struct SecondaryRippleItem: Identifiable, Equatable { let id = UUID(); let center: CGPoint }

private struct SecondaryRippleLayer<S: Shape>: View {
    @Binding var ripples: [SecondaryRippleItem]
    let size: CGSize
    let duration: Double
    let intensity: Double
    let shape: S
    var body: some View {
        ZStack {
            ForEach(ripples) { ripple in
                SecondarySingleRipple(center: ripple.center, containerSize: size, duration: duration, intensity: intensity) {
                    if let idx = ripples.firstIndex(of: ripple) { ripples.remove(at: idx) }
                }
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

private struct SecondarySingleRipple: View {
    let center: CGPoint
    let containerSize: CGSize
    let duration: Double
    let intensity: Double
    let onComplete: () -> Void
    @State private var scale: CGFloat = 0.01
    @State private var opacity: Double = 1.0
    var body: some View {
        let diameter = hypot(containerSize.width, containerSize.height)
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(intensity),
                        Color.white.opacity(intensity * 0.35),
                        Color.white.opacity(0.0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.55
                )
            )
            .frame(width: diameter, height: diameter)
            .scaleEffect(scale)
            .opacity(opacity)
            .blendMode(.plusLighter)
            .position(center)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: duration)) { scale = 1.2; opacity = 0.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { onComplete() }
            }
    }
}

private struct SecondaryButtonSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct SecondaryPaletteButtonColors {
    let background: Color
    let text: Color
    let stroke: Color
    let bigShadow: Color
    let smallShadow: Color
    let innerBright: Color
    let innerDark: Color
}

private struct SecondaryFixedFrameModifier: ViewModifier {
    let fixedSize: CGFloat?
    func body(content: Content) -> some View {
        if let fixedSize { content.frame(width: fixedSize, height: fixedSize) } else { content }
    }
}

#if canImport(UIKit)
private final class SecondaryButtonHaptics {
    static let shared = SecondaryButtonHaptics()
    private let impactGenerator: UIImpactFeedbackGenerator
    private init() { impactGenerator = UIImpactFeedbackGenerator(style: .soft); impactGenerator.prepare() }
    func prepare() { impactGenerator.prepare() }
    func fire() { impactGenerator.impactOccurred(intensity: 1.0); impactGenerator.prepare() }
}
#endif

private struct SecondaryButtonBackground: View {
    let background: Color
    let stroke: Color
    let innerBright: Color
    let innerDark: Color
    let pressProgress: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(background)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1.0)
            )
            // No outer shadows for secondary
            .overlay(innerBrightOverlay)
            .overlay(innerDarkOverlay)
    }

    // Halved sizes compared to primary's inner bright overlay
    private var innerBrightOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.95), innerBright.opacity(0.35), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75 // 1.5 -> 0.75
            )
            .blur(radius: 1) // 2 -> 1
            .offset(x: 1.5, y: 2) // (3,4) -> (1.5,2)
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

    // Halved sizes compared to primary's inner dark overlay
    private var innerDarkOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [.clear, innerDark.opacity(0.6), innerDark.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.0 // 2.0 -> 1.0
            )
            .blur(radius: 1.5) // 3 -> 1.5
            .offset(x: -1, y: -1.5) // (-2,-3) -> (-1,-1.5)
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

// MARK: - Design System Extensions (Secondary)

extension View {
    func dsPaletteSecondaryButton(horizontalPadding: CGFloat = 12, verticalPadding: CGFloat = 4) -> some View {
        self.buttonStyle(DSPaletteSecondaryButtonStyle(horizontalPadding: horizontalPadding, verticalPadding: verticalPadding))
    }

    func dsPaletteSecondaryIconButton(diameter: CGFloat) -> some View {
        self.buttonStyle(DSPaletteSecondaryButtonStyle(iconDiameter: diameter))
    }
}
