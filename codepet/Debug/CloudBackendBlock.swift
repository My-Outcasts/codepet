import Foundation
import os

/// Refuses every request to the Cloud Functions host, so a turn that reaches the paid path
/// FAILS LOUDLY instead of quietly working.
///
/// **What this is for.** Once `cp_claudeCodeAuthorised` routes chat to the founder's own
/// Claude Code, the interesting question stops being "does local work" and becomes "is
/// anything still going to the API key". That is hard to answer by looking: a silent
/// fallback produces a correct-looking reply. So this makes the cloud path unreachable and
/// lets the app prove its own claim — anything that still answers, answered locally.
///
/// **It does NOT touch the secret.** `ANTHROPIC_API_KEY` stays in Firebase and the
/// functions stay deployed. Destroying the secret would break production for everyone and
/// is close to impossible to undo cleanly; blocking the client is reversible by relaunching.
///
/// **DEBUG only, on purpose.** A shipped kill switch for the backend is a liability, not a
/// feature.
///
/// Enable with a LAUNCH ARGUMENT:
///
///     open <path>/codepet.app --args -CODEPET_BLOCK_BACKEND YES
///
/// `defaults write app.murror.codepet CODEPET_BLOCK_BACKEND -bool YES` **does not work and
/// fails silently** — the same trap `MockChat` documents. A sandboxed container left over
/// from when this app WAS sandboxed still exists at
/// `~/Library/Containers/app.murror.codepet`, and `defaults` resolves the bundle id THROUGH
/// it, so the write lands in a plist the unsandboxed app never reads.
enum CloudBackendBlock {

    static let launchKey = "CODEPET_BLOCK_BACKEND"
    static let log = Logger(subsystem: "app.murror.codepet", category: "BackendBlock")

    /// Every Cloud Function lives here. Firestore and Firebase Auth do NOT — they use
    /// `firestore.googleapis.com` and `identitytoolkit.googleapis.com` — which is what keeps
    /// the app usable while blocked, and therefore what makes the test meaningful: the
    /// company still loads, so a failure to answer is about the model call and nothing else.
    static let blockedHostFragment = "cloudfunctions.net"

    #if DEBUG
    static var isOn: Bool { UserDefaults.standard.bool(forKey: launchKey) }

    /// Registers the interceptor. Call once, before anything makes a request.
    ///
    /// `URLProtocol.registerClass` reaches `URLSession.shared` and any session built from a
    /// `.default` configuration, which is every caller here. It would NOT reach a session
    /// with its own `protocolClasses` — none exist, and a test that injects its own session
    /// is deliberately unaffected.
    static func installIfRequested() {
        guard isOn else { return }
        URLProtocol.registerClass(BlockingURLProtocol.self)
        log.warning("backend blocked — every cloudfunctions.net request will fail")
    }
    #else
    static var isOn: Bool { false }
    static func installIfRequested() {}
    #endif
}

#if DEBUG
/// Fails matching requests rather than dropping them. A failure surfaces as an error the
/// app already knows how to report; a hang would look like a slow network and teach nothing.
final class BlockingURLProtocol: URLProtocol {

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.contains(CloudBackendBlock.blockedHostFragment) ?? false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.lastPathComponent ?? "?"
        CloudBackendBlock.log.error("BLOCKED \(path, privacy: .public)")
        // `.notConnectedToInternet` on purpose: every client here already has an honest
        // offline path for it, so the app degrades the way it was designed to instead of
        // through an error nobody wrote copy for. The log line above is what tells a
        // developer it was deliberate.
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
#endif
