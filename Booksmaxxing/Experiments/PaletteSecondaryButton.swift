import SwiftUI

struct PaletteSecondaryButtonSample: View {
    var action: () -> Void = {}
    @State private var toggled: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // 1) Icon + Text
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) { toggled.toggle() }
                action()
            }) {
                DSPaletteButtonLabel(icon: "star.fill", text: "Secondary Action", iconSize: 14)
            }
            .dsPaletteSecondaryButton()

            // 2) Text only
            Button(toggled ? "Text Only (On)" : "Text Only") {}
                .dsPaletteSecondaryButton()

            // 3) Icon only
            Button(action: {}) {
                Image(systemName: toggled ? "heart.fill" : "heart.fill")
                    .font(.system(size: 14, weight: .regular))
            }
            .dsPaletteSecondaryIconButton(diameter: 38)
        }
    }
}

#Preview("Palette Secondary Button") {
    PaletteSecondaryButtonSample()
        .padding()
        .environmentObject(ThemeManager())
}
