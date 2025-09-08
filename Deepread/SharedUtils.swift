import Foundation

enum SharedUtils {
    /// Extracts the outermost JSON object substring from a response string.
    /// Falls back to returning the full response if braces are not found.
    static func extractJSONObjectString(_ response: String) -> String {
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}") {
            return String(response[startIndex...endIndex])
        }
        return response
    }
}

