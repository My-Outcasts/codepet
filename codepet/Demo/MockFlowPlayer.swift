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

    var beats: [MockFlowScript.Beat] { MockFlowScript.beats }
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
        }
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
