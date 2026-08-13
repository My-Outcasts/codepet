// codepetTests/ReviewPaneTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// The Review pane's three honest states, its copy, and the per-line hit target
/// inline comments will attach to.
///
/// Whether the diff LOOKS right is a handoff — Screen Recording is denied, so
/// no agent can see it running. What is checkable is that it draws, that it
/// fits, and that it never presents a partial answer as a complete one.
@MainActor
final class ReviewPaneTests: XCTestCase {

    private static let paneWidth: CGFloat = 620
    /// Rendered on a wider canvas than the pane so overflow DRAWS rather than
    /// being clipped away by the renderer's own bounds — without this the width
    /// assertion compares 620 to itself and cannot fail.
    private static let canvasWidth: CGFloat = 1100

    private func store(_ diff: EngDiffSummary?) -> EngineeringRunStore {
        EngineeringRunStore(runner: ScriptedRunner(diff: diff ?? .empty))
    }

    /// A store with a run already started, because `loadDiff` guards on `runId`
    /// and does nothing without one — correctly: a diff has no meaning outside a
    /// run. The first version of these tests skipped `start` and read a nil
    /// diff, which looked like the pane dropping data and was the test's fault.
    private func startedStore(_ diff: EngDiffSummary) async -> EngineeringRunStore {
        let s = store(diff)
        await s.start(ask: "add stripe checkout")
        return s
    }

