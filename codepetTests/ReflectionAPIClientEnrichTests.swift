import XCTest
@testable import codepet

/// `enrichBrief` is the first call onboarding makes, and it used to be the clearest example of
/// "not granted means use the Cloud Function". That function spends an Anthropic key Codepet no
/// longer holds, so the two tests that used to live here — a 200 merged from the server, and a
/// 429 rethrown — were pinning a route that can only answer 401.
final class ReflectionAPIClientEnrichTests: XCTestCase {

    override func setUp() {
        super.setUp()
        LocalTransportRouter.apply(companyId: nil)
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// The guard: an ungranted founder gets an error, and the Cloud Function is never asked.
    /// Deleting the `.blocked` arm in `localOneShot` turns this red on the second assertion —
    /// the stub would be hit and a brief would come back.
    func testEnrichBriefRefusesRatherThanCallingTheCloudFunction() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let reached = Reached()
        StubURLProtocol.handler = { _ in
            reached.hit = true
            let body = #"{"brief":{"projectName":"Codepet","summary":"A recap companion.","audience":"devs","categories":["macOS app"]}}"#
            return (200, Data(body.utf8))
        }
        let client = ReflectionAPIClient(session: URLSession(configuration: config)) { "test-token" }
        do {
            _ = try await client.enrichBrief(CompanyBrief(projectName: "Codepet", oneLiner: "a recap tool"))
            XCTFail("expected a refusal, not a hosted answer")
        } catch {
            // expected
        }
        XCTAssertFalse(reached.hit, "an ungranted founder must not reach the Cloud Function")
    }
}

/// A box, because `StubURLProtocol.handler` is a non-escaping-looking global the test has to
/// read back after the call returns.
private final class Reached: @unchecked Sendable { var hit = false }

/// Minimal URLProtocol stub (add once; skip if the test target already has one).
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
