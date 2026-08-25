import XCTest
@testable import codepet

/// What a diagnostics document is allowed to contain.
///
/// Every test here is about the PRIVACY boundary, not about plumbing: the founder's chat
/// is their company's private strategy, so this system records an error type, a call
/// site, a count and a timestamp — and must be structurally incapable of recording
/// anything else, including when a call site passes it something careless.
@MainActor
final class DiagnosticsPayloadTests: XCTestCase {

    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    // MARK: - Redaction

    func testSanitizeReplacesAnAbsolutePathWithARedactionMarker() {
        // The known leak shape: `ChatAttachment.id` is a path under the founder's home.
        let path = "\(home)/Documents/pitch-deck-v4.pdf"
        XCTAssertEqual(DiagnosticRedaction.sanitize(path), DiagnosticRedaction.redacted)
    }

    func testSanitizeReplacesARelativePathAndATildePath() {
        XCTAssertEqual(DiagnosticRedaction.sanitize(".codepet/session_chats.json"),
                       DiagnosticRedaction.redacted)
        XCTAssertEqual(DiagnosticRedaction.sanitize("~/Desktop/runway.xlsx"),
                       DiagnosticRedaction.redacted)
    }

    func testSanitizeReplacesAnEmailAddressAndAnyProseWithASpaceInIt() {
        XCTAssertEqual(DiagnosticRedaction.sanitize("founder@murror.app"),
                       DiagnosticRedaction.redacted)
        // A sentence is how a prompt or a model's reasoning would arrive. Nothing in
        // this payload is supposed to be a sentence.
        XCTAssertEqual(DiagnosticRedaction.sanitize("we should raise a seed round"),
                       DiagnosticRedaction.redacted)
    }

    func testSanitizeKeepsTheIdentifiersThePayloadIsActuallyMadeOf() {
        // The guard has to let the real vocabulary through, or it is just an off switch.
        for token in ["quota", "bad_response", "NSURLErrorDomain", "under10s",
                      "run_started", "NSInvalidArgumentException", "concurrentInstance"] {
            XCTAssertEqual(DiagnosticRedaction.sanitize(token), token,
                           "\(token) is shape, not content, and must survive")
        }
    }

    func testAContextValueCarryingAPathIsRedactedByTheTimeItIsAPayloadField() {
        // The end-to-end version: a call site that hands over a path anyway cannot
        // publish one, because the builder — not the caller — does the sanitising.
        let event = DiagnosticEvent(kind: .handledError, site: .chatThreadLoad,
                                    context: ["file": "\(home)/.codepet/session_chats.json"])
        let payload = event.payload(launchId: "L", appVersion: "1.0", build: "1",
                                    osVersion: "macOS 26.2", clientAt: Date())
        XCTAssertEqual(payload["ctx_file"] as? String, DiagnosticRedaction.redacted)
        let joined = payload.values.map { "\($0)" }.joined(separator: " ")
        XCTAssertFalse(joined.contains(home), "no payload field may contain the home directory")
    }

    // MARK: - Error shape

    func testACorruptJSONDecodingErrorReportsItsCaseAndNotTheBytesThatBrokeIt() throws {
        // `DecodingError.dataCorrupted.debugDescription` quotes the offending input —
        // "Unexpected character 'S' around line 1, column 1" and worse. That input is
        // the founder's own chat file, so `String(describing:)` is banned here.
        let secret = "SERIES-A-AT-40M"
        let data = Data(secret.utf8)
        var thrown: Error?
        do {
            _ = try JSONDecoder().decode([String: String].self, from: data)
        } catch { thrown = error }
        let error = try XCTUnwrap(thrown)

        let shape = DiagnosticErrorShape.of(error)
        XCTAssertEqual(shape.type, "DecodingError.dataCorrupted")
        let rendered = "\(shape)"
        XCTAssertFalse(rendered.contains(secret),
                       "the shape must not carry any byte of the undecodable input")
        XCTAssertFalse(rendered.contains("Unexpected character"),
                       "the shape must not carry the decoder's debugDescription")
    }

