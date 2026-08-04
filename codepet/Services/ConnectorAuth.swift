// The founder's half of the connector consent round-trip.
//
//   1. ask githubOAuthStart (authenticated) for a consent URL
//   2. open it in ASWebAuthenticationSession
//   3. GitHub redirects to the Cloud Function, which stores the token and then
//      redirects to codepet://oauth/callback
//   4. the session recognises that scheme, closes itself, and hands the URL back
//
// The app never sees the access token — step 3 happens entirely between GitHub
// and the function. All that comes back here is whether it worked.
import Foundation
import AuthenticationServices
import FirebaseAuth

/// Why a connector attempt ended. `denied` is the founder pressing Cancel on the
/// provider's consent screen, which is a normal outcome and not worth an error.
enum ConnectorAuthResult: Equatable {
    case connected
    case denied
    case failed(String)
}

enum ConnectorProvider: String, CaseIterable {
    case github

    /// The `start` endpoint that mints this provider's consent URL.
    var startEndpoint: URL {
        switch self {
        case .github:
            return URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/githubOAuthStart")!
        }
    }

    /// Matches the `Toolkit` catalog id, so a row can find its provider.
    var toolId: String { rawValue }
}

@MainActor
final class ConnectorAuth: NSObject {
    static let shared = ConnectorAuth()

    /// Held for the lifetime of the sheet: ASWebAuthenticationSession is
    /// deallocated — and the sheet silently vanishes — if nothing retains it.
    private var session: ASWebAuthenticationSession?

    private struct StartResponse: Decodable { let authorizeUrl: String }

    /// Runs the whole round-trip. Returns only once the sheet has closed.
    func connect(_ provider: ConnectorProvider) async -> ConnectorAuthResult {
        guard let token = try? await Auth.auth().currentUser?.getIDToken() else {
            return .failed("not_signed_in")
        }

        var request = URLRequest(url: provider.startEndpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let start = try? JSONDecoder().decode(StartResponse.self, from: data),
              let authorizeUrl = URL(string: start.authorizeUrl)
        else {
            return .failed("start_failed")
        }

        return await presentConsent(authorizeUrl)
    }

    private func presentConsent(_ url: URL) async -> ConnectorAuthResult {
        await withCheckedContinuation { continuation in
            // The continuation must be resumed exactly once. The completion
            // handler is the single resume point, and `session` is cleared there
            // so a second callback cannot reach a spent continuation.
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "codepet"
            ) { [weak self] callbackURL, error in
                self?.session = nil
                continuation.resume(returning: Self.interpret(callbackURL: callbackURL, error: error))
            }
            session.presentationContextProvider = self
            // Consent belongs to the founder's own browser session — reusing the
            // shared cookie jar means an already-signed-in GitHub user sees a
            // one-click approve rather than a login form.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            if !session.start() {
                self.session = nil
                continuation.resume(returning: .failed("could_not_present"))
            }
        }
    }

    /// The function encodes the outcome in the query string it redirects to, so
    /// the app learns what happened without ever touching the token.
    static func interpret(callbackURL: URL?, error: Error?) -> ConnectorAuthResult {
        if let error = error as? ASWebAuthenticationSessionError,
           error.code == .canceledLogin {
            return .denied   // the founder closed the sheet
        }
        if let error { return .failed(error.localizedDescription) }
        guard let callbackURL,
              let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        else {
            return .failed("no_callback")
        }
        let value = { (name: String) in items.first { $0.name == name }?.value }
        switch value("status") {
        case "ok":
            return .connected
        case "error":
            // "denied" here is the provider's own cancel, distinct from closing the sheet.
            return value("reason") == "denied" ? .denied : .failed(value("reason") ?? "unknown")
        default:
            return .failed("bad_callback")
        }
    }
}

extension ConnectorAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
