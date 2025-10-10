import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Centralized palette-aware primary button for the design system
// Expose via View extensions: `.dsPalettePrimaryButton()` and `.dsPaletteIconButton(diameter:)`
struct DSPalettePrimaryButtonStyle: ButtonStyle {
    @EnvironmentObject private var themeManager: ThemeManager
    private static let defaultPalette = PaletteGenerator.generateMonochromeRoles()

    struct Layout {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let minHeight: CGFloat
    }

    private enum Variant {
        case text(Layout)
        case icon(diameter: CGFloat)
    }

    private let variant: Variant

    init(horizontalPadding: CGFloat = 24, verticalPadding: CGFloat = 16, minHeight: CGFloat = 52) {
        let layout = Layout(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            minHeight: minHeight
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
    private func makeContent(configuration: Configuration, colors: PaletteButtonColors) -> some View {
        switch variant {
        case .text(let layout):
            StyledContent(
                configuration: configuration,
                colors: colors,
                layout: layout,
                fixedSize: nil
            )
        case .icon(let diameter):
            let layout = Layout(horizontalPadding: 0, verticalPadding: 0, minHeight: diameter)
            StyledContent(
                configuration: configuration,
                colors: colors,
                layout: layout,
                fixedSize: diameter
            )
        }
    }

    private static func resolveColors(palette: [PaletteRole]) -> PaletteButtonColors {
        let background = palette.color(role: .primary, tone: 90) ?? DS.Colors.gray100
        let stroke = palette.color(role: .primary, tone: 80) ?? DS.Colors.gray200
        let bigShadow = palette.color(role: .primary, tone: 80) ?? DS.Colors.gray300
        let smallShadow = palette.color(role: .primary, tone: 70) ?? DS.Colors.gray400
        let innerBright = palette.color(role: .primary, tone: 95) ?? DS.Colors.gray100
        let innerDark = palette.color(role: .primary, tone: 70) ?? DS.Colors.gray400
        let text = palette.color(role: .primary, tone: 30) ?? DS.Colors.primaryText

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

// MARK: - Internal Styled Content + Effects

private struct StyledContent: View {
    let configuration: ButtonStyle.Configuration
    let colors: PaletteButtonColors
    let layout: DSPalettePrimaryButtonStyle.Layout
    let fixedSize: CGFloat?

    @Environment(\.isEnabled) private var isEnabled
    @State private var ripples: [RippleItem] = []
    @State private var buttonSize: CGSize = .zero
    @State private var pressProgress: CGFloat = 0

    private let rippleDuration: Double = 0.4
    private let rippleIntensity: Double = 0.125
    private let pressInAnimation: Animation = .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.2)
    private let pressOutAnimation: Animation = .interactiveSpring(response: 0.32, dampingFraction: 0.68, blendDuration: 0.12)
    private let bounceReleaseDelay: Double = 0.1

    var body: some View { content }

    private var content: some View {
        let cornerRadius = layout.minHeight / 2
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return configuration.label
            .font(DS.Typography.fraunces(size: 16, weight: .semibold))
            .tracking(DS.Typography.tightTracking(for: 16))
            .foregroundColor(isEnabled ? colors.text : colors.text.opacity(0.45))
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
            .frame(minHeight: layout.minHeight)
            .modifier(FixedFrameModifier(fixedSize: fixedSize))
            .background(
                ButtonBackground(
                    background: colors.background,
                    stroke: colors.stroke,
                    bigShadow: colors.bigShadow,
                    smallShadow: colors.smallShadow,
                    innerBright: colors.innerBright,
                    innerDark: colors.innerDark,
                    pressProgress: pressProgress,
                    cornerRadius: cornerRadius
                )
            )
            .overlay(
                RippleLayer(
                    ripples: $ripples,
                    size: effectiveSize,
                    duration: rippleDuration,
                    intensity: rippleIntensity,
                    shape: shape
                )
            )
            .overlay(
                GeometryReader { proxy in
                    Color.clear.preference(key: ButtonSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(ButtonSizePreferenceKey.self) { buttonSize = $0 }
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
            .onTapGesture {
                triggerBounceSequence()
                addRipple(at: CGPoint(x: effectiveSize.width / 2, y: effectiveSize.height / 2))
                triggerSoftHaptic()
            }
    }

    private var effectiveSize: CGSize {
        if buttonSize == .zero {
            if let fixedSize { return CGSize(width: fixedSize, height: fixedSize) }
            return CGSize(width: 280, height: layout.minHeight)
        }
        return buttonSize
    }

    private func addRipple(at point: CGPoint) { ripples.append(RippleItem(center: point)) }

    private func triggerSoftHaptic() {
        #if canImport(UIKit)
        PaletteButtonHaptics.shared.fire()
        #endif
    }

    private func prepareSoftHaptic() {
        #if canImport(UIKit)
        PaletteButtonHaptics.shared.prepare()
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

private struct RippleItem: Identifiable, Equatable { let id = UUID(); let center: CGPoint }

private struct RippleLayer<S: Shape>: View {
    @Binding var ripples: [RippleItem]
    let size: CGSize
    let duration: Double
    let intensity: Double
    let shape: S
    var body: some View {
        ZStack {
            ForEach(ripples) { ripple in
                SingleRipple(center: ripple.center, containerSize: size, duration: duration, intensity: intensity) {
                    if let idx = ripples.firstIndex(of: ripple) { ripples.remove(at: idx) }
                }
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

private struct SingleRipple: View {
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

private struct ButtonSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
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

private struct FixedFrameModifier: ViewModifier {
    let fixedSize: CGFloat?
    func body(content: Content) -> some View {
        if let fixedSize { content.frame(width: fixedSize, height: fixedSize) } else { content }
    }
}

#if canImport(UIKit)
private final class PaletteButtonHaptics {
    static let shared = PaletteButtonHaptics()
    private let impactGenerator: UIImpactFeedbackGenerator
    private init() { impactGenerator = UIImpactFeedbackGenerator(style: .soft); impactGenerator.prepare() }
    func prepare() { impactGenerator.prepare() }
    func fire() { impactGenerator.impactOccurred(intensity: 1.0); impactGenerator.prepare() }
}
#endif

private struct ButtonBackground: View {
    let background: Color
    let stroke: Color
    let bigShadow: Color
    let smallShadow: Color
    let innerBright: Color
    let innerDark: Color
    let pressProgress: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(background)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 2.6)
            )
            .shadow(color: bigShadow.opacity(outerShadowOpacity), radius: outerShadowRadius, x: 0, y: outerShadowOffset)
            .shadow(color: smallShadow.opacity(innerShadowOpacity), radius: innerShadowRadius, x: innerShadowOffset, y: innerShadowOffset)
            .overlay(innerBrightOverlay)
            .overlay(innerDarkOverlay)
    }

    private var outerShadowRadius: CGFloat { interpolated(from: 24, to: 8) }
    private var outerShadowOpacity: Double { interpolated(from: 0.60, to: 0.42) }
    private var outerShadowOffset: CGFloat { interpolated(from: 0, to: 8) }
    private var innerShadowRadius: CGFloat { interpolated(from: 3, to: 1) }
    private var innerShadowOpacity: Double { interpolated(from: 0.18, to: 0.36) }
    private var innerShadowOffset: CGFloat { interpolated(from: 2, to: 1) }

    private var innerBrightOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.95), innerBright.opacity(0.35), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5
            )
            .blur(radius: 2)
            .offset(x: 3, y: 4)
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

    private var innerDarkOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [.clear, innerDark.opacity(0.6), innerDark.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2.0
            )
            .blur(radius: 3)
            .offset(x: -2, y: -3)
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

    private func interpolated(from start: CGFloat, to end: CGFloat) -> CGFloat { start + (end - start) * pressProgress }
    private func interpolated(from start: Double, to end: Double) -> Double { start + (end - start) * pressProgress }
}

// MARK: - Design System Extensions

extension View {
    func dsPalettePrimaryButton(horizontalPadding: CGFloat = 24, verticalPadding: CGFloat = 16, minHeight: CGFloat = 52) -> some View {
        self.buttonStyle(DSPalettePrimaryButtonStyle(horizontalPadding: horizontalPadding, verticalPadding: verticalPadding, minHeight: minHeight))
    }

    func dsPaletteIconButton(diameter: CGFloat) -> some View {
        self.buttonStyle(DSPalettePrimaryButtonStyle(iconDiameter: diameter))
    }
}
