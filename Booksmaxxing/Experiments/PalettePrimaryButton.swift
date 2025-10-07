import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PaletteAwarePrimaryButtonStyle: ButtonStyle {
    @EnvironmentObject private var themeManager: ThemeManager
    private static let defaultPalette = PaletteGenerator.generateMonochromeRoles()

    func makeBody(configuration: Configuration) -> some View {
        let palette = themeManager.usingBookPalette ? themeManager.activeRoles : Self.defaultPalette
        let colors = PaletteAwarePrimaryButtonStyle.resolveColors(palette: palette, themeManager: themeManager)

        return StyledPalettePrimaryButtonContent(configuration: configuration, colors: colors)
    }

    private static func resolveColors(palette: [PaletteRole], themeManager: ThemeManager) -> PaletteButtonColors {
        let background = palette.color(role: .primary, tone: 90) ?? DS.Colors.gray100
        let stroke = palette.color(role: .primary, tone: 80) ?? DS.Colors.gray200
        let bigShadow = palette.color(role: .primary, tone: 80) ?? DS.Colors.gray300
        let smallShadow = palette.color(role: .primary, tone: 70) ?? DS.Colors.gray400
        // Inner shadows (palette-aware):
        // - innerBright should use the brightest primary tone
        // - innerDark should use a darker primary tone for contrast
        let innerBright = palette.color(role: .primary, tone: 95) ?? DS.Colors.gray100
        let innerDark = palette.color(role: .primary, tone: 70) ?? DS.Colors.gray400

        // Text should always be a darker shade of the primary
        // to avoid low contrast on light backgrounds.
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

// MARK: - Pressable styled content with ripple + haptics

private struct StyledPalettePrimaryButtonContent: View {
    let configuration: ButtonStyle.Configuration
    let colors: PaletteButtonColors

    @State private var ripples: [RippleItem] = []
    @State private var buttonSize: CGSize = .zero
    @State private var pressProgress: CGFloat = 0

    private let rippleDuration: Double = 0.4 // shorter, snappier
    private let rippleIntensity: Double = 0.125
    private let pressInAnimation: Animation = .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.2)
    private let pressOutAnimation: Animation = .interactiveSpring(response: 0.32, dampingFraction: 0.68, blendDuration: 0.12)
    private let bounceReleaseDelay: Double = 0.1

    var body: some View {
        configuration.label
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
                    innerDark: colors.innerDark,
                    pressProgress: pressProgress
                )
            )
            // Place ripple above background and label to ensure visibility
            .overlay(
                RippleLayer(ripples: $ripples, size: effectiveSize, duration: rippleDuration, intensity: rippleIntensity)
            )
            // Measure size with overlay to avoid layout quirks
            .overlay(
                GeometryReader { proxy in
                    Color.clear.preference(key: ButtonSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(ButtonSizePreferenceKey.self) { buttonSize = $0 }
            .contentShape(Capsule())
            .scaleEffect(scaleAmount)
            .onAppear(perform: prepareSoftHaptic)
            // Trigger ripple/haptic on press state change (center-based)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    withAnimation(pressInAnimation) { pressProgress = 1.0 }
                    addRipple(at: CGPoint(x: effectiveSize.width/2, y: effectiveSize.height/2))
                    triggerSoftHaptic()
                } else {
                    triggerBounceSequence()
                }
            }
            // Also trigger on a regular tap so quick taps show feedback reliably
            .onTapGesture {
                triggerBounceSequence()
                addRipple(at: CGPoint(x: effectiveSize.width/2, y: effectiveSize.height/2))
                triggerSoftHaptic()
            }
    }

    private var scaleAmount: CGFloat {
        1.0 - (0.14 * pressProgress)
    }

    private var effectiveSize: CGSize {
        if buttonSize == .zero { return CGSize(width: 280, height: 52) }
        return buttonSize
    }

    private func addRipple(at point: CGPoint) {
        ripples.append(RippleItem(center: point))
    }

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
            withAnimation(pressInAnimation) {
                pressProgress = 1.0
            }
        }
        triggerBounceReset()
    }

    private func triggerBounceReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + bounceReleaseDelay) {
            withAnimation(pressOutAnimation) {
                pressProgress = 0.0
            }
        }
    }
}

