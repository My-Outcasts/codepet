// codepetTests/FirstApprovalNoteTests.swift
import XCTest
@testable import codepet

/// Guards on the draft card admitting it is not saved yet.
///
/// The rule "nothing is committed until you approve" is stated BEFORE a run (`BeaconOffer`:
/// "you approve before it is filed") and confirmed AFTER ("Added to Library"). In between, the
/// founder looks at a finished-LOOKING deliverable beside a button marked Approve, with nothing
/// saying it is unsaved. That middle moment is what this note fills.
@MainActor
final class FirstApprovalNoteTests: XCTestCase {

    // MARK: - Task 1: the field and its wire shape

    /// Millis, not ISO — `introSeenAt` next to it is a number and the web reads both.
    func testFirstApprovalPayloadIsEpochMillis() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = CompanyData.firstApprovalPayload(at)
        XCTAssertEqual(payload["firstApprovalAt"] as? Double, 1_700_000_000_000)
    }

    /// **The landmine this file's own comment warns about.** `CompanyState.init(from:)` is
    /// hand-written because Swift's synthesised `Decodable` throws `keyNotFound` rather than
    /// falling back to a declared default. Every company document in Firestore predates this
    /// field, so a required decode would fail to load EVERY existing account.
    func testACompanyDocumentWithoutTheFieldStillDecodes() throws {
        let json = #"{"companionId":"byte","stage":"building"}"#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertNil(state.firstApprovalAt)
        XCTAssertEqual(state.companionId, "byte")
    }

    func testItRoundTripsWhenPresent() throws {
        var state = CompanyState.empty
        state.firstApprovalAt = Date(timeIntervalSince1970: 1_700_000_000)
        let back = try JSONDecoder().decode(
            CompanyState.self, from: try JSONEncoder().encode(state))
        XCTAssertEqual(back.firstApprovalAt?.timeIntervalSince1970, 1_700_000_000)
    }

    // MARK: - Task 2: the store sets it

    /// Same stubs as `CompanyStoreChatRunTests`: the live defaults reach Firestore and Firebase
    /// Auth, both of which trap under an unconfigured `FirebaseApp`.
    private func store(tasks: [RoadmapTask] = [],
                       saver: @escaping (String, Date) async -> Bool = { _, _ in true })
        -> CompanyStore {
        CompanyStore(loader: { _ in
            CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .building,
                         companionId: "byte", onboardedAt: Date(), tasks: tasks)
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in
               AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
           },
           taskRunner: { _ in nil }, librarySaver: { _, _ in true },
           // BEFORE `decisionExtractor`, matching the declaration order in
           // `CompanyStore.init` — Swift requires labelled arguments to appear in the order
           // they are declared, and `firstApprovalSaver` sits next to `introSeenSaver`, which
           // is well above `decisionExtractor`.
           firstApprovalSaver: saver,
           decisionExtractor: { _, _ in [] })
    }

    private func draft(_ taskId: String? = nil) -> Deliverable {
        // `kind` before `title` — see `Deliverable.init`.
        Deliverable(id: "d1", kind: .doc, title: "T", body: "B", sourceTaskId: taskId)
    }

    func testApprovingFromChatRecordsTheFirstApproval() async {
        let s = store()
        await s.hydrate(companyId: "u")
        XCTAssertNil(s.company.firstApprovalAt, "a fresh account has approved nothing")
        s.seedChatMessagesForTesting([
            CopilotMessage(id: "m1", role: .companion, text: "", draft: draft())
        ])
        await s.approveDraft(messageId: "m1")
        XCTAssertNotNil(s.company.firstApprovalAt)
    }

    /// The board is a real path to the same lesson. Both approve paths funnel through
    /// `fileApproval`, so this passes for free — and goes red the moment someone writes the
    /// flag in `approveDraft` instead of at the chokepoint.
    func testApprovingFromTheBoardRecordsItToo() async {
        let task = RoadmapTask(id: "t1", title: "T", detail: "", phase: .build, who: .draft,
                               drafted: true, draft: draft("t1"))
        let s = store(tasks: [task])
        await s.hydrate(companyId: "u")
        await s.approveTask(id: "t1")
        XCTAssertNotNil(s.company.firstApprovalAt)
    }

    /// Written once. A second approval must not move the timestamp — it is "when did they
    /// learn this", not "when did they last approve".
    func testTheTimestampIsNotOverwrittenByLaterApprovals() async {
        let s = store()
        await s.hydrate(companyId: "u")
        s.seedChatMessagesForTesting([
            CopilotMessage(id: "m1", role: .companion, text: "", draft: draft()),
            CopilotMessage(id: "m2", role: .companion, text: "", draft: draft())
        ])
        await s.approveDraft(messageId: "m1")
        let first = s.company.firstApprovalAt
        await s.approveDraft(messageId: "m2")
        XCTAssertEqual(s.company.firstApprovalAt, first)
    }

    /// Fail-soft, matching `markIntroSeen`: a rejected write leaves the in-memory flag set, so
    /// the founder is not re-taught inside the session they just learned it in.
    func testAFailedWriteStillRetiresTheNoteInSession() async {
        let s = store(saver: { _, _ in false })
        await s.hydrate(companyId: "u")
        s.seedChatMessagesForTesting([
            CopilotMessage(id: "m1", role: .companion, text: "", draft: draft())
        ])
        await s.approveDraft(messageId: "m1")
        XCTAssertNotNil(s.company.firstApprovalAt)
    }

    // MARK: - Task 3: the decision

    /// A pure static, not a condition inside `draftCard`'s body. Same reasoning as
    /// `DraftPayloadPreview.hasStructuredPreview`: the bug worth guarding lives in the
    /// decision, and a decision inside a `View` body is only testable by rendering it.
    func testTheNoteShowsOnlyBeforeTheFirstApproval() {
        XCTAssertTrue(DraftCardCopy.shouldShowNotFiledNote(hasApproved: false,
                                                           draftApproved: false))
        XCTAssertFalse(DraftCardCopy.shouldShowNotFiledNote(hasApproved: true,
                                                            draftApproved: false),
                       "retired once the founder has approved anything")
    }

    /// An approved card already says "Added to Library". Two answers to one question on one
    /// card is worse than none.
    func testTheNoteNeverShowsOnAnApprovedCard() {
        XCTAssertFalse(DraftCardCopy.shouldShowNotFiledNote(hasApproved: false,
                                                            draftApproved: true))
        XCTAssertFalse(DraftCardCopy.shouldShowNotFiledNote(hasApproved: true,
                                                            draftApproved: true))
    }

    func testTheCopyIsExactlyWhatTheSpecSays() {
        XCTAssertEqual(DraftCardCopy.notFiledNote(.en),
                       "Not saved yet — approving files it in your Library.")
        XCTAssertEqual(DraftCardCopy.notFiledNote(.vi),
                       "Chưa lưu — duyệt để đưa vào Thư viện.")
    }

    /// An em dash, not a hyphen — every other string on this card uses one, and a lone hyphen
    /// reads as a typo beside them.
    func testTheCopyUsesAnEmDash() {
        XCTAssertTrue(DraftCardCopy.notFiledNote(.en).contains("\u{2014}"))
        XCTAssertTrue(DraftCardCopy.notFiledNote(.vi).contains("\u{2014}"))
    }
}
