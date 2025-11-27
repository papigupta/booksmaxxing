import SwiftUI

enum PaletteRoleName: String {
    case primary = "Primary"
    case secondary = "Secondary"
    case tertiary = "Tertiary"
    case neutral = "Neutral"
    case neutralVariant = "Neutral Variant"
}

extension Array where Element == PaletteRole {
    func color(role: PaletteRoleName, tone: Int) -> Color? {
        guard let role = first(where: { $0.name == role.rawValue }) else { return nil }
        if let exact = role.tones.first(where: { $0.tone == tone })?.color {
            return exact
        }
        let nearest = role.tones.min(by: { abs($0.tone - tone) < abs($1.tone - tone) })
        return nearest?.color
    }

    /// Shared helper for everyday practice contexts so surfaces look consistent.
    func practiceBackgroundColor(fallback tokens: ThemeTokens) -> Color {
        color(role: .primary, tone: 95)
            ?? color(role: .neutral, tone: 95)
            ?? color(role: .neutralVariant, tone: 95)
            ?? tokens.background
    }
}
