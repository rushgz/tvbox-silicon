import Foundation

/// One match of a regular expression, with captures numbered as a regex literal's are:
/// `match.group(0)` is the whole match and `match.group(1)` the first group.
public struct TextMatch {
    public let text: String
    fileprivate let bounds: [Range<String.Index>]
    fileprivate init(text: String, bounds: [Range<String.Index>]) { self.text = text; self.bounds = bounds }
    public var whole: String { String(text[bounds[0]]) }
    /// The capture at `number` (0 is the whole match), or an empty string when it did not participate.
    public func group(_ number: Int) -> String {
        guard bounds.indices.contains(number) else { return "" }
        return String(text[bounds[number]])
    }
    public subscript(_ number: Int) -> Substring { text[bounds[number]] }
}

public extension StringProtocol where SubSequence == Substring {
    /// The first match, using the same pattern a regex literal would. `$` matches the end even
    /// without a trailing newline, as the literal does.
    func firstMatch(pattern: String) -> TextMatch? { matches(pattern: pattern, firstOnly: true).first }

    /// Every non-overlapping match.
    func matches(pattern: String) -> [TextMatch] { matches(pattern: pattern, firstOnly: false) }

    private func matches(pattern: String, firstOnly: Bool) -> [TextMatch] {
        let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        guard let expression else { return [] }
        let text = String(self)
        let range = NSRange(text.startIndex..., in: text)
        var found: [TextMatch] = []
        expression.enumerateMatches(in: text, range: range) { result, _, stop in
            guard let result else { return }
            let bounds = (0..<result.numberOfRanges).map { index -> Range<String.Index> in
                let span = result.range(at: index)
                guard span.location != NSNotFound, let range = Range(span, in: text) else { return text.endIndex..<text.endIndex }
                return range
            }
            found.append(TextMatch(text: text, bounds: bounds))
            if firstOnly { stop.pointee = true }
        }
        return found
    }
}
