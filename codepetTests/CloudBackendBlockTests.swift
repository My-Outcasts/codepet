import XCTest
@testable import codepet

/// The test-only kill switch that makes "nothing still uses the API key" provable instead
/// of asserted. A silent fallback produces a correct-looking reply, so the only way to know
/// is to make the paid path unreachable and see whether anything still answers.
final class CloudBackendBlockTests: XCTestCase {

    private func request(_ url: String) -> URLRequest {
        URLRequest(url: URL(string: url)!)
    }

    // MARK: - What gets blocked

    /// Every Cloud Function lives on this host, so matching it catches all eighteen
    /// key-holding endpoints without touching a single client.
    func testItInterceptsTheCloudFunctionsHost() {
        XCTAssertTrue(BlockingURLProtocol.canInit(with:
            request("https://us-central1-devpet-8f4b1.cloudfunctions.net/companyChat")))
        XCTAssertTrue(BlockingURLProtocol.canInit(with:
            request("https://us-central1-devpet-8f4b1.cloudfunctions.net/runTask")))
        XCTAssertTrue(BlockingURLProtocol.canInit(with:
            request("https://us-central1-devpet-8f4b1.cloudfunctions.net/virtualCompanyRun")))
    }

    /// **This is what makes the experiment meaningful.** Firestore and Firebase Auth are on
    /// different hosts, so the app still signs in and still loads the company while blocked.
    /// If they were caught too, a chat that failed to answer would be indistinguishable from
    /// an app that never got off the ground — and the test would prove nothing.
    func testItLeavesFirestoreAndAuthAlone() {
        XCTAssertFalse(BlockingURLProtocol.canInit(with:
            request("https://firestore.googleapis.com/v1/projects/devpet-8f4b1/databases")))
        XCTAssertFalse(BlockingURLProtocol.canInit(with:
            request("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword")))
        XCTAssertFalse(BlockingURLProtocol.canInit(with:
            request("https://securetoken.googleapis.com/v1/token")))
    }

    /// Anthropic is never reached from the app — only from a Cloud Function or from the
    /// founder's own `claude`. Asserted anyway, because a future direct call would be a
    /// design violation this catches for free.
    func testItLeavesUnrelatedHostsAlone() {
        XCTAssertFalse(BlockingURLProtocol.canInit(with: request("https://api.anthropic.com/v1/messages")))
        XCTAssertFalse(BlockingURLProtocol.canInit(with: request("https://claude.ai/install.sh")))
    }

    // MARK: - How it fails

    /// Fails rather than hangs, and fails as `.notConnectedToInternet` specifically: every
    /// client here already has an honest offline path for that code, so the app degrades the
    /// way it was designed to instead of through an error nobody wrote copy for.
    func testAnInterceptedRequestFailsAsOffline() {
        let expectation = expectation(description: "the request fails")
        let protocolInstance = BlockingURLProtocol(
            request: request("https://us-central1-devpet-8f4b1.cloudfunctions.net/companyChat"),
            cachedResponse: nil,
            client: FailureRecorder { error in
                XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
                expectation.fulfill()
            })
        protocolInstance.startLoading()
        wait(for: [expectation], timeout: 2)
    }

    // MARK: - Off unless asked for

    /// A launch argument, never a preference. `defaults write` does not reach this app and
    /// fails SILENTLY — a leftover sandbox container at
    /// `~/Library/Containers/app.murror.codepet` makes `defaults` resolve the bundle id
    /// through it, so the write lands in a plist the unsandboxed app never reads. The same
    /// trap `MockChat` documents, and it cost an hour there.
    func testTheFlagIsALaunchArgumentName() {
        XCTAssertEqual(CloudBackendBlock.launchKey, "CODEPET_BLOCK_BACKEND")
    }

    /// Off in this test run, which is also the proof it is off by default: no launch
    /// argument was passed, so nothing is intercepted and every other suite is unaffected.
    func testItIsOffWithoutTheLaunchArgument() {
        XCTAssertFalse(CloudBackendBlock.isOn)
    }
}

/// Captures the failure a `URLProtocol` reports, so the error can be asserted without a
/// network round trip.
private final class FailureRecorder: NSObject, URLProtocolClient {
    private let onFailure: (Error) -> Void
    init(onFailure: @escaping (Error) -> Void) { self.onFailure = onFailure }

    func urlProtocol(_ protocol: URLProtocol, didFailWithError error: Error) { onFailure(error) }

    // Unused, but required by the protocol.
    func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) {}
    func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) {}
    func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) {}
    func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {}
    func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {}
    func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) {}
    func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) {}
}
