import Foundation
import os

/// Decides whether a chat turn can run on the founder's own Claude Code, and hands it over
/// when it can.
///
/// **There is only one runner now.** Codepet holds no Anthropic key — it was deleted on
/// 26 Aug 2026 — so the `companyChat` Cloud Function this used to fall back to answers 401
/// and nothing else. The router therefore answers "the founder's own Claude Code, or why
/// not" rather than "whose machine".
///
/// **One switch decides, and it is the one that already exists.**
/// `cp_claudeCodeAuthorised` means "Codepet may spend my Claude plan". A founder who
/// granted that did not grant it for some features; they granted it. So chat follows it
/// like everything else does, and there is no second knob to learn. The alternative —
/// cloud by default with a per-turn "run this on my Claude" offer, the shape `Build`
/// uses (`localBuildAvailable` / `switchBuildToLocal`) — was considered and rejected for
/// chat: Build happens a few times a week, chat happens dozens of times a day, and it
/// would leave the API key paying for most messages, which is the thing this work exists
/// to stop.
///
/// **It never falls back to the hosted path.** That would break two things at once: the
/// no-silent-routing rule recorded at `CompanyStore.swift:743`, and the founder's
/// expectation that granting the switch stopped Codepet spending anyone else's money. So
/// an unavailable local path FAILS, with a reason the UI can act on.
///
/// The decision is made per turn rather than at `init` because the grant is keyed per
/// company id, and the company id arrives on the request.
enum ChatTransportRouter {

    static let log = Logger(subsystem: "app.murror.codepet", category: "ChatTransport")

    enum Transport: Equatable {
        /// Runs on the founder's own machine, on the named provider's plan.
        ///
        /// **It does not vary yet, and carrying it anyway is deliberate.** No chat path can
        /// run a second CLI this phase, so `transport` below answers `.claudeCode`
        /// unconditionally. The payload is here because this enum is documented (just below)
        /// as holding `LocalTransportRouter.Transport`'s shape, and leaving one of them bare
        /// while the other carried a provider is exactly the drift that comment forbids.
        ///
        /// **Do not read this as a selectable choice.** A router that could answer `.codex`
        /// here would promise the founder something no chat path can honour. The day chat
        /// runs on a second CLI, the shape is already right and only the derivation changes.
        case local(AIProvider)
        /// Cannot run here, and why. **There is deliberately no hosted case**: Codepet holds
        /// no Anthropic key, so "fall back to the Cloud Function" is not a slower success, it
        /// is a 401 the founder cannot act on. Shaped exactly like
        /// `LocalTransportRouter.Transport` so the two cannot drift.
        case blocked(BlockReason)
    }

    /// Which transport a turn should use.
    ///
    /// Deliberately does NOT probe for `claude` — that costs two subprocesses and would
    /// run on every message. `ClaudeCodeEnvironment` answers that question in Settings,
    /// where the founder is looking at the answer. A `claude` that is missing at run time
    /// surfaces through the run's own stderr instead, which is where the real reason is.
    static func transport(
        companyId: String?,
        authorisation: ClaudeCodeAuthorisation = ClaudeCodeAuthorisation(),
        sidecarAvailable: () -> Bool = { LocalChatStreamer.isAvailable() }
    ) -> Transport {
        // No company id means no grant can exist. That used to route to the Cloud Function;
        // there is nothing there to route to now, so it blocks on the grant it lacks.
        guard let companyId, !companyId.isEmpty else { return .blocked(.notGranted) }
        guard authorisation.isAuthorised(companyId) else { return .blocked(.notGranted) }
        guard sidecarAvailable() else { return .blocked(.sidecarMissing) }
        // Unconditional, and it is the whole of chat's provider story: chat has one runner.
        // See `Transport.local` above for why the value is carried at all.
        return .local(.claudeCode)
    }

    /// Drop-in for `CompanyChatClient.send`: the NON-STREAMING retry, routed the same way.
    ///
    /// **Why this exists at all.** `CompanyStore` retries a turn without streaming when the
    /// stream produced no `.done` frame (`ChatTailAction.decide` → `.fallback`). That retry
    /// was wired straight to the Cloud Function, so a granted founder whose local stream died
    /// was silently answered by the API key they had just said not to spend — the exact
    /// failure the router exists to prevent, one layer below where the router was looking.
    ///
    /// The retry keeps its meaning on the local path: it runs the sidecar again and collects
    /// the whole turn instead of streaming it. A second attempt is what the fallback IS, and
    /// on this transport it costs another turn of the founder's plan rather than money.
    ///
    /// `nil` on failure, the shape the store already handles, so its refusal copy is what the
    /// founder sees rather than an unexplained empty reply.
    static func send(_ req: CompanyChatRequest) async -> CompanyChatReply? {
        switch transport(companyId: req.companyId) {
        case .blocked(let reason):
            log.error("non-streaming retry refused: \(String(describing: reason), privacy: .public)")
            return nil
        case .local:
            return await collect(LocalChatStreamer.sendStream(req))
        }
    }

    /// Fold a stream into one reply.
    ///
    /// Text accumulates; the action fields come from the `done` frame, which is the only
    /// frame that carries them. A stream that throws before `done` yields nil rather than a
    /// partial reply: half a turn presented as a whole one is worse than an honest failure,
    /// and the store already has copy for the failure.
    /// Internal, not private, so the fold has tests: it decides whether a turn counts as
    /// answered, and a wrong answer there either hides a failure or discards a good reply.
    static func collect(
        _ stream: AsyncThrowingStream<CompanyChatStreamEvent, Error>
    ) async -> CompanyChatReply? {
        var text = ""
        var action: ChatDoneAction?
        do {
            for try await event in stream {
                switch event {
                case .delta(let chunk):
                    text += chunk
                case .tool:
                    // This fold produces one NON-streaming reply — there is no row to show
                    // a mid-turn tool on here, and no text/action it contributes either.
                    break
                case .done(_, _, let done):
                    action = done
                }
            }
        } catch {
            log.error("local retry failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        // No `done` frame means the same thing here as it does in the store: the turn did not
        // complete. Presenting the deltas that did arrive as a whole reply would hide that.
        guard let action else { return nil }
        return CompanyChatReply(
            text: text,
            runTaskId: action.runTaskId, nav: action.nav, setup: action.setup,
            remember: action.remember, completeTaskId: action.completeTaskId,
            addTask: action.addTask, drafts: action.drafts)
    }

    /// Drop-in for `CompanyChatClient.sendStream`: same signature, routes per turn.
    static func sendStream(_ req: CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        switch transport(companyId: req.companyId) {
        case .local(let provider):
            log.info("chat turn routed to the founder's \(provider.displayName, privacy: .public)")
            return LocalChatStreamer.sendStream(req)
        case .blocked(let reason):
            log.error("blocked: \(String(describing: reason), privacy: .public)")
            return AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.blocked(reason)) }
        }
    }
}