    func testAMissingKeyReportsTheSchemaPathAndNotTheValuesAroundIt() throws {
        struct Row: Decodable { let role: String }
        let data = Data(#"{"text":"our burn is 40k a month"}"#.utf8)
        var thrown: Error?
        do { _ = try JSONDecoder().decode(Row.self, from: data) } catch { thrown = error }
        let shape = DiagnosticErrorShape.of(try XCTUnwrap(thrown))

        XCTAssertEqual(shape.type, "DecodingError.keyNotFound")
        // The coding path is OUR schema — the field that broke — which is the one thing
        // that makes a decode bug fixable. It is not the founder's data.
        XCTAssertFalse("\(shape)".contains("burn"),
                       "a sibling field's VALUE must never ride along with a coding path")
    }

    func testAURLErrorReportsDomainAndCodeAndNotTheFailingURL() {
        // `URLError.userInfo` carries NSURLErrorFailingURLStringErrorKey — a full URL
        // with whatever query string was on it.
        let error = URLError(.notConnectedToInternet,
                             userInfo: [NSURLErrorFailingURLStringErrorKey:
                                            "https://api.example.com/x?token=sk-live-abc123"])
        let shape = DiagnosticErrorShape.of(error)
        XCTAssertEqual(shape.domain, NSURLErrorDomain)
        XCTAssertEqual(shape.code, URLError.Code.notConnectedToInternet.rawValue)
        XCTAssertFalse("\(shape)".contains("sk-live-abc123"),
                       "a token in the error's userInfo must not reach the shape")
    }

    // MARK: - Payload structure

    func testThePayloadCarriesNoAccountFieldBecauseTheDocumentPathAlreadyIdentifiesIt() {
        let payload = DiagnosticEvent(kind: .handledError, site: .chatTurn)
            .payload(launchId: "L", appVersion: "1.0", build: "1",
                     osVersion: "macOS 26.2", clientAt: Date())
        for forbidden in ["userId", "uid", "email", "displayName", "companyId"] {
            XCTAssertNil(payload[forbidden],
                         "\(forbidden) duplicates companies/{uid}/… and is a second thing to keep right")
        }
    }

    func testAContextKeyCannotOverwriteTheBudgetsCount() {
        // `count` is the one field an admin will act on. A call site passing
        // `context: ["count": "1"]` must not be able to rewrite it, so context is
        // namespaced rather than merged.
        let event = DiagnosticEvent(kind: .handledError, site: .chatTurn, count: 137,
                                    context: ["count": "1", "kind": "nothing"])
        let payload = event.payload(launchId: "L", appVersion: "1.0", build: "1",
                                    osVersion: "macOS 26.2", clientAt: Date())
        XCTAssertEqual(payload["count"] as? Int, 137)
        XCTAssertEqual(payload["kind"] as? String, DiagnosticKind.handledError.rawValue)
        XCTAssertEqual(payload["ctx_count"] as? String, "1")
    }

    func testTwoOccurrencesOfTheSameFailureShareABudgetKeyAndADifferentCodeDoesNot() {
        let base = DiagnosticErrorShape(type: "CompanyChatStreamError", domain: "d",
                                         code: 500, codingPath: nil)
        let other = DiagnosticErrorShape(type: "CompanyChatStreamError", domain: "d",
                                          code: 429, codingPath: nil)
        let a = DiagnosticEvent(kind: .handledError, site: .chatTurn, shape: base,
                                count: 1, context: ["cause": "http"])
        let b = DiagnosticEvent(kind: .handledError, site: .chatTurn, shape: base,
                                count: 99, context: ["cause": "somethingElse"])
        let c = DiagnosticEvent(kind: .handledError, site: .chatTurn, shape: other)
        // Neither the count nor varying context may split the key, or the budget would
        // never coalesce anything.
        XCTAssertEqual(a.budgetKey, b.budgetKey)
        // A 500 and a 429 are different problems and must be counted apart.
        XCTAssertNotEqual(a.budgetKey, c.budgetKey)
    }

    // MARK: - Buckets

    func testAnEmptyThreadFileIsBucketedApartFromAFullOneBecauseTheyAreDifferentBugs() {
        // 0 bytes is a truncated write (ours, and fixable); a full file that will not
        // decode is a schema break (also ours, differently). The DecodingError alone
        // cannot tell them apart.
        XCTAssertEqual(SessionChatStore.sizeBucket(0), "empty")
        XCTAssertEqual(SessionChatStore.sizeBucket(90_000), "under1m")
        XCTAssertEqual(SessionChatStore.sizeBucket(nil), "unread")
        XCTAssertNotEqual(SessionChatStore.sizeBucket(0), SessionChatStore.sizeBucket(90_000))
    }

    func testTheSessionAgeBucketSeparatesALaunchCrashFromALongSessionOne() {
        let now = Date()
        XCTAssertEqual(DiagnosticsBootstrap.ageBucket(now.addingTimeInterval(-3), now: now),
                       "under10s")
        XCTAssertEqual(DiagnosticsBootstrap.ageBucket(now.addingTimeInterval(-9_000), now: now),
                       "under8h")
        // A clock that moved backwards must not produce a negative bucket.
        XCTAssertEqual(DiagnosticsBootstrap.ageBucket(now.addingTimeInterval(60), now: now),
                       "unknown")
    }

    // MARK: - Server-supplied strings

    func testAnUnrecognisedSSEEventNameIsNotForwardedIntoThePayloadVerbatim() {
        // The event name comes off the wire, so it is not ours to trust — and it lands
        // in a Firestore document.
        XCTAssertEqual(VirtualCompanyEvent.knownEventName("brief"), "brief")
        XCTAssertEqual(VirtualCompanyEvent.knownEventName("agent_error"), "agent_error")
        XCTAssertEqual(VirtualCompanyEvent.knownEventName("\(home)/secrets"), "unrecognised")
        XCTAssertEqual(VirtualCompanyEvent.knownEventName(""), "unrecognised")
    }
}
