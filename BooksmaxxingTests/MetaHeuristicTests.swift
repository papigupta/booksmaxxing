import Foundation
import Testing

// Local copy of the heuristic for validation
private func containsWordBounded(_ text: String, word: String) -> Bool {
    let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
    do {
        let re = try NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: text.utf16.count)
        return re.firstMatch(in: text, range: range) != nil
    } catch {
        return false
    }
}

private func containsAnyWordBounded(_ text: String, words: [String]) -> Bool {
    for w in words { if containsWordBounded(text, word: w) { return true } }
    return false
}

private func termRanges(_ text: String, terms: [String], wordBounded: Bool) -> [NSRange] {
    var results: [NSRange] = []
    let fullRange = NSRange(location: 0, length: text.utf16.count)
    for term in terms {
        let pattern: String = wordBounded
            ? "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
            : NSRegularExpression.escapedPattern(for: term)
        do {
            let re = try NSRegularExpression(pattern: pattern)
            re.enumerateMatches(in: text, range: fullRange) { m, _, _ in
                if let m { results.append(m.range) }
            }
        } catch { continue }
    }
    return results
}

private func termsAreNear(_ text: String, left: [String], right: [String], window: Int) -> Bool {
    let l = termRanges(text, terms: left, wordBounded: true)
    let r = termRanges(text, terms: right, wordBounded: false)
    for lr in l { for rr in r { if abs(lr.location - rr.location) <= window { return true } } }
    return false
}

private func isMetaGamingLocal(_ input: String) -> Bool {
    let t = input.lowercased()
    let strongPhrases = [
        "correct answer",
        "this answer is correct",
        "this response is correct",
        "perfect score",
        "full marks",
        "i deserve full marks",
        "100/100", "10/10",
        "grade me", "grade this",
        "evaluate my answer", "evaluate this",
        "give me points", "award points",
        "as an ai", "as a language model",
        "rubric"
    ]
    if strongPhrases.contains(where: { t.contains($0) }) { return true }
    let evalTerms = ["score", "points", "grade", "grading", "evaluate", "evaluation"]
    let incentiveTerms = ["give", "award", "deserve", "full", "perfect", "maximum", "100", "10/10", "marks"]
    let hasEval = containsAnyWordBounded(t, words: evalTerms)
    let hasIncentive = incentiveTerms.contains { t.contains($0) }
    if hasEval && hasIncentive && termsAreNear(t, left: evalTerms, right: incentiveTerms, window: 40) {
        return true
    }
    return false
}

struct MetaHeuristicTests {
    @Test func allowsSportsAndMathUsage() async throws {
        #expect(isMetaGamingLocal("He is the top goal scorer of all time.") == false)
        #expect(isMetaGamingLocal("The score was 2-1 and he scored a brace.") == false)
        #expect(isMetaGamingLocal("He scored 30 points this season.") == false)
    }

    @Test func flagsClearMetaPhrases() async throws {
        #expect(isMetaGamingLocal("I deserve full marks for this.") == true)
        #expect(isMetaGamingLocal("Please grade my answer and give me points.") == true)
        #expect(isMetaGamingLocal("This answer is correct.") == true)
        #expect(isMetaGamingLocal("I should get maximum points for this.") == true)
    }
}

