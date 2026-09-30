// codepet/Models/SheetFormula.swift
import Foundation

/// The formula language a `sheet` output is written in (CP-002 D) — the line-for-line twin of
/// `functions/src/sheetFormula.ts`. Both are held to one table of cases
/// (`functions/src/__tests__/fixtures/sheetFormulaCases.json`, read by `SheetFormulaTests` and by
/// jest), so a formula can never compute one number on the server and another in the app.
///
/// Numbers, names, `+ - * / ^`, parentheses, and `min max round ceil floor`. `×`, `÷` and `−` are
/// accepted because that is how the viewer prints a formula. No `eval` of any kind.
indirect enum SheetFormula: Hashable {
    case num(Double)
    case ref(String)
    case neg(SheetFormula)
    case bin(Character, SheetFormula, SheetFormula)
    case call(String, [SheetFormula])

    private static let funcs: [String: ClosedRange<Int>] = [
        "min": 2...8, "max": 2...8, "round": 1...1, "ceil": 1...1, "floor": 1...1,
    ]

    private enum Tok: Equatable { case num(Double), id(String), op(Character) }

    private static func tokenize(_ src: String) -> [Tok]? {
        let s = Array(src.replacingOccurrences(of: "×", with: "*")
                         .replacingOccurrences(of: "÷", with: "/")
                         .replacingOccurrences(of: "−", with: "-"))
        var out: [Tok] = []
        var i = 0
        func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
        func isLower(_ c: Character) -> Bool { c >= "a" && c <= "z" }
        while i < s.count {
            let c = s[i]
            if c == " " || c == "\t" { i += 1; continue }
            if "+-*/^(),".contains(c) { out.append(.op(c)); i += 1; continue }
            if isDigit(c) {
                var j = i
                while j < s.count, isDigit(s[j]) { j += 1 }
                if j + 1 < s.count, s[j] == ".", isDigit(s[j + 1]) {
                    j += 1
                    while j < s.count, isDigit(s[j]) { j += 1 }
                }
                // `1e3` would otherwise read as the number 1 followed by the name `e3`.
                if j < s.count, s[j].isLetter || s[j] == "_" { return nil }
                guard let v = Double(String(s[i..<j])) else { return nil }
                out.append(.num(v)); i = j; continue
            }
            if isLower(c) {
                var j = i
                while j < s.count, isLower(s[j]) || isDigit(s[j]) || s[j] == "_" { j += 1 }
                out.append(.id(String(s[i..<j]))); i = j; continue
            }
            return nil
        }
        return out
    }

    /// The parsed formula, or nil when it is not one: a syntax error, or an unknown function.
    static func parse(_ src: String) -> SheetFormula? {
        guard let toks = tokenize(src), !toks.isEmpty else { return nil }
        var p = 0
        func isOp(_ c: Character) -> Bool { p < toks.count && toks[p] == .op(c) }

        func expr() -> SheetFormula? {
            guard var a = term() else { return nil }
            while isOp("+") || isOp("-") {
                guard case .op(let op) = toks[p] else { return nil }
                p += 1
                guard let b = term() else { return nil }
                a = .bin(op, a, b)
            }
            return a
        }
        func term() -> SheetFormula? {
            guard var a = unary() else { return nil }
            while isOp("*") || isOp("/") {
                guard case .op(let op) = toks[p] else { return nil }
                p += 1
                guard let b = unary() else { return nil }
                a = .bin(op, a, b)
            }
            return a
        }
        func unary() -> SheetFormula? {
            if isOp("-") { p += 1; return unary().map { .neg($0) } }
            return power()
        }
        func power() -> SheetFormula? {
            guard let a = atom() else { return nil }
            if isOp("^") { p += 1; return unary().map { .bin("^", a, $0) } }
            return a
        }
        func atom() -> SheetFormula? {
            guard p < toks.count else { return nil }
            switch toks[p] {
            case .num(let v):
                p += 1; return .num(v)
            case .op("("):
                p += 1
                guard let x = expr(), isOp(")") else { return nil }
                p += 1; return x
            case .id(let name):
                p += 1
                guard isOp("(") else { return .ref(name) }
                guard let arity = funcs[name] else { return nil }
                p += 1
                var args: [SheetFormula] = []
                if !isOp(")") {
                    while true {
                        guard let x = expr() else { return nil }
                        args.append(x)
                        if isOp(",") { p += 1; continue }
                        break
                    }
                }
                guard isOp(")") else { return nil }
                p += 1
                guard arity.contains(args.count) else { return nil }
                return .call(name, args)
            default:
                return nil
            }
        }

        guard let root = expr(), p == toks.count else { return nil }
        return root
    }

    /// Every name this formula reads.
    var refs: Set<String> {
        switch self {
        case .num: return []
        case .ref(let n): return [n]
        case .neg(let x): return x.refs
        case .bin(_, let a, let b): return a.refs.union(b.refs)
        case .call(_, let args): return args.reduce(into: Set<String>()) { $0.formUnion($1.refs) }
        }
    }

    /// NaN for a name `env` does not have. `round` is half-up (`floor(x + 0.5)`), as on the server.
    func evaluate(_ env: [String: Double]) -> Double {
        switch self {
        case .num(let v): return v
        case .ref(let n): return env[n] ?? .nan
        case .neg(let x): return -x.evaluate(env)
        case .bin(let op, let a, let b):
            let x = a.evaluate(env), y = b.evaluate(env)
            switch op {
            case "+": return x + y
            case "-": return x - y
            case "*": return x * y
            case "/": return x / y
            default:  return pow(x, y)
            }
        case .call(let fn, let args):
            let xs = args.map { $0.evaluate(env) }
            switch fn {
            case "min":   return xs.min() ?? .nan
            case "max":   return xs.max() ?? .nan
            case "round": return (xs[0] + 0.5).rounded(.down)
            case "ceil":  return xs[0].rounded(.up)
            default:      return xs[0].rounded(.down)
            }
        }
    }

    /// How the viewer prints a formula: `×`, `÷`, `−` for the ASCII the model writes.
    static func display(_ src: String) -> String {
        src.replacingOccurrences(of: "*", with: "×")
           .replacingOccurrences(of: "/", with: "÷")
           .replacingOccurrences(of: " - ", with: " − ")
    }
}
