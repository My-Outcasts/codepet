import XCTest
@testable import codepet

/// The founder-facing switch that refuses every call which would spend Codepet's Anthropic
/// key. Every case here guards either what gets refused or what must keep working.
final class CloudAIBlockTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "cloud-ai-block-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        CloudAIBlock.apply(companyId: nil, defaults: defaults)   // known-off baseline
    }

    override func tearDown() {
        CloudAIBlock.apply(companyId: nil, defaults: defaults)
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func cf(_ name: String) -> URLRequest {
        URLRequest(url: URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/\(name)")!)
    }

    // MARK: - Off by default

    /// A build that never calls `apply` must behave exactly as it did before this existed.
    func testNothingIsRefusedUntilAFounderAsksForIt() {
        XCTAssertFalse(CloudAIBlock.isRefusing)
        XCTAssertFalse(CloudAIBlock.shouldRefuse(cf("companyChat")))
    }

    func testTheSettingIsOffForACompanyThatNeverSetIt() {
        XCTAssertFalse(CloudAIBlock.isEnabled(companyId: "c1", defaults: defaults))
    }

    // MARK: - What it refuses

    func testEveryKeySpendingEndpointIsRefusedWhenOn() {
        CloudAIBlock.setEnabled(true, companyId: "c1", defaults: defaults)
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
    /// repo connection for a switch whose label says nothing about repos.
    func testGitHubOAuthKeepsWorking() {
        CloudAIBlock.setEnabled(true, companyId: "c1", defaults: defaults)
        XCTAssertFalse(CloudAIBlock.shouldRefuse(cf("githubOAuthStart")))
        XCTAssertFalse(CloudAIBlock.shouldRefuse(cf("githubOAuthCallback")))
    }

    /// `index.ts:162` states outright that these do not touch Anthropic, so they declare no
    /// key — and refusing them would break the repo features for no gain.
    func testTheNonAIEngineeringHandlersKeepWorking() {
        CloudAIBlock.setEnabled(true, companyId: "c1", defaults: defaults)
        for name in ["engDiff", "engShip", "engPreview", "engListRepos", "engLinkRepo", "engCreateRepo", "engBalance"] {
            XCTAssertFalse(CloudAIBlock.shouldRefuse(cf(name)), "\(name) must stay reachable")
        }
    }

    /// Firestore and Auth are what keep the app usable while refusing — sign-in works, the
    /// company loads, and a failure to answer is therefore about the model call alone.
    func testFirestoreAndAuthAreUntouched() {
        CloudAIBlock.setEnabled(true, companyId: "c1", defaults: defaults)
        for url in ["https://firestore.googleapis.com/v1/projects/x",
                    "https://identitytoolkit.googleapis.com/v1/accounts:lookup",
                    "https://securetoken.googleapis.com/v1/token"] {
            XCTAssertFalse(CloudAIBlock.shouldRefuse(URLRequest(url: URL(string: url)!)))
        }
    }

    // MARK: - Per company, and immediate

    /// One Mac can hold two accounts. Founder A choosing to run without the key must not
    /// silently break founder B's app — the same reasoning the grant is keyed by.
    func testOneFoundersRefusalDoesNotGovernAnother() {
        CloudAIBlock.setEnabled(true, companyId: "c1", defaults: defaults)
        XCTAssertFalse(CloudAIBlock.isEnabled(companyId: "c2", defaults: defaults))

        // Switching accounts re-points the mirror rather than inheriting the refusal.
        CloudAIBlock.apply(companyId: "c2", defaults: defaults)
        XCTAssertFalse(CloudAIBlock.shouldRefuse(cf("companyChat")))
    }

    /// Signing out must stop the previous account's refusal from governing whoever is next.
    func testSigningOutClearsTheMirror() {
        CloudAIBlock.setEnabled(true, companyId: "c1", defaults: defaults)
        XCTAssertTrue(CloudAIBlock.shouldRefuse(cf("companyChat")))
        CloudAIBlock.apply(companyId: nil, defaults: defaults)
        XCTAssertFalse(CloudAIBlock.shouldRefuse(cf("companyChat")))
    }

    /// No relaunch: the founder asked for a switch, and a switch that needs a restart is a
    /// setting they will not trust. Turning it off takes effect on the next request.
    func testTurningItOffTakesEffectImmediately() {
        CloudAIBlock.setEnabled(true, companyId: "c1", defaults: defaults)
        XCTAssertTrue(CloudAIBlock.shouldRefuse(cf("companyChat")))
        CloudAIBlock.setEnabled(false, companyId: "c1", defaults: defaults)
        XCTAssertFalse(CloudAIBlock.shouldRefuse(cf("companyChat")))
    }

    /// The key is swept per uid by AccountDataStore, and scoped so a switch path that
    /// forgets the vault is still correct.
    func testTheKeyIsPrefixedAndScoped() {
        let key = CloudAIBlock.key("c1")
        XCTAssertTrue(key.hasPrefix("cp_"))
        XCTAssertTrue(key.contains("c1"))
    }
}
