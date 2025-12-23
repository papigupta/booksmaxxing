import Foundation

enum OptionSanitizer {
    private static let labelOnlySet: Set<String> = [
        "a", "b", "c", "d",
        "1", "2", "3", "4",
        "option a", "option b", "option c", "option d",
        "option 1", "option 2", "option 3", "option 4"
    ]

    private static let labelPrefixPatterns: [NSRegularExpression] = [
        // A., A), A: , A- , (A) prefixes.
        try! NSRegularExpression(pattern: #"^\s*\(?\s*([A-Da-d]|[1-4])\s*\)?\s*[\.\:\-\)]\s*"#),
        // Option A: / Option 1) prefixes.
        try! NSRegularExpression(pattern: #"^\s*(?i:option)\s*([A-Da-d]|[1-4])\s*[\.\:\-\)]\s*"#),
        // Option A <text> prefixes without punctuation.
        try! NSRegularExpression(pattern: #"^\s*(?i:option)\s*([A-Da-d]|[1-4])\s+"#)
    ]

    static func sanitize(_ options: [String]) -> [String] {
        return options.map { sanitizeOption($0) }
    }

    static func firstInvalidReason(in options: [String]) -> String? {
        for option in options {
            let normalized = normalize(option)
            if normalized.isEmpty {
                return "empty option after sanitization"
            }
            if labelOnlySet.contains(normalized) {
                return "label-only option '\(option)'"
            }
        }
        return nil
    }

    private static func sanitizeOption(_ option: String) -> String {
        var output = option.trimmingCharacters(in: .whitespacesAndNewlines)
        var previous = ""
        var passes = 0
        while output != previous && passes < 2 {
            previous = output
            output = stripLeadingLabel(from: output)
            passes += 1
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingLabel(from text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for regex in labelPrefixPatterns {
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let matchRange = Range(match.range, in: text) {
                let stripped = text.replacingCharacters(in: matchRange, with: "")
                return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private static func normalize(_ option: String) -> String {
        return option
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
