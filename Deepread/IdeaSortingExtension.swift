import Foundation

extension Array where Element == Idea {
    /// Sorts ideas by their numeric ID values (e.g., i1, i2, i10, i11, b1i1, b1i2, b1i10)
    /// This ensures consistent ordering across all views
    func sortedByNumericId() -> [Idea] {
        return self.sorted { idea1, idea2 in
            // Extract the numeric part after the last "i" in the ID
            // Handles formats like "i1", "b1i1", "b5i10", etc.
            let components1 = idea1.id.split(separator: "i")
            let components2 = idea2.id.split(separator: "i")
            
            let num1 = components1.last.flatMap { Int($0) } ?? 0
            let num2 = components2.last.flatMap { Int($0) } ?? 0
            
            return num1 < num2
        }
    }
}

extension Collection where Element == Idea {
    /// Sorts ideas by their numeric ID values (e.g., i1, i2, i10, i11)
    /// This ensures consistent ordering across all views
    func sortedByNumericId() -> [Idea] {
        return Array(self).sortedByNumericId()
    }
}