import XCTest
@testable import codepet

/// The attachment cap, as arithmetic.
///
/// This suite exists because the cap it replaces failed *invisibly*. Three 8 MB files
/// under `ChatAttachment.maxBytes` are ~32 MB of base64, which is the Cloud Run gen2
/// request ceiling — over it the request is refused by the infrastructure, so
/// `handleCompanyChat` never runs, nothing appears in `functions:log`, and the
/// backend's drop table (the thing that explains every other bad attachment) never
/// sees it either. There is no observation that distinguishes it from the model
/// ignoring the picture, which is why the rule has to be checkable here.
@MainActor
final class AttachmentBudgetTests: XCTestCase {

    /// `data` is what goes on the wire, so the fixture's size is stated in ENCODED
    /// bytes. `byteCount` is deliberately left at the same number and never read by
    /// the budget — using it was the original bug.
    private func att(_ name: String, encoded: Int) -> ChatAttachment {
        ChatAttachment(id: name, kind: .image, filename: name, mediaType: "image/png",
                       data: String(repeating: "A", count: encoded), byteCount: encoded)
    }

    /// Base64 of `raw` bytes, to the byte: 4 characters per 3 bytes, padded.
    private func base64Size(ofRaw raw: Int) -> Int { ((raw + 2) / 3) * 4 }

    // MARK: - The cap itself

    /// **The headline: the old per-file rule admitted a request that cannot be sent.**
    ///
    /// Three files at exactly `ChatAttachment.maxBytes` each pass the per-file check
    /// they were written for, and together they are ~32 MB encoded. Against the real
    /// `maxTotalBase64Bytes` only the first survives. This is the one test that uses
    /// the production constant rather than an injected limit.
    func testThreeFilesAtThePerFileLimitDoNotAllFit() {
        let encoded = base64Size(ofRaw: ChatAttachment.maxBytes)
        let picked = [att("a.png", encoded: encoded),
                      att("b.png", encoded: encoded),
                      att("c.png", encoded: encoded)]

        // Each one passes the per-file rule on its own — that is why it failed silently.
        XCTAssertEqual(picked.count, ChatAttachment.max)
        XCTAssertGreaterThan(AttachmentBudget.base64Bytes(picked),
                             AttachmentBudget.maxTotalBase64Bytes,
                             "the three-file worst case must be over the total cap, or this test proves nothing")

        let admission = AttachmentBudget.admit(picked, to: [])
        XCTAssertEqual(admission.accepted.map(\.filename), ["a.png"])
        XCTAssertEqual(admission.refused, ["b.png", "c.png"])
        XCTAssertEqual(admission.reason, .overBudget)
    }

    /// The cap is measured on the ENCODED string, not on `byteCount`. Same `byteCount`,
    /// different `data` lengths, opposite answers.
    func testTheBudgetMeasuresEncodedBytesNotByteCount() {
        let big = ChatAttachment(id: "b", kind: .image, filename: "big.png",
                                 mediaType: "image/png",
                                 data: String(repeating: "A", count: 200), byteCount: 1)
        let small = ChatAttachment(id: "s", kind: .image, filename: "small.png",
                                   mediaType: "image/png",
                                   data: String(repeating: "A", count: 10), byteCount: 1)
        XCTAssertEqual(AttachmentBudget.admit([big], to: [], limit: 100).refused, ["big.png"])
        XCTAssertEqual(AttachmentBudget.admit([small], to: [], limit: 100).accepted.count, 1)
    }

    /// Both edges of the total, in bytes: exactly at the limit is admitted, one over is not.
    func testTheTotalIsInclusiveAtTheEdge() {
        XCTAssertEqual(AttachmentBudget.admit([att("x", encoded: 100)], to: [], limit: 100)
                        .accepted.count, 1)
        XCTAssertEqual(AttachmentBudget.admit([att("x", encoded: 101)], to: [], limit: 100)
                        .refused, ["x"])
    }

    /// What is already pinned counts. A second file that would fit an empty composer
    /// does not fit beside the first.
    func testWhatIsAlreadyAttachedIsChargedToo() {
        let first = att("a", encoded: 60)
        let admission = AttachmentBudget.admit([att("b", encoded: 60)], to: [first], limit: 100)
        XCTAssertEqual(admission.refused, ["b"])
        XCTAssertEqual(admission.reason, .overBudget)
    }

