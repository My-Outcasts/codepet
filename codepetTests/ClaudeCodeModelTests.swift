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
                guard let raw = defaults!.string(forKey: ClaudeCodeModelPreference.modelKey(companyId)),
                      let parsed = ClaudeCodeModel(rawValue: raw) else { return .inherit }
                return parsed
            },
            setModel: { [defaults] companyId, model in
                defaults!.set(model.rawValue, forKey: ClaudeCodeModelPreference.modelKey(companyId))
            },
            effort: { [defaults] companyId in
                guard let raw = defaults!.string(forKey: ClaudeCodeModelPreference.effortKey(companyId)),
                      let parsed = ClaudeCodeEffort(rawValue: raw) else { return .inherit }
                return parsed
            },
            setEffort: { [defaults] companyId, effort in
                defaults!.set(effort.rawValue, forKey: ClaudeCodeModelPreference.effortKey(companyId))
            }
        )
    }

    // MARK: - Aliases

    /// Pinned ids, not aliases — the reversal the enum documents. A founder who wants Opus
    /// 4.6 specifically cannot ask an alias for it. Every one of these answered a real turn
    /// on 2.1.241 and reported itself back in `modelUsage`.
    func testEveryPickableModelSendsAPinnedId() {
        XCTAssertEqual(ClaudeCodeModel.fable5.flag, "claude-fable-5")
        XCTAssertEqual(ClaudeCodeModel.opus5.flag, "claude-opus-5")
        XCTAssertEqual(ClaudeCodeModel.sonnet5.flag, "claude-sonnet-5")
        XCTAssertEqual(ClaudeCodeModel.haiku45.flag, "claude-haiku-4-5")
        XCTAssertEqual(ClaudeCodeModel.opus48.flag, "claude-opus-4-8")
        XCTAssertEqual(ClaudeCodeModel.opus47.flag, "claude-opus-4-7")
        XCTAssertEqual(ClaudeCodeModel.opus46.flag, "claude-opus-4-6")
        XCTAssertEqual(ClaudeCodeModel.sonnet46.flag, "claude-sonnet-4-6")
    }

    /// Every case is offered somewhere. A model in the enum but in neither group is one the
    /// founder can never reach, and a stored value they can never change back to.
    func testEveryCaseIsReachableFromTheMenu() {
        let offered = Set([ClaudeCodeModel.inherit] + ClaudeCodeModel.current + ClaudeCodeModel.older)
        XCTAssertEqual(offered, Set(ClaudeCodeModel.allCases))
    }

    /// Effort passes through the same way, verified on 2.1.241 alongside every model above.
    func testEffortSendsItsLevelAndInheritSendsNothing() {
        XCTAssertNil(ClaudeCodeEffort.inherit.flag)
        XCTAssertEqual(ClaudeCodeEffort.high.flag, "high")
        XCTAssertEqual(ClaudeCodeEffort.max.flag, "max")
        XCTAssertEqual(Set(ClaudeCodeEffort.choices), Set(ClaudeCodeEffort.allCases))
    }

    func testAnEffortChoiceRoundTrips() {
        let pref = preference()
        pref.setEffort("c1", .xhigh)
        XCTAssertEqual(pref.effort("c1"), .xhigh)
        XCTAssertEqual(pref.effort("c2"), .inherit, "effort is per company too")
    }

    /// No alias means no `--model` flag at all, which is not the same as picking a model
    /// that happens to match their default: it leaves the decision where the founder already
    /// made it, in their own CLI.
    func testInheritSendsNoFlag() {
        XCTAssertNil(ClaudeCodeModel.inherit.flag)
    }

    /// An ALIAS here would now be the bug: it would drift to a different model under the
    /// founder without the menu ever changing, which is what pinning exists to prevent.
    func testNoFlagIsABareAlias() {
        for model in ClaudeCodeModel.allCases {
            guard let flag = model.flag else { continue }
            XCTAssertTrue(flag.hasPrefix("claude-"), "\(flag) is an alias, not a pinned id")
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
        pref.setModel("c1", .sonnet5)
        XCTAssertEqual(pref.model("c1"), .sonnet5)
    }

    func testEveryChoiceSurvivesStorage() {
        let pref = preference()
        for model in ClaudeCodeModel.allCases {
            pref.setModel("c1", model)
            XCTAssertEqual(pref.model("c1"), model)
        }
    }

    /// One Mac, two accounts: A's taste is not B's.
    func testOneFoundersChoiceDoesNotApplyToAnother() {
        let pref = preference()
        pref.setModel("c1", .opus5)
        XCTAssertEqual(pref.model("c2"), .inherit)
    }

    /// A value written by an older or newer build that this one does not know must read as
    /// the default rather than crash or resolve to something arbitrary.
    func testAnUnknownStoredValueFallsBackToInherit() {
        defaults.set("gpt-9", forKey: ClaudeCodeModelPreference.modelKey("c1"))
        XCTAssertEqual(preference().model("c1"), .inherit)
    }

    func testTheKeyIsPrefixedAndScoped() {
        let key = ClaudeCodeModelPreference.modelKey("c1")
        XCTAssertTrue(key.hasPrefix("cp_"))
        XCTAssertTrue(key.contains("c1"))
    }

    // MARK: - Copy

    /// Each option says what it costs the founder, because it is their quota being spent.
    /// An option with no note is one they would pick blind.
    func testEveryOptionExplainsItselfInBothLanguages() {
        for model in ClaudeCodeModel.allCases {
            for lang in [AppLanguage.en, AppLanguage.vi] {
                XCTAssertFalse(model.shortName.isEmpty, "\(model) has no short name")
                XCTAssertFalse(model.note(lang).isEmpty, "\(model) has no note in \(lang)")
            }
        }
    }

    /// Fable's note must warn that a plan may not include it. It is the only option likely
    /// to fail for a paying founder, and the failure lands mid-conversation.
    func testFableWarnsThatAPlanMayNotHaveIt() {
        XCTAssertTrue(ClaudeCodeModel.fable5.note(.en).lowercased().contains("may not"))
        XCTAssertTrue(ClaudeCodeModel.fable5.note(.vi).lowercased().contains("chưa có"))
    }
}
