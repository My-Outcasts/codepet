import Foundation

/// A hand-rolled, single-line syntax tokeniser for the Review pane.
///
/// **Why hand-rolled.** An artifact of the deployment, not a preference: the
/// app ships no highlighting library and adding one for a diff viewer is a
/// dependency for decoration. This covers the four token classes that carry
/// nearly all the signal — comment, string, number, keyword — and deliberately
/// stops there. It is not a parser and will never be right about everything.
///
/// **Single line, no state carried between lines.** A diff is not a file: the
/// pane renders hunks with gaps, so line 40 may follow line 12 and there is no
/// honest way to know whether an unterminated `/*` above was ever closed. A
/// tokeniser that guessed would paint whole hunks as comment on a diff that
/// merely started mid-block. Each line is read on its own, which gets the
/// common cases right and fails visibly rather than plausibly on the rest.
enum SyntaxHighlight {

    enum Kind: Equatable {
        case plain, keyword, string, comment, number
    }

    struct Span: Equatable {
        let text: String
        let kind: Kind
    }

    /// What language to read a file as, from its extension. `nil` means "do
    /// not guess" — an unknown extension renders plain, which is correct
    /// rather than colourful.
    enum Language: Equatable {
        case cFamily        // swift, ts, tsx, js, jsx, java, kt, go, c, cpp
        case python
        case css
        case markup         // html, xml, svg
        case json

        static func of(path: String) -> Language? {
            switch (path as NSString).pathExtension.lowercased() {
            case "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs",
                 "java", "kt", "go", "c", "h", "cpp", "hpp", "cs", "rs":
                return .cFamily
            case "py": return .python
            case "css", "scss", "less": return .css
            case "html", "htm", "xml", "svg", "vue": return .markup
            case "json": return .json
            default: return nil
            }
        }

        var lineComment: String? {
            switch self {
            case .cFamily: return "//"
            case .python: return "#"
            case .css, .markup, .json: return nil
            }
        }

        var keywords: Set<String> {
            switch self {
            case .cFamily:
                return ["func", "let", "var", "const", "if", "else", "for", "while", "return",
                        "class", "struct", "enum", "protocol", "extension", "import", "export",
                        "default", "switch", "case", "break", "continue", "new", "async", "await",
                        "try", "catch", "throw", "throws", "guard", "in", "is", "as", "self",
                        "this", "true", "false", "nil", "null", "undefined", "interface", "type",
                        "public", "private", "static", "override", "init", "def", "from"]
            case .python:
                return ["def", "class", "if", "elif", "else", "for", "while", "return", "import",
                        "from", "as", "try", "except", "finally", "raise", "with", "lambda",
                        "None", "True", "False", "and", "or", "not", "in", "is", "pass", "yield"]
            case .css:
                return ["important", "media", "import", "keyframes", "root"]
            case .markup:
                return []
            case .json:
                return ["true", "false", "null"]
            }
        }
    }

    /// Split one line into spans. Concatenating `span.text` in order always
    /// reproduces the input exactly — the renderer relies on it, and a
    /// tokeniser that dropped a character would silently corrupt the diff.
    static func spans(_ line: String, language: Language?) -> [Span] {
        guard let language, !line.isEmpty else { return [Span(text: line, kind: .plain)] }

        // A whole-line comment first: everything after the marker is comment,
        // including anything that would otherwise tokenise as a string.
        if let marker = language.lineComment,
           let range = line.range(of: marker),
           !isInsideQuotes(line, upTo: range.lowerBound) {
            let head = String(line[line.startIndex..<range.lowerBound])
            let tail = String(line[range.lowerBound...])
            return spans(head, language: language).filter { !$0.text.isEmpty }
                + [Span(text: tail, kind: .comment)]
        }

        var out: [Span] = []
        var current = ""
        var currentKind = Kind.plain

        func flush() {
            guard !current.isEmpty else { return }
            // A word is only a keyword once it is whole — `information` must
            // not colour because it starts with `in`.
            let kind: Kind = currentKind == .plain && language.keywords.contains(current)
                ? .keyword : currentKind
            out.append(Span(text: current, kind: kind))
            current = ""
            currentKind = .plain
        }

        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]

            if ch == "\"" || ch == "'" || ch == "`" {
                flush()
                let (text, next) = readString(line, from: index, quote: ch)
                out.append(Span(text: text, kind: .string))
                index = next
                continue
            }

            let isWord = ch.isLetter || ch == "_" || ch == "$"
            let isDigit = ch.isNumber

            if isWord || (isDigit && (currentKind == .plain && !current.isEmpty)) {
                if currentKind != .plain { flush() }
                current.append(ch)
            } else if isDigit {
                if currentKind != .number { flush(); currentKind = .number }
                current.append(ch)
            } else if ch == "." && currentKind == .number {
                current.append(ch)   // 3.14 stays one number
            } else {
                flush()
                out.append(Span(text: String(ch), kind: .plain))
            }
            index = line.index(after: index)
        }
        flush()
        return out.isEmpty ? [Span(text: line, kind: .plain)] : out
    }

    /// A quoted run including both quotes, or to end of line when unterminated
    /// — a diff truncates lines, and an unclosed quote is normal there.
    private static func readString(
        _ line: String, from start: String.Index, quote: Character
    ) -> (String, String.Index) {
        var index = line.index(after: start)
        var escaped = false
        while index < line.endIndex {
            let ch = line[index]
            if escaped { escaped = false }
            else if ch == "\\" { escaped = true }
            else if ch == quote { return (String(line[start...index]), line.index(after: index)) }
            index = line.index(after: index)
        }
        return (String(line[start...]), line.endIndex)
    }

    /// Whether a position sits inside a quoted run, so a `//` in a URL is not
    /// read as the start of a comment. The reason `https://x` survives.
    private static func isInsideQuotes(_ line: String, upTo target: String.Index) -> Bool {
        var open: Character?
        var escaped = false
        var index = line.startIndex
        while index < target, index < line.endIndex {
            let ch = line[index]
            if escaped { escaped = false }
            else if ch == "\\" { escaped = true }
            else if let quote = open { if ch == quote { open = nil } }
            else if ch == "\"" || ch == "'" || ch == "`" { open = ch }
            index = line.index(after: index)
        }
        return open != nil
    }
}