    /// Returns whatever diff the test planted, so `loadDiff` puts it on the store.
    private final class ScriptedRunner: EngineeringRunning {
        let diffToReturn: EngDiffSummary
        init(diff: EngDiffSummary) { diffToReturn = diff }
        func start(ask: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws -> String { "run_1" }
        func attach(runId: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws {}
        func send(runId: String, turn: EngineeringTurn) async throws {}
        func diff(runId: String, scope: ReviewScope) async throws -> EngDiffSummary { diffToReturn }
    }

    private func summary(
        files: [EngFileDiff] = [],
        truncated: Bool = false,
        fellBack: Bool = false
    ) -> EngDiffSummary {
        EngDiffSummary(
            files: files,
            additions: files.reduce(0) { $0 + $1.additions },
            deletions: files.reduce(0) { $0 + $1.deletions },
            truncated: truncated,
            scope: .branch,
            scopeFellBack: fellBack
        )
    }

    private func textFile(_ name: String = "api/billing.ts") -> EngFileDiff {
        EngFileDiff(file: name, path: name, additions: 2, deletions: 1, status: "modified",
                    patch: "@@ -1,2 +1,3 @@\n const a = 1\n-const b = 2\n+const b = 3\n+const c = 4")
    }

    private func binaryFile() -> EngFileDiff {
        EngFileDiff(file: "public/logo.png", path: "public/logo.png", additions: 0,
                    deletions: 0, status: "modified", patch: nil)
    }

    private func drawnExtent(_ view: some View, width: CGFloat) -> (first: Int, last: Int)? {
        let renderer = ImageRenderer(
            content: view.frame(width: width).frame(width: Self.canvasWidth, alignment: .leading)
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

    // MARK: - the three honest states, asserted on the model that drives them

    func test_aFallenBackScopeIsCarriedOnTheDiffSoThePaneCanSaySo() async {
        // The founder asked for one turn and is looking at the whole branch.
        // Without this flag they read earlier turns' work as this turn's — a
        // wrong answer wearing the right label.
        let s = await startedStore(summary(files: [textFile()], fellBack: true))
        await s.loadDiff(scope: .turn)
        XCTAssertEqual(s.diff?.scopeFellBack, true)
    }

    func test_truncationIsCarriedRatherThanSwallowed() async {
        // GitHub caps a compare at 300 files. Showing 300 as if they were all of
        // them is a lie of omission the founder cannot detect.
        let s = await startedStore(summary(files: [textFile()], truncated: true))
        await s.loadDiff(scope: .branch)
        XCTAssertEqual(s.diff?.truncated, true)
    }

    func test_aBinaryFileIsARowWithNoBodyRatherThanADroppedFile() async {
        let s = await startedStore(summary(files: [textFile(), binaryFile()]))
        await s.loadDiff(scope: .branch)
        XCTAssertEqual(s.diff?.files.count, 2)
        XCTAssertTrue(s.diff?.files.contains(where: \.isBinary) == true)
    }

    func test_loadingADiffWithNoRunInFlightDoesNothing() async {
        // The guard that broke the first version of these tests, pinned as the
        // behaviour it is: a diff has no meaning outside a run, and `loadDiff`
        // must not invent one. The pane renders "nothing to review yet".
        let s = store(summary(files: [textFile()]))
        await s.loadDiff(scope: .branch)
        XCTAssertNil(s.diff)
    }

    // MARK: - it draws, and it fits

    func test_thePaneRendersSomething() throws {
        let pane = ReviewPane(store: store(summary(files: [textFile()])), onScope: { _ in })
            .environment(\.uiLanguage, .en)
        let extent = try XCTUnwrap(drawnExtent(pane, width: Self.paneWidth),
                                   "ImageRenderer produced no drawn pixels for ReviewPane")
        XCTAssertGreaterThan(extent.last - extent.first, 100)
    }

    func test_aLongFilePathDoesNotWidenThePane() throws {
        // Truncation is `.middle`, so the extension stays readable; the guard
        // here is only that it truncates at all rather than pushing the +/−
        // counts off the edge.
        let deep = String(repeating: "very/deep/path/", count: 10) + "billing.ts"
        let pane = ReviewPane(store: store(summary(files: [textFile(deep)])), onScope: { _ in })
            .environment(\.uiLanguage, .en)
        let extent = try XCTUnwrap(drawnExtent(pane, width: Self.paneWidth))
        XCTAssertLessThanOrEqual(extent.last, Int(Self.paneWidth),
                                 "a long path widened the pane instead of truncating")
    }

    // MARK: - copy

    func test_bothScopesAreLabelledInBothLanguages() {
        for scope in ReviewScope.allCases {
            let en = ReviewPane.scopeLabel(scope, lang: .en)
            let vi = ReviewPane.scopeLabel(scope, lang: .vi)
            XCTAssertFalse(en.isEmpty)
            XCTAssertFalse(vi.isEmpty)
            XCTAssertNotEqual(en, vi, "\(scope) shows English to a Vietnamese founder")
        }
    }

    func test_theTwoScopesDoNotShareALabel() {
        XCTAssertNotEqual(ReviewPane.scopeLabel(.branch, lang: .en),
                          ReviewPane.scopeLabel(.turn, lang: .en))
    }

    func test_theFileCountSingularises() {
        XCTAssertEqual(ReviewPane.fileCountLabel(1, lang: .en), "1 file")
        XCTAssertEqual(ReviewPane.fileCountLabel(3, lang: .en), "3 files")
    }
}

/// The seam inline comments attach to. Nothing is wired to it at freeze — the
/// point is that the GEOMETRY exists, because that is the part that would force
/// a rewrite of the renderer in v1.1 if it did not.
final class DiffLineHitTargetTests: XCTestCase {

    func test_everyRenderableLineOffersAnAnchor() {
        // If any line a founder can see lacks a number, a comment on it has
        // nowhere to attach.
        let lines = DiffPatch.parse("""
        @@ -1,3 +1,3 @@
         context
        -removed
        +added
        """)
        for line in lines where line.kind != .hunk {
            XCTAssertNotNil(line.commentAnchor, "\(line.kind) offers no comment anchor")
        }
    }

    func test_aHunkHeaderOffersNoAnchorBecauseItIsNotCode() {
        let lines = DiffPatch.parse("@@ -1,1 +1,1 @@\n a")
        XCTAssertNil(lines[0].commentAnchor)
    }

    func test_theAnchorIsTheLineAFounderWouldNameOutLoud() {
        // On an added line, the number in their editor is the NEW one.
        let added = DiffPatch.parse("@@ -5,0 +7,1 @@\n+new")
        XCTAssertEqual(added[1].commentAnchor, 7)
        // On a deleted line, the only number that ever existed is the old one.
        let removed = DiffPatch.parse("@@ -5,1 +7,0 @@\n-gone")
        XCTAssertEqual(removed[1].commentAnchor, 5)
    }
}

/// The two admissions that separate a partial diff from a misleading one.
///
/// Asserted against the pure `warnings(for:)` value rather than the rendered
/// view, because a rendered banner is unprovable here: `ImageRenderer` yields
/// pixels, not text, so deleting one from the body would leave every other test
/// in this file green. Extracting the list is what makes "which warnings show"
/// a thing a test can pin.
final class ReviewPaneWarningTests: XCTestCase {

    private func diff(truncated: Bool = false, fellBack: Bool = false) -> EngDiffSummary {
        EngDiffSummary(files: [], additions: 0, deletions: 0,
                       truncated: truncated, scope: .branch, scopeFellBack: fellBack)
    }

    func test_aCleanDiffAdmitsNothing() {
        // A complete answer must not carry a caveat — a warning shown when
        // nothing is wrong teaches the founder to ignore the ones that matter.
        XCTAssertEqual(ReviewPane.warnings(for: diff()), [])
    }

    func test_noDiffAtAllAdmitsNothing() {
        XCTAssertEqual(ReviewPane.warnings(for: nil), [])
    }

    func test_aFallenBackScopeIsAdmitted() {
        XCTAssertEqual(ReviewPane.warnings(for: diff(fellBack: true)), [.scopeFellBack])
    }

    func test_truncationIsAdmitted() {
        XCTAssertEqual(ReviewPane.warnings(for: diff(truncated: true)), [.truncated])
    }

    func test_bothAreAdmittedTogether() {
        // They co-occur: a turn-scoped request that fell back to a branch wide
        // enough to hit GitHub's file cap. Showing one and swallowing the other
        // would be the worst case — the founder trusts the caveat they can see.
        XCTAssertEqual(ReviewPane.warnings(for: diff(truncated: true, fellBack: true)),
                       [.scopeFellBack, .truncated])
    }

    func test_everyWarningHasCopyInBothLanguagesAndDiffers() {
        for warning in [ReviewPane.Warning.scopeFellBack, .truncated] {
            let en = ReviewPane.warningText(warning, lang: .en)
            let vi = ReviewPane.warningText(warning, lang: .vi)
            XCTAssertFalse(en.isEmpty)
            XCTAssertFalse(vi.isEmpty)
            XCTAssertNotEqual(en, vi, "\(warning) shows English to a Vietnamese founder")
        }
    }

    func test_theTwoWarningsDoNotShareCopy() {
        XCTAssertNotEqual(ReviewPane.warningText(.scopeFellBack, lang: .en),
                          ReviewPane.warningText(.truncated, lang: .en))
    }
}
