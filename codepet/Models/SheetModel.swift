// codepet/Models/SheetModel.swift
import Foundation

// MARK: - The sheet payload (CP-002 D)

/// One assumption the founder can move.
struct SheetVariable: Codable, Hashable {
    var key: String
    var name: String
    var unit: String
    var val: Double
    var min: Double
    var max: Double
    var step: Double
}

/// One result, written as a formula over the inputs and other outputs. `value` is what the server
/// computed at the defaults — kept for anything that reads the payload without evaluating it, and
/// never what the viewer shows: the viewer evaluates `formula` against the live sliders.
struct SheetOutput: Codable, Hashable {
    var key: String
    var name: String
    var unit: String
    var formula: String
    var value: Double?
}

/// A `.sheet` deliverable: a live model of whatever the task was about.
///
/// It was four fixed inputs (price, waitlist, conversion, churn) and six outputs whose maths lived
/// in `SheetModel.compute`, whatever Finance had been asked for — the demo's inference-cost model
/// talked about session length and cost per minute beside four pricing sliders. Now the model
/// declares its inputs and writes each output as a formula (`SheetFormula`).
///
/// **Two shapes decode.** The new one (`inputs`/`outputs`), and the OLD fixed four, which are
/// lifted with the same table the server uses (`LEGACY_SHEET_*` in `runTaskCore.ts`) — so every
/// sheet already in a Library opens as a model, with the same six numbers it always showed, plus
/// the $2,500 of monthly costs break-even always divided by, now an input the founder can see and
/// move (founder decision, 30 Sep). The old shape is never written back: encoding is the new shape
/// only, so a re-saved sheet migrates itself.
struct SheetPayload: Codable, Hashable {
    var inputs: [SheetVariable]
    var outputs: [SheetOutput]
    var summary: String?
    /// Lifted from the old fixed four. The viewer localises the names it knows for these; a new
    /// sheet's names were written by the model in the founder's language already.
    var legacy: Bool = false

    init(inputs: [SheetVariable], outputs: [SheetOutput], summary: String? = nil, legacy: Bool = false) {
        self.inputs = inputs
        self.outputs = outputs
        self.summary = summary
        self.legacy = legacy
    }

    private enum CodingKeys: String, CodingKey {
        case inputs, outputs, summary, legacy
        case price, waitlist, conversion, churn
    }

