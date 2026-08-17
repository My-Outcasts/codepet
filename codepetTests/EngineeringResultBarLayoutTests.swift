// codepetTests/EngineeringResultBarLayoutTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// What can be checked about a view I cannot see.
///
/// Screen Recording is denied on this machine, so no agent can screenshot the
/// running app — whether this bar LOOKS right is a handoff to Mona. What is
/// measurable offscreen is whether it draws at all, whether it fits the dock's
/// narrowest width without clipping, and what it says. Those are the failures
/// that would otherwise reach her as "it looks broken" with no detail.
///
/// `ImageRenderer` at `scale = 1` (one pixel == one point), same technique as
/// `DepartmentHeaderLayoutTests`. It renders NOTHING inside a `ScrollView`, so
/// the bar is measured in isolation rather than embedded in a transcript.
@MainActor
final class EngineeringResultBarLayoutTests: XCTestCase {

    /// The narrowest the docked copilot column gets. A card that overflows here
    /// clips in the place a founder actually reads it.
    private static let dockWidth: CGFloat = 320
    /// Wide enough that anything spilling past `dockWidth` is drawn rather than
    /// clipped away by the renderer's own bounds.
    private static let canvasWidth: CGFloat = 700

    private func store(
        phase: EngineeringFrame? = nil,
        diff: EngDiffSummary? = nil
    ) -> EngineeringRunStore {
        let store = EngineeringRunStore(runner: MockEngineeringRunner())
        store.handle(.step(ExecStep(id: "s1", label: "read the repository", done: true, kind: .mono)))
        store.handle(.step(ExecStep(id: "s2", label: "npm install stripe", done: false, kind: .mono)))
        if let phase { store.handle(phase) }
        return store
    }

    private func bar(_ store: EngineeringRunStore) -> some View {
        EngineeringResultBar(store: store, elapsed: 41, onReview: {})
            .environment(\.uiLanguage, .en)
    }

    /// Leftmost and rightmost drawn pixel columns, or nil when nothing drew —
    /// reported rather than silently passing.
    ///
    /// The view is constrained to `width` and then rendered on a WIDER canvas.
    /// That second frame is the whole point: `ImageRenderer(content:
    /// view.frame(width: 320))` sizes the image to 320, so anything overflowing
    /// is clipped by the render and `last <= 320` holds no matter what the view
    /// does. Three tests here were vacuous for exactly that reason until a
    /// mutation run proved they could not fail. On a 700pt canvas, overflow has
    /// somewhere to draw and the assertion means something.
    private func drawnExtent(_ view: some View, width: CGFloat) -> (first: Int, last: Int)? {
        let renderer = ImageRenderer(
            content: view
                .frame(width: width)
                .frame(width: Self.canvasWidth, alignment: .leading)
        )
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var first: Int?, last: Int?
        for x in 0..<w {
            var drawn = false
            for y in 0..<h where pixels[(y * w + x) * 4 + 3] > 8 { drawn = true; break }
            if drawn {
                if first == nil { first = x }
                last = x
            }
        }
        guard let f = first, let l = last else { return nil }
        return (f, l)
    }

    private func height(_ view: some View, width: CGFloat) -> CGFloat? {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        return CGFloat(cg.height)
    }

    // MARK: - it draws, and it fits

    func test_theBarActuallyRendersSomething() throws {
        // Without this the assertions below would have nothing to measure and
        // could all look green.
        let extent = try XCTUnwrap(drawnExtent(bar(store()), width: Self.dockWidth),
                                   "ImageRenderer produced no drawn pixels for EngineeringResultBar")
        XCTAssertGreaterThan(extent.last - extent.first, 100,
                             "the bar drew something, but far too narrow to be the card")
    }

    func test_theBarStaysInsideTheDocksNarrowestWidth() throws {
        let extent = try XCTUnwrap(drawnExtent(bar(store()), width: Self.dockWidth))
        XCTAssertLessThanOrEqual(extent.last, Int(Self.dockWidth),
                                 "the card drew past the dock's right edge — it clips where it is read")
        XCTAssertGreaterThanOrEqual(extent.first, 0)
    }

    func test_longProseWrapsRatherThanWidensTheBar() throws {
        // Was the ASK until 14 Aug — the bar repeated it above the summary,
        // and this pinned its wrapping. The ask now lives only in the
        // founder's own bubble, and the long text in this surface is the
        // agent's prose, which arrives in paragraphs and is the thing that can
        // overflow. `fixedSize(horizontal: false, vertical: true)` is what
        // makes it wrap; without it the Text refuses to compress.
        let s = store()
        s.handle(.message(String(repeating:
            "Added Stripe checkout and a customer portal across four files. ", count: 4)))
        let extent = try XCTUnwrap(drawnExtent(bar(s), width: Self.dockWidth))
        XCTAssertLessThanOrEqual(extent.last, Int(Self.dockWidth),
                                 "long prose widened the bar instead of wrapping")
    }

