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
    ///
    /// **Amendment 4, 6 Sep — a deliberate, separately-flagged exception now exists.**
    /// `CODEPET_LIVE_AI` (see `liveAI` below) puts autoplay through the real model instead
    /// of `MockChat`'s canned replies — the founder asked for exactly that, having been
    /// shown the trade-offs (unpredictable 20-60s runs, real spend, a run that can fail
    /// mid-demo). That is precisely the shape this comment used to call unattended and
    /// unsafe, and it still would be BY ACCIDENT. So `CODEPET_LIVE_AI` is deliberately NOT
    /// added here: the implication between these three stays exactly what it was, and the
    /// accident above still cannot happen by default. Live mode is reached only by setting
    /// `CODEPET_LIVE_AI` on top of one of these three, never by any of these three alone —
    /// a guard that is silently bypassed is worse than one that is openly qualified.
    static let launchKeys = ["CODEPET_MOCK_CHAT", "CODEPET_MOCK_FLOW", "CODEPET_MOCK_AUTOPLAY"]

    #if DEBUG
    /// **Where the mode is read from — and the one reason this is a variable.**
    ///
    /// Every read below used `UserDefaults.standard`. The XCTest host IS the app, so it shares
    /// that domain, and a founder clicking the prototype-mode toggle changed what the test
    /// target exercised: six `CompanyChatClientTests` began receiving `MockChat` fixture text
    /// because `CompanyChatClient.sendStream` short-circuits on `MockChat.enabled` (issue #117).
    ///
    /// **The loud failure was the lucky one.** The same coupling means any test that would pass
    /// against fixtures and fail against the real client passes for the WRONG REASON whenever
    /// prototype mode is on, and a green run tells nobody.
    ///
    /// It also could not be diagnosed by inspection: the plist read `false` while the suite still
    /// saw mock data, because a running app holds the live value in `cfprefsd` and the test host
    /// reads through the same daemon. `defaults read` answers from an empty sandbox container
    /// while the unsandboxed app uses `~/Library/Preferences/app.murror.codepet.plist`, so it
    /// confirms the wrong answer twice over.
    ///
    /// **Under XCTest this defaults to a scratch suite, wiped on creation.** Isolation is
    /// automatic rather than opt-in on purpose: a per-suite `setUp` only protects the suites
    /// somebody remembered, and the dangerous case is the test nobody is looking at. Tests that
    /// want to exercise prototype-mode behaviour still write through this property and are still
    /// honoured — the seam is redirected, not disabled.
    ///
    /// Detecting the test host in app code is normally an anti-pattern. It is confined here to
    /// one `#if DEBUG` property behind a developer-only toggle, which is a smaller cost than a
    /// suite that can silently verify fixtures.
    static var store: UserDefaults = {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil else {
            return .standard
        }
        let name = "app.murror.codepet.tests.prototype"
        guard let scratch = UserDefaults(suiteName: name) else { return .standard }
        // Wiped on creation so a run never inherits the previous run's writes.
        scratch.removePersistentDomain(forName: name)
        return scratch
    }()

    /// **The launch arguments, as a seam** — the same reason `store` above is one.
    /// `isLocked` is the property that decides whether the UI offers a control at all, and
    /// `ProcessInfo.arguments` cannot be set from a test, so the lock could only ever be
    /// asserted in whichever direction the test runner happened to be launched. One test
    /// below used to branch on `isLocked` and assert nothing in the common case.
    static var arguments: [String] = ProcessInfo.processInfo.arguments

    /// Forced from the command line, and therefore not switchable this session.
    ///
    /// **`cp_prototypeMode` itself counts, not only the three declared flags.**
    /// `NSArgumentDomain` outranks every preference file for ANY key, so launching with
    /// `-cp_prototypeMode NO` pins `isOn` for the process exactly as a flag would. Reading
    /// only `launchKeys` missed that: the switch rendered live, `set` returned true, and
    /// `CompanyStore.setPrototypeMode`'s `on != isOn` guard swallowed every press in the
    /// direction the argument already held — returning `true` as it did so. That is a dead
    /// control reporting success, which is the one outcome this type was written to avoid.
    static var isLocked: Bool {
        if wasPassedAsArgument(key) { return true }
        return launchKeys.contains { store.bool(forKey: $0) && wasPassedAsArgument($0) }
    }

    /// **Which way a lock holds it**, or `nil` when nothing is locked.
    ///
    /// The caption has to name the direction. The three flags can only force the mode ON, so
    /// "held on by a launch argument" was always true before; a direct `-cp_prototypeMode NO`
    /// holds it OFF, and offering to "relaunch to switch off" something already off would put
    /// a second dead affordance on top of the first.
    static var lockedValue: Bool? { isLocked ? isOn : nil }

    static var isOn: Bool {
        if launchKeys.contains(where: { store.bool(forKey: $0) }) { return true }
        return store.bool(forKey: key)
    }

    /// `-CODEPET_LIVE_AI YES` (or the persisted key, read through `store` like everything
    /// else here): keeps every prototype fixture — the board, the nine-question chain, the
    /// departments — but swaps the chat/task/VC TRANSPORT off `MockChat`'s canned replies
    /// onto `LocalTransportRouter`, the founder's own Claude plan via the sidecars, the same
    /// path the real product uses.
    ///
    /// **Deliberately its own flag, not a fourth entry in `launchKeys`.** See that property's
    /// amended comment: live autoplay is the exact configuration the three-flag implication
    /// was built to prevent by accident, so it is entered only on purpose, by setting this
    /// flag ON TOP of one of the three — never implied by them, and never implying them back.
    /// Meaningless with all three off: nothing schedules a chat/task/VC call for it to swap.
    static var liveAI: Bool { store.bool(forKey: "CODEPET_LIVE_AI") }

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
        store.bool(forKey: "CODEPET_MOCK_FLOW")
            || store.bool(forKey: "CODEPET_MOCK_AUTOPLAY")
    }

    /// Ignored while locked — a launch argument wins, and pretending otherwise would
    /// leave the preference and the running app disagreeing about which one is true.
    @discardableResult
    /// **`-CODEPET_LIVE_AI` turns prototype mode on, once, WITHOUT locking the toggle.**
    ///
    /// Live mode means "run the prototype on my own Claude plan", which is meaningless with
    /// prototype mode off — so asking for it has to switch it on. The obvious way is to make
    /// `isOn` return true whenever `liveAI` is set, and that is wrong: the founder could then
    /// never switch it OFF, which is the exact complaint that started this. A computed
    /// implication is not a default, it is a lock wearing a different hat.
    ///
    /// So it SEEDS the stored preference instead, once at launch and only when the founder has
    /// no preference of her own yet. After that the toggle behaves normally in both directions.
    ///
    /// `CODEPET_LIVE_AI` stays out of `launchKeys` (see that property): the accident those
    /// three guard against — autoplay driving real Cloud Functions unattended — is unchanged,
    /// because live mode is fixtures plus a real transport, never a real board.
    ///
    /// Called once from `CodePetApp.init`. Idempotent: a second call finds the key set and
    /// leaves the founder's own choice alone.
    static func seedFromLiveAIFlag() {
        guard liveAI, !isLocked else { return }
        guard store.object(forKey: key) == nil else { return }   // she has already chosen
        store.set(true, forKey: key)
    }

    static func set(_ on: Bool) -> Bool {
        guard !isLocked else { return false }
        store.set(on, forKey: key)
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
        arguments.contains("-" + name)
    }
    #else
    static var isLocked: Bool { true }
    static var lockedValue: Bool? { false }
    static var isOn: Bool { false }
    static var liveAI: Bool { false }
    static var startsAtColdOpen: Bool { false }
    @discardableResult
    static func set(_ on: Bool) -> Bool { false }
    static func seedFromLiveAIFlag() {}
    static var allowsCloudWrites: Bool { true }
    #endif
}
