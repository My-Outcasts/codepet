import Foundation
import os

/// A founder-facing switch that refuses every Cloud Function call which would spend
/// Codepet's Anthropic API key.
///
/// **Why an interceptor rather than a check in each client.** There is no shared HTTP
/// helper: six clients build their own requests. A guarantee that only holds for the
/// clients someone remembered to update is not a guarantee — so this sits below all of
/// them, and a client added next month is covered without being told about this file.
///
/// **Why a path list rather than the whole host.** `githubOAuthStart` and
/// `githubOAuthCallback` live on the same host and spend a GitHub secret, not the Anthropic
/// key. Blocking them would break repo connection for a switch that says nothing about it.
/// The `eng*` handlers split the same way: three of them reach Anthropic, the rest are
/// GitHub and Firestore only (`index.ts:162` says so outright).
///
/// **Consulted per request, so the switch takes effect immediately.** No relaunch — a
/// founder who turns it off mid-session gets the next turn answered.
enum CloudAIBlock {

    static let log = Logger(subsystem: "app.murror.codepet", category: "CloudAIBlock")

    /// Persisted per company id, never device-global — the same reasoning
    /// `ClaudeCodeAuthorisation` records. One Mac can hold two accounts, and founder A
    /// deciding to run without the key must not silently break founder B's app.
    static func key(_ companyId: String) -> String { "cp_neverUseApiKey_\(companyId)" }

    /// **Every Cloud Function that declares `ANTHROPIC_API_KEY` and is reachable from the
    /// app.** Derived from the `secrets:` declarations in `functions/src/index.ts`, which is
    /// the authority — not from memory of which features feel AI-ish.
    ///
    /// Absent on purpose: `githubOAuthStart` / `githubOAuthCallback` (GitHub secret),
    /// `engDiff` / `engShip` / `engPreview` / `engListRepos` / `engLinkRepo` /
    /// `engCreateRepo` / `engBalance` (GitHub and Firestore only), `revenueCatWebhook`.
    static let blockedPaths: Set<String> = [
        "companyChat", "virtualCompanyRun", "runTask",
        "generateRoadmap", "extractDecisions", "generatePlan", "generateGuidance",
        "generateDictionary", "enrichBrief", "synthesizeBrief", "distillReference",
        "summarizeTurn", "summarizeSession", "chatSession",
        "engStartRun", "engStream", "engSendTurn",
    ]

    static let hostFragment = "cloudfunctions.net"

    /// Whether requests are being refused right now.
    ///
    /// A MIRROR of the persisted setting, not the source of truth. `URLProtocol.canInit` is
    /// a class function with no access to the signed-in company, so it cannot read a
    /// per-company key itself. Whoever knows the company — the panel that flips the switch,
    /// and the store when it loads one — calls `apply(_:)`. Defaults to false so a build
    /// that never calls it behaves exactly as it did before this file existed.
    private(set) nonisolated(unsafe) static var isRefusing = false

    /// Point the mirror at a company's setting. Safe to call repeatedly.
    static func apply(companyId: String?,
                      defaults: UserDefaults = .standard) {
        guard let companyId, !companyId.isEmpty else {
            isRefusing = forcedOn
            return
        }
        isRefusing = forcedOn || defaults.bool(forKey: key(companyId))
    }

    static func isEnabled(companyId: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(companyId))
    }

    static func setEnabled(_ on: Bool, companyId: String, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key(companyId))
        isRefusing = forcedOn || on
        log.info("api-key refusal \(on ? "on" : "off", privacy: .public)")
    }

    /// The DEBUG launch argument still forces it on, for tests and for a run where nobody
    /// wants to click through Settings first. It cannot be turned off from the UI while set,
    /// which is why `apply` and `setEnabled` both OR it in rather than overwriting.
    static var forcedOn: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: CloudBackendBlock.launchKey)
        #else
        return false
        #endif
    }

    /// Whether this request would spend the API key. Pure, so it is testable without a
    /// network or a registered protocol.
    static func shouldRefuse(_ request: URLRequest) -> Bool {
        guard isRefusing else { return false }
        guard let url = request.url,
              url.host?.contains(hostFragment) == true else { return false }
        return blockedPaths.contains(url.lastPathComponent)
    }

    /// Install once, at launch. The protocol asks `shouldRefuse` per request, so
    /// registering unconditionally costs nothing while the switch is off.
    static func install() {
        URLProtocol.registerClass(CloudAIBlockingURLProtocol.self)
    }
}

/// Fails a refused request rather than dropping it, so the app reports something.
final class CloudAIBlockingURLProtocol: URLProtocol {

    override class func canInit(with request: URLRequest) -> Bool {
        CloudAIBlock.shouldRefuse(request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.lastPathComponent ?? "?"
        CloudAIBlock.log.error("REFUSED \(path, privacy: .public) — founder turned the API key off")
        // `.notConnectedToInternet`, for the reason `CloudBackendBlock` records: every client
        // here already has an honest offline path for that code, so the app degrades the way
        // it was designed to instead of through an error nobody wrote copy for.
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
