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
    /// What is asserted here is the ordering that remains true of the mixed pick: nine
    /// pills at the boundary of the max, then a huge file (refused for size, count unchanged),
    /// then two small ones (the first fits, the second is one too many).
    func testTheSizeRefusalIsTheOneReportedInAMixedPick() {
        let current = (0..<9).map { att("p\($0)", encoded: 1) }
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

    /// **The reported bug's fix.** A 16 MB `mml-book.pdf` was told "Codepet can't read
    /// mml-book.pdf" (8 Sep) — false, since PDFs are supported and the real limit is
    /// `ChatAttachment.maxBytes`. `oversizedMessage` must name the file AND state the
    /// megabyte figure, and the two assertions have to be genuinely independent —
    /// an earlier test on this branch used a fixture named `s10.png` and asserted the
    /// message contained "10", which the FILENAME itself already satisfied. This fixture
    /// name (`report-manual.pdf`) contains no digits, so the "8" assertion can only pass
    /// by the limit actually appearing.
    func testOversizedMessageNamesTheFileAndStatesTheMegabyteLimit() {
        XCTAssertNil(AttachmentBudget.oversizedMessage([], .en))

        let mb = ChatAttachment.maxBytes / (1024 * 1024)
        let en = AttachmentBudget.oversizedMessage(["report-manual.pdf"], .en)
        XCTAssertNotNil(en)
        XCTAssertTrue(en!.contains("report-manual.pdf"), "does not name the file: \(en!)")
        XCTAssertTrue(en!.contains("\(mb)"), "does not state the megabyte limit: \(en!)")

        let vi = AttachmentBudget.oversizedMessage(["report-manual.pdf"], .vi)
        XCTAssertNotNil(vi)
        XCTAssertTrue(vi!.contains("report-manual.pdf"), "does not name the file: \(vi!)")
        XCTAssertTrue(vi!.contains("\(mb)"), "does not state the megabyte limit: \(vi!)")
        XCTAssertNotEqual(en, vi, "the two languages must not collapse to the same copy")
    }

    /// F2, final review: the Engineering route discards attachments silently unless
    /// something names them. nil for an empty list mirrors `unsupportedMessage` (no
    /// notice when there is nothing to report), and both languages must actually name
    /// the file rather than just acknowledge one was dropped — a founder chasing a bug
    /// needs to know WHICH screenshot vanished when she attached more than one.
    func testTheEngineeringNoticeNamesTheFilesAndIsSilentWhenEmpty() {
        XCTAssertNil(AttachmentBudget.engineeringUnsupportedMessage([], .en))
        XCTAssertNil(AttachmentBudget.engineeringUnsupportedMessage([], .vi))

        let en = AttachmentBudget.engineeringUnsupportedMessage(["shot.png"], .en)
        XCTAssertNotNil(en)
        XCTAssertTrue(en!.contains("shot.png"), "does not name the file: \(en!)")

        let vi = AttachmentBudget.engineeringUnsupportedMessage(["shot.png"], .vi)
        XCTAssertNotNil(vi)
        XCTAssertTrue(vi!.contains("shot.png"), "does not name the file: \(vi!)")
        XCTAssertNotEqual(en, vi, "the two languages must not collapse to the same copy")

        let multi = AttachmentBudget.engineeringUnsupportedMessage(["a.png", "b.png"], .en)
        XCTAssertNotNil(multi)
        XCTAssertTrue(multi!.contains("a.png") && multi!.contains("b.png"),
                      "a mixed pick must name every file, not just the first: \(multi!)")
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

    /// **Ten, and the byte budget is what actually binds.** The count is a sanity guard;
    /// `maxTotalBase64Bytes` is what protects the request, and a downscaled screenshot is
    /// 1–3 MB, so a realistic set hits bytes long before it hits ten.
    func testTenFilesFitAndTheEleventhIsRefusedByName() {
        let candidates = (0..<11).map { att("s\($0).png", encoded: 1024) }
        let admission = AttachmentBudget.admit(candidates, to: [])
        XCTAssertEqual(admission.accepted.count, 10)
        XCTAssertEqual(admission.refused, ["s10.png"])
        XCTAssertEqual(admission.reason, .tooMany)
    }

    /// The refusal has to NAME the file and state the rule. "Some files were skipped" is
    /// not actionable; this is the sentence the founder reads instead of silence.
    ///
    /// **The filenames deliberately carry no digits.** An earlier version numbered them
    /// `s0…s10`, so the refused file was `s10.png` and `contains("10")` was satisfied by the
    /// FILENAME — a `refusalMessage` that dropped the cap entirely would still have passed.
    /// Letters make the two assertions independent, and the cap is read from the constant so
    /// the test cannot outlive a change to it.
    func testTheCountRefusalNamesTheFileAndTheRule() {
        let names = (0..<11).map { "shot-\(Character(UnicodeScalar(97 + $0)!)).png" }
        let admission = AttachmentBudget.admit(names.map { att($0, encoded: 1024) }, to: [])
        let msg = AttachmentBudget.refusalMessage(admission, .en)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("shot-k.png"), "must name the refused file — got: \(msg!)")
        XCTAssertTrue(msg!.contains(String(ChatAttachment.max)),
                      "must state the cap — got: \(msg!)")
    }

    /// A pin is grounding, a file is payload. They shared a ceiling only because they share
    /// a row, and raising one must not drag the other.
    func testPinsKeepTheirOwnCeiling() {
        XCTAssertEqual(ContextPin.max, 3)
        XCTAssertEqual(ChatAttachment.max, 10)
    }
}
