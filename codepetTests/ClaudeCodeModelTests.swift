import XCTest
@testable import codepet

/// The founder's model choice. What it costs is their quota now, which is the whole reason
/// the choice can be theirs — so these guard that the choice is honoured exactly and
/// nothing is substituted behind it.
final class ClaudeCodeModelTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "claude-model-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func preference() -> ClaudeCodeModelPreference {
        ClaudeCodeModelPreference(
            model: { [defaults] companyId in
                guard let raw = defaults!.string(forKey: ClaudeCodeModelPreference.key(companyId)),
                      let parsed = ClaudeCodeModel(rawValue: raw) else { return .inherit }
                return parsed
            },
            setModel: { [defaults] companyId, model in
                defaults!.set(model.rawValue, forKey: ClaudeCodeModelPreference.key(companyId))
            }
        )
    }

    // MARK: - Aliases

    /// Aliases, not pinned versions. A pinned `claude-opus-5` would quietly become last
    /// year's model when a new one ships and nothing here would notice; an alias tracks the
    /// latest of its tier. All four were verified against the real CLI on 2.1.241.
    func testEveryPickableModelSendsAnAlias() {
        XCTAssertEqual(ClaudeCodeModel.haiku.alias, "haiku")
        XCTAssertEqual(ClaudeCodeModel.sonnet.alias, "sonnet")
        XCTAssertEqual(ClaudeCodeModel.opus.alias, "opus")
        XCTAssertEqual(ClaudeCodeModel.fable.alias, "fable")
    }

    /// No alias means no `--model` flag at all, which is not the same as picking a model
    /// that happens to match their default: it leaves the decision where the founder already
    /// made it, in their own CLI.
    func testInheritSendsNoFlag() {
        XCTAssertNil(ClaudeCodeModel.inherit.alias)
    }

    /// A pinned version string here would be the bug this design avoids, so assert none
    /// crept in.
    func testNoAliasIsAPinnedVersion() {
        for model in ClaudeCodeModel.all {
            guard let alias = model.alias else { continue }
            XCTAssertFalse(alias.contains("-"), "\(alias) looks pinned, not an alias")
            XCTAssertFalse(alias.hasPrefix("claude"), "\(alias) looks like a full model id")
        }
    }

    // MARK: - Default and persistence

    /// Inherit is the default because a founder who set a model in their own CLI has already
    /// answered this question, and overriding that silently would be Codepet deciding
    /// something they decided.
    func testTheDefaultIsToInherit() {
        XCTAssertEqual(preference().model("c1"), .inherit)
    }

    func testAChoiceRoundTrips() {
        let pref = preference()
        pref.setModel("c1", .sonnet)
        XCTAssertEqual(pref.model("c1"), .sonnet)
    }

    func testEveryChoiceSurvivesStorage() {
        let pref = preference()
        for model in ClaudeCodeModel.all {
            pref.setModel("c1", model)
            XCTAssertEqual(pref.model("c1"), model)
        }
    }

    /// One Mac, two accounts: A's taste is not B's.
    func testOneFoundersChoiceDoesNotApplyToAnother() {
        let pref = preference()
        pref.setModel("c1", .opus)
        XCTAssertEqual(pref.model("c2"), .inherit)
    }

    /// A value written by an older or newer build that this one does not know must read as
    /// the default rather than crash or resolve to something arbitrary.
    func testAnUnknownStoredValueFallsBackToInherit() {
        defaults.set("gpt-9", forKey: ClaudeCodeModelPreference.key("c1"))
        XCTAssertEqual(preference().model("c1"), .inherit)
    }

    func testTheKeyIsPrefixedAndScoped() {
        let key = ClaudeCodeModelPreference.key("c1")
        XCTAssertTrue(key.hasPrefix("cp_"))
        XCTAssertTrue(key.contains("c1"))
    }

    // MARK: - Copy

    /// Each option says what it costs the founder, because it is their quota being spent.
    /// An option with no note is one they would pick blind.
    func testEveryOptionExplainsItselfInBothLanguages() {
        for model in ClaudeCodeModel.all {
            for lang in [AppLanguage.en, AppLanguage.vi] {
                XCTAssertFalse(model.title(lang).isEmpty, "\(model) has no title in \(lang)")
                XCTAssertFalse(model.note(lang).isEmpty, "\(model) has no note in \(lang)")
            }
        }
    }

    /// Fable's note must warn that a plan may not include it. It is the only option likely
    /// to fail for a paying founder, and the failure lands mid-conversation.
    func testFableWarnsThatAPlanMayNotHaveIt() {
        XCTAssertTrue(ClaudeCodeModel.fable.note(.en).lowercased().contains("may not"))
        XCTAssertTrue(ClaudeCodeModel.fable.note(.vi).lowercased().contains("chưa có"))
    }
}
