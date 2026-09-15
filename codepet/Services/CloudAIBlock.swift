import Foundation
import os

/// Refuses every Cloud Function call which would spend Codepet's Anthropic API key.
///
/// **Unconditional, not a preference.** The key was deleted from the Anthropic console on
/// 26 Aug 2026: every one of these endpoints now answers 401, and every one of them has a
/// local path. There is nothing left to decide, so this refuses every time, for every
/// company, with no setting to consult.
///
/// **Why an interceptor rather than a check in each client.** There is no shared HTTP
/// helper: six clients build their own requests. A guarantee that only holds for the
/// clients someone remembered to update is not a guarantee — so this sits below all of
/// them, and a client added next month is covered without being told about this file.
///
/// **Why a path list rather than the whole host.** `githubOAuthStart` and
/// `githubOAuthCallback` live on the same host and spend a GitHub secret, not the Anthropic
/// key. Blocking them would break repo connection for a change that says nothing about it.
/// The `eng*` handlers split the same way: three of them reach Anthropic, the rest are
/// GitHub and Firestore only (`index.ts:162` says so outright).
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

    /// Whether this request would spend the API key. Pure, so it is testable without a
    /// network or a registered protocol.
    ///
    /// **No longer gated on a setting.** Codepet holds no Anthropic key: every one of these
    /// endpoints answers 401, and every one of them has a local path. Refusing here turns a
    /// slow remote failure the founder cannot act on into an immediate local one that names
    /// the real problem.
    static func shouldRefuse(_ request: URLRequest) -> Bool {
        guard let url = request.url,
              url.host?.contains(hostFragment) == true else { return false }
        return blockedPaths.contains(url.lastPathComponent)
    }

    /// Install once, at launch.
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
        CloudAIBlock.log.error("REFUSED \(path, privacy: .public) — Codepet holds no Anthropic key")
        // `.notConnectedToInternet`, for the reason `CloudBackendBlock` records: every client
        // here already has an honest offline path for that code, so the app degrades the way
        // it was designed to instead of through an error nobody wrote copy for.
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
