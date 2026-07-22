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
            } else if authManager.currentUser == nil {
                // Not signed in — always show sign-in. Guest mode is blocked, so a
                // stale persisted cp_isGuestMode can never strand a signed-out user
                // in the company-less, non-persisting shell (companyId is nil until
                // an account hydrates).
                ReturningSignInView()
            } else if companyStore.isOnboarding {
                // Fresh account — first-run cinematic onboarding before the shell.
                // .id on the company scopes the wizard's @State per account, so a
                // mid-onboarding account switch can't inherit the prior draft/step.
                OnboardingView()
                    .id(companyStore.companyId)
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
        .onReceive(authManager.$currentUser) { user in
            guard let user = user else {
                // Signed out — intentionally keep the stored UID and in-memory
                // data: a same-account re-login is then unchanged, and a different
                // account signing in next still trips the UID comparison below.
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
