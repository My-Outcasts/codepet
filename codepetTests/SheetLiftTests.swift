import XCTest
@testable import codepet

/// CP-002 D: every sheet filed before now had four fixed inputs. It is lifted into the model
/// shape on decode, and must show EXACTLY the numbers the old fixed model computed — across the
/// whole input range, not just at the defaults — or every sheet in every Library changes its
/// figures the day this ships. The one visible addition is the fifth input, the $2,500 of monthly
/// costs break-even always divided by (founder decision, 30 Sep).
final class SheetLiftTests: XCTestCase {

    private func legacyJSON(price: Double, waitlist: Double, conversion: Double, churn: Double) -> String {
        #"{"id":"s","kind":"sheet","title":"T","body":"b","payload":{"price":{"val":\#(price),"min":0,"max":50,"step":1},"waitlist":{"val":\#(waitlist),"min":0,"max":5000,"step":50},"conversion":{"val":\#(conversion),"min":0,"max":40,"step":1},"churn":{"val":\#(churn),"min":0,"max":25,"step":1},"summary":"s"}}"#
    }

    private func lifted(price: Double, waitlist: Double, conversion: Double, churn: Double) throws -> SheetPayload {
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(legacyJSON(price: price, waitlist: waitlist, conversion: conversion, churn: churn).utf8))
        return try XCTUnwrap(d.payload?.sheet, "the legacy four did not decode")
    }

    func testTheShapeOfALiftedSheet() throws {
        let s = try lifted(price: 6, waitlist: 400, conversion: 8, churn: 9)
        XCTAssertTrue(s.legacy)
        XCTAssertEqual(s.inputs.map(\.key), ["price", "waitlist", "conversion", "churn", "costs"])
        XCTAssertEqual(s.inputs.last, SheetPayload.legacyCosts)
        XCTAssertEqual(s.outputs.map(\.key), ["mrr", "paid", "arr", "ltv", "life", "breakeven"])
        XCTAssertEqual(s.summary, "s")
    }

    /// The parity the whole lift rests on, over a grid that includes both floors (price 0, churn 0).
    func testLiftedFormulasReproduceTheOldModelEverywhere() throws {
        for price in [0.0, 1, 6, 12, 49] {
            for waitlist in [0.0, 50, 400, 1504, 5000] {
                for conversion in [0.0, 1, 8, 37] {
                    for churn in [0.0, 0.5, 1, 9, 25] {
                        let old = SheetModel.compute(price: price, waitlist: waitlist, conversion: conversion, churn: churn)
                        let s = try lifted(price: price, waitlist: waitlist, conversion: conversion, churn: churn)
                        let r = s.evaluate(s.defaults)
                        let at = "price \(price) waitlist \(waitlist) conversion \(conversion) churn \(churn)"
                        XCTAssertEqual(r["paid"], Double(old.paid), at)
                        XCTAssertEqual(r["mrr"], old.mrr, at)
                        XCTAssertEqual(r["arr"], old.arr, at)
                        XCTAssertEqual(r["ltv"], Double(old.ltv), at)
                        XCTAssertEqual(r["life"], Double(old.life), at)
                        XCTAssertEqual(r["breakeven"], Double(old.breakeven), at)
                    }
                }
            }
        }
    }

    /// The fifth input is live: moving costs moves break-even and nothing else.
    func testCostsDrivesBreakEvenOnly() throws {
        let s = try lifted(price: 6, waitlist: 400, conversion: 8, churn: 9)
        var v = s.defaults
        let before = s.evaluate(v)
        v["costs"] = 6000
        let after = s.evaluate(v)
        XCTAssertEqual(after["breakeven"], 1000)
        for k in ["mrr", "paid", "arr", "ltv", "life"] { XCTAssertEqual(after[k], before[k], k) }
    }

    /// A re-saved lifted sheet is written in the new shape, and reads back identical.
    func testALiftedSheetMigratesOnSave() throws {
        let s = try lifted(price: 6, waitlist: 400, conversion: 8, churn: 9)
        let data = try JSONEncoder().encode(s)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        XCTAssertEqual(keys, ["inputs", "legacy", "outputs", "summary"])
        XCTAssertEqual(try JSONDecoder().decode(SheetPayload.self, from: data), s)
    }

    /// Keep the two lift tables in step: the server's and this one must be the same model.
    func testTheLiftMatchesTheServersTable() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("functions/src/runTaskCore.ts")
        let ts = try String(contentsOf: url, encoding: .utf8)
        for o in SheetPayload.legacyOutputs {
            XCTAssertTrue(ts.contains(#"["\#(o.key)", "\#(o.name)", "\#(o.unit)", "\#(o.formula)"]"#), "server lift table is missing \(o.key)")
        }
        let c = SheetPayload.legacyCosts
        XCTAssertTrue(ts.contains(#"key: "costs", name: "\#(c.name)", unit: "$", val: \#(Int(c.val)), min: \#(Int(c.min)), max: \#(Int(c.max)), step: \#(Int(c.step))"#))
    }

    func testANonSheetPayloadGrowsNoSheet() throws {
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(#"{"id":"d","kind":"doc","title":"T","body":"b","payload":{"call":"c","sections":[{"h":"h","p":"p"}]}}"#.utf8))
        XCTAssertNil(d.payload?.sheet)
    }
}
