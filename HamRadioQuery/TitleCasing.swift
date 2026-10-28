import Foundation

/// Title-cases license text the way the web app's "Apply Title Case" option does.
/// Postal abbreviations that should stay uppercase are preserved.
enum TitleCasing {
    private static let smallWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "in", "nor", "of", "on", "or", "the", "to", "via",
    ]

    private static let preserved: Set<String> = ["PO", "RR", "HC", "NE", "NW", "SE", "SW"]

    static func apply(_ value: String) -> String {
        let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return "" }
        return words.enumerated().map { index, word in
            format(word, isEdge: index == 0 || index == words.count - 1)
        }.joined(separator: " ")
    }

    private static func format(_ word: String, isEdge: Bool) -> String {
        let upper = word.uppercased()
        if preserved.contains(upper) {
            return upper
        }
        let cased = titleCaseWord(word)
        if !isEdge, smallWords.contains(cased.lowercased()) {
            return cased.lowercased()
        }
        return cased
    }

    private static func titleCaseWord(_ word: String) -> String {
        var result = ""
        result.reserveCapacity(word.count)
        var capitalizeNext = true
        for character in word {
            if character == "-" || character == "/" || character == "'" || character == "’" {
                result.append(character)
                capitalizeNext = true
                continue
            }
            if character.isLetter {
                let text = String(character)
                result.append(contentsOf: capitalizeNext ? text.uppercased() : text.lowercased())
                capitalizeNext = false
            } else {
                result.append(character)
            }
        }
        return result
    }
}
