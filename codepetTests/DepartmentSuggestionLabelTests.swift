import XCTest
@testable import codepet

/// The hover sentence is what makes a wrong guess legible instead of spooky — the founder can
/// see it matched "support" in a sentence about investors and dismiss it knowing why. It lives
/// in a pure type because a SwiftUI `.help()` string cannot be asserted on, which is the same
/// reason `DepartmentMenu` exists.
final class DepartmentSuggestionLabelTests: XCTestCase {
    private let design = DepartmentCatalog.find("design")!

    func testTopicalNamesTheWordThatFired() {
        let s = DepartmentSuggestionLabel.help(tier: .topical, matched: "landing page",
                                               pet: "luna", department: design, lang: .en)
        XCTAssertTrue(s.contains("landing page"), s)
        XCTAssertTrue(s.lowercased().contains("mentioned"), s)
    }

    /// `.addressed` is grouped with `.topical` in the switch, and the grouping is the whole
    /// point: "ask design about the hero" named a word too. If someone folds `.addressed` in
    /// with `.carryOver` instead, an addressed guess would claim to be continuing a
    /// conversation that never happened — this goes red on that.
    func testAddressedAlsoNamesTheWordThatFired() {
        let s = DepartmentSuggestionLabel.help(tier: .addressed, matched: "design",
                                               pet: "luna", department: design, lang: .en)
        XCTAssertTrue(s.contains("design"), s)
        XCTAssertTrue(s.lowercased().contains("mentioned"), s)
        XCTAssertFalse(s.lowercased().contains("continuing"), s)
    }

    func testCarryOverSaysItIsContinuing() {
        let s = DepartmentSuggestionLabel.help(tier: .carryOver, matched: nil,
                                               pet: "luna", department: design, lang: .en)
        XCTAssertTrue(s.lowercased().contains("continuing"), s)
        XCTAssertTrue(s.contains("Design"), s)
    }

    /// A topical hit with no recorded term must not claim a mention at all.
    ///
    /// The brief's assertion here was `XCTAssertFalse(s.contains("mentioned \"\""))` with STRAIGHT
    /// quotes, while the sentence is built with CURLY ones — it could never fail, and would have
    /// passed with the `guard` deleted. Asserting the word "mentioned" is absent is the real
    /// claim: delete the guard and the nil term renders `you mentioned “”`, which goes red.
    func testTopicalWithoutATermFallsBackToTheDepartment() {
        let s = DepartmentSuggestionLabel.help(tier: .topical, matched: nil,
                                               pet: "luna", department: design, lang: .en)
        XCTAssertFalse(s.lowercased().contains("mentioned"), s)
        XCTAssertTrue(s.contains("Design"), s)
    }

    /// `!matched.isEmpty` is the second half of the same guard and fails independently: a router
    /// that recorded an empty term would otherwise render `you mentioned “”`.
    func testTopicalWithAnEmptyTermFallsBackToo() {
        let s = DepartmentSuggestionLabel.help(tier: .topical, matched: "",
                                               pet: "luna", department: design, lang: .en)
        XCTAssertFalse(s.lowercased().contains("mentioned"), s)
        XCTAssertTrue(s.contains("Design"), s)
    }

    /// No mapped pet means the department alone — never a dangling separator. `DepartmentMenu`
    /// holds the same rule for the menu rows; the hover must not promise a pet that will not
    /// appear either.
    func testNoPetNamesTheDepartmentAloneWithNoDanglingSeparator() {
        let s = DepartmentSuggestionLabel.help(tier: .carryOver, matched: nil,
                                               pet: nil, department: design, lang: .en)
        XCTAssertTrue(s.contains("Design"), s)
        XCTAssertFalse(s.contains(" · "), s)
        XCTAssertFalse(s.contains("Luna"), s)
    }

    /// An id with no `PetCharacter` behind it takes the same fallback — the flatMap, not a crash
    /// and not an empty name.
    func testUnknownPetIdFallsBackToTheDepartment() {
        let s = DepartmentSuggestionLabel.help(tier: .carryOver, matched: nil,
                                               pet: "not-a-pet", department: design, lang: .en)
        XCTAssertTrue(s.contains("Design"), s)
        XCTAssertFalse(s.contains(" · "), s)
    }

    /// Both branches, not just one. The brief tested only `.carryOver`, which leaves the topical
    /// Vietnamese branch free to be English without anything going red.
    func testVietnameseIsTranslated() {
        let s = DepartmentSuggestionLabel.help(tier: .carryOver, matched: nil,
                                               pet: "luna", department: design, lang: .vi)
        XCTAssertFalse(s.lowercased().contains("continuing"), s)
        XCTAssertFalse(s.isEmpty)

        let topical = DepartmentSuggestionLabel.help(tier: .topical, matched: "landing page",
                                                     pet: "luna", department: design, lang: .vi)
        XCTAssertFalse(topical.lowercased().contains("mentioned"), topical)
        XCTAssertFalse(topical.lowercased().contains("suggested"), topical)
        // The founder's own words survive translation — the term is quoted, never localised.
        XCTAssertTrue(topical.contains("landing page"), topical)

        let noTerm = DepartmentSuggestionLabel.help(tier: .topical, matched: nil,
                                                    pet: "luna", department: design, lang: .vi)
        XCTAssertFalse(noTerm.lowercased().contains("suggested"), noTerm)
        XCTAssertFalse(noTerm.isEmpty)
    }

    /// The pet leads and the department follows, exactly as `DepartmentMenu.rowTitle` renders it
    /// and exactly as the reply is signed. The chip beside the hover says `Luna · Design`; a
    /// hover that said `Design · Luna` would read as a second feature.
    func testWhoMatchesTheChipLabel() {
        let s = DepartmentSuggestionLabel.help(tier: .carryOver, matched: nil,
                                               pet: "luna", department: design, lang: .en)
        XCTAssertTrue(s.contains(DepartmentMenu.rowTitle(design, host: "byte")), s)
    }
}
