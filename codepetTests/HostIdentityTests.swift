import XCTest
@testable import codepet

/// Codepet is the host; the pets are department characters. Two names that must not merge.
///
/// These exist because renaming the `byte` character is the kind of change that half-lands:
/// three surfaces resolved the host's name through `company.companionId` and rendered
/// "Codepet" only because byte happened to be called that. Renaming byte without touching
/// them turns the empty-state greeting into "Byte", and nothing else would have complained.
@MainActor
final class HostIdentityTests: XCTestCase {

    /// The character got its own name back so "Codepet · Engineering" cannot appear.
    func testByteIsNamedByte() throws {
        let byte = try XCTUnwrap(PetCharacter.all["byte"])
        XCTAssertEqual(byte.name, "Byte")
        XCTAssertNotEqual(byte.name, CodepetBrand.name,
                          "the product's voice and a department's voice would share a name")
    }

    /// The id is a Firestore key — `actor:'byte'`, `companionId`, and `char-byte` all read it.
    /// Only the display name moved.
    func testByteKeepsItsId() throws {
        let byte = try XCTUnwrap(PetCharacter.all["byte"])
        XCTAssertEqual(byte.id, "byte")
        XCTAssertEqual(byte.imageName, "char-byte")
        XCTAssertTrue(PetCharacter.starters.contains("byte"))
    }

    /// Byte now speaks for Engineering, so the header reads "Byte · Engineering".
    func testEngineeringSignsAsByte() throws {
        let pet = try XCTUnwrap(DepartmentCompanions.companionId(for: "eng"))
        let eng = try XCTUnwrap(DepartmentCatalog.find("eng"))
        XCTAssertEqual(DepartmentMenu.rowTitle(eng), "Byte · Engineering")
        XCTAssertEqual(PetCharacter.all[pet]?.name, "Byte")
    }

    /// The composer menu's "no department" row names the host. It used to say
    /// "Anyone — byte routes it", which after the recast would tell the founder that
    /// Engineering's pet routes everything.
    func testTheAnyoneRowNamesCodepetNotAPet() {
        for lang in [AppLanguage.en, AppLanguage.vi] {
            let label = DepartmentMenu.anyoneLabel(lang)
            XCTAssertTrue(label.contains(CodepetBrand.name),
                          "\(lang) label '\(label)' does not name the host")
            XCTAssertFalse(label.lowercased().contains("byte"),
                           "\(lang) label '\(label)' names a department pet as the router")
        }
    }
}

extension HostIdentityTests {
    /// The hero's beacon card says who can and cannot do a task, and it names the host in
    /// prose: "This one needs you — Codepet can only prepare it…". The product is what
    /// speaks there, so the name must be the brand, never a pet.
    ///
    /// This is the reachable half of the guard. Its other half is structural: `ChatEmptyState`
    /// no longer HAS a `hostName` — it passes `CodepetBrand.name` at the call site — so there
    /// is no resolved-from-companion value left to revert.
    func testTheBeaconNamesTheProductNotAPet() throws {
        // `who: .you` selects the one branch whose copy interpolates the host.
        let task = RoadmapTask(id: "t1", title: "Talk to five users",
                               detail: "", phase: .find, who: .you, dept: "eng")
        let offer = try XCTUnwrap(BeaconOffer.offer(for: task, in: [task],
                                                    host: CodepetBrand.name, language: .en))
        XCTAssertTrue(offer.detail.contains("Codepet"),
                      "the beacon detail '\(offer.detail)' does not name the host")
        XCTAssertFalse(offer.detail.contains("Byte"),
                       "a pet is claiming the product's line")
    }

    /// A run with no department is the product's own work, so every surface on that card
    /// names the product — not whichever pet happens to be the founder's companion.
    ///
    /// This is the test that was missing. `ChatExecLog` resolved its name by falling back to
    /// `company.companionId`, which rendered "Codepet" only while the byte character was
    /// displayed as "Codepet". After the rename the same card read "CODEPET" in its kicker and
    /// "Byte is doing the work…" one line below, and 2045 green tests said nothing.
    func testAHostlessRunIsNamedForTheProductNotThePet() {
        XCTAssertEqual(CodepetBrand.speakerName(companionId: nil), CodepetBrand.name)
        XCTAssertEqual(CodepetBrand.speakerName(companionId: ""), CodepetBrand.name)
        XCTAssertEqual(CodepetBrand.speakerName(companionId: "nope"), CodepetBrand.name)
        // And a real specialist still signs with its own name.
        XCTAssertEqual(CodepetBrand.speakerName(companionId: "byte"), "Byte")
        XCTAssertEqual(CodepetBrand.speakerName(companionId: "nova"), "Nova")
    }
}
