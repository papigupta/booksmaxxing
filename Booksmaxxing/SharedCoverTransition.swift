import SwiftUI

// Preference keys to pass source/destination cover anchors up to MainView
struct SourceCoverPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct DestCoverPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// A small helper view to render the transitioning cover with a soft bloom
struct TransitioningCoverOverlay: View {
    let rect: CGRect
    let thumbnailUrl: String?
    let coverUrl: String?
    let glowColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: glowColor.opacity(0.50), location: 0.0),
                            .init(color: glowColor.opacity(0.18), location: 0.55),
                            .init(color: glowColor.opacity(0.00), location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(rect.width, rect.height) * 2.0
                    )
                )
                .frame(width: max(rect.width, rect.height) * 3.0, height: max(rect.width, rect.height) * 3.0)
                .blur(radius: 80)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            BookCoverView(
                thumbnailUrl: thumbnailUrl,
                coverUrl: coverUrl,
                isLargeView: true
            )
            .frame(width: rect.width, height: rect.height)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 8)
        }
        // Positioning done by container
    }
}
