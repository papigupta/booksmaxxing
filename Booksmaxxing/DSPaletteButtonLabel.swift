import SwiftUI

// Consistent icon+text label for the palette-aware primary button
// Usage:
// Button { ... } label: { DSPaletteButtonLabel(icon: "plus", text: "Add a new book") }
struct DSPaletteButtonLabel: View {
    let icon: String?
    let text: String?
    let spacing: CGFloat
    let iconSize: CGFloat

    init(icon: String? = nil, text: String? = nil, spacing: CGFloat = 8, iconSize: CGFloat = 16) {
        self.icon = icon
        self.text = text
        self.spacing = spacing
        self.iconSize = iconSize
    }

    var body: some View {
        HStack(spacing: spacing) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .regular))
            }
            if let text {
                Text(text)
            }
        }
    }
}
