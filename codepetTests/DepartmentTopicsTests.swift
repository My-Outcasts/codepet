import XCTest
@testable import codepet

/// The vocabulary is data, and these three tests are what stop it rotting into a source of
/// silent no-ops and stolen turns.
final class DepartmentTopicsTests: XCTestCase {

    /// A single-word entry shorter than 3 characters, or one that is a stopword, is DEAD:
    /// `TextRelevance.tokenize` drops it, so it can never match and nothing says so. This is
    /// why the lexicon has no "ux", "ui" or "ci".
    ///
    /// Both this and `testNoEntryIsADepartmentName` walk `en + vi`, not `en`. The entire case
    /// for shipping an empty `vi` table is that filling it later is "a data fill, not a
    /// refactor" (spec §2.6) — which is only true if the two guards that stop the lexicon
    /// rotting into dead entries and stolen turns actually SEE that fill. Iterating `en` alone
    /// meant the Vietnamese table would arrive unguarded.
    func testEverySingleWordEntrySurvivesTheTokenizer() {
        for (key, vocab) in DepartmentTopics.map {
            for term in (vocab.en + vocab.vi) where !term.contains(" ") {
                XCTAssertGreaterThanOrEqual(term.count, 3,
                    "\(key): \"\(term)\" is under 3 chars — tokenize() drops it, so it can never match")
                XCTAssertFalse(TextRelevance.stopwords.contains(term),
                    "\(key): \"\(term)\" is a stopword — tokenize() drops it")
                XCTAssertEqual(term, term.lowercased(),
                    "\(key): \"\(term)\" must be lowercase — tokenize() lowercases before comparing")
            }
        }
    }

    /// Department NAMES belong to tier 1, which requires them to be ADDRESSED. Putting a name
    /// in a lexicon lets tier 2 fire on a bare mention and re-opens the Aug 10 regression from
    /// underneath — "we have support from two angel investors" summoning Sage · Support.
    func testNoEntryIsADepartmentName() {
        let names = Set(DepartmentCatalog.all.map { $0.name.lowercased() })
        for (key, vocab) in DepartmentTopics.map {
            for term in (vocab.en + vocab.vi) {
                XCTAssertFalse(names.contains(term),
                    "\(key): \"\(term)\" is a department name — tier 1 owns that word")
            }
        }
    }

    /// Every key must resolve to a real department that HAS a pet. `product` is in the catalog
    /// to resolve a Virtual Company wire key and has no companion, so a lexicon for it would
    /// score a department that can never be suggested.
    func testEveryKeyIsAMappedDepartment() {
        for key in DepartmentTopics.map.keys {
            XCTAssertNotNil(DepartmentCatalog.find(key), "\(key) is not in the catalog")
            XCTAssertNotNil(DepartmentCompanions.companionId(for: key),
                            "\(key) has no companion — it can never be suggested")
        }
        XCTAssertNil(DepartmentTopics.map["product"], "product has no pet; see spec §2.5")
    }

    func testTermsForLanguageReturnsEnglishAndAnEmptyVietnamese() {
        XCTAssertFalse(DepartmentTopics.terms(for: "fin", language: .en).isEmpty)
        XCTAssertTrue(DepartmentTopics.terms(for: "fin", language: .vi).isEmpty,
                      "the vi table ships present and empty — spec §2.6")
        XCTAssertTrue(DepartmentTopics.terms(for: "product", language: .en).isEmpty)
    }

    /// The worked example in spec §4.4 depends on this exact word.
    func testFinanceKnowsInvestors() {
        XCTAssertTrue(DepartmentTopics.terms(for: "fin", language: .en).contains("investors"))
    }
}
