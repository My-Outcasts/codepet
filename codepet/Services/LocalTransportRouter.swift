import Foundation
import os

/// Decides whether a model call that is NOT chat can run on the founder's own Claude Code —
/// the one-shot ops (`enrichBrief`, `synthesizeBrief`, `generateRoadmap`, `runTask`) and the
/// virtual company meeting.
///
/// **There is only one runner now.** Codepet holds no Anthropic key — it was deleted on
/// 26 Aug 2026 — so the Cloud Functions these calls used to fall back to answer 401 and
/// nothing else. The router therefore answers "the founder's own Claude Code, or why not"
/// rather than "whose machine": a second provider extends that question, it does not
/// replace it.
///
/// **The same switch chat follows, deliberately.** `ProviderAuthorisation` means "Codepet
/// may spend my Claude plan". A founder who granted that did not grant it for chat; they
/// granted it. So `enrichBrief`, `synthesizeBrief` and the ops that follow read the same
/// grant, and there is no second knob to learn. `ChatTransportRouter` records the reasoning
/// in full — this is its non-streaming twin, separate only because availability is a
/// different question (a different bundle has to be on disk).
///
/// **Why an active-company mirror.** The grant is keyed per company id, and these clients
/// take none: `ReflectionAPIClient.enrichBrief(_:)` is called from onboarding models that
/// know nothing about companies, and widening every signature would reach mocks and tests
/// that have no stake in transports. So whoever knows the company says once, on load and on
/// account switch — `CompanyStore.hydrate` is the one call site.
enum LocalTransportRouter {

    static let log = Logger(subsystem: "app.murror.codepet", category: "LocalTransport")

    enum Transport: Equatable {
        /// Runs on the founder's own machine, on the named provider's plan.
        ///
        /// **The provider is carried so a run can say what paid for it.** `.local` alone
        /// could not: with a second CLI behind the same seam, "it ran locally" stopped being
        /// an answer to "whose plan did that spend". Nothing here ACTS on the value yet —
        /// every `case .local` site behaves exactly as it did when the case was bare.
        case local(AIProvider)
        /// Cannot run here, and why. **There is deliberately no hosted case**: Codepet holds
        /// no Anthropic key, so "fall back to the Cloud Function" is not a slower success, it
        /// is a 401 the founder cannot act on.
        case blocked(BlockReason)
    }

    /// The signed-in company, as last reported by whoever knows it.
    ///
    /// A MIRROR of a fact that lives elsewhere, and nil until someone says — which now blocks
    /// rather than routing to a hosted runner, because there is no hosted runner to route to.
    private(set) nonisolated(unsafe) static var activeCompanyId: String?

    /// Point the mirror at a company. Safe to call repeatedly; call it on load and on
    /// account switch, or a founder's grant silently stops applying.
    static func apply(companyId: String?) {
        activeCompanyId = (companyId?.isEmpty == false) ? companyId : nil
        log.error("apply: activeCompanyId set to \(activeCompanyId ?? "nil", privacy: .public)")
    }

    /// The one-shot ops, which need the `oneShotSidecar` bundle.
    ///
    /// `prefer` is the seam a caller uses to name a provider explicitly — the run card's
    /// future "Re-run on Codex". It is honoured only when the founder has actually granted
    /// that provider; see `chooseProvider`.
    static func forOneShot(
        companyId: String? = activeCompanyId,
        authorisation: ProviderAuthorisation = ProviderAuthorisation(),
        prefer: AIProvider? = nil
    ) -> Transport {
        transport(companyId: companyId, authorisation: authorisation, prefer: prefer,
                  sidecarAvailable: { LocalOneShotRunner.isAvailable() })
    }

    /// The virtual company meeting, which needs the `vcSidecar` bundle.
    ///
    /// A SEPARATE availability question, not a tidier one: the two bundles are built by the
    /// same script but fail independently, and a founder whose meeting bundle is missing
    /// should still get their roadmap rather than being told everything local is unavailable.
    ///
    /// **Deliberately does NOT call the shared `transport(...)` helper.** That helper routes
    /// through `chooseProvider`, which picks freely between whichever of Claude/Codex the
    /// founder granted — exactly right for the one-shot ops, and exactly wrong here: `vcSidecar`
    /// has no Codex adapter at all (`grep -c codex codepet/Resources/vcSidecar.js` is 0) and
    /// always spawns `claude`. Omitting a `prefer:` parameter from `transport(...)` does NOT
    /// make it Claude-only — a founder who granted only Codex still resolves `.local(.codex)`
    /// there, and the meeting would run on Claude while claiming to run on the plan she
    /// withheld. So this checks `.claudeCode` authorisation directly, the same shape
    /// `ChatTransportRouter.transport` already uses for the same reason.
    static func forVirtualCompany(
        companyId: String? = activeCompanyId,
        authorisation: ProviderAuthorisation = ProviderAuthorisation(),
        sidecarAvailable: () -> Bool = { LocalVirtualCompanyStreamer.isAvailable() }
    ) -> Transport {
        guard let companyId, !companyId.isEmpty else {
            log.error("forVirtualCompany: blocked — no companyId (mirror unset)")
            return .blocked(.notGranted)
        }
        guard authorisation.isAuthorised(.claudeCode, companyId) else {
            log.error("forVirtualCompany: blocked — companyId=\(companyId, privacy: .public) not granted for Claude Code")
            return .blocked(.notGranted)
        }
        guard sidecarAvailable() else {
            log.error("forVirtualCompany: blocked — companyId=\(companyId, privacy: .public) granted but sidecar missing")
            return .blocked(.sidecarMissing)
        }
        log.error("forVirtualCompany: local — companyId=\(companyId, privacy: .public) provider=claudeCode")
        return .local(.claudeCode)
    }

    /// Runs a meeting, or fails it with a reason.
    ///
    /// Shaped like `ChatTransportRouter.sendStream` so the store's three `vcRunner`
    /// assignments each change by one word, and none of them has to know which runner won.
    ///
    /// `.blocked` FAILS the run rather than reaching for the Cloud Function. A meeting is the
    /// most expensive thing Codepet buys — the measured ~$0.20 against ~$0.005 for an ordinary
    /// turn — so a silent fallback here would be the most expensive possible version of the
    /// mistake the grant exists to prevent, and since the key is gone it would not even buy an
    /// answer.
    static func runVirtualCompany(
        _ req: VirtualCompanyRequest
    ) -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        // `VirtualCompanyRequest` carries no company id — it never needed one, since the CF
        // read the uid off the token. So the grant is read from the mirror, the same way the
        // one-shot ops read it.
        switch forVirtualCompany() {
        case .local:
            return LocalVirtualCompanyStreamer.run(req)
        case .blocked(let reason):
            log.error("meeting blocked: \(String(describing: reason), privacy: .public)")
            return AsyncThrowingStream { $0.finish(throwing: VirtualCompanyRunError.malformedResponse) }
        }
    }

    /// Which provider runs this call.
    ///
    /// **Precedence, not preference-by-default.** Claude wins a tie because it is the
    /// incumbent and because the spec deliberately ships NO per-company default — the run
    /// card's offer is how a founder deviates, and shipping the card first is how we learn
    /// whether a stored default is wanted at all.
    ///
    /// `prefer` is that deviation. It is honoured only when the founder has actually
    /// granted it: a preference is not consent, and substituting the other provider would
    /// spend a plan she did not pick.
    static func chooseProvider(companyId: String,
                               authorisation: ProviderAuthorisation,
                               prefer: AIProvider?) -> AIProvider? {
        if let prefer {
            return authorisation.isAuthorised(prefer, companyId) ? prefer : nil
        }
        for candidate in [AIProvider.claudeCode, .codex]
        where authorisation.isAuthorised(candidate, companyId) {
            return candidate
        }
        return nil
    }

    /// Whether a call can run here, given what its own transport needs on disk.
    ///
    /// Deliberately does NOT probe for `claude` — that costs a subprocess per call and
    /// `CLIEnvironment` already answers it in Settings, where the founder is looking
    /// at the answer. A `claude` missing at run time surfaces through the sidecar's own
    /// stderr, which carries the real reason.
    static func transport(
        companyId: String? = activeCompanyId,
        authorisation: ProviderAuthorisation = ProviderAuthorisation(),
        prefer: AIProvider? = nil,
        sidecarAvailable: () -> Bool
    ) -> Transport {
        guard let companyId, !companyId.isEmpty else {
            log.error("transport: blocked — no companyId (mirror unset)")
            return .blocked(.notGranted)
        }
        guard let provider = chooseProvider(companyId: companyId,
                                            authorisation: authorisation,
                                            prefer: prefer) else {
            log.error("transport: blocked — companyId=\(companyId, privacy: .public) not granted")
            return .blocked(.notGranted)
        }
        guard sidecarAvailable() else {
            log.error("transport: blocked — companyId=\(companyId, privacy: .public) granted but sidecar missing")
            return .blocked(.sidecarMissing)
        }
        log.error("transport: local — companyId=\(companyId, privacy: .public) provider=\(provider.rawValue, privacy: .public)")
        return .local(provider)
    }
}
