import Foundation
import FirebaseAuth

/// One repo the founder can pick, as `engListRepos` returns it.
///
/// Mirrors `RepoChoice` in `engGitHub.ts`. A repo missing `fullName` or
/// `defaultBranch` is dropped by the backend rather than offered, because
/// `loadRepo` fails closed on a blank branch — so every row that arrives here
/// is one a run could actually mount.
struct EngRepoChoice: Identifiable, Equatable, Codable {
    let fullName: String
    let url: String
    let defaultBranch: String
    let isPrivate: Bool
    /// ISO-8601, GitHub's `pushed_at`. The list arrives sorted by it, newest
    /// first, so the repo the founder is actually working in is at the top.
    let pushedAt: String

    var id: String { fullName }

    /// `owner/repo` split for display. The whole name is shown, but the owner
    /// is dimmed: a founder scanning twenty rows is reading the repo name.
    var owner: String { fullName.split(separator: "/").first.map(String.init) ?? "" }
    var name: String { fullName.split(separator: "/").last.map(String.init) ?? fullName }
}

/// What came back from linking or creating.
struct EngRepoLink: Equatable, Codable {
    let url: String
    let defaultBranch: String
    /// Only `create` returns one, and it is a URL to hand the founder rather
    /// than to open for them: installing the Vercel app is a decision on their
    /// own account, and Codepet holds no Vercel credential.
    let vercelSetupUrl: String?
}

/// The three repo calls, behind a seam.
///
/// A protocol for the same reason `EngineeringRunning` is one: the XCTest host
/// on Xcode 26.2 crashes when a `@MainActor ObservableObject` deallocates, and
/// a sheet that reaches for the network is a sheet no suite can drive.
protocol EngineeringRepoServing {
    func listRepos() async throws -> [EngRepoChoice]
    func link(fullName: String) async throws -> EngRepoLink
    /// `name` nil lets the backend derive one from the company brief —
    /// `engCreateRepo` slugs whatever it is given anyway, because GitHub
    /// rejects most of what a founder might type and its 422 is not something
    /// they can act on.
    func create(name: String?) async throws -> EngRepoLink
}

/// Which of §5.4's three first-run states the sheet is in.
///
/// All three are reachable on a first send and none may dead-end: the spec's
/// §7 table says "No repo connected → first-run sheet. **Never a dead-end.**"
/// So `needsGitHub` offers the OAuth round-trip rather than an explanation,
/// and `createOnly` is a state in its own right rather than an empty list —
/// a founder with no repos shown an empty picker has been told "no" by a
/// control that looks like it should work.
enum ConnectRepoState: Equatable {
    case loading
    case needsGitHub
    case choose([EngRepoChoice])
    case createOnly
    /// Something we cannot fix from here. Carries the error so the sheet can
    /// use the same words the result bar does.
    case failed(EngineeringError)
}

enum ConnectRepo {
    /// The pure core: what the listing outcome means.
    ///
    /// Separated from the sheet because a `View` cannot be asserted on —
    /// `EngineeringResultBar.message` was moved out for the same reason. Here
    /// the distinction that matters is between "connected, owns nothing" and
    /// "not connected", which the wire reports as an empty array and a 409 and
    /// which lead to two completely different screens.
    static func state(after result: Result<[EngRepoChoice], EngineeringError>) -> ConnectRepoState {
        switch result {
        case .success(let repos):
            return repos.isEmpty ? .createOnly : .choose(repos)
        case .failure(.gitHubNotConnected):
            return .needsGitHub
        case .failure(let error):
            return .failed(error)
        }
    }
}

/// The production `EngineeringRepoServing`.
///
/// Plain JSON, no SSE — none of these three stream. Same base URL, same bearer
/// token and the same `EngineeringClient.error` mapping, so a refusal reads
/// identically whether it came from starting a run or from listing repos.
final class EngineeringRepoClient: EngineeringRepoServing {

    private let base: URL
    private let session: URLSession
    private let idToken: () async throws -> String

    init(
        base: URL = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net")!,
        session: URLSession = .shared,
        idToken: (() async throws -> String)? = nil
    ) {
        self.base = base
        self.session = session
        self.idToken = idToken ?? {
            guard let token = try await Auth.auth().currentUser?.getIDToken() else {
                throw EngineeringError.unknown(401)
            }
            return token
        }
    }

    func listRepos() async throws -> [EngRepoChoice] {
        let data = try await send(path: "engListRepos", method: "GET", body: nil)
        struct Payload: Decodable { let repos: [EngRepoChoice] }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw EngineeringError.unknown(502)
        }
        return payload.repos
    }

    func link(fullName: String) async throws -> EngRepoLink {
        let data = try await send(path: "engLinkRepo", method: "POST", body: ["fullName": fullName])
        return try decodeLink(data)
    }

    func create(name: String?) async throws -> EngRepoLink {
        // An absent name is OMITTED rather than sent empty: `engCreateRepo`
        // branches on a non-blank string, and sending "" would take the same
        // path as nil while looking, on the wire, like a deliberate choice.
        let body = name.map { ["name": $0] } ?? [:]
        let data = try await send(path: "engCreateRepo", method: "POST", body: body)
        return try decodeLink(data)
    }

    // MARK: - plumbing

    private func decodeLink(_ data: Data) throws -> EngRepoLink {
        guard let link = try? JSONDecoder().decode(EngRepoLink.self, from: data) else {
            throw EngineeringError.unknown(502)
        }
        return link
    }

    private func send(path: String, method: String, body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(try await idToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineeringError.unknown(0) }
        guard http.statusCode == 200 else {
            throw EngineeringClient.error(status: http.statusCode, body: data)
        }
        return data
    }
}
