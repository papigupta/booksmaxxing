import Foundation

/// Immutable concept wrapper with a sequential ID (`i1`, `i2`, …).
struct Idea: Identifiable, Codable, Hashable {
    let id: String     // e.g. "i1"
    let title: String  // e.g. "Godel's Incompleteness Theorem"
    let description: String  // e.g. "Mathematical systems cannot prove their own consistency."
    let bookTitle: String  // e.g. "Godel, Escher, Bach"
} 