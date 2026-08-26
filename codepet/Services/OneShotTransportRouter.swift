import Foundation
import os

/// Decides whether a NON-STREAMING model call runs on the founder's own Claude Code or on
/// the Cloud Function.
///
/// **The same switch chat follows, deliberately.** `ClaudeCodeAuthorisation` means "Codepet
/// may spend my Claude plan". A founder who granted that did not grant it for chat; they
/// granted it. So `enrichBrief`, `synthesizeBrief` and the ops that follow read the same
/// grant, and there is no second knob to learn. `ChatTransportRouter` records the reasoning
/// in full — this is its non-streaming twin, separate only because availability is a
/// different question (a different bundle has to be on disk).
///
/// **It never falls back to cloud.** A granted founder whose machine cannot run the local
/// path FAILS, with a reason. Falling back would spend the API key they had just said not to
/// spend — and since `CloudAIBlock` may be refusing that host anyway, it would fail as an
/// unexplained network error instead of an answerable one.
///
/// **Why an active-company mirror.** The grant is keyed per company id, and these clients
/// take none: `ReflectionAPIClient.enrichBrief(_:)` is called from onboarding models that
/// know nothing about companies, and widening every signature would reach mocks and tests
/// that have no stake in transports. So whoever knows the company says once — the same
/// shape, and the same call site, as `CloudAIBlock.apply(companyId:)`.
enum OneShotTransportRouter {

    static let log = Logger(subsystem: "app.murror.codepet", category: "OneShotTransport")

    enum Transport: Equatable {
        case cloud
        case local
        /// Granted, but this machine cannot honour it. Carries the founder-facing reason;
        /// silently using cloud instead is the one thing this case exists to prevent.
        case localUnavailable(String)
    }

    /// The signed-in company, as last reported by whoever knows it.
    ///
    /// A MIRROR of a fact that lives elsewhere, exactly like `CloudAIBlock.isRefusing`, and
    /// nil until someone says — which routes to cloud, the behaviour every build had before
    /// this file existed.
    private(set) nonisolated(unsafe) static var activeCompanyId: String?

    /// Point the mirror at a company. Safe to call repeatedly; call it on load and on
    /// account switch, or a founder's grant silently stops applying.
    static func apply(companyId: String?) {
        activeCompanyId = (companyId?.isEmpty == false) ? companyId : nil
    }

    /// Which transport an op should use.
    ///
    /// Deliberately does NOT probe for `claude` — that costs a subprocess per call and
    /// `ClaudeCodeEnvironment` already answers it in Settings, where the founder is looking
    /// at the answer. A `claude` missing at run time surfaces through the sidecar's own
    /// stderr, which carries the real reason.
    static func transport(
        companyId: String? = activeCompanyId,
        authorisation: ClaudeCodeAuthorisation = ClaudeCodeAuthorisation(),
        sidecarAvailable: () -> Bool = { LocalOneShotRunner.isAvailable() }
    ) -> Transport {
        // No company id means no grant can exist — an ungranted call is a cloud call, not a
        // failure. Onboarding's first enrich lands here if the mirror was never set.
        guard let companyId, !companyId.isEmpty else { return .cloud }
        guard authorisation.isAuthorised(companyId) else { return .cloud }
        guard sidecarAvailable() else {
            return .localUnavailable("Codepet can't reach its local runner on this Mac.")
        }
        return .local
    }
}
