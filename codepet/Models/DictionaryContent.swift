import Foundation

struct DictionaryTopic: Identifiable, Hashable {
    let id: String        // slug
    let title: L10n
    let icon: String      // SF Symbol
    /// Brand color that themes this topic across the sidebar, hero banner, and
    /// (as a fallback) any card whose term declares no diagram accent.
    let accent: DiagramAccent
    /// One-line hook shown under the topic title in the hero banner.
    let blurb: L10n
}

struct DictionaryTerm: Identifiable, Hashable {
    let id: String                // slug
    let topicId: String
    let title: L10n

    /// One zero-jargon sentence a 12-year-old understands. Shown on the
    /// collapsed card. Supports inline markdown via `Text(markdown:)`.
    let cardDefinition: L10n
    /// 2–3 sentences expanding the idea, shown when the card is expanded.
    /// Rule: don't use another undefined jargon word without rephrasing/linking.
    let whatItReallyMeans: L10n

    /// A small labeled diagram (replaces the old Lego "analogy"). `nil` →
    /// render the text-only fallback (just `whatItReallyMeans`).
    let diagram: DiagramSpec?

    let codeExample: String?
    let whenToUse: L10n?

    /// Tech-stack tags for project-aware matching. Empty = universal term
    /// (a fundamental that isn't tied to any particular stack).
    let tags: [ProjectTag]
    /// Ids of related terms (rendered as jump chips in a later phase).
    let related: [String]
}

enum DictionaryContent {

    static let topics: [DictionaryTopic] = [
        .init(id: "variables",    title: L10n(vi: "Biến & Kiểu dữ liệu", en: "Variables & Types"), icon: "shippingbox.fill",
              accent: .purple,
              blurb: L10n(vi: "Những viên gạch dữ liệu: hộp, chữ, số, danh sách.",
                          en: "The data building blocks: boxes, text, numbers, lists.")),
        .init(id: "functions",    title: L10n(vi: "Hàm",                 en: "Functions"),         icon: "function",
              accent: .pink,
              blurb: L10n(vi: "Đóng gói các bước thành cái máy có tên, dùng lại mãi.",
                          en: "Bundle steps into named machines you reuse forever.")),
        .init(id: "control-flow", title: L10n(vi: "Luồng điều khiển",    en: "Control Flow"),      icon: "arrow.triangle.branch",
              accent: .blue,
              blurb: L10n(vi: "Cách code quyết định, rẽ nhánh và lặp lại.",
                          en: "How code decides, branches, and repeats.")),
        .init(id: "tools",        title: L10n(vi: "Công cụ",             en: "Tools"),             icon: "wrench.and.screwdriver.fill",
              accent: .gold,
              blurb: L10n(vi: "Git, terminal và bộ đồ nghề quanh việc viết code.",
                          en: "Git, the terminal, and the kit around your code.")),
        .init(id: "web",          title: L10n(vi: "Cơ bản về Web",       en: "Web Basics"),        icon: "globe",
              accent: .teal,
              blurb: L10n(vi: "Trang web ghép lại thế nào: HTML, API, frontend & backend.",
                          en: "How the web fits together: HTML, APIs, frontend & backend.")),
    ]

    /// Look up a topic by id (sidebar selection, hero banner theming).
    static func topic(forId id: String) -> DictionaryTopic? {
        topics.first { $0.id == id }
    }

    /// The brand accent for a topic — used as a card's fallback color when its
    /// term declares no diagram accent. Defaults to purple for safety.
    static func accent(forTopicId id: String) -> DiagramAccent {
        topic(forId: id)?.accent ?? .purple
    }

    /// All terms, assembled from per-topic arrays. Splitting the content across
    /// extension files keeps any single array literal small enough that Swift's
    /// type-checker stays fast as the dictionary grows toward ~150 terms.
    static var terms: [DictionaryTerm] {
        variablesTerms + functionsTerms + controlFlowTerms + toolsTerms + webTerms
    }

    static func terms(in topicId: String) -> [DictionaryTerm] {
        terms.filter { $0.topicId == topicId }
    }

    /// Search across both vi and en text so users find terms regardless of UI
    /// language. Covers title + both definition layers + diagram caption.
    /// (Deliberately not `codeExample` — too noisy.)
    static func search(_ query: String) -> [DictionaryTerm] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return terms }
        return terms.filter { term in
            let haystack = [
                term.title.vi, term.title.en,
                term.cardDefinition.vi, term.cardDefinition.en,
                term.whatItReallyMeans.vi, term.whatItReallyMeans.en,
                term.diagram?.caption?.vi ?? "", term.diagram?.caption?.en ?? "",
            ]
            return haystack.contains { $0.lowercased().contains(q) }
        }
    }
}

