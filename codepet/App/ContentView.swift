import SwiftUI
import Combine
import FirebaseAuth
import os

private let logger = Logger(subsystem: "app.murror.codepet", category: "ContentView")

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var demoController: DemoScriptController
    // Live stores that must also be reset on account switch (otherwise the
    // previous user's in-memory data lingers and gets re-saved under the new uid).
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var tipsState: TipsState
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var interviewCoordinator: InterviewCoordinator
    @EnvironmentObject var challengeProgress: ChallengeProgress
    @EnvironmentObject var learnProgress: LearnProgress
    @EnvironmentObject var sessionStatusStore: SessionStatusStore
    @EnvironmentObject var chatStore: SessionChatStore
    @State private var isLoadingCloudData = false
    @State private var showSplash = true

    private let cloudSync = CloudSyncService()

    // MARK: - Prototype mode does not require an account

    /// The company id the fixture shell hydrates under when nobody is signed in.
    ///
    /// A literal, not a uid: there is no account, and the fixtures ignore the id entirely
    /// (`CompanyData.load` answers from `MockChat` before it looks at it). It exists so the
    /// bootstrapping gate below has something to compare against — a nil id would leave the
    /// shell waiting on a hydrate that had already finished.
    static let prototypeCompanyId = "prototype"

    /// **Whether the sign-in screen is the honest answer to "nobody is signed in".**
    ///
    /// It was, unconditionally, until 2026-09-03. The auth gate sits ABOVE everything the
    /// demo touches — `CompanyData.load` is the only place the selected demo project is read,
    /// and it is unreachable while signed out — so prototype mode silently required a live
    /// Firebase login and a network. Reported from the app as *"I cannot press the button"*
    /// and *"why don't I see any changes at all?"*: the flags were correct, the fixtures were
    /// correct, and the founder was looking at a sign-in card the whole time.
    ///
    /// A demo that needs an account is a demo you cannot show on a plane, and the failure
    /// reads as "the build did nothing" rather than as "you are signed out".
    ///
    /// Safe because prototype mode already gates the dangerous direction:
    /// `PrototypeMode.allowsCloudWrites` is false whenever it is on, checked inside
    /// `CompanyData` rather than at each call site, so nothing fixture-shaped can reach a
    /// real account — and there is no account here to reach.
    /// Pure, so the routing decision is testable without a Firebase session or a rendered
    /// view. The bug this replaces could not be caught by any fixture test — every one of
    /// those asserted the fixtures were RIGHT, none that they were REACHABLE — and it could
    /// only ever have been caught here.
    static func needsSignIn(signedIn: Bool, prototypeOn: Bool) -> Bool {
        guard !signedIn else { return false }
        #if DEBUG
        return !prototypeOn
        #else
        return true
        #endif
    }

    private var needsSignIn: Bool {
        Self.needsSignIn(signedIn: authManager.currentUser != nil,
                         prototypeOn: PrototypeMode.isOn)
    }

    /// The id the hydrated company must carry before the shell may render — the signed-in
    /// founder's uid, or the fixture id when prototype mode is standing in for an account.
    ///
    /// Without the second case the bootstrapping gate compares `"prototype"` against a nil
    /// uid, never matches, and holds the demo on the splash screen forever.
    static func expectedCompanyId(uid: String?, prototypeOn: Bool) -> String? {
        #if DEBUG
        if uid == nil, prototypeOn { return prototypeCompanyId }
        #endif
        return uid
    }

    private var expectedCompanyId: String? {
        Self.expectedCompanyId(uid: authManager.currentUser?.uid,
                               prototypeOn: PrototypeMode.isOn)
    }

    /// True while the fixture shell is standing in for a signed-out account — and therefore
    /// the one state in which the hydrate below must be driven by something other than the
    /// `currentUser` publisher.
    static func prototypeStandIn(signedIn: Bool, prototypeOn: Bool) -> Bool {
        #if DEBUG
        return !signedIn && prototypeOn
        #else
        return false
        #endif
    }

    private var prototypeStandIn: Bool {
        Self.prototypeStandIn(signedIn: authManager.currentUser != nil,
                              prototypeOn: PrototypeMode.isOn)
    }

    var body: some View {
        Group {
            if showSplash {
                // Splash always shows first
                SplashView(onContinue: {
                    withAnimation {
                        showSplash = false
                    }
                })
            } else if authManager.isLoading || isLoadingCloudData {
                // Still checking auth state or loading cloud data
                SplashView()
            } else if needsSignIn {
                // Not signed in — always show sign-in. Guest mode is blocked, so a
                // stale persisted cp_isGuestMode can never strand a signed-out user
                // in the company-less, non-persisting shell (companyId is nil until
                // an account hydrates).
                //
                // `needsSignIn` rather than `currentUser == nil`: in DEBUG, prototype
                // mode falls through to the fixture shell instead. See below.
                ReturningSignInView()
            } else if companyStore.companyId != expectedCompanyId || companyStore.isHydrating {
                // Bootstrapping — signed in, but this account's company hasn't finished
                // hydrating yet (companyId not yet swapped to this uid, or a hydrate is
                // in flight). Mirrors the web's "Setting up your company…" gate so we
                // never flash the shell or onboarding before `isOnboarding` is known.
                SplashView()
            } else if companyStore.isOnboarding {
                // Fresh account — first-run cinematic onboarding before the shell.
                // .id on the company scopes the wizard's @State per account, so a
                // mid-onboarding account switch can't inherit the prior draft/step.
                OnboardingView()
                    .id(companyStore.companyId)
            } else if TwoModeShell.enabled {
                // The two-mode shell — **the default since 23 Aug.** It was opt-in
                // while being built, which meant two days of shipped work nobody
                // could open. `-CODEPET_LEGACY_SHELL YES` falls through to the
                // web-parity shell below without needing a new build.
                TwoModeShellView()
            } else {
                // Authenticated (or guest) — the company shell (web product).
                AppShellView()
            }
        }
        .overlay {
            if let stage = demoController.activeHealthModal {
                HealthNudgeModal(stage: stage)
                    .transition(.opacity)
            }
        }
        .sheet(item: $interviewCoordinator.active) { project in
            ProjectInterviewView(projectId: project.id) { interviewCoordinator.active = nil }
                .environmentObject(projectStore)
        }
        .animation(.easeInOut(duration: 0.25), value: demoController.activeHealthModal)
        .animation(.easeInOut(duration: 0.3), value: showSplash)
        .animation(.easeInOut(duration: 0.3), value: appState.onboardingComplete)
        .animation(.easeInOut(duration: 0.3), value: authManager.currentUser == nil)
        // The fixture company has to be hydrated by SOMETHING. Every other path into
        // `hydrate` hangs off the `currentUser` publisher below, which by definition never
        // fires when nobody signs in — so without this the bypass renders a shell whose
        // company was never loaded, and `isOnboarding` sends the founder into onboarding
        // instead of the demo.
        .task(id: prototypeStandIn) {
            guard prototypeStandIn,
                  companyStore.companyId != Self.prototypeCompanyId else { return }
            await companyStore.hydrate(companyId: Self.prototypeCompanyId)
        }
        .onReceive(authManager.$currentUser) { user in
            guard let user = user else {
                // Signed out — intentionally keep the stored UID and in-memory
                // data: a same-account re-login is then unchanged, and a different
                // account signing in next still trips the UID comparison below.
                // Real sign-out (a prior sign-in exists): return to the brand splash
                // before the sign-in screen, mirroring web Gate's wasAuthed/splashSeen.
                if PersistenceManager.shared.currentUserId != nil {
                    withAnimation { showSplash = true }
                }
                return
            }
            // NOTE: anonymous (PIN) users flow through the same isolation path as
            // real accounts. Their uid scopes the vault, the chat file, and
            // currentUserId, so a PIN session can't inherit or overwrite a real
            // account's working data. (They're still excluded from cloud backup.)

            let storedUID = PersistenceManager.shared.currentUserId
            let isDifferentUser = storedUID != nil && storedUID != user.uid

            // Cancel any pending cloud save for the OUTGOING account so it can't
            // fire after we've swapped in a different account's data.
            cloudSync.cancelPendingSave()

            // Non-destructive account-data swap: snapshot the outgoing account
            // and restore the incoming one. Nothing is deleted — each account
            // keeps its own data under its uid, so switching back restores it.
            let hadLocalData = AccountDataStore.shared.activate(uid: user.uid, previousUID: storedUID)
            if isDifferentUser {
                logger.info("Account switch (\(storedUID ?? "none", privacy: .private) → \(user.uid, privacy: .private)) — restored this account's local data")
                reloadAllStores()
            }

            // Scope the session chat file to this account on every sign-in (not
            // just on a switch) so chat history is always isolated per uid.
            chatStore.activate(uid: user.uid)
            // Hydrate the account's company, then reconcile the shell/game sprite
            // (appState.activeChar) with the account-scoped companion of record
            // (company.companionId) so the header, Copilot, and AI persona all agree.
            Task {
                await companyStore.hydrate(companyId: user.uid)
                appState.activeChar = companyStore.company.companionId
            }

            // Legacy onboarding flag — keep code that still reads it satisfied.
            if !appState.onboardingComplete {
                appState.onboardingComplete = true
            }

            // Sync display name from Firebase Auth if AppState doesn't have one.
            if appState.displayName.isEmpty {
                if let authName = authManager.latestDisplayName, !authName.isEmpty {
                    appState.displayName = authName
                } else if let fbName = user.displayName, !fbName.isEmpty {
                    appState.displayName = fbName
                }
            }

            // Record this account as the owner of the current working data.
            PersistenceManager.shared.currentUserId = user.uid

            // Reflection isolation: established accounts (those with their own
            // local data) see their full machine coding history; fresh/empty
            // accounts only see sessions from their first sign-in onward.
            if hadLocalData {
                ReflectionAccountWatermark.record(forUID: user.uid, date: .distantPast)
                sessionStatusStore.activeAccountStart = .distantPast
            } else {
                sessionStatusStore.activeAccountStart =
                    ReflectionAccountWatermark.ensureStart(forUID: user.uid, fallback: Date())
            }

            // Cloud restore when this account has no *meaningful* local progress
            // yet. We key off real progress (XP / completed lessons / challenges)
            // instead of "any cp_ key exists": on a fresh device a returning user
            // can have stray default keys written at launch, which previously made
            // `hadLocalData` true and skipped the restore — then the empty local
            // state overwrote their cloud backup. Anonymous accounts never have a
            // cloud backup. When real local progress exists it stays the source of
            // truth — we must NOT let older cloud data clobber it.
            if !appState.hasMeaningfulProgress && !user.isAnonymous {
                isLoadingCloudData = true
                cloudSync.loadFromCloud(userId: user.uid, appState: appState) { hasData in
                    isLoadingCloudData = false
                    if hasData {
                        logger.info("Restored cloud backup for \(user.uid, privacy: .private)")
                        // Cloud had progress → established account → full history.
                        ReflectionAccountWatermark.record(forUID: user.uid, date: .distantPast)
                        sessionStatusStore.activeAccountStart = .distantPast
                    } else {
                        logger.info("No cloud backup for \(user.uid, privacy: .private) — fresh account")
                    }
                }
            }
        }
        // Continuous cloud backup: debounce-save AppState progress to Firestore
        // so an account's data survives a wiped/replaced Mac. Snapshots the uid
        // at schedule time; the swap above cancels stale saves.
        .onReceive(appState.objectWillChange) { _ in
            guard let u = authManager.currentUser, !u.isAnonymous, !isLoadingCloudData else { return }
            cloudSync.scheduleSave(userId: u.uid, appState: appState)
        }
    }

    /// Re-hydrate every live store from the (account-swapped) UserDefaults keys
    /// so the in-memory `@Published` objects reflect the account that just
    /// signed in. Each store resets to fresh-account defaults first, then loads
    /// any persisted keys — without deleting them. Called after the vault swap.
    /// Reflection JSONL (machine-local coding activity in ~/.codepet) is filtered
    /// per-account by the watermark, not reloaded here.
    private func reloadAllStores() {
        appState.reloadFromPersistence()
        gameState.reloadFromPersistence()
        tipsState.reset()
        TipsPersistence.shared.load(into: tipsState)
        projectStore.reload()
        companyStore.reset()
        challengeProgress.load()
        learnProgress.reload()
        sessionStatusStore.reload()
        PetMemoryStore.shared.reload()
        // A pending founder-interview sheet is per-account state (it targets a
        // specific project id); clear it so a sheet/submit surviving the swap
        // can't write under the wrong account.
        interviewCoordinator.active = nil
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(AuthManager())
        .environmentObject(DemoScriptController())
        .environmentObject(GameState())
        .environmentObject(TipsState())
        .environmentObject(ProjectStore())
        .environmentObject(CompanyStore())
        .environmentObject(InterviewCoordinator())
        .environmentObject(ChallengeProgress())
        .environmentObject(LearnProgress())
        .environmentObject(SessionStatusStore())
}
