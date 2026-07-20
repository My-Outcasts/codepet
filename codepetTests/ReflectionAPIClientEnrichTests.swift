import XCTest
@testable import codepet

final class ReflectionAPIClientEnrichTests: XCTestCase {
    func testEnrichBriefReturnsMergedBriefFromServer() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { _ in
            let body = #"{"brief":{"projectName":"Codepet","summary":"A recap companion.","audience":"devs","categories":["macOS app"]}}"#
            return (200, Data(body.utf8))
        }
        let client = ReflectionAPIClient(session: URLSession(configuration: config)) { "test-token" }
        let out = try await client.enrichBrief(CompanyBrief(projectName: "Codepet", oneLiner: "a recap tool"))
        XCTAssertEqual(out.summary, "A recap companion.")
        XCTAssertEqual(out.categories, ["macOS app"])
    }

    func testEnrichBriefThrowsOnHTTPError() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { _ in (429, Data(#"{"error":"daily_limit_reached"}"#.utf8)) }
        let client = ReflectionAPIClient(session: URLSession(configuration: config)) { "t" }
        do { _ = try await client.enrichBrief(CompanyBrief(oneLiner: "x")); XCTFail("expected throw") }
        catch { /* expected */ }
    }
}

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
