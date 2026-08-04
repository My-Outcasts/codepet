import XCTest
import AuthenticationServices
@testable import codepet

/// `interpret` is the whole decision surface of the consent round-trip: everything
/// the app learns about a connector attempt arrives as a callback URL or an error.
/// It is deliberately a static pure function so it can be tested without presenting
/// a sheet.
final class ConnectorAuthTests: XCTestCase {

    private func callback(_ query: String) -> URL {
        URL(string: "codepet://oauth/callback?\(query)")!
    }

    func testSuccessfulCallbackConnects() {
        let result = ConnectorAuth.interpret(
            callbackURL: callback("provider=github&status=ok"), error: nil)
        XCTAssertEqual(result, .connected)
    }

    /// The founder pressing Cancel on GitHub's consent screen: the function
    /// redirects with reason=denied. That is a normal outcome, not a failure —
    /// surfacing it as an error would put a red banner on a deliberate choice.
    func testProviderDenialIsDeniedNotFailure() {
        let result = ConnectorAuth.interpret(
            callbackURL: callback("provider=github&status=error&reason=denied"), error: nil)
        XCTAssertEqual(result, .denied)
    }

    /// Closing the sheet raises canceledLogin with no callback URL — the same
    /// user intent as above, reached by a different path, so it maps the same way.
    func testClosingTheSheetIsDenied() {
        let err = ASWebAuthenticationSessionError(.canceledLogin)
        XCTAssertEqual(ConnectorAuth.interpret(callbackURL: nil, error: err), .denied)
    }

    func testExchangeFailureCarriesTheReason() {
        let result = ConnectorAuth.interpret(
            callbackURL: callback("provider=github&status=error&reason=exchange_failed"), error: nil)
        XCTAssertEqual(result, .failed("exchange_failed"))
    }

    /// A state that failed verification must not read as success.
    func testBadStateIsFailure() {
        let result = ConnectorAuth.interpret(
            callbackURL: callback("provider=github&status=error&reason=bad_state"), error: nil)
        XCTAssertEqual(result, .failed("bad_state"))
    }

    func testMissingCallbackIsFailure() {
        XCTAssertEqual(ConnectorAuth.interpret(callbackURL: nil, error: nil), .failed("no_callback"))
    }

    /// A callback with no recognisable status must not be treated as connected —
    /// the default branch is the one that would silently mark a connector live.
    func testUnknownStatusIsFailure() {
        XCTAssertEqual(
            ConnectorAuth.interpret(callbackURL: callback("provider=github"), error: nil),
            .failed("bad_callback"))
        XCTAssertEqual(
            ConnectorAuth.interpret(callbackURL: callback("status=weird"), error: nil),
            .failed("bad_callback"))
    }

    func testProviderEndpointAndToolIdLineUpWithTheCatalog() {
        XCTAssertEqual(ConnectorProvider.github.toolId, "github")
        XCTAssertTrue(ConnectorProvider.github.startEndpoint.absoluteString.hasSuffix("githubOAuthStart"))
        // The row in Environment finds its provider by the catalog id, so a rename
        // on either side has to break a test rather than silently stop matching.
        XCTAssertNotNil(Toolkit.catalog.first { $0.id == ConnectorProvider.github.toolId })
    }
}
