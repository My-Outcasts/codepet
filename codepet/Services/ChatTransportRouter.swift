import Foundation
import os

/// Decides whether a chat turn runs on the founder's own Claude Code or on the Cloud
/// Function, and hands it to whichever wins.
///
/// **One switch decides, and it is the one that already exists.**
/// `cp_claudeCodeAuthorised` means "Codepet may spend my Claude plan". A founder who
/// granted that did not grant it for some features; they granted it. So chat follows it
/// like everything else will, and there is no second knob to learn. The alternative —
/// cloud by default with a per-turn "run this on my Claude" offer, the shape `Build`
/// uses (`localBuildAvailable` / `switchBuildToLocal`) — was considered and rejected for
/// chat: Build happens a few times a week, chat happens dozens of times a day, and it
/// would leave the API key paying for most messages, which is the thing this work exists
/// to stop.
///
/// **It never falls back to cloud.** That would break two things at once: the
/// no-silent-routing rule recorded at `CompanyStore.swift:743`, and the founder's
/// expectation that granting the switch stopped Codepet spending anyone else's money. So
/// an unavailable local path FAILS, with a reason the UI can act on.
///
/// The decision is made per turn rather than at `init` because the grant is keyed per
/// company id, and the company id arrives on the request.
enum ChatTransportRouter {

    static let log = Logger(subsystem: "app.murror.codepet", category: "ChatTransport")

    enum Transport: Equatable {
        case cloud
        case local
        /// Granted, but this machine cannot honour it. Carries the founder-facing reason;
        /// silently using cloud instead is the one thing this case exists to prevent.
        case localUnavailable(String)
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
        // No company id means no grant can exist — an ungranted turn is a cloud turn, not
        // a failure.
        guard let companyId, !companyId.isEmpty else { return .cloud }
        guard authorisation.isAuthorised(companyId) else { return .cloud }
        guard sidecarAvailable() else {
            return .localUnavailable("Codepet can't reach its local runner on this Mac.")
        }
        return .local
    }

    /// Drop-in for `CompanyChatClient.sendStream`: same signature, routes per turn.
    static func sendStream(_ req: CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        switch transport(companyId: req.companyId) {
        case .cloud:
            return CompanyChatClient.sendStream(req)
        case .local:
            log.info("chat turn routed to the founder's Claude Code")
            return LocalChatStreamer.sendStream(req)
        case .localUnavailable(let reason):
            log.error("granted but unavailable: \(reason, privacy: .public)")
            return AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.localUnavailable(reason)) }
        }
    }
}