// MARK: - Glossary scanning (narrative term highlighting)

/// Finds dictionary terms inside free narrative text so the Reflection feature
/// can highlight + link them. Matching is deliberately CONSERVATIVE: whole-word
/// (optional trailing plural "s"), English keywords only (code terms read the
/// same in vi and en text), the most ambiguous common-word titles are skipped,
/// and only the FIRST occurrence of each term per passage is returned.
enum DictionaryGlossary {

    /// One matched span: a character range in the source string + the term id.
    struct Hit { let range: Range<String.Index>; let termId: String }

    /// Single-word titles that are too common to highlight safely (they appear
    /// constantly as ordinary English). Multi-word phrases are always kept —
    /// they're unambiguous ("pure function", "merge conflict").
    private static let ambiguous: Set<String> = [
        "if", "else", "state", "string", "number", "object",
    ]

    /// Synonyms/abbreviations that aren't in a term's title but show up in
    /// narratives. Keys are term ids that must exist.
    private static let aliases: [String: [String]] = [
        "terminal":        ["shell", "cli", "command line"],
        "package-manager": ["npm", "yarn", "pip"],
        "directory":       ["folder", "dir"],
        "dependency":      ["dependencies", "library", "libraries"],
        "javascript":      [".js", ".jsx", "js", "jsx"],
        "typescript":      [".tsx", ".ts", "tsx"],
        "git":             ["github"],
    ]

    /// (keyword, termId) pairs, longest keyword first so phrases win over the
    /// single words they contain (e.g. "pure function" before "function").
    private static let entries: [(keyword: String, termId: String)] = {
        var out: [(keyword: String, termId: String)] = []
        for term in DictionaryContent.terms {
            for kw in keywords(for: term) where !(isSingleWord(kw) && ambiguous.contains(kw)) {
                out.append((kw, term.id))
            }
        }
        for (termId, words) in aliases {
            for kw in words where !(isSingleWord(kw) && ambiguous.contains(kw)) {
                out.append((kw, termId))
            }
        }
        return out.sorted { $0.keyword.count > $1.keyword.count }
    }()

    private static func isSingleWord(_ s: String) -> Bool { !s.contains(" ") }

    /// Derive match keywords from a term's English title: split off any
    /// parenthetical, then break on "/" and " vs " into alternatives.
    /// e.g. "Null (nil)" → ["null", "nil"]; "Async / await" → ["async", "await"];
    /// "Frontend vs Backend" → ["frontend", "backend"]; "Pure function" → ["pure function"].
    private static func keywords(for term: DictionaryTerm) -> [String] {
        let raw = term.title.en.lowercased()
        var outside = "", paren = "", depth = 0
        for ch in raw {
            if ch == "(" { depth += 1; continue }
            if ch == ")" { depth = max(0, depth - 1); continue }
            if depth > 0 { paren.append(ch) } else { outside.append(ch) }
        }
        var pieces: [String] = []
        for chunk in [outside, paren] {
            let normalized = chunk.replacingOccurrences(of: " vs ", with: "/")
            for part in normalized.split(separator: "/") {
                let p = part.trimmingCharacters(in: .whitespaces)
                if p.count >= 2 { pieces.append(p) }
            }
        }
        return Array(Set(pieces))
    }

    /// First-occurrence, non-overlapping matches in `text`, longest phrases
    /// preferred. Each term contributes at most one hit.
    static func scan(_ text: String) -> [Hit] {
        guard !text.isEmpty else { return [] }
        var used = Set<String>()
        var hits: [Hit] = []
        for (kw, termId) in entries {
            guard !used.contains(termId) else { continue }
            guard let r = firstWordRange(of: kw, in: text) else { continue }
            guard !hits.contains(where: { $0.range.overlaps(r) }) else { continue }
            hits.append(Hit(range: r, termId: termId))
            used.insert(termId)
        }
        return hits
    }

    /// First case-insensitive, whole-word occurrence of `keyword` in `text`,
    /// allowing an optional trailing plural "s" on single-word keywords.
    private static func firstWordRange(of keyword: String, in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while let r = text.range(of: keyword, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            var end = r.upperBound
            if isSingleWord(keyword), end < text.endIndex,
               text[end] == "s" || text[end] == "S" {
                end = text.index(after: end)
            }
            let beforeOK = r.lowerBound == text.startIndex
                || !isWordChar(text[text.index(before: r.lowerBound)])
            let afterOK = end == text.endIndex || !isWordChar(text[end])
            if beforeOK && afterOK { return r.lowerBound..<end }
            searchStart = r.upperBound
        }
        return nil
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
}
