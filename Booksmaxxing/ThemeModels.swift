import SwiftData
import SwiftUI

@Model
final class BookTheme {
    var id: UUID = UUID()
    // Provide default values to satisfy CloudKit/SwiftData container requirements
    var bookId: UUID = UUID()
    var seedHex: String = ""
    var rolesJSON: Data = Data() // Serialized roles/tones (for debugging and regeneration)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(bookId: UUID, seedHex: String, rolesJSON: Data) {
        self.bookId = bookId
        self.seedHex = seedHex
        self.rolesJSON = rolesJSON
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// Resolved tokens used by UI
struct ThemeTokens {
    // Surfaces
    let background: Color
    let surface: Color
    let surfaceVariant: Color
    let onSurface: Color

    // Primary
    let primary: Color
    let onPrimary: Color
    let primaryContainer: Color
    let onPrimaryContainer: Color

    // Secondary
    let secondary: Color
    let onSecondary: Color
    let secondaryContainer: Color
    let onSecondaryContainer: Color

    // Tertiary
    let tertiary: Color
    let onTertiary: Color
    let tertiaryContainer: Color
    let onTertiaryContainer: Color

    // Outlines/Dividers
    let outline: Color
    let divider: Color

    // Semantic accents
    let success: Color
    let error: Color
}
