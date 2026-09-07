// codepet/Demo/MockFlowPlayer.swift
#if DEBUG
import AppKit
import Combine
import Foundation
import SwiftUI
import os

/// Plays `MockFlowScript` against the real store — the prototype's `stepStory()`.
///
/// Gated on `-CODEPET_MOCK_AUTOPLAY YES`, which IMPLIES `CODEPET_MOCK_FLOW` the
/// same way `MockChat.flowEnabled` implies `enabled`: autoplay without the
/// fixtures behind it would either spend real credits or narrate an empty
/// company, and two flags where one is meaningless alone is a state you can get
/// half-right.
///
/// Timers, not `Task.sleep`: pausing has to stop the clock rather than let an
/// awaited sleep finish into a paused player, and jumping a chapter has to cancel
/// whatever was pending. Both are one-liners with a cancellable timer and neither
/// is with a detached sleep.
@MainActor
final class MockFlowPlayer: ObservableObject {

    /// Off by default. `CODEPET_MOCK_AUTOPLAY` implies the flow fixtures.
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "CODEPET_MOCK_AUTOPLAY") }

    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    /// The caption on screen, or nil when captions are off or nothing is playing.
    @Published private(set) var caption: String?
    /// Published rather than read from the shell, because `TwoModeShellView` owns
    /// `mode` as `@State` and the player cannot reach into it.
    @Published private(set) var requestedMode: WorkspaceMode?
    /// Subtitles, the prototype's `CC` toggle.
    @Published var captionsOn = true
    /// Slow / Steady / Brisk — the prototype's `PACE`.
    @Published var pace: Double = 1.0
    /// **Set once a scripted run fails or times out, and sticky for the rest of THIS
    /// playthrough.** Both scripts close on a caption that narrates unqualified success —
    /// day-one's "Ten questions in, and the board has moved.", the tour's "Every success
    /// needed the founder's approval" — text authored assuming every run before it landed.
    /// Under `CODEPET_LIVE_AI` a run can fail (see `reportRunFailure`), and a demo that
    /// plays that line anyway over a board that did NOT move is worse than one that stops:
    /// it tells the founder the product worked when it didn't. Read by
    /// `performCurrentAndCaption` to override exactly that closing line; every other
    /// beat's authored caption is untouched. Reset by `restart()` so a replay isn't
    /// haunted by the previous run's failure.
    @Published private(set) var hadRunFailure = false

    private var timer: Timer?
    private weak var store: CompanyStore?
    private var language: AppLanguage = .en

    private static let log = Logger(subsystem: "app.murror.codepet", category: "MockFlowPlayer")

    /// How long `.approveNewestDraft` will wait for a draft to exist before giving up and
    /// logging rather than silently no-op'ing.
    ///
    /// Bounded, not immediate: the beat used to check once and return if the run that
    /// precedes it hadn't produced its draft yet, which raced three real cases — Reduce
    /// Motion capping every beat at 0.8s, a Brisk pace below 1.0 shrinking the authored
    /// margin further, and `CODEPET_SLOW_RUNS`, which multiplies the run's OWN step timing
    /// (unaffected by the player's pace) by up to 20×. That last one sets the ceiling: a run
    /// is six exec steps at 420ms plus a 260ms settle (`CompanyStore.execStepNanos` /
    /// `execDoneBeatNanos`), so the slowest realistic run is 6*420ms*20 + 260ms*20 ≈ 55.6s.
    /// 90s leaves real headroom above that without ever hanging the player — past it the
    /// beat gives up loudly instead of waiting forever.
    private static let approvalWaitCeiling: TimeInterval = 90
    /// **`CODEPET_LIVE_AI`'s own ceiling — not a reuse of `approvalWaitCeiling`.** That one is
    /// sized off `CODEPET_SLOW_RUNS`'s worst case (a MOCKED run's own step timing, multiplied up
    /// to 20×). A live run answers a different question: it is the founder's own Claude plan
    /// replying for real, measured (Amendment 4, 6 Sep) at an unpredictable 20-60s with no
    /// multiplier to bound it. Reusing 90s here would be exactly the "one flag standing in for
    /// two meanings" mistake `PrototypeMode.launchKeys` was written to avoid — a mocked run's
    /// ceiling and a live run's answer different questions and must be free to diverge. 180s
    /// leaves 3× headroom above the measured worst case (60s) without ever hanging the player —
    /// past it the beat gives up loudly (see the timeout branch below) instead of waiting forever.
    private static let liveApprovalWaitCeiling: TimeInterval = 180
    private static let approvalPollInterval: UInt64 = 100_000_000  // 0.1s

    /// The in-flight `.approveNewestDraft` wait, if one is pending. Cancelled in `pause()`
    /// (and so by `restart()` and `jump()`, which both call it first) so a wait started
    /// before a pause/restart/jump can never land its approval into a player that has since
    /// stopped or moved on to a different beat — a wait that outlives a pause would be a new
    /// race, not a fix for this one.
    private var pendingWait: Task<Void, Never>?

    /// **Added for the artifact-lands-under-the-wrong-department race.** The in-flight wait for
    /// a `.runTask` beat's OWN run to resolve, if one is pending. Same shape as `pendingWait`
    /// above — bounded, cancellable, account-guarded, cancelled by `pause()` — but a SEPARATE
    /// slot rather than reusing `pendingWait`: `schedule(after:)` needs to know, at the moment
    /// it arms the beat's timer, whether THIS beat has a run to join before it may advance, and
    /// sharing one property with `.approveNewestDraft`'s wait would make that ambiguous (is the
    /// current occupant an approve-wait that should NOT gate advancing, or a run-wait that
    /// should?). Two properties, one scheme, applied twice — not two schemes.
    private var pendingRunWait: Task<Void, Never>?

    /// Which sequence is playing. The 24-beat tour by default; the day-one simulation when the
    /// day-one fixture is selected. A stored property rather than a computed one so a running
    /// player cannot have the script changed under it mid-beat — `private(set)` so that
    /// invariant is enforced by the compiler, not by convention.
    private(set) var script: [MockFlowScript.Beat] = DemoProject.current.id == "murror-day-one"
        ? DayOneScript.beats : MockFlowScript.beats
    var beats: [MockFlowScript.Beat] { script }
    var currentChapter: String? {
        guard index < beats.count else { return nil }
        return beats[index].chapter
    }

    /// The chapters of WHICHEVER script is playing, deduplicated in order — the chapter bar's
    /// jump buttons. `MockFlowScript.chapters` is computed from `MockFlowScript.beats` alone, so
    /// it always listed the tour's chapters even while the day-one simulation was playing.
    /// Mirrors that computation against `script` instead of duplicating it against `beats` a
    /// second time.
    var chapters: [String] {
        var seen = Set<String>()
        return script.compactMap { seen.insert($0.chapter).inserted ? $0.chapter : nil }
    }

    /// The index of the first beat of a chapter, within WHICHEVER script is playing.
    func firstBeat(of chapter: String) -> Int? {
        script.firstIndex { $0.chapter == chapter }
    }

    func attach(store: CompanyStore, language: AppLanguage) {
        self.store = store
        self.language = language
    }

    // MARK: - Transport

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        step()
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        // See `pendingWait`'s doc comment: this is what makes a bounded wait safe
        // across pause/restart/jump instead of just bounded.
        pendingWait?.cancel()
        pendingWait = nil
        pendingRunWait?.cancel()
        pendingRunWait = nil
    }

    func toggle() { isPlaying ? pause() : play() }

    /// Restart from the top. Does NOT reset the company — the fixtures are
    /// process-lifetime and a replay over a company that already approved the
    /// draft would narrate "nothing has been filed yet" over a full Library.
    /// Relaunching is how you get a clean first run, exactly as `flowOnboarded`
    /// documents for the flow flag.
    func restart() {
        pause()
        index = 0
        caption = nil
        hadRunFailure = false
    }

    func jump(toChapter chapter: String) {
        guard let i = firstBeat(of: chapter) else { return }
        let wasPlaying = isPlaying
        pause()
        index = i
        if wasPlaying { play() } else { performCurrentAndCaption() }
    }

    // MARK: - The clock

    private func step() {
        guard isPlaying else { return }
        guard index < beats.count else {
            // Ends where the prototype ends: stopped on the last caption rather
            // than looping, so the closing line stays readable.
            isPlaying = false
            return
        }
        let beat = beats[index]
        performCurrentAndCaption()
        let seconds = beat.seconds
        index += 1
        // **The race this guards.** `.runTask` used to fire `Task { await store.runTask(...) }`
        // and let the TIMER below advance the player on the beat's authored `seconds` regardless
        // — fine in mock mode, where a run finishes in ~2.5s against a 2.6s beat, but under
        // `CODEPET_LIVE_AI` a real run takes 20-60s and the player was already several beats and
        // departments further along by the time the draft actually landed in chat: the founder's
        // own screenshot, a Sales artifact appearing under Support's message.
        //
        // `armRunTaskWait` arms `pendingRunWait` for THIS beat; `schedule(after:)` below is what
        // actually joins it — see that function's comment for why waiting is a JOIN against the
        // timer rather than something stacked after it.
        if case .runTask(let id) = beat.intent {
            armRunTaskWait(taskId: id, beatIndex: index - 1)
        } else {
            // A non-`.runTask` beat has nothing to join — clearing this stops a stale, already-
            // resolved wait from a PRIOR run beat from being re-captured by `schedule` below.
            pendingRunWait = nil
        }
        schedule(after: seconds)
    }

    /// Arms `pendingRunWait`: a bounded, cancellable, account-guarded wait for `taskId` to leave
    /// `runningTaskIds` — i.e. for its run to be DONE, success or failure either way. Extends the
    /// same shape `.approveNewestDraft`'s wait (`pendingWait`) already uses — the two ceilings,
    /// the poll interval, the account re-check, `.public` logging on timeout, `reportRunFailure`
    /// — rather than inventing a second waiting scheme; only the READY condition differs, and
    /// only because a run beat isn't waiting for a draft to appear, it's waiting for itself to
    /// finish.
    private func armRunTaskWait(taskId: String, beatIndex: Int) {
        let isLiveRun = MockChat.enabled && PrototypeMode.liveAI
        let ceiling = isLiveRun ? Self.liveApprovalWaitCeiling : Self.approvalWaitCeiling
        pendingRunWait?.cancel()
        pendingRunWait = Task { [weak self] in
            guard let self, let cid = self.store?.companyId else { return }
            let deadline = Date().addingTimeInterval(ceiling)
            while !Task.isCancelled {
                // Re-checked every pass, matching every sibling wait in this file: an account
                // switch mid-run must bail rather than advance the player against the new
                // account's state.
                guard let store = self.store, store.companyId == cid else { return }
                guard store.runningTaskIds.contains(taskId) else { return }  // done — success or failure
                guard Date() < deadline else {
                    Self.log.error("runTask: still running after \(ceiling, privacy: .public)s at beat \(beatIndex, privacy: .public), task \(taskId, privacy: .public) — advancing without it")
                    self.reportRunFailure(
                        "This run took too long and timed out — nothing was filed for this step.")
                    return
                }
                try? await Task.sleep(nanoseconds: Self.approvalPollInterval)
            }
        }
    }

    /// Arms `pendingRunWait` for a LIVE CHAT REPLY rather than a run — same shape, same
    /// ceilings, same account re-check, different ready condition: a reply is done when the
    /// store stops streaming and stops showing the typing indicator.
    ///
    /// Reuses `pendingRunWait` deliberately. `schedule(after:)` already joins that handle
    /// before stepping, so a reply gets the same "do not advance past your own beat" guarantee
    /// runs and approvals now have — and a third handle would be a third thing to forget to
    /// join. Measured: a live reply streams in ~13s, well inside the mock ceiling.
    private func armChatReplyWait(beatIndex: Int) {
        let ceiling = Self.liveApprovalWaitCeiling
        pendingRunWait?.cancel()
        pendingRunWait = Task { [weak self] in
            guard let self, let cid = self.store?.companyId else { return }
            let deadline = Date().addingTimeInterval(ceiling)
            // The turn has not necessarily STARTED streaming the instant this arms, so a naive
            // "stop when not streaming" would return immediately. Wait for it to begin (or for
            // the reply to have already landed) before waiting for it to end.
            var started = false
            while !Task.isCancelled {
                guard let store = self.store, store.companyId == cid else { return }
                let busy = store.isStreaming || store.isCompanionTyping
                if busy { started = true }
                if started && !busy { return }
                guard Date() < deadline else {
                    Self.log.error("liveReply: no reply after \(ceiling, privacy: .public)s at beat \(beatIndex, privacy: .public) — advancing without it")
                    self.reportRunFailure(
                        "That reply didn't come back — this step has nothing behind it.")
                    return
                }
                try? await Task.sleep(nanoseconds: Self.approvalPollInterval)
            }
        }
    }

    private func schedule(after seconds: Double) {
        timer?.invalidate()
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Reduce Motion shortens the beats rather than disabling the walkthrough —
        // the captions are the content, and the motion is only the pacing.
        let delay = reduce ? min(seconds, 0.8) : seconds * pace
        // Captured NOW, not read from `self.pendingRunWait` inside the timer's closure later:
        // by the time the timer fires, a LATER beat could have armed (or cleared) a different
        // wait, and this beat must join only the one that was actually pending for IT.
        //
        // **A join, not a second delay stacked after the first.** The timer already fires on the
        // beat's own authored `seconds` — that has not changed, and in mock mode the run beneath
        // it (~2.5s) is normally already done well before this fires, so `await runWait?.value`
        // resolves instantly and the player advances exactly when it always did. Only when the
        // run outlasts the beat's authored `seconds` (`CODEPET_LIVE_AI`'s 20-60s against a 2.6s
        // beat) does this actually hold the player — which is the fix, not a tax on the common
        // case.
        let runWait = pendingRunWait
        // **The approval wait has to be joined too, and leaving it out was half a fix.**
        // `.runTask` waiting made the RUN land in its own chapter, but `.approveNewestDraft`
        // arms `pendingWait` and was still orphaned — the player advanced on the beat's
        // authored seconds while the approval was in flight. So a department's draft sat
        // UNAPPROVED (and therefore unfiled) while the next department's beats played, and
        // `offerChainIfNeeded` — which fires on an unfiled dependency, not an unfinished one —
        // truthfully reported "Byte hasn't produced it yet" under a card of Byte's work that
        // was visible on screen at that moment. The founder photographed exactly that.
        //
        // Worse, `pendingApproval?.cancel()` means the NEXT approve beat cancels this one, so
        // a slow approval was not merely late — it never happened at all, and its task stayed
        // drafted for the rest of the run.
        let approvalWait = pendingWait
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await runWait?.value
                await approvalWait?.value
                self?.step()
            }
        }
    }

    private func performCurrentAndCaption() {
        guard index < beats.count else { return }
        let beat = beats[index]
        // The closing beat of either script is the one line that narrates the WHOLE
        // walkthrough as landed — it is authored for the case where nothing above it
        // failed. `hadRunFailure` means that assumption is false, so this is not the
        // moment to play it: same principle as the timeout branch, applied to the one
        // beat that would otherwise claim a completion the founder didn't get.
        if hadRunFailure, index == beats.count - 1 {
            caption = captionsOn
                ? "This walkthrough didn't finish as scripted — a run above failed, so the board hasn't moved as far as this story expects."
                : nil
        } else {
            caption = captionsOn ? beat.caption : nil
        }
        perform(beat.intent, chapter: beat.chapter)
    }

    // MARK: - Intents

    /// Performs one intent against the store.
    ///
    /// Every branch is a no-op when its precondition is missing rather than a
    /// crash or a lie: a beat is never load-bearing (the prototype wraps each
    /// action in a bare `try/catch` for the same reason). A tour that stops dead
    /// because one fixture moved is worse than one that narrates past it.
    ///
    /// Internal, not `private`: `@testable import` lets a test drive a SINGLE intent
    /// directly (`.petSays(deptKey:line:)` in particular) without going through the
    /// Timer-scheduled `play()`, which is real `Foundation`/`AppKit` run-loop machinery
    /// a test has no business depending on just to prove which method a beat calls.
    ///
    /// `chapter` defaults to nil so every existing direct call (`DayOneBridgeTests` drives
    /// `.petSays(deptKey: "mkt", ...)` this way) keeps resolving exactly as before — only
    /// `.petSays` reads it, and only to pick between Byte's original chapter and one of its
    /// Amendment 3 encores (see `DayOneScript.extraAppearances`).
    func perform(_ intent: MockFlowScript.Intent, chapter: String? = nil) {
        guard let store else { return }
        switch intent {
        case .hold:
            break
        case .mode(let m):
            requestedMode = m
        case .go(let view):
            store.select(view)
        case .newChat:
            store.newChat()
            store.view = TwoModeLayout.newChatDestination
        case .say(let text):
            store.view = .chat
            Task { await store.sendChat(text, language: language) }
        case .runBeacon:
            store.view = .chat
            guard let task = RoadmapEngine.nextStep(store.company.tasks) else { return }
            Task { await store.runTask(task, language: language) }
        case .approveNewestDraft:
            // Waits for the draft rather than racing it — see `pendingWait` and
            // `approvalWaitCeiling`. `beatIndex` is captured now (not read from `self.index`
            // inside the task later, by which point later beats may have advanced it) purely
            // so a timeout's log line names the beat that actually stalled.
            let beatIndex = index
            // The run this beat is waiting on went out over `CODEPET_LIVE_AI` — see
            // `liveApprovalWaitCeiling`'s comment for why that gets its own, larger bound
            // rather than sharing `approvalWaitCeiling`. Read once, at the wait's start: the
            // flag does not change mid-wait, and every other seam here reads it at the point
            // the decision is made rather than mid-flight.
            let isLiveRun = MockChat.enabled && PrototypeMode.liveAI
            let ceiling = isLiveRun ? Self.liveApprovalWaitCeiling : Self.approvalWaitCeiling
            pendingWait?.cancel()
            pendingWait = Task { [weak self] in
                guard let self, let cid = self.store?.companyId else { return }
                let deadline = Date().addingTimeInterval(ceiling)
                while !Task.isCancelled {
                    // Re-read `self.store` (rather than close over the `store` this `perform`
                    // call already unwrapped) each pass, matching how every sibling `Task {}`
                    // in this file and `CompanyStore` re-checks `companyId == cid`: an account
                    // switch mid-wait must bail rather than approve into the new account.
                    guard let store = self.store, store.companyId == cid else { return }
                    if let id = self.newestDraftMessageId(in: store) {
                        await store.approveDraft(messageId: id)
                        return
                    }
                    // **A run that already ENDED without a draft failed — it did not merely
                    // take a while.** `runningTaskIds` is inserted at the top of
                    // `CompanyStore.runTask` and only removed after `produceDraftInline`
                    // returns — success or failure — and that path always spends several
                    // hundred ms on its own exec-step reveal first. So an empty set here can
                    // never be this beat's run not having started yet; it is that run having
                    // already finished (an instant 401, an offline sidecar, whatever) and
                    // posted its own honest "Couldn't generate…" bubble to chat with no draft
                    // behind it. Reported immediately, on the shape Task 2's diagnosis
                    // actually produced, instead of silently waiting out the full ceiling for
                    // a run that already told the founder it failed.
                    if store.runningTaskIds.isEmpty {
                        Self.log.error("approveNewestDraft: run ended with no draft at beat \(beatIndex, privacy: .public) — treating as a failed run, not a stall")
                        self.reportRunFailure(
                            "This run didn't produce anything — nothing was filed for this step.")
                        return
                    }
                    guard Date() < deadline else {
                        // A genuine stall: something is still running and never finished
                        // inside the ceiling. `runningTaskIds` names it, for the same reason
                        // the fast-fail branch above names the beat.
                        let stillRunning = store.runningTaskIds.sorted().joined(separator: ", ")
                        Self.log.error("approveNewestDraft: no draft after \(ceiling, privacy: .public)s at beat \(beatIndex, privacy: .public) — still running: \(stillRunning.isEmpty ? "none" : stillRunning, privacy: .public) — nothing filed")
                        self.reportRunFailure(
                            "This run took too long and timed out — nothing was filed for this step.")
                        return
                    }
                    try? await Task.sleep(nanoseconds: Self.approvalPollInterval)
                }
            }
        case .convene(let ask):
            store.view = .chat
            // Nothing on the wire under plain prototype mode, because `vcRunner` resolves to
            // `MockVirtualCompany` whenever `MockChat.usesMockTransport`. Under `CODEPET_LIVE_AI`
            // that is deliberately no longer true — this beat convenes a real room on the
            // founder's own Claude plan, same as `.runTask`/`.runBeacon` now run a real task.
            Task { await store.sendChat(ask, language: language, convenesRoom: true) }
        case .linkDemoFolder:
            // A real directory with a real file: `ProjectProbe` reads the disk, so an
            // invented path would link something that does not exist and the pane
            // would wake up describing nothing.
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("codepet-walkthrough", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("SignupView.swift")
            if !FileManager.default.fileExists(atPath: file.path) {
                try? "// demo target for the walkthrough\nstruct SignupView {}\n"
                    .write(to: file, atomically: true, encoding: .utf8)
            }
            // **A second seed, because two scripts ask this folder for different things.**
            // The 24-beat tour runs "fix the signup validation" against the Swift stub above.
            // Day one runs "build the Murror landing page" — and under `CODEPET_LIVE_AI` that
            // is now a REAL coding agent, which would otherwise be asked for a landing page in
            // a directory containing one Swift struct and would produce something real and
            // incoherent. Seeding a page it can actually edit is what keeps the live run's
            // output belonging to the story the caption is telling.
            let page = dir.appendingPathComponent("index.html")
            if !FileManager.default.fileExists(atPath: page.path) {
                try? """
                <!doctype html>
                <title>Murror</title>
                <h1>Murror</h1>
                <p>AI that brings people closer.</p>
                """.write(to: page, atomically: true, encoding: .utf8)
            }
            Self.prepareWalkthroughRepo(at: dir.path)
            // **Always this folder, even when something is already linked.** The guard
            // used to be `activeProjectLink == nil`, which reads as politeness and is
            // the opposite: the link is restored from a bookmark at launch, so on any
            // Mac where the founder had linked their own project, the walkthrough
            // skipped this beat and then ran a coding beat — branch, edit and all —
            // against their actual repo, unattended. A demo works on demo material.
            //
            // `bootstrapClaudeMd: false`, always. The consent rule is that a CLAUDE.md
            // is never written without an explicit yes, and an unattended walkthrough
            // cannot give one on the founder's behalf.
            _ = store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        case .codeRun(let ask):
            store.view = .chat
            guard store.activeProjectLink != nil else { return }
            store.startCodeRun(ask: ask)
        case .confirmCodeRun:
            // A multi-file change stops on the plan preview and waits, and the pane is
            // what starts it — nothing in the app did until now, so this beat's absence
            // is why the walkthrough sat on `PREPARING` for the whole chapter.
            guard store.codingRun.run?.phase == .previewing else { return }
            Task { await store.codingRun.execute() }
        case .approveCodeRun:
            guard let run = store.codingRun.run, !run.diffs.isEmpty else { return }
            // `acceptedPaths`, not `diffs.map(\.path)`: the coordinator keeps these
            // relative to the commit root and the apply step re-joins them to it.
            // Absolute paths made every file miss and the beat ended in a failure card.
            Task { await store.codingRun.approve(acceptedPaths: run.acceptedPaths) }
        case let .petSays(deptKey, line):
            store.view = .chat
            // An unmapped department returns without posting rather than posting
            // unattributed — same fallthrough `.petAsks` had.
            guard let companionId = DepartmentCompanions.companionId(for: deptKey),
                  let dept = DepartmentCatalog.find(deptKey),
                  let text = DayOneScript.line(for: deptKey, line, language: language, chapter: chapter)
            else { return }
            // Amendment, 6 Sep: `asks` is the FOUNDER's own question — no speaker row, no
            // companion attribution. `frames`/`reports` are still the department answering,
            // unchanged.
            // **The founder writes the script; Codepet's answer runs in real time.**
            // Founder decision, 7 Sep. `asks` is her own question and stays authored in both
            // modes — that IS the script. Under `CODEPET_LIVE_AI` the department's answer is
            // generated instead of read from `DayOneScript`: `sendChat` posts her question and
            // streams a real reply from that department's specialist (~13s, measured), through
            // the same path the shipping product uses.
            //
            // `frames` is SKIPPED live rather than posted, because the live reply IS the
            // answer it used to stand in for — posting both would have the department answer
            // twice, once for real and once from a fixture.
            //
            // `reports` stays authored even live, and that is a deliberate exception: those
            // lines carry the chain's hand-off ("Luna's turn: now we know who…"), and a
            // generated reply cannot be relied on to name the next department. Losing that
            // would cost the sequence the thing that makes it read as one company rather than
            // eight unrelated segments. Stated here rather than silently dropped.
            let live = MockChat.enabled && PrototypeMode.liveAI
            if line == .asks {
                if live {
                    let beatIndex = index
                    // **Never arm the department chip for Engineering here.**
                    // `sendChat` checks `EditCodeRouting.shouldRoute(department:projectLinked:)`
                    // — `department?.key == "eng" && projectLinked` — BEFORE it does anything
                    // else, and diverts the whole turn into `startCodeRun`. The `Code · Byte`
                    // chapter asks its question AFTER `.linkDemoFolder` has run, so arming the
                    // chip there would silently start a coding run instead of speaking a line:
                    // the beat would look like it did nothing and the demo would lurch.
                    //
                    // That check reads the RAW argument, not a resolved specialist, so passing
                    // nil avoids it entirely — and the reply is still attributed correctly,
                    // because `speakerFor` falls back to the department NAMED in the text and
                    // every one of these questions names its own department's work.
                    let armed = dept.key == "eng" ? nil : dept
                    Task { await store.sendChat(text, language: language, department: armed) }
                    armChatReplyWait(beatIndex: beatIndex)
                } else {
                    store.postScriptedFounderMessage(text)
                }
            } else if line == .frames {
                if !live {
                    store.postScriptedCompanionMessage(text, companionId: companionId, deptName: dept.name)
                }
            } else if live, let instruction = DayOneScript.liveInstruction(chapterDept: deptKey) {
                // `reports` used to stay authored even live, to keep the chain's hand-off. The
                // instruction now carries the hand-off instead — it names the next department
                // explicitly — so the line can be genuinely generated without the sequence
                // falling apart into eight unrelated segments. `text` is the fallback: a dead
                // transport degrades to the authored demo, not to a hole in the conversation.
                let beatIndex = index
                Task {
                    await store.postLiveLine(instruction: instruction, fallback: text,
                                             language: language, companionId: companionId,
                                             deptName: dept.name, deptKey: deptKey)
                }
                armChatReplyWait(beatIndex: beatIndex)
            } else {
                store.postScriptedCompanionMessage(text, companionId: companionId, deptName: dept.name)
            }
        case .opening(let line):
            store.view = .chat
            let text = DayOneScript.openingText(line)
            // `founderReply` is the founder's own words — `role: .me`, right-aligned, exactly
            // like `.petSays(line: .asks)`. `summary`/`prompt`/`setup` are the PRODUCT talking:
            // no companion, no department — see `postScriptedHostMessage`.
            let live = MockChat.enabled && PrototypeMode.liveAI
            if line == .founderReply {
                // Her words. Never generated, in either mode — that is the script.
                store.postScriptedFounderMessage(text)
            } else if live, let instruction = DayOneScript.openingInstruction(line) {
                // Codepet opening the conversation before she has said anything. `sendChat`
                // cannot serve this: it would have to invent a founder message to reply to.
                let beatIndex = index
                Task {
                    await store.postLiveLine(instruction: instruction, fallback: text,
                                             language: language)
                }
                armChatReplyWait(beatIndex: beatIndex)
            } else {
                store.postScriptedHostMessage(text)
            }
        case .walkthroughFounderTask:
            store.view = .chat
            // The first founder-only task still open. `BeaconOffer.candidates` is the
            // same ordered list the hero's card walks, so the beat asks about the task
            // the founder would actually have been offered — not an arbitrary one.
            guard let task = BeaconOffer.candidates(store.company.tasks)
                .first(where: { $0.who == .you }) else { return }
            let ask = WalkthroughAsk.compose(for: task, language: language)
            Task {
                await store.sendChat(ask.text, language: language, aboutTask: ask.task)
            }
        case .runTask(let id):
            store.view = .chat
            // The same three guards `runTask` enforces. A beat that fires on a task already
            // running or drafted would produce a second draft and double the credits.
            guard let task = store.company.tasks.first(where: { $0.id == id }),
                  !task.done, !task.drafted else { return }
            Task { await store.runTask(task, language: language) }
        case .recordFounderTask(let taskId):
            store.view = .chat
            guard let task = store.company.tasks.first(where: { $0.id == taskId }) else { return }
            let entry = DemoProject.current.deliverable(for: task.title)
            let body = MockChat.fill(entry.body, title: task.title)
            Task { await store.recordFounderOutcome(taskId: taskId, body: body,
                                                    kind: DeliverableKind(raw: entry.kind)) }
        }
    }

    /// Make the walkthrough's scratch folder a real git repo, with one commit.
    ///
    /// **Because the story's biggest claim is about a branch.** "Approving commits to
    /// a branch and stops there" is the ceiling this product sells, and on a plain
    /// folder the app takes the shadow backend instead — no branch, the session bar
    /// reads `not a git repo`, and the beat narrates a safety guarantee the screen is
    /// not demonstrating. `git init` costs two subprocesses in a temp directory and
    /// makes the claim true.
    ///
    /// Identity is pinned with `-c` rather than written to a config: the commit must
    /// not depend on the founder having `user.email` set globally, and a walkthrough
    /// has no business editing anyone's git identity. Every failure is soft — if git
    /// is missing or refuses, the folder still links and the run still happens on the
    /// shadow backend. Degraded, not broken.
    /// It also has to survive a REPLAY. The scratch folder outlives the process, so a
    /// second walkthrough finds it sitting on the `codepet/*` branch the first one
    /// made — and `beginGit` does `checkout -b <same name>`, which fails on an
    /// existing branch and ends the chapter on "Couldn't start a git branch". Put it
    /// back the way a first run finds it.
    private static func prepareWalkthroughRepo(at path: String) {
        // Only ever this folder. Every destructive git verb below is safe solely
        // because of where it points, so the guard is on the path and not on intent.
        let expected = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codepet-walkthrough", isDirectory: true)
            .standardizedFileURL.path
        guard URL(fileURLWithPath: path).standardizedFileURL.path == expected else { return }

        if GitRunner.run(["rev-parse", "--is-inside-work-tree"], in: path).ok {
            _ = GitRunner.run(["checkout", "--force", "main"], in: path)
            _ = GitRunner.run(["reset", "--hard"], in: path)
            _ = GitRunner.run(["clean", "-fd"], in: path)
            let branches = GitRunner.run(["for-each-ref", "--format=%(refname:short)",
                                          "refs/heads/codepet"], in: path)
                .stdout.split(whereSeparator: \.isNewline).map(String.init)
            for branch in branches { _ = GitRunner.run(["branch", "-D", branch], in: path) }
            return
        }
        guard GitRunner.run(["init", "-b", "main"], in: path).ok else { return }
        _ = GitRunner.run(["add", "."], in: path)
        _ = GitRunner.run(["-c", "user.name=Codepet Walkthrough",
                           "-c", "user.email=walkthrough@codepet.local",
                           "commit", "-m", "the folder as it was before Codepet touched it"],
                          in: path)
    }

    /// Surface a failed/timed-out run **on screen, not just in the log.** A demo that
    /// silently skips a beat reads as a product that lost the work — this reuses the same
    /// caption surface every other beat narrates through, rather than inventing a second
    /// one. Left up until the next beat's own `performCurrentAndCaption` overwrites it,
    /// same as any other caption. Also flips `hadRunFailure`, which is the sticky half of
    /// this fix — see its doc comment.
    private func reportRunFailure(_ message: String) {
        hadRunFailure = true
        guard captionsOn else { return }
        caption = message
    }

    /// The newest reply carrying a draft that is still awaiting approval. Searched
    /// from the end, because a walkthrough that ran two tasks would otherwise
    /// approve the first — and `draftApproved` is checked so a replay cannot
    /// "approve" something already filed.
    private func newestDraftMessageId(in store: CompanyStore) -> String? {
        store.chatMessages.last { $0.draft != nil && !$0.draftApproved }?.id
    }
}
#endif
