// codepetTests/SheetModelTests.swift
import XCTest
@testable import codepet

/// Locks `SheetModel.compute` to web's `computeSheetModel` (lib/ai/sheetModel.ts)
/// formulas. Struct-only — no @MainActor, no SwiftUI dependency.
final class SheetModelTests: XCTestCase {

    /// Known input → output pair from web's seed defaults
    /// (price 12, waitlist 1504, conversion 8%, churn 5%):
    ///   paid = round(1504 * 0.08) = round(120.32) = 120
    ///   mrr = 120 * 12 = 1440; arr = 17280
    ///   ltv = round(12 / 0.05) = 240; life = round(1 / 0.05) = 20
    ///   breakeven = ceil(2500 / 12) = 209
    func testSeedDefaultsMatchWeb() {
        let m = SheetModel.compute(price: 12, waitlist: 1504, conversion: 8, churn: 5)
        XCTAssertEqual(m.paid, 120)
        XCTAssertEqual(m.mrr, 1440)
        XCTAssertEqual(m.arr, 17280)
        XCTAssertEqual(m.ltv, 240)
        XCTAssertEqual(m.life, 20)
        XCTAssertEqual(m.breakeven, 209)
    }

    /// Churn is floored at 0.01 (1%) so `price / churn` and `1 / churn` never
    /// blow up — even a zero/garbage churn input stays finite, per web's guarantee.
    func testChurnFlooredNeverBlowsUp() {
        let m = SheetModel.compute(price: 10, waitlist: 1000, conversion: 10, churn: 0)
        XCTAssertEqual(m.life, 100) // 1 / 0.01 = 100
        XCTAssertEqual(m.ltv, 1000) // 10 / 0.01 = 1000
    }

    /// Price is floored at 1 so `2500 / price` (breakeven) never divides by zero.
    func testPriceFlooredNeverBlowsUp() {
        let m = SheetModel.compute(price: 0, waitlist: 100, conversion: 10, churn: 5)
        XCTAssertEqual(m.breakeven, 2500) // ceil(2500 / 1)
    }

    /// Non-finite inputs (NaN) fall back to web's seed defaults rather than
    /// propagating NaN through the model.
    func testNonFiniteInputsFallBackToSeedDefaults() {
        let m = SheetModel.compute(price: .nan, waitlist: .nan, conversion: .nan, churn: .nan)
        XCTAssertEqual(m.paid, 120)
        XCTAssertEqual(m.mrr, 1440)
    }
}
