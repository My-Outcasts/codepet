import Foundation
import Combine

@MainActor
final class SessionChatController: ObservableObject {

    @Published private(set) var inFlightSessionId: String?
    @Published private(set) var streamingText: String = ""
    @Published var error: ChatError?

    enum ChatError: Equatable {
        case notSignedIn
        case rateLimited(resetAt: Date?, limit: Int?)
        case networkOrServer(message: String)
    }

    private let api: ReflectionAPIClientProtocol
    private let store: SessionChatStore
    private var currentTask: Task<Void, Never>?

    /// Probed once at construction, not per send — same reasoning as `CompanyStore`'s own
    /// instance (`InstalledProviders`'s doc comment: a subprocess per render/call is the
    /// thing this cache exists to avoid). This chat runs through `LocalTransportRouter
    /// .forOneShot()` (Task 9's context note: no `prefer`, so either CLI may pick it up), which
    /// is why a `.blocked(.notGranted)` reaching this controller needs to know what is
    /// actually installed before naming a fix.
    let installedProviders = InstalledProviders()

    init(api: ReflectionAPIClientProtocol, store: SessionChatStore) {
        self.api = api
        self.store = store
        // Skipped under XCTest — same reasoning as `CompanyStore.hydrate` (Task 9): a real
        // subprocess probe racing every test that constructs this controller would make
        // `.blocked` mapping depend on whatever CLIs happen to be on the machine running the
        // suite. A test that wants a specific installed set calls `installedProviders.apply(_:)`
        // itself.
        if !AppEnvironment.isRunningTests {
            Task { await installedProviders.refresh() }
        }
    }

    /// Send a user message and stream the pet reply for the given session.
    /// Returns when the stream completes, errors, or is cancelled.
    func send(userText: String, sessionId: String, request: ChatSessionRequest) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Append the user message immediately.
        let userMsg = ChatMessage(id: UUID(), role: .user, text: trimmed, createdAt: Date())
        store.append(userMsg, to: sessionId)

        inFlightSessionId = sessionId
        streamingText = ""
        error = nil

        let task = Task { @MainActor in
            do {
                for try await event in api.chatSessionStream(request) {
                    if Task.isCancelled { return }
                    switch event {
                    case .delta(let text):
                        streamingText += text
                    case .done:
                        let petMsg = ChatMessage(
                            id: UUID(),
                            role: .pet,
                            text: streamingText,
                            createdAt: Date()
                        )
                        if !petMsg.text.isEmpty {
                            store.append(petMsg, to: sessionId)
                        }
                    }
                }
                streamingText = ""
                inFlightSessionId = nil
            } catch let apiError as ReflectionAPIError {
                streamingText = ""
                inFlightSessionId = nil
                // `request.language` (a wire `String`, "en"/"vi") is the founder's language for
                // THIS turn — reachable here because `request` is this method's own parameter,
                // captured by the closure like everything else in this `do` block. Task 9: the
                // pre-existing gap was that `map` had no Vietnamese branch at all and answered
                // English unconditionally, which this closes now that the call site actually has
                // somewhere to read the language from.
                let lang = AppLanguage(rawValue: request.language) ?? .en
                error = Self.map(apiError, installed: installedProviders.installed, lang: lang)
            } catch is CancellationError {
                streamingText = ""
                inFlightSessionId = nil
            } catch {
                streamingText = ""
                inFlightSessionId = nil
                self.error = .networkOrServer(message: String(describing: error))
            }
        }
        currentTask = task
        await task.value
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        streamingText = ""
        inFlightSessionId = nil
    }

    /// `installed`/`lang` are only read by `.blocked` — every other case's message is
    /// language-agnostic (an HTTP status, a describing-error string), so they stay as they
    /// were rather than gaining a Vietnamese branch that has nothing to translate.
    private static func map(_ apiError: ReflectionAPIError, installed: Set<AIProvider>,
                           lang: AppLanguage) -> ChatError {
        switch apiError {
        case .notSignedIn, .optedOut:
            return .notSignedIn
        case .http(let status, let body):
            if status == 429 {
                let resetAt = body?.resetAt.flatMap(ISO8601DateFormatter().date(from:))
                return .rateLimited(resetAt: resetAt, limit: body?.limit)
            }
            return .networkOrServer(message: body?.error ?? "HTTP \(status)")
        case .malformedResponse:
            return .networkOrServer(message: "malformed response")
        case .network(let err):
            return .networkOrServer(message: String(describing: err))
        case .blocked(let reason):
            // The reason already names the founder's next move; wrapping it in "network or
            // server" wording would be a lie about whose problem it is. This chat runs
            // through `LocalTransportRouter.forOneShot()` with no `prefer` (see
            // `ReflectionAPIClient.localOneShot`) — either CLI may pick it up, so the surface
            // is `.anyProvider`: a Codex-only founder gets the Codex grant named, not sent to
            // grant a Claude plan she does not have (Task 9).
            let offer = BlockedOffer.resolve(reason: reason, installed: installed)
            return .networkOrServer(message: offer.founderText(lang: lang))
        }
    }
}
