// codepet/Services/MockChat.swift
#if DEBUG
import Foundation

/// Dev-only chat stub. When the `CODEPET_MOCK_CHAT` UserDefaults flag is set,
/// `CompanyChatClient.send`/`sendStream` short-circuit to this instead of the
/// Cloud Function — so the redesigned chat UI (streaming orb, un-bubbled
/// messages, thumbs, cards) can be exercised with ZERO Anthropic spend.
///
/// Compiled ONLY under `#if DEBUG`; the flag defaults to off, so a normal build
/// still hits the real CF. Toggle from the CLI:
///   defaults write app.murror.codepet CODEPET_MOCK_CHAT -bool YES   # on
///   defaults write app.murror.codepet CODEPET_MOCK_CHAT -bool NO    # off
enum MockChat {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "CODEPET_MOCK_CHAT") }

    /// A canned, founder-assistant-flavored reply. Long + multi-sentence on
    /// purpose so the un-bubbled multi-line rendering is visible.
    private static func text(for req: CompanyChatRequest) -> String {
        let msg = req.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty {
            return "I'm here — tell me what you're working on and I'll help you plan the next move."
        }
        return """
        Good question — let's break it down. For the next few weeks I'd focus on three moves: \
        first, lock your core value proposition into a single clear sentence; second, get five \
        real user conversations booked this week; and third, ship the smallest thing they can \
        actually try. Want me to draft a plan for any of these?
        """
    }

    /// Non-streaming counterpart of `stream`.
    static func reply(_ req: CompanyChatRequest) async -> CompanyChatReply? {
        try? await Task.sleep(nanoseconds: 300_000_000)
        return CompanyChatReply(text: text(for: req))
    }

    /// Streams the canned reply word-by-word (with small delays) then a `.done`
    /// frame — mirroring the real CF's SSE shape so the UI path is identical.
    static func stream(_ req: CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        let full = text(for: req)
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                // Brief "thinking" beat so the orb's "Working on it…" is visible.
                try? await Task.sleep(nanoseconds: 500_000_000)
                // Yield in whitespace-preserving chunks for a natural stream.
                var chunk = ""
                for ch in full {
                    chunk.append(ch)
                    if ch == " " {
                        continuation.yield(.delta(chunk))
                        chunk = ""
                        try? await Task.sleep(nanoseconds: 45_000_000)
                    }
                }
                if !chunk.isEmpty { continuation.yield(.delta(chunk)) }
                continuation.yield(.done(model: "mock", cacheHit: false, action: ChatDoneAction()))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
