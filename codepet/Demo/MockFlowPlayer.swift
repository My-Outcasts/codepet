// codepet/Demo/MockFlowPlayer.swift
#if DEBUG
import AppKit
import Combine
import Foundation
import SwiftUI

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

    private var timer: Timer?
    private weak var store: CompanyStore?
    private var language: AppLanguage = .en

    /// Which sequence is playing. The 24-beat tour by default; the day-one simulation when the
    /// day-one fixture is selected. A stored property rather than a computed one so a running
    /// player cannot have the script changed under it mid-beat.
    var script: [MockFlowScript.Beat] = DemoProject.current.id == "murror-day-one"
        ? DayOneScript.beats : MockFlowScript.beats
    var beats: [MockFlowScript.Beat] { script }
    var currentChapter: String? {
        guard index < beats.count else { return nil }
        return beats[index].chapter
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
    }

    func jump(toChapter chapter: String) {
        guard let i = MockFlowScript.firstBeat(of: chapter) else { return }
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
        performCurrentAndCaption()
        let seconds = beats[index].seconds
        index += 1
        schedule(after: seconds)
    }

    private func schedule(after seconds: Double) {
        timer?.invalidate()
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Reduce Motion shortens the beats rather than disabling the walkthrough —
        // the captions are the content, and the motion is only the pacing.
        let delay = reduce ? min(seconds, 0.8) : seconds * pace
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
    }

    private func performCurrentAndCaption() {
        guard index < beats.count else { return }
        let beat = beats[index]
        caption = captionsOn ? beat.caption : nil
        perform(beat.intent)
    }

    // MARK: - Intents

    /// Performs one intent against the store.
    ///
    /// Every branch is a no-op when its precondition is missing rather than a
    /// crash or a lie: a beat is never load-bearing (the prototype wraps each
    /// action in a bare `try/catch` for the same reason). A tour that stops dead
    /// because one fixture moved is worse than one that narrates past it.
    private func perform(_ intent: MockFlowScript.Intent) {
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
            guard let id = newestDraftMessageId(in: store) else { return }
            Task { await store.approveDraft(messageId: id) }
        case .convene(let ask):
            store.view = .chat
            // Safe under the demo flags only because `vcRunner` resolves to
            // `MockVirtualCompany` when `MockChat.enabled` — nothing on the wire.
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
        case .walkthroughFounderTask:
            store.view = .chat
            // The first founder-only task still open. `BeaconOffer.candidates` is the
            // same ordered list the hero's card walks, so the beat asks about the task
            // the founder would actually have been offered — not an arbitrary one.
            guard let task = BeaconOffer.candidates(store.company.tasks)
                .first(where: { $0.who == .you }) else { return }
            Task {
                await store.sendChat(
                    language == .vi ? "Hướng dẫn tôi làm: \(task.title)"
                                    : "Walk me through: \(task.title)",
                    language: language)
            }
        case .runTask(let id):
            store.view = .chat
            // The same three guards `runTask` enforces. A beat that fires on a task already
            // running or drafted would produce a second draft and double the credits.
            guard let task = store.company.tasks.first(where: { $0.id == id }),
                  !task.done, !task.drafted else { return }
            Task { await store.runTask(task, language: language) }
        case .recordFounderTask(let taskId, let body):
            store.view = .chat
            Task { await store.recordFounderOutcome(taskId: taskId, body: body, kind: .doc) }
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

    /// The newest reply carrying a draft that is still awaiting approval. Searched
    /// from the end, because a walkthrough that ran two tasks would otherwise
    /// approve the first — and `draftApproved` is checked so a replay cannot
    /// "approve" something already filed.
    private func newestDraftMessageId(in store: CompanyStore) -> String? {
        store.chatMessages.last { $0.draft != nil && !$0.draftApproved }?.id
    }
}
#endif