    func test_contentActuallyReachesTheScreen() throws {
        // Rewritten 14 Aug. It used to assert the collapsed card sat between
        // 40 and 400 points — a range that encoded the card's own chrome
        // (padding, eyebrow, the repeated ask). The card is gone, an empty run
        // now draws two grey lines at ~32pt, and the old floor was measuring
        // furniture rather than content.
        //
        // What is worth pinning is that content REACHES the render at all.
        // `store.messages` was collected and drawn nowhere for a fortnight,
        // and no height assertion would have caught it — this one would.
        let empty = try XCTUnwrap(height(bar(store()), width: Self.dockWidth))
        XCTAssertGreaterThan(empty, 12, "even an empty run draws its metadata lines")

        let full = store()
        full.handle(.message("Added Stripe checkout across three files. Tests pass."))
        full.handle(.step(ExecStep(id: "s1", label: "npm install stripe", done: true, kind: .mono)))
        let withContent = try XCTUnwrap(height(bar(full), width: Self.dockWidth))

        XCTAssertGreaterThan(withContent, empty + 20,
                             "the agent's prose added no height — it is not being rendered")
        XCTAssertLessThan(withContent, 400, "the bar is tall enough to be showing everything at once")
    }

    // MARK: - what it says
    //
    // Asserted against the PURE static functions, not by rendering. Copy that
    // reads @Environment can only be exercised by drawing it, and drawing
    // cannot assert on words — the first version of these tests called an
    // instance method and did not compile. That failure was the useful kind:
    // untestable copy is copy nobody checks.

    // MARK: - the file list, folded like Codex's

    func test_threeFilesShowAndTheRestFold() {
        let diff = Self.diff(fileCount: 6)
        XCTAssertEqual(EngineeringResultBar.shownFiles(diff, expanded: false).count, 3)
        XCTAssertEqual(EngineeringResultBar.hiddenCount(diff, expanded: false), 3)
        XCTAssertEqual(EngineeringResultBar.shownFiles(diff, expanded: true).count, 6)
    }

    func test_thereIsNoFoldWhenNothingIsHidden() {
        // Three files or fewer: no control, because there is nothing behind it.
        XCTAssertNil(EngineeringResultBar.hiddenCount(Self.diff(fileCount: 3), expanded: false))
        XCTAssertNil(EngineeringResultBar.hiddenCount(Self.diff(fileCount: 1), expanded: false))
    }

    func test_theFoldCountsInTheSingular() {
        // "Show 1 more files" is the kind of thing that makes a product feel
        // unfinished, and it is exactly what a naive interpolation produces.
        XCTAssertEqual(EngineeringResultBar.foldLabel(more: 1, lang: .en), "Show 1 more file")
        XCTAssertEqual(EngineeringResultBar.foldLabel(more: 4, lang: .en), "Show 4 more files")
        XCTAssertEqual(EngineeringResultBar.foldLabel(more: 0, lang: .en), "Collapse files")
        XCTAssertNotEqual(EngineeringResultBar.foldLabel(more: 1, lang: .vi),
                          EngineeringResultBar.foldLabel(more: 1, lang: .en))
    }

    func test_thePathSplitsSoTheFilenameCarriesTheWeight() {
        // Scanning a diff means reading basenames; the directory recedes.
        XCTAssertEqual(EngineeringResultBar.directory("outputs/site/index.html"), "outputs/site/")
        XCTAssertEqual(EngineeringResultBar.basename("outputs/site/index.html"), "index.html")
    }

    func test_aBareFilenameIsAllBasename() {
        XCTAssertEqual(EngineeringResultBar.directory("README.md"), "")
        XCTAssertEqual(EngineeringResultBar.basename("README.md"), "README.md")
        // Concatenating the two must always reproduce the path, or a row shows
        // a file that is not the file that changed.
        for path in ["a/b/c.ts", "c.ts", "a/b/", "", "outputs/x y/z.tsx"] {
            XCTAssertEqual(EngineeringResultBar.directory(path)
                           + EngineeringResultBar.basename(path), path, "split lost \(path)")
        }
    }

    private static func diff(fileCount: Int) -> EngDiffSummary {
        EngDiffSummary(
            files: (0..<fileCount).map {
                EngFileDiff(file: "src/f\($0).ts", path: "src/f\($0).ts",
                            additions: 1, deletions: 0, status: "modified", patch: "@@")
            },
            additions: fileCount, deletions: 0, truncated: false,
            scope: .branch, scopeFellBack: false)
    }

