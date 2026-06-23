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

    init(api: ReflectionAPIClientProtocol, store: SessionChatStore) {
        self.api = api
        self.store = store
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
                error = Self.map(apiError)
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

    private static func map(_ apiError: ReflectionAPIError) -> ChatError {
        switch apiError {
        case .notSignedIn:
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
        }
    }
}
