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

    func testLiveKindsStillSayLive() {
        XCTAssertEqual(Lib.status(.site, .en), "Live")
        XCTAssertEqual(Lib.status(.sheet, .vi), "Trực tiếp")
        XCTAssertEqual(Lib.status(.doc, .en), "Saved")
        XCTAssertEqual(Lib.status(.doc, .vi), "Đã lưu")
    }
}
