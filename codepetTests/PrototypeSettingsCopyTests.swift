// codepetTests/PrototypeSettingsCopyTests.swift
import XCTest
@testable import codepet

/// Guards on "Settings says which half of itself is real".
///
/// **The bug these exist for.** Prototype mode swaps the company for a fixture and leaves the
/// account alone, and nothing on screen said so. The sidebar read "A fixture company, 0
/// credits. Nothing is written to your account" while Advanced read "Your progress stays saved
/// in the cloud" and Billing and Usage rendered real numbers. Each sentence was true about a
/// different half; together they made the mode read as untrustworthy, because a founder who
/// spots one wrong sentence has no way to tell which of the others to believe.
///
/// Reported as the flow "confusing the real version and prototype mode".
final class PrototypeSettingsCopyTests: XCTestCase {

    /// The sentence that was false. Not a wording assertion — it pins that the two states say
    /// DIFFERENT things, so a future edit cannot collapse them back into one string.
    func testSignOutCopyDiffersInPrototypeMode() {
        let real = PrototypeSettingsCopy.signOutDescription(prototypeOn: false, lang: .en)
        let proto = PrototypeSettingsCopy.signOutDescription(prototypeOn: true, lang: .en)
        XCTAssertNotEqual(real, proto,
                          "prototype mode saves nothing; saying otherwise is the bug")
    }

    /// A real founder's copy is untouched — the fix must not change what someone NOT in
    /// prototype mode reads.
    func testSignOutCopyIsUnchangedOutsidePrototypeMode() {
        XCTAssertEqual(PrototypeSettingsCopy.signOutDescription(prototypeOn: false, lang: .en),
                       "Your progress stays saved in the cloud.")
        XCTAssertEqual(PrototypeSettingsCopy.signOutDescription(prototypeOn: false, lang: .vi),
                       "Tiến trình của bạn vẫn được lưu trên đám mây.")
    }

    /// Both languages move together. The English and Vietnamese live in one function precisely
    /// so an edit cannot fix one and leave the other asserting the old, false claim — which is
    /// a silent failure for exactly the founders who read the one that was missed.
    func testBothLanguagesChangeInPrototypeMode() {
        for lang in [AppLanguage.en, .vi] {
            XCTAssertNotEqual(PrototypeSettingsCopy.signOutDescription(prototypeOn: false, lang: lang),
                              PrototypeSettingsCopy.signOutDescription(prototypeOn: true, lang: lang),
                              "\(lang) still claims a fixture run was saved")
        }
    }

    /// The note is shown ONLY in prototype mode. A banner about fixtures on a real founder's
    /// Settings would be its own lie.
    func testTheNoteIsShownOnlyInPrototypeMode() {
        XCTAssertTrue(PrototypeSettingsCopy.showsAccountIsRealNote(prototypeOn: true))
        XCTAssertFalse(PrototypeSettingsCopy.showsAccountIsRealNote(prototypeOn: false))
    }

    /// The note has to name the account side as real — that is its entire job. A note that
    /// only repeated "this is a fixture" would restate the sidebar and leave Billing and Usage
    /// exactly as ambiguous as before.
    func testTheNoteNamesWhatIsRealNotOnlyWhatIsFixture() {
        let en = PrototypeSettingsCopy.accountIsRealNote(lang: .en).lowercased()
        XCTAssertTrue(en.contains("fixture"), "must say the company is not real")
        XCTAssertTrue(en.contains("real"), "must say which half IS real")
        for word in ["account", "billing", "usage"] {
            XCTAssertTrue(en.contains(word), "the note must name \(word), which renders real data")
        }
    }

    /// Vietnamese carries the same two claims. Pinned by shape rather than by wording so a
    /// translator can improve the sentence without breaking the guard.
    func testTheVietnameseNoteCarriesBothClaims() {
        let vi = PrototypeSettingsCopy.accountIsRealNote(lang: .vi)
        XCTAssertFalse(vi.isEmpty)
        XCTAssertNotEqual(vi, PrototypeSettingsCopy.accountIsRealNote(lang: .en),
                          "an untranslated note is a note half the founders cannot read")
    }
}
