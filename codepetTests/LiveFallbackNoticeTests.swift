import XCTest
@testable import codepet

/// The authored fallback used to be indistinguishable from a live reply. These pin the two
/// halves of making it visible: the copy, and the flag the view keys off.
final class LiveFallbackNoticeTests: XCTestCase {

    func testTheNoticeIsLocalisedAndNonEmpty() {
        for lang in [AppLanguage.en, .vi] {
            let t = LiveFallbackNotice.text(lang)
            XCTAssertFalse(t.trimmingCharacters(in: .whitespaces).isEmpty, "\(lang) notice is blank")
        }
        XCTAssertNotEqual(LiveFallbackNotice.text(.en), LiveFallbackNotice.text(.vi),
                          "Vietnamese must not fall through to the English string")
    }

    /// It has to name the thing that happened. A notice reading "Error" would satisfy the
    /// emptiness check above while telling the founder nothing about WHY the line is authored.
    func testTheNoticeSaysTheReplyDidNotArrive() {
        XCTAssertTrue(LiveFallbackNotice.text(.en).lowercased().contains("scripted"))
        XCTAssertTrue(LiveFallbackNotice.text(.vi).lowercased().contains("có sẵn"))
    }

    /// **An ordinary message must never claim to be a fallback.** The flag defaults to false,
    /// and every non-`postLiveLine` construction relies on that default — a flipped default
    /// would stamp the notice under every reply in the app.
    func testAnOrdinaryMessageIsNotMarked() {
        XCTAssertFalse(CopilotMessage(role: .companion, text: "hello").scriptedFallback)
        XCTAssertFalse(CopilotMessage(role: .me, text: "hi").scriptedFallback)
    }

    /// And a message that IS the fallback carries it, so the view has something to key off.
    func testAMarkedMessageCarriesTheFlag() {
        let m = CopilotMessage(role: .companion, text: "authored line", scriptedFallback: true)
        XCTAssertTrue(m.scriptedFallback)
        // The text is still the authored line — the notice annotates it, never replaces it.
        XCTAssertEqual(m.text, "authored line")
    }
}