    /// The file count still holds, and it reports its own reason — "remove one first" and
    /// "attach something smaller" are different instructions.
    func testTheFileCountCapStillRefusesWithItsOwnReason() {
        let current = (0..<ChatAttachment.max).map { att("p\($0)", encoded: 1) }
        let admission = AttachmentBudget.admit([att("one-more", encoded: 1)], to: current)
        XCTAssertTrue(admission.accepted.isEmpty)
        XCTAssertEqual(admission.reason, .tooMany)
    }

    /// **A pick that trips both caps reports the size one — and it does so structurally,
    /// not because anything prefers it.**
    ///
    /// This test found a defect in the implementation it was written for. The reason was
    /// picked by `if reason == nil || refuse == .overBudget`, i.e. a rule that let a later
    /// size refusal overwrite an earlier count refusal. Deleting that clause changed
    /// nothing — 0 failed / 73 passed — because it is unreachable: `count` only rises, so
    /// after the first `.tooMany` every later candidate is refused for count before the
    /// size branch is evaluated, and an `.overBudget` can never follow a `.tooMany`. The
    /// clause was removed; "first refusal wins" gives the same answer for every input.
    ///
    /// What is asserted here is the ordering that remains true of the mixed pick: two
    /// pills, then a huge file (refused for size, count unchanged), then two small ones
    /// (the first fits, the second is one too many).
    func testTheSizeRefusalIsTheOneReportedInAMixedPick() {
        let current = [att("p0", encoded: 1), att("p1", encoded: 1)]
        let admission = AttachmentBudget.admit([att("huge", encoded: 10_000),
                                                att("fits", encoded: 1),
                                                att("one-too-many", encoded: 1)],
                                               to: current, limit: 100)
        XCTAssertEqual(admission.accepted.map(\.filename), ["fits"])
        XCTAssertEqual(admission.refused, ["huge", "one-too-many"])
        XCTAssertEqual(admission.reason, .overBudget,
                       "both reasons fired here; the size one is the one the founder can act on")
    }

    /// The mirror of the above: when the count is the ONLY thing in the way, that is
    /// what is reported. Without this, `.overBudget` winning unconditionally would pass.
    func testACountOnlyRefusalStillSaysCount() {
        let current = (0..<ChatAttachment.max).map { att("p\($0)", encoded: 1) }
        let admission = AttachmentBudget.admit([att("one-more", encoded: 1)],
                                               to: current, limit: 100)
        XCTAssertEqual(admission.reason, .tooMany)
    }

    // MARK: - History replay

    /// The client mirrors `ATTACHMENT_REPLAY_WINDOW = 6`: base64 on an older turn is
    /// paid for on the wire and then discarded by the backend. Both edges are pinned —
    /// the 6th-newest entry keeps its file, the 7th does not.
    func testOnlyTheLastSixHistoryEntriesKeepTheirAttachments() {
        let history = (0..<8).map { [att("h\($0)", encoded: 1)] }
        let out = AttachmentBudget.replay(history, alongside: [])
        XCTAssertTrue(out[0].isEmpty, "the 8th-newest entry must not carry base64")
        XCTAssertTrue(out[1].isEmpty, "the 7th-newest entry must not carry base64 — one past the window")
        XCTAssertEqual(out[2].map(\.filename), ["h2"], "the 6th-newest is the window's edge and must be kept")
        XCTAssertEqual(out[7].map(\.filename), ["h7"])
    }

    /// This turn's own file is charged first and never trimmed: it is the one the
    /// founder is looking at. A past screenshot gives way instead.
    func testTheOutgoingFileIsChargedAndThePastGivesWay() {
        let history = [[att("old", encoded: 60)]]
        let out = AttachmentBudget.replay(history, alongside: [att("new", encoded: 60)], limit: 100)
        XCTAssertTrue(out[0].isEmpty, "the past turn must give way to the file being sent now")
    }

