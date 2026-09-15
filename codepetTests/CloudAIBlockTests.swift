import XCTest
@testable import codepet

/// The interceptor that refuses every call which would spend Codepet's Anthropic key.
/// Codepet holds no such key any more — every one of these endpoints answers 401 — so
/// refusal is unconditional, not a preference. Every case here guards either what gets
/// refused or what must keep working.
final class CloudAIBlockTests: XCTestCase {

    private func cf(_ name: String) -> URLRequest {
        URLRequest(url: URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/\(name)")!)
    }

    // MARK: - Unconditional refusal

    /// **The refusal is no longer a preference.** Codepet does not hold an Anthropic key any
    /// more, so a request to a key-spending endpoint cannot succeed — it can only fail slowly,
    /// after a round trip, with a 401 the founder cannot act on. Refusing locally is the
    /// honest answer.
    func testRefusesWithoutAnyCompanyOrSetting() {
        let url = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/runTask")!
        XCTAssertTrue(CloudAIBlock.shouldRefuse(URLRequest(url: url)),
                      "a key-spending path was allowed through with no company set")
    }

    /// The neighbours must still pass. Blocking the whole host would break repo connection for a
    /// change that says nothing about GitHub.
    func testStillAllowsTheNonAIneighbours() {
        for path in ["githubOAuthStart", "githubOAuthCallback", "engShip", "engPreview",
                     "engDiff", "engListRepos", "engLinkRepo", "engCreateRepo",
                     "revenueCatWebhook", "capabilities"] {
            let url = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/\(path)")!
            XCTAssertFalse(CloudAIBlock.shouldRefuse(URLRequest(url: url)),
                           "\(path) spends no Anthropic key and must not be refused")
        }
    }

    // MARK: - What it refuses

    func testEveryKeySpendingEndpointIsRefused() {
        for name in CloudAIBlock.blockedPaths {
            XCTAssertTrue(CloudAIBlock.shouldRefuse(cf(name)), "\(name) still reachable")
        }
    }

    /// The list is derived from the `secrets:` declarations in functions/src/index.ts, which
    /// is the authority. These three are the ones a reader would most expect to be missing.
    func testTheListCoversTheExpensiveOnes() {
        XCTAssertTrue(CloudAIBlock.blockedPaths.contains("virtualCompanyRun"))
        XCTAssertTrue(CloudAIBlock.blockedPaths.contains("companyChat"))
        XCTAssertTrue(CloudAIBlock.blockedPaths.contains("runTask"))
    }

    // MARK: - What must keep working

    /// GitHub OAuth spends a GITHUB secret, not the Anthropic key. Blocking it would break
    /// repo connection for a change that says nothing about repos.
    func testGitHubOAuthKeepsWorking() {
        XCTAssertFalse(CloudAIBlock.shouldRefuse(cf("githubOAuthStart")))
        XCTAssertFalse(CloudAIBlock.shouldRefuse(cf("githubOAuthCallback")))
    }

    /// `index.ts:162` states outright that these do not touch Anthropic, so they declare no
    /// key — and refusing them would break the repo features for no gain.
    func testTheNonAIEngineeringHandlersKeepWorking() {
        for name in ["engDiff", "engShip", "engPreview", "engListRepos", "engLinkRepo", "engCreateRepo", "engBalance"] {
            XCTAssertFalse(CloudAIBlock.shouldRefuse(cf(name)), "\(name) must stay reachable")
        }
    }

    /// Firestore and Auth are what keep the app usable while refusing — sign-in works, the
    /// company loads, and a failure to answer is therefore about the model call alone.
    func testFirestoreAndAuthAreUntouched() {
        for url in ["https://firestore.googleapis.com/v1/projects/x",
                    "https://identitytoolkit.googleapis.com/v1/accounts:lookup",
                    "https://securetoken.googleapis.com/v1/token"] {
            XCTAssertFalse(CloudAIBlock.shouldRefuse(URLRequest(url: URL(string: url)!)))
        }
    }

    // MARK: - The key

    /// The key builder is retained even though no setting reads it any more — see the task
    /// report for why it was not deleted alongside `isEnabled`/`setEnabled`.
    func testTheKeyIsPrefixedAndScoped() {
        let key = CloudAIBlock.key("c1")
        XCTAssertTrue(key.hasPrefix("cp_"))
        XCTAssertTrue(key.contains("c1"))
    }
}
