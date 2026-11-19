import Foundation

struct ApplicationSearcher: Sendable {
    private enum Rank: Int {
        case exact, prefix, substring, wordPrefix, fuzzy
    }

    private typealias Score = (tier: Int, penalty: Int, position: Int, remainder: Int)

    private struct SearchText: Sendable {
        private static let locale = Locale(identifier: "en_US_POSIX")

        let words: [Substring]
        let phrase: String
        let compact: String

        init(_ text: String) {
            let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Self.locale)
                .precomposedStringWithCanonicalMapping
            words = folded.split { $0.isWhitespace || $0.isPunctuation }
            phrase = words.joined(separator: " ")
            compact = words.count > 1 ? words.joined() : phrase
        }
    }

    private struct Entry: Sendable {
        let application: ApplicationItem
        let name: SearchText
        let letters: [Character]
        let initials: String

        init(_ application: ApplicationItem) {
            self.application = application
            name = SearchText(application.name)
            letters = Array(name.compact)
            initials = String(name.words.compactMap(\.first))
        }
    }

    private let entries: [Entry]

    var isEmpty: Bool { entries.isEmpty }

    init(items: [ApplicationItem]) {
        entries = items.map(Entry.init).sorted { lhs, rhs in
            if lhs.name.phrase != rhs.name.phrase { return lhs.name.phrase < rhs.name.phrase }
            if lhs.application.name != rhs.application.name { return lhs.application.name < rhs.application.name }
            return lhs.application.url.path.utf8.lexicographicallyPrecedes(rhs.application.url.path.utf8)
        }
    }

    func search(_ text: String, limit: Int = 7) -> [ApplicationItem] {
        guard limit > 0, !entries.isEmpty else { return [] }
        let query = SearchText(text)
        guard !query.compact.isEmpty else { return entries.prefix(limit).map(\.application) }

        let letters = Array(query.compact)
        var best: [(score: Score, index: Int)] = []
        best.reserveCapacity(min(limit, entries.count))

        // The index already provides tie-breaking order. Keep only the requested number of matches.
        for (index, entry) in entries.enumerated() {
            guard let score = Self.score(for: query, letters: letters, in: entry) else { continue }
            if best.count == limit, let last = best.last, score >= last.score { continue }

            let insertion = best.firstIndex { score < $0.score } ?? best.endIndex
            if best.count == limit { best.removeLast() }
            best.insert((score, index), at: insertion)
        }

        return best.map { entries[$0.index].application }
    }

    private static func score(for query: SearchText, letters: [Character], in entry: Entry) -> Score? {
        let remaining = entry.letters.count - letters.count
        guard remaining >= 0 else { return nil }

        let name = entry.name
        if name.phrase == query.phrase {
            return (Rank.exact.rawValue, 0, 0, 0)
        }
        if name.phrase.hasPrefix(query.phrase) || name.compact.hasPrefix(query.compact) {
            return (Rank.prefix.rawValue, 0, 0, remaining)
        }
        if let range = name.phrase.range(of: query.phrase, options: .literal) {
            let startsWord = name.phrase[..<range.lowerBound].last == " "
            let position = name.phrase.distance(from: name.phrase.startIndex, to: range.lowerBound)
            return (Rank.substring.rawValue, startsWord ? 0 : 1, position, remaining)
        }
        if name.phrase != name.compact || query.phrase != query.compact,
           let range = name.compact.range(of: query.compact, options: .literal) {
            let position = name.compact.distance(from: name.compact.startIndex, to: range.lowerBound)
            return (Rank.substring.rawValue, 2, position, remaining)
        }
        if entry.initials.hasPrefix(query.compact) {
            return (Rank.wordPrefix.rawValue, entry.initials.count - letters.count, 0, remaining)
        }
        if query.words.count > 1, let match = orderedWordPrefixes(query.words, in: name.words) {
            return (Rank.wordPrefix.rawValue, match.gaps, match.start, remaining)
        }
        if let match = subsequence(letters, in: entry.letters) {
            return (Rank.fuzzy.rawValue, match.gaps, match.start, remaining)
        }
        return nil
    }

    private static func orderedWordPrefixes(_ query: [Substring], in words: [Substring]) -> (gaps: Int, start: Int)? {
        guard query.count <= words.count else { return nil }
        var matched = 0
        var start = 0
        for (position, word) in words.enumerated() where word.hasPrefix(query[matched]) {
            if matched == 0 { start = position }
            matched += 1
            if matched == query.count {
                return (position - start + 1 - matched, start)
            }
        }
        return nil
    }

    private static func subsequence(_ query: [Character], in letters: [Character]) -> (gaps: Int, start: Int)? {
        var matched = 0
        var start = 0
        for (position, letter) in letters.enumerated() where letter == query[matched] {
            if matched == 0 { start = position }
            matched += 1
            if matched == query.count {
                return (position - start + 1 - matched, start)
            }
        }
        return nil
    }
}