    /// Throws when the container holds neither shape — which is what keeps a non-sheet payload
    /// (decoded from the same flat container by `DeliverablePayload`) from growing a sheet.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        if c.contains(.inputs) {
            inputs = try c.decode([SheetVariable].self, forKey: .inputs)
            outputs = try c.decode([SheetOutput].self, forKey: .outputs)
            legacy = try c.decodeIfPresent(Bool.self, forKey: .legacy) ?? false
            guard !inputs.isEmpty, !outputs.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .inputs, in: c, debugDescription: "empty sheet")
            }
        } else {
            let lifted = Self.lift(price: try c.decode(SheetInput.self, forKey: .price),
                                   waitlist: try c.decode(SheetInput.self, forKey: .waitlist),
                                   conversion: try c.decode(SheetInput.self, forKey: .conversion),
                                   churn: try c.decode(SheetInput.self, forKey: .churn),
                                   summary: summary)
            inputs = lifted.inputs
            outputs = lifted.outputs
            legacy = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(inputs, forKey: .inputs)
        try c.encode(outputs, forKey: .outputs)
        try c.encodeIfPresent(summary, forKey: .summary)
        if legacy { try c.encode(true, forKey: .legacy) }
    }

    // MARK: legacy lift — keep in step with `LEGACY_SHEET_*` in functions/src/runTaskCore.ts

    static let legacyCosts = SheetVariable(key: "costs", name: "Monthly costs", unit: "$",
                                           val: 2500, min: 0, max: 20000, step: 100)

    static let legacyOutputs: [SheetOutput] = [
        SheetOutput(key: "mrr", name: "Seed MRR", unit: "$", formula: "paid * max(price, 1)"),
        SheetOutput(key: "paid", name: "Paid users", unit: "users", formula: "round(waitlist * conversion / 100)"),
        SheetOutput(key: "arr", name: "Run-rate ARR", unit: "$", formula: "mrr * 12"),
        SheetOutput(key: "ltv", name: "LTV / user", unit: "$", formula: "round(max(price, 1) / (max(churn, 1) / 100))"),
        SheetOutput(key: "life", name: "Churn-adj. life", unit: "mo", formula: "round(100 / max(churn, 1))"),
        SheetOutput(key: "breakeven", name: "Break-even users", unit: "users", formula: "ceil(costs / max(price, 1))"),
    ]

    static func lift(price: SheetInput, waitlist: SheetInput, conversion: SheetInput, churn: SheetInput,
                     summary: String?) -> SheetPayload {
        func v(_ key: String, _ name: String, _ unit: String, _ i: SheetInput) -> SheetVariable {
            SheetVariable(key: key, name: name, unit: unit, val: i.val, min: i.min, max: i.max, step: i.step)
        }
        var sheet = SheetPayload(inputs: [
            v("price", "Pro price / mo", "$", price), v("waitlist", "Waitlist size", "users", waitlist),
            v("conversion", "Waitlist → paid", "%", conversion), v("churn", "Monthly churn", "%", churn),
            legacyCosts,
        ], outputs: legacyOutputs, summary: summary, legacy: true)
        let values = sheet.evaluate(sheet.defaults)
        sheet.outputs = sheet.outputs.map { var o = $0; o.value = values[o.key]; return o }
        return sheet
    }

    /// The names the old viewer showed, in the founder's language. Only for a lifted sheet.
    static func legacyName(_ key: String, _ lang: AppLanguage) -> String? {
        guard lang == .vi else { return nil }
        return [
            "price": "Giá gói Pro / tháng", "waitlist": "Danh sách chờ", "conversion": "Chờ → trả phí",
            "churn": "Rời bỏ hàng tháng", "costs": "Chi phí hàng tháng",
            "mrr": "MRR khởi điểm", "paid": "Người dùng trả phí", "arr": "ARR ước tính",
            "ltv": "LTV / người dùng", "life": "Tuổi thọ (theo rời bỏ)", "breakeven": "Hòa vốn (số người dùng)",
        ][key]
    }

    // MARK: evaluation

    /// Each input at its default.
    var defaults: [String: Double] {
        Dictionary(inputs.map { ($0.key, $0.val) }, uniquingKeysWith: { a, _ in a })
    }

    /// Every output's value for these input values; an output that cannot be computed (a formula
    /// that does not parse, reads an unknown name, or sits in a cycle) is absent, and one that
    /// divides by zero at these values is non-finite. Kahn's order, as on the server, because an
    /// output may read outputs listed after it — the headline usually does.
    func evaluate(_ values: [String: Double]) -> [String: Double] {
        let parsed = outputs.compactMap { o in SheetFormula.parse(o.formula).map { (o.key, $0) } }
        var env = values
        var placed = Set(values.keys)
        var progress = true
        while progress {
            progress = false
            for (key, node) in parsed where !placed.contains(key) && node.refs.isSubset(of: placed) {
                env[key] = node.evaluate(env)
                placed.insert(key)
                progress = true
            }
        }
        return env.filter { k, _ in outputs.contains { $0.key == k } }
    }
}

// MARK: - The OLD fixed model (reference only)

/// The pre-CP-002-D pricing model: four fixed inputs, six outputs. No viewer or export reads it
/// any more — a lifted sheet computes from its formulas — but it is kept as the reference the
/// lift is tested against (`SheetLiftTests`): the lifted formulas must reproduce these numbers
/// exactly, across the input range, or every sheet in every Library changes its figures.
///
/// Guarantee from the original port of web's `computeSheetModel`: price is floored at 1 and churn
/// at 0.01 (1%), so nothing here divides by zero.
struct SheetModel: Hashable {
    var paid: Int
    var mrr: Double
    var arr: Double
    var ltv: Int
    var life: Int
    var breakeven: Int

    static func compute(price: Double, waitlist: Double, conversion: Double, churn: Double) -> SheetModel {
        let safePrice = Swift.max(1, price.isFinite ? price : 12)
        let wl = waitlist.isFinite ? waitlist : 1504
        let conv = (conversion.isFinite ? conversion : 8) / 100
        let churnFrac = Swift.max(0.01, (churn.isFinite ? churn : 5) / 100)

        let paid = Int((wl * conv).rounded())
        let mrr = Double(paid) * safePrice

        return SheetModel(
            paid: paid,
            mrr: mrr,
            arr: mrr * 12,
            ltv: Int((safePrice / churnFrac).rounded()),
            life: Int((1 / churnFrac).rounded()),
            breakeven: Int((2500 / safePrice).rounded(.up))
        )
    }
}
