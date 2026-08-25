// codepet/Models/PrototypeMode.swift
import Foundation

/// Prototype mode: the whole product on fixtures, switchable from inside the app.
///
/// It already existed as `-CODEPET_MOCK_CHAT` / `-CODEPET_MOCK_FLOW` /
/// `-CODEPET_MOCK_AUTOPLAY`, which meant quitting and relaunching to move between
/// the demo and the real thing. This is the same three flags behind one switch that
/// can be thrown at runtime.
///
/// **Two things had to be true before a button was safe.**
///
/// 1. **Nothing fixture-shaped may reach the founder's account.** The `save*`
///    functions write to `companies/{uid}` and were never gated on the mock flag —
///    tolerable for a launch argument you opt into deliberately, not for a switch in
///    a menu. `allowsCloudWrites` is that gate, and it is checked in `CompanyData`
///    rather than at the call sites so a new saver is covered by default.
/// 2. **A switch that cannot switch has to say so.** `NSArgumentDomain` outranks
///    every preference file, so when the app is launched with one of the flags, no
///    write to `UserDefaults` can turn it off. That is not a bug to route around —
///    it is the same precedence that makes the launch args reliable — so the mode is
///    reported as LOCKED and the UI renders it disabled with the reason, instead of
///    offering a control that silently does nothing.
///
/// `#if DEBUG` throughout, because the fixtures it switches to are.
enum PrototypeMode {

    /// The persisted preference — only consulted when no launch argument is present.
    static let key = "cp_prototypeMode"

    /// The launch arguments that force it on. Any one of them implies the others:
    /// autoplay without the fixtures behind it would drive the real Cloud Functions
    /// unattended, and two flags where one is meaningless alone is a state you can
    /// get half-right.
    static let launchKeys = ["CODEPET_MOCK_CHAT", "CODEPET_MOCK_FLOW", "CODEPET_MOCK_AUTOPLAY"]

    #if DEBUG
    /// Forced on from the command line, and therefore not switchable this session.
    static var isLocked: Bool {
        launchKeys.contains { UserDefaults.standard.bool(forKey: $0) && wasPassedAsArgument($0) }
    }

    static var isOn: Bool {
        if launchKeys.contains(where: { UserDefaults.standard.bool(forKey: $0) }) { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// **Whether the demo starts at the COLD OPEN**, which is not the same question
    /// as whether fixtures are on — and collapsing the two was a regression CI caught
    /// on the first full run of the suite.
    ///
    /// `-CODEPET_MOCK_CHAT` alone boots an ALREADY-ONBOARDED company; that is what
    /// makes chat and engineering reachable in a single launch, and it is the mode
    /// most of the mock work uses. `-CODEPET_MOCK_FLOW` / `-CODEPET_MOCK_AUTOPLAY`
    /// additionally rewind to onboarding, which is the one stretch of the product a
    /// plain mock has never been able to show. Making `MockChat.flowEnabled` follow
    /// `isOn` sent plain mock mode into the cold open — `MockFlowTests` names exactly
    /// that and went red.
    ///
    /// Deliberately NOT satisfied by the runtime switch: dropping a founder
    /// mid-session into a first-run flow they did not ask for reads as the app losing
    /// their account. Flipping the toggle gives fixtures and the walkthrough controls;
    /// launching with the flag is what starts the story at the beginning.
    static var startsAtColdOpen: Bool {
        UserDefaults.standard.bool(forKey: "CODEPET_MOCK_FLOW")
            || UserDefaults.standard.bool(forKey: "CODEPET_MOCK_AUTOPLAY")
    }

    /// Ignored while locked — a launch argument wins, and pretending otherwise would
    /// leave the preference and the running app disagreeing about which one is true.
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        guard !isLocked else { return false }
        UserDefaults.standard.set(on, forKey: key)
        return true
    }

    /// **The safety gate.** Fixture tasks, fixture deliverables and a fixture brief
    /// must never be written to a real company document. In prototype mode the whole
    /// company lives in memory and is rebuilt from fixtures on every load, so there
    /// is nothing worth persisting and a great deal worth not persisting.
    static var allowsCloudWrites: Bool { !isOn }

    /// Whether the argument came from the COMMAND LINE rather than from a
    /// preference someone wrote. `UserDefaults.bool(forKey:)` cannot tell them
    /// apart — the argument domain is layered under the same lookup — so the flag's
    /// presence in `ProcessInfo` is the only way to know the switch is outranked.
    private static func wasPassedAsArgument(_ name: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains("-" + name)
    }
    #else
    static var isLocked: Bool { true }
    static var isOn: Bool { false }
    static var startsAtColdOpen: Bool { false }
    @discardableResult
    static func set(_ on: Bool) -> Bool { false }
    static var allowsCloudWrites: Bool { true }
    #endif
}
