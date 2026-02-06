import Foundation

struct WordToken: Hashable {
    let range: NSRange
    let normalized: String
}

enum WordTokenizer {
    private static let wordRegex = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}']+", options: [])
    private static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by",
        "for", "from", "has", "have", "he", "her", "him", "his",
        "i", "if", "in", "is", "it", "its", "me", "my", "not",
        "of", "on", "or", "our", "ours", "she", "so", "that",
        "the", "their", "them", "they", "this", "to", "us",
        "was", "we", "were", "what", "when", "where", "who",
        "with", "you", "your", "yours"
    ]

    static func tokenize(_ text: String) -> [WordToken] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = wordRegex.matches(in: text, options: [], range: fullRange)
        return matches.map { match in
            let word = nsText.substring(with: match.range)
            return WordToken(range: match.range, normalized: normalize(word))
        }
    }

    static func normalize(_ word: String) -> String {
        word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }

    static func lineRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }
        var ranges: [NSRange] = []
        var index = 0
        while index < nsText.length {
            let range = nsText.lineRange(for: NSRange(location: index, length: 0))
            ranges.append(range)
            index = range.location + range.length
        }
        return ranges
    }

    static func isStopword(_ word: String) -> Bool {
        stopwords.contains(word)
    }

    static func isFuzzyMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.isEmpty || b.isEmpty { return false }
        if a.count < 4 || b.count < 4 { return false }
        if abs(a.count - b.count) > 2 { return false }
        let maxDistance = (max(a.count, b.count) >= 7) ? 2 : 1
        return editDistance(a, b, maxDistance: maxDistance) <= maxDistance
    }

    private static func editDistance(_ a: String, _ b: String, maxDistance: Int) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if abs(aChars.count - bChars.count) > maxDistance { return maxDistance + 1 }
        var previous = Array(0...bChars.count)
        for i in 1...aChars.count {
            var current = Array(repeating: 0, count: bChars.count + 1)
            current[0] = i
            var minInRow = current[0]
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
                if current[j] < minInRow { minInRow = current[j] }
            }
            if minInRow > maxDistance { return maxDistance + 1 }
            previous = current
        }
        return previous.last ?? maxDistance + 1
    }
}
