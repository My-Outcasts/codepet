// codepet/Views/Library/ProviderConsentPrompt.swift
import SwiftUI

/// Consent asked for at the moment a plan would actually be spent — never during onboarding.
///
/// Tapping "Re-run on Codex" on a deliverable card when Codex is not yet granted IS the
/// consent prompt. This file holds the flow that decides whether to ask, and the copy for
/// the prompt itself.

/// Copy for the one moment a re-run is about to spend a plan the founder has not yet
/// authorised for THIS provider. Named per-provider rather than hardcoded to "ChatGPT" so a
/// third provider does not inherit Codex's wording by accident.
enum ProviderConsentCopy {
    static func message(_ provider: AIProvider, lang: AppLanguage) -> String {
        switch provider {
        case .codex:
            return lang == .vi
                ? "Chạy lại ở đây sẽ dùng gói ChatGPT của bạn. Cho phép Codepet dùng gói này?"
                : "Re-running here uses your ChatGPT plan. Allow Codepet to spend it?"
        case .claudeCode:
            return lang == .vi
                ? "Chạy lại ở đây sẽ dùng gói Claude của bạn. Cho phép Codepet dùng gói này?"
                : "Re-running here uses your Claude plan. Allow Codepet to spend it?"
        }
    }

    static func allow(lang: AppLanguage) -> String { lang == .vi ? "Cho phép" : "Allow" }
    static func notNow(lang: AppLanguage) -> String { lang == .vi ? "Để sau" : "Not now" }
}

/// Holds the pending re-run and the provider being asked about.
///
/// **Not an `ObservableObject`.** The XCTest host on Xcode 26.2 crashes when a `@MainActor
/// ObservableObject` deallocates (landmine 3, CLAUDE.md), and this type's whole state — a
/// flag, a provider, a company id, a closure — is plain enough that a caller's own `@State`
/// (driving what's actually presented on screen) is all the reactivity anything here needs.
///
/// **Consent is never transitive.** `allow()` writes the grant for exactly the provider that
/// was asked about, through `ProviderAuthorisation.setAuthorised`, which is keyed per
/// `(provider, companyId)` — see that type's own doc comment on why the key is written out
/// per case rather than derived. Granting Codex here cannot write, read, or imply the Claude
/// key, and the reverse, because nothing in this type ever touches a key it wasn't asked
/// about.
///
/// **An already-granted provider must not re-ask.** `requestReRun` checks the grant FIRST and
/// runs immediately when it already holds — being asked again for permission already given
/// reads as the app having lost it.
///
/// **Declining must not run.** `decline()` drops the pending closure without invoking it. A
/// consent prompt that runs anyway is worse than no prompt.
final class ProviderConsentFlow {
    private let authorisation: ProviderAuthorisation

    private(set) var isAsking = false
    private(set) var pendingProvider: AIProvider?
    private var pendingCompanyId: String?
    private var pendingRun: (() -> Void)?

    init(authorisation: ProviderAuthorisation) {
        self.authorisation = authorisation
    }

    /// Ask to re-run on `provider` for `companyId`. Runs immediately, with no prompt, when
    /// already granted; otherwise starts the ask and waits for `allow()` or `decline()`.
    func requestReRun(provider: AIProvider, companyId: String, run: @escaping () -> Void) {
        if authorisation.isAuthorised(provider, companyId) {
            clear()
            run()
            return
        }
        isAsking = true
        pendingProvider = provider
        pendingCompanyId = companyId
        pendingRun = run
    }

    /// Grants the pending provider for the pending company, then runs the pending closure.
    /// A no-op if nothing is pending (no double-fire from a stray second tap).
    func allow() {
        guard isAsking, let provider = pendingProvider, let companyId = pendingCompanyId else { return }
        authorisation.setAuthorised(provider, companyId, true)
        let run = pendingRun
        clear()
        run?()
    }

    /// Drops the pending ask without granting or running anything.
    func decline() {
        clear()
    }

    private func clear() {
        isAsking = false
        pendingProvider = nil
        pendingCompanyId = nil
        pendingRun = nil
    }
}

/// Attaches the consent alert: "Re-running here uses your ChatGPT plan. Allow Codepet to
/// spend it?" — Allow · Not now. `isPresented` and `provider` are the caller's own `@State`,
/// driven by `ProviderConsentFlow.isAsking`/`pendingProvider`; this modifier only renders.
private struct ProviderConsentAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let provider: AIProvider?
    let lang: AppLanguage
    let onAllow: () -> Void
    let onDecline: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            provider.map { $0.displayName } ?? "",
            isPresented: $isPresented,
            actions: {
                Button(ProviderConsentCopy.notNow(lang: lang), role: .cancel, action: onDecline)
                Button(ProviderConsentCopy.allow(lang: lang), action: onAllow)
            },
            message: {
                Text(ProviderConsentCopy.message(provider ?? .claudeCode, lang: lang))
            }
        )
    }
}

extension View {
    /// See `ProviderConsentAlertModifier`. `provider` names whose plan the message describes;
    /// pass the SAME provider that was asked about, not one re-derived from anything else.
    func providerConsentAlert(isPresented: Binding<Bool>, provider: AIProvider?, lang: AppLanguage,
                               onAllow: @escaping () -> Void, onDecline: @escaping () -> Void) -> some View {
        modifier(ProviderConsentAlertModifier(isPresented: isPresented, provider: provider, lang: lang,
                                               onAllow: onAllow, onDecline: onDecline))
    }
}
