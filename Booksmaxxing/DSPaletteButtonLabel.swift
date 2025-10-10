import SwiftUI

// Consistent icon+text label for the palette-aware primary button
// Usage:
// Button { ... } label: { DSPaletteButtonLabel(icon: "plus", text: "Add a new book") }
struct DSPaletteButtonLabel: View {
    let icon: String?
    let text: String?
    let spacing: CGFloat

    init(icon: String? = nil, text: String? = nil, spacing: CGFloat = 8) {
        self.icon = icon
        self.text = text
        self.spacing = spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
            }
            if let text {
                Text(text)
            }
        }
    }
}

