// codepet/Models/WorkspaceMode.swift
import Foundation

/// The shell's two destinations. **A place, not a per-message intent.**
///
/// This is what `ChatMode` becomes. `ChatMode` asked the founder to pick
/// `ask / plan / build` per message, and its own header records why that was
/// wrong: Build and Developer "differed only in WHERE the work executed", which
/// made a founder understand our deployment before they could send a sentence.
/// Intent stays inferred from what they typed; the PLACE decides which agents may
/// act and on which backend. One door per agent.
///
/// Spec: `docs/superpowers/specs/2026-08-17-codepet-two-mode-product-design.md` §3.
enum WorkspaceMode: String, CaseIterable, Identifiable {
    /// Talk to your company — the nine departments, on the cloud backend.
    case ask
    /// Your company touches your code — Local CLI or the cloud Managed Agent.
    case developer

    var id: String { rawValue }

    /// **Display only — the cases are not renamed.** `rawValue` is what
    /// `persist(to:)` writes to `cp_workspaceMode`, so renaming `ask`/`developer`
    /// would make every already-stored value unreadable and silently reset every
    /// founder to Ask on next launch. Same rule the Byte → Codepet rename followed:
    /// the label changes, the id does not.
    ///
    /// Vietnamese keeps "Lập trình" rather than borrowing "Code". The first draft of
    /// this rename used "Code" for both languages, and `testModeTitlesAreBilingual`
    /// caught it — that test asserts `en != vi` for every label precisely to catch a
    /// branch that inspects `lang` and ignores it. Documenting an exception would
    /// have weakened a guard that has already caught one real defect on this feature,
    /// to save translating a word that translates fine.
    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.ask, .vi):       return "Trò chuyện"
        case (.ask, _):         return "Chat"
        case (.developer, .vi): return "Lập trình"
        case (.developer, _):   return "Code"
        }
    }

    /// One line under the switch, retired once Developer has been opened.
    /// Guidance that outstays its welcome is just clutter.
    ///
    /// **Not gated on the current mode.** It used to show in Ask only, which meant
    /// the rail was two lines taller in Ask than in Developer and every switch made
    /// `+ New` and the whole workspace nav jump ~33pt. Its visibility is a property
    /// of the ACCOUNT ("have you been to Developer yet"), never of where you are
    /// standing right now.
    static func hint(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "Trò chuyện với công ty của bạn. Code để chạm vào mã của bạn."
            : "Chat talks to your company. Code touches your code."
    }

    // MARK: - The sidebar's company surfaces

    /// The five that never move. They are STATE the founder browses — they feed
    /// context slices and expose verbs; work itself only ever happens in chat.
    ///
    /// `.chat` and `.secondBrain` are deliberately absent: chat is the surface
    /// these sit beside, and Second Brain becomes a tab inside Company.
    static let workspaceSurfaces: [AppView] = [.roadmap, .company, .tasks, .library, .environment]

    /// Ask shows the five open; Developer collapses them to a single row so a
    /// session gets the vertical space, without making them unreachable — a
    /// roadmap task and the code that satisfies it belong one click apart.
    var collapsesWorkspace: Bool { self == .developer }

    // MARK: - Persistence

    /// `cp_`-prefixed per the project's UserDefaults convention.
    static let defaultsKey = "cp_workspaceMode"

    /// Restored on launch. An unknown or absent value opens on Ask, which is the
    /// mode that needs no repo and no CLI.
    static func restore(from defaults: UserDefaults = .standard) -> WorkspaceMode {
        guard let raw = defaults.string(forKey: defaultsKey),
              let mode = WorkspaceMode(rawValue: raw) else { return .ask }
        return mode
    }

    func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
        if self == .developer { defaults.set(true, forKey: Self.seenDeveloperKey) }
    }

    /// Set the first time Developer is opened; retires the hint.
    static let seenDeveloperKey = "cp_twoModeSeenDeveloper"

    /// Whether the hint under the switch still has a job. Reads the flag rather
    /// than the live mode, so switching back to Ask does not bring it back — a
    /// founder who has seen Developer does not need to be told it exists.
    static func showsHint(in defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: seenDeveloperKey)
    }
}

/// Whether the two-mode shell replaces `AppShellView`.
///
/// **ON by default since 23 Aug.** It was opt-in via `-CODEPET_TWO_MODE YES` while
/// it was being built, which meant that for two days everything shipped — the shell,
/// the composer controls, voice mode, record, the attachment wiring — was
/// unreachable without launch arguments. Beta runs 22–28 Aug; a feature nobody can
/// open is not in the beta.
///
/// **The old shell is kept, not deleted, and reachable without a rebuild.**
/// `-CODEPET_LEGACY_SHELL YES` returns to `AppShellView`. Flipping the default for
/// every existing founder five days before launch is worth doing; doing it with no
/// way back is not — if the two-mode shell turns out to be wrong on someone's
/// machine, the answer should be one launch argument, not a new build.
///
/// GOTCHA (measured Aug 13): `defaults write app.murror.codepet …` does NOT reach
/// a sandboxed build — a stale container eats the write and `defaults read` still
/// reports success. Pass either flag as a launch ARGUMENT:
/// `open -n <app> --args -CODEPET_LEGACY_SHELL YES`.
enum TwoModeShell {
    /// Kept so the historical opt-in argument is still recognised and so anything
    /// that referenced it keeps compiling. It no longer gates anything.
    static let flagKey = "CODEPET_TWO_MODE"

    /// The escape hatch back to the web-parity shell.
    static let legacyFlagKey = "CODEPET_LEGACY_SHELL"

    static var enabled: Bool { !UserDefaults.standard.bool(forKey: legacyFlagKey) }
}
