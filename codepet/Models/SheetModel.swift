// codepet/Models/SheetModel.swift
import Foundation

/// Pure logic for the Finance pricing model (`.sheet` deliverable). Ported 1:1 from
/// web's `computeSheetModel` (lib/ai/sheetModel.ts) so `SheetViewer`'s live slider
/// recompute matches the web artifact exactly. Struct-only, no SwiftUI/@MainActor
/// dependency — unit-testable in isolation (see SheetModelTests).
///
/// Guarantee ported from web: the result can never be non-finite — price is floored
/// at 1 and churn at 0.01 (1%), so `price / churn` and `1 / churn` never divide by
/// zero or blow up to infinity/NaN, even with garbage/out-of-range slider input.
struct SheetModel: Hashable {
    var paid: Int
    var mrr: Double
    var arr: Double
    var ltv: Int
    var life: Int
    var breakeven: Int

    /// `vals` are the live slider values in the fixed order
    /// [price, waitlist, conversion%, churn%] — mirrors web's `computeSheetModel(vals: number[])`.
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