    // MARK: - the run's state, carried by the worked line

    func test_theTenseIsTheStatus() {
        // There was a phase chip in an eyebrow until 14 Aug — "Working",
        // "Needs you", "Ready to review" — and it went with the card. Codex
        // carries the same thing in one line, and a founder reading
        // "Working… 41s" does not also need a badge saying Working.
        XCTAssertTrue(EngineeringResultBar.workedPrefix(running: true, lang: .en)
            .lowercased().contains("working"))
        XCTAssertTrue(EngineeringResultBar.workedPrefix(running: false, lang: .en)
            .lowercased().contains("worked"))
        XCTAssertNotEqual(EngineeringResultBar.workedPrefix(running: true, lang: .vi),
                          EngineeringResultBar.workedPrefix(running: true, lang: .en))
    }

    func test_awaitingApprovalStillCountsAsRunning() {
        // The session is alive and billing; it is blocked on a human. A run
        // that showed "Worked for" while an unanswered card sat under it would
        // read as finished.
        XCTAssertTrue(EngineeringResultBar.isRunning(.preparing))
        XCTAssertTrue(EngineeringResultBar.isRunning(.running))
        XCTAssertTrue(EngineeringResultBar.isRunning(.awaitingApproval))
        XCTAssertFalse(EngineeringResultBar.isRunning(.reviewing))
        XCTAssertFalse(EngineeringResultBar.isRunning(.budgetReached))
        XCTAssertFalse(EngineeringResultBar.isRunning(.failed("x")))
    }

    func test_aFailedRunIsNeverSilent() {
        // `EngineeringRun.phase(fromStopReason:)` maps an unrecognised reason
        // to `.failed` and attaches NO refusal. The chip was the only thing
        // marking that state, and the chip is gone — without this the run
        // would simply stop, with nothing anywhere saying so.
        let note = EngineeringResultBar.note(phase: .failed("unknown_stop_reason"),
                                             failure: nil, lang: .en)
        XCTAssertNotNil(note, "a failed run with no refusal says nothing at all")
        XCTAssertTrue(note?.lowercased().contains("branch") == true,
                      "does not say the work survived: \(note ?? "nil")")
        XCTAssertNotEqual(note, EngineeringResultBar.note(phase: .failed("x"),
                                                         failure: nil, lang: .vi))
    }

    func test_aSpecificRefusalStillWinsOverTheGenericOne() {
        // The generic line is a floor, not a replacement: when we know WHY,
        // say why.
        let specific = EngineeringResultBar.note(phase: .failed("x"),
                                                 failure: .noCredits, lang: .en)
        XCTAssertEqual(specific, EngineeringResultBar.message(for: .noCredits, lang: .en))
    }

    func test_ourOwnMisconfigurationIsNeverBlamedOnTheFounder() {
        // A 500 is ours. "Check your settings" would read as their fault for
        // something they cannot see or fix.
        let english = EngineeringResultBar.message(for: .misconfigured, lang: .en)
        XCTAssertTrue(english.lowercased().contains("our side"),
                      "a deploy misconfiguration must be owned, not deflected: \(english)")
        XCTAssertFalse(english.lowercased().contains("your"),
                       "our own misconfiguration must not be worded as the founder's problem")
    }

    func test_theTwoConnectionRefusalsSayDifferentThings() {
        // "Connect a repo" and "connect GitHub" need different actions, and a
        // founder given the wrong one goes to the wrong screen.
        for lang in [AppLanguage.en, .vi] {
            XCTAssertNotEqual(EngineeringResultBar.message(for: .noRepoLinked, lang: lang),
                              EngineeringResultBar.message(for: .gitHubNotConnected, lang: lang),
                              "the two 409s must not share copy in \(lang)")
        }
    }

    func test_everyRefusalHasCopyInBothLanguages() {
        let refusals: [EngineeringError] = [
            .noRepoLinked, .gitHubNotConnected, .noCredits,
            .misconfigured, .unavailable, .unknown(418)
        ]
        for refusal in refusals {
            XCTAssertFalse(EngineeringResultBar.message(for: refusal, lang: .en).isEmpty,
                           "\(refusal) has no English copy")
            XCTAssertFalse(EngineeringResultBar.message(for: refusal, lang: .vi).isEmpty,
                           "\(refusal) has no Vietnamese copy")
            XCTAssertNotEqual(EngineeringResultBar.message(for: refusal, lang: .en),
                              EngineeringResultBar.message(for: refusal, lang: .vi),
                              "\(refusal) shows English to a Vietnamese founder")
        }
    }
}