    /// Trimming stops at the first entry that does not fit and drops everything older
    /// with it — no hole in the middle of the window.
    ///
    /// The sizes are chosen so 'a' really would fit — 30 + 10 is under 100 — and is
    /// dropped only because the walk stopped at 'b'. My first version used 10/80/10,
    /// which totals exactly 100 and therefore all fit: the test failed by asserting a
    /// trim that the arithmetic never called for.
    func testTrimmingDropsTheOlderEntriesTogether() {
        let history = [[att("a", encoded: 10)], [att("b", encoded: 80)], [att("c", encoded: 30)]]
        let out = AttachmentBudget.replay(history, alongside: [], limit: 100)
        XCTAssertEqual(out[2].map(\.filename), ["c"])
        XCTAssertTrue(out[1].isEmpty, "'b' is 80 on top of 30 — over the limit")
        XCTAssertTrue(out[0].isEmpty, "'a' would fit on its own, but 'b' already stopped the walk")
    }

    /// A conversation with no attachments is unchanged — the ordinary case stays
    /// byte-identical, which is the claim `AttachmentDTO.wire` turns into an omitted key.
    func testAnAttachmentFreeHistoryStaysEmpty() {
        let out = AttachmentBudget.replay([[], [], []], alongside: [])
        XCTAssertEqual(out, [[], [], []])
    }

    // MARK: - Copy

    /// Bilingual, and actually translated. A past defect in this repo was
    /// `lang == .vi ? why : why`, so every bilingual function here asserts en != vi.
    func testTheOverBudgetRefusalIsBilingualAndNamesTheLimit() {
        let admission = AttachmentBudget.Admission(accepted: [], refused: ["shot.png"],
                                                   reason: .overBudget)
        let en = AttachmentBudget.refusalMessage(admission, .en)
        let vi = AttachmentBudget.refusalMessage(admission, .vi)
        XCTAssertNotNil(en)
        XCTAssertNotNil(vi)
        XCTAssertNotEqual(en, vi)
        // The founder is told the number, and the number comes from the constant.
        let mb = "\(AttachmentBudget.maxTotalBase64Bytes / (1024 * 1024))"
        XCTAssertTrue(en?.contains(mb) ?? false)
        XCTAssertTrue(vi?.contains(mb) ?? false)
        XCTAssertTrue(en?.contains("shot.png") ?? false, "the founder must be told WHICH file")
    }

    func testTheTooManyRefusalIsBilingualAndDistinctFromTheSizeOne() {
        let tooMany = AttachmentBudget.Admission(accepted: [], refused: ["c.pdf"], reason: .tooMany)
        let over = AttachmentBudget.Admission(accepted: [], refused: ["c.pdf"], reason: .overBudget)
        XCTAssertNotEqual(AttachmentBudget.refusalMessage(tooMany, .en),
                          AttachmentBudget.refusalMessage(tooMany, .vi))
        XCTAssertNotEqual(AttachmentBudget.refusalMessage(tooMany, .en),
                          AttachmentBudget.refusalMessage(over, .en),
                          "two reasons need two sentences — the fix is different")
    }

    func testTheUnsupportedNoticeIsBilingualAndSilentWhenEmpty() {
        XCTAssertNil(AttachmentBudget.unsupportedMessage([], .en))
        XCTAssertNotEqual(AttachmentBudget.unsupportedMessage(["a.sketch"], .en),
                          AttachmentBudget.unsupportedMessage(["a.sketch"], .vi))
    }

    /// A clean pick says nothing. The notice is assigned on every pick, so a nil here
    /// is what clears a stale refusal off the composer.
    func testACleanPickProducesNoNotice() {
        let clean = AttachmentBudget.admit([att("a", encoded: 1)], to: [])
        XCTAssertNil(AttachmentBudget.refusalMessage(clean, .en))
    }

    // MARK: - The declared media type after a downscale

    /// `AttachmentPicker` re-encodes every non-JPEG image as PNG when it downscales, so
    /// a resized `.webp` is PNG bytes. Declaring it `image/webp` is a header that
    /// contradicts its payload: legal to the backend's check, fatal at the API, and
    /// invisible in every log we own.
    func testADownscaledWebPIsDeclaredAsThePNGItNowIs() {
        XCTAssertEqual(ChatAttachment.mediaType(for: .image, pathExtension: "webp"), "image/webp")
        XCTAssertEqual(ChatAttachment.downscaledMediaType(pathExtension: "webp"), "image/png")
        XCTAssertEqual(ChatAttachment.downscaledMediaType(pathExtension: "gif"), "image/png")
        XCTAssertEqual(ChatAttachment.downscaledMediaType(pathExtension: "JPG"), "image/jpeg")
        XCTAssertEqual(ChatAttachment.downscaledMediaType(pathExtension: "png"), "image/png")
    }
}