private struct RippleItem: Identifiable, Equatable {
    let id = UUID()
    let center: CGPoint
}

private struct RippleLayer: View {
    @Binding var ripples: [RippleItem]
    let size: CGSize
    let duration: Double
    let intensity: Double

    var body: some View {
        ZStack {
            ForEach(ripples) { ripple in
                SingleRipple(center: ripple.center, containerSize: size, duration: duration, intensity: intensity) {
                    if let idx = ripples.firstIndex(of: ripple) { ripples.remove(at: idx) }
                }
            }
        }
        .clipShape(Capsule())
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
        // Compute a circle large enough to cover the control's diagonal
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
                withAnimation(.easeInOut(duration: duration)) {
                    scale = 1.2
                    opacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    onComplete()
                }
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

#if canImport(UIKit)
private final class PaletteButtonHaptics {
    static let shared = PaletteButtonHaptics()

    private let impactGenerator: UIImpactFeedbackGenerator

    private init() {
        impactGenerator = UIImpactFeedbackGenerator(style: .soft)
        impactGenerator.prepare()
    }

    func prepare() {
        impactGenerator.prepare()
    }

    func fire() {
        impactGenerator.impactOccurred(intensity: 1.0)
        impactGenerator.prepare()
    }
}
#endif

private struct PalettePrimaryButtonBackground: View {
    let background: Color
    let stroke: Color
    let bigShadow: Color
    let smallShadow: Color
    let innerBright: Color
    let innerDark: Color
    let pressProgress: CGFloat

    var body: some View {
        Capsule()
            .fill(background)
            .overlay(
                Capsule()
                    .strokeBorder(stroke, lineWidth: 2.5)
            )
            .shadow(color: bigShadow.opacity(outerShadowOpacity), radius: outerShadowRadius, x: 0, y: outerShadowOffset)
            .shadow(color: smallShadow.opacity(innerShadowOpacity), radius: innerShadowRadius, x: innerShadowOffset, y: innerShadowOffset)
            .overlay(innerBrightOverlay)
            .overlay(innerDarkOverlay)
    }

    private var outerShadowRadius: CGFloat { interpolated(from: 24, to: 8) }
    private var outerShadowOpacity: Double { interpolated(from: 0.66, to: 0.429) }
    private var outerShadowOffset: CGFloat { interpolated(from: 0, to: 8) }

    private var innerShadowRadius: CGFloat { interpolated(from: 3, to: 1) }
    private var innerShadowOpacity: Double { interpolated(from: 0.2, to: 0.4) }
    private var innerShadowOffset: CGFloat { interpolated(from: 2, to: 1) }

    private var innerBrightOverlay: some View {
        Capsule()
            .stroke(
                // Slightly lighter highlight by leaning toward white
                LinearGradient(
                    colors: [Color.white.opacity(0.95), innerBright.opacity(0.35), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5
            )
            .blur(radius: 2)
            // Matches Figma: X 3, Y 4 (light inner shadow)
            .offset(x: 3, y: 4)
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
                // Slightly thicker stroke to be more pronounced without darkening
                lineWidth: 2.0
            )
            // Reduced blur to sharpen the edge a touch
            .blur(radius: 3)
            // Matches Figma: X -3, Y -4 (dark inner shadow)
            .offset(x: -2, y: -3)
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

    private func interpolated(from start: CGFloat, to end: CGFloat) -> CGFloat {
        start + (end - start) * pressProgress
    }

    private func interpolated(from start: Double, to end: Double) -> Double {
        start + (end - start) * pressProgress
    }
}

struct PalettePrimaryButtonSample: View {
    var action: () -> Void = {}
    @State private var showCopyButton: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) { showCopyButton.toggle() }
                action()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .regular))
                    Text("Add a new book")
                        .font(DS.Typography.fraunces(size: 16, weight: .regular))
                        .tracking(DS.Typography.tightTracking(for: 16))
                }
            }
            .buttonStyle(PaletteAwarePrimaryButtonStyle())

            if showCopyButton {
                Button("Copy Test") {}
                    .dsSmallButton()
            }
        }
    }
}

#Preview("Palette Primary Button") {
    PalettePrimaryButtonSample()
        .padding()
        .environmentObject(ThemeManager())
}
