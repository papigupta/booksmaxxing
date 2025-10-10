import SwiftUI

// This experiment now references the centralized DS palette button.
// Kept as a playground/sample to visualize the control.
typealias PaletteAwarePrimaryButtonStyle = DSPalettePrimaryButtonStyle

struct PalettePrimaryButtonSample: View {
    var action: () -> Void = {}
    @State private var showCopyButton: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) { showCopyButton.toggle() }
                action()
            }) {
                DSPaletteButtonLabel(icon: "plus", text: "Add a new book")
            }
            .buttonStyle(DSPalettePrimaryButtonStyle())

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
