// codepetTests/LibraryStatusLabelTests.swift
import XCTest
@testable import codepet

/// Build 4, 28 Sep: after a Team Build approve the Library read "05 LIVE · 10 DRAFT" although all
/// fifteen items had been approved. Only approved work is ever filed there, so nothing in it is a
/// draft; the pip was only ever saying whether the kind renders live (a site, a sheet). Everything
/// else is "Saved" now. `legal` keeps "legal draft" in its tag on purpose — that one really is a
/// draft, not legal advice.
final class LibraryStatusLabelTests: XCTestCase {

    func testNoFiledItemIsCalledADraft() {
        for k in DeliverableKind.allCases {
            for lang in [AppLanguage.en, .vi] {
                let status = Lib.status(k, lang).lowercased()
                XCTAssertFalse(status.contains("draft") || status.contains("nháp"), "\(k) \(lang): \(status)")
                if k != .legal {
                    let tag = Lib.tag(k, lang).lowercased()
                    XCTAssertFalse(tag.contains("draft") || tag.contains("nháp"), "\(k) \(lang) tag: \(tag)")
                }
            }
        }
    }

    /// 5 Oct, testing as a non-technical founder: "LIVE SITE" / "Live" read as "published on
    /// the internet", but a site in the Library is a page on this Mac that previews in the app.
    /// The pip now says what it is — something you can click through.
    func testInteractiveKindsSayInteractive() {
        XCTAssertEqual(Lib.status(.site, .en), "Interactive")
        XCTAssertEqual(Lib.status(.sheet, .vi), "Tương tác")
        XCTAssertEqual(Lib.status(.doc, .en), "Saved")
        XCTAssertEqual(Lib.status(.doc, .vi), "Đã lưu")
    }

    func testNothingInTheLibraryClaimsToBeLive() {
        for k in DeliverableKind.allCases {
            for lang in [AppLanguage.en, .vi] {
                for s in [Lib.status(k, lang), Lib.tag(k, lang)] {
                    XCTAssertFalse(s.lowercased().contains("live") || s.lowercased().contains("trực tiếp"),
                                   "\(k) \(lang): \(s)")
                }
            }
        }
    }
}
