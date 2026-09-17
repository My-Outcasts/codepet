import SwiftUI
import Combine
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import os

/// **`print` is invisible here, and that cost a diagnosis.**
///
/// The app is normally started with `open`, which discards stdout, and running the binary
/// directly gives nothing either — so every `[Auth]` line below went nowhere. On 17 Sep a
/// founder hit "Google Sign-In configuration error" on a live build; the one line that
/// explains it ("no Firebase clientID") had already been printed into the void, two log
/// captures returned zero lines, and the cause could not be established at all.
///
/// **Privacy is split deliberately, not blanket-`.public`.** os_log redacts interpolations by
/// default, so a diagnostic that is `<private>` is as useless as a `print` — but the opposite
/// mistake writes a founder's email address into the unified log, where anything on the
/// machine can read it. So the BRANCH TAKEN and the error domain/code are public, because
/// those are what a diagnosis needs; emails and display names stay private. Uids follow the
/// house precedent in `LocalTransportRouter`, which logs company ids publicly.
private let log = Logger(subsystem: "app.murror.codepet", category: "Auth")


class AuthManager: ObservableObject {
    @Published var currentUser: User? = nil
    @Published var isLoading: Bool = true
    @Published var authError: String? = nil
    @Published var authMethod: String? = nil // "google", "email", "pin"

    /// Local-only guest mode — user chose to skip sign-in entirely (no Firebase account).
    /// Persisted via UserDefaults so the choice sticks across launches.
    @Published var isGuestMode: Bool = UserDefaults.standard.bool(forKey: "cp_isGuestMode") {
        didSet { UserDefaults.standard.set(isGuestMode, forKey: "cp_isGuestMode") }
    }

    private var authStateListener: AuthStateDidChangeListenerHandle?

    /// The most recent display name from sign-up / sign-in (propagated to AppState by ContentView)
    @Published var latestDisplayName: String? = nil

    init() {
        // Under XCTest, don't touch Firebase at all (it aborts in the test
        // runner). Leave currentUser nil and stop the loading state so the host
        // app can finish launching while tests run.
        guard !AppEnvironment.isRunningTests else {
            isLoading = false
            return
        }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        // Listen for auth state changes
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.currentUser = user
                self?.isLoading = false
                if let user = user {
                    // Capture Firebase displayName so AppState can save it to UserDefaults
                    if let name = user.displayName, !name.isEmpty {
                        self?.latestDisplayName = name
                    }
                    log.error("signed in: uid=\(user.uid, privacy: .public) anonymous=\(user.isAnonymous, privacy: .public) hasName=\(user.displayName?.isEmpty == false, privacy: .public)")
                } else {
                    log.error("signed out")
                }
            }
        }
    }

    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    // MARK: - Friendly Error Messages

    private func friendlyError(_ error: Error, context: String) -> String {
        let nsError = error as NSError
        let code = nsError.code
        let domain = nsError.domain

        log.error("\(context, privacy: .public) failed — domain=\(domain, privacy: .public) code=\(code, privacy: .public) description=\(error.localizedDescription, privacy: .public)")
        log.debug("full error: \(nsError, privacy: .private)")

        switch code {
        case 17004, 17009:
            return "Incorrect email or password. If you're new, tap 'Create an account' first."
        case 17011, 17008:
            return "No account found with this email. Try creating a new account."
        case 17007:
            return "An account with this email already exists. Try signing in instead."
        case 17026:
            return "Password is too weak. Use at least 6 characters."
        case 17010:
            return "Too many attempts. Please wait a moment and try again."
        case 17020:
            return "Network error. Check your internet connection and try again."
        case 17999:
            return "Connection error. Please check your internet and try again."
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Email & Password

    func signInWithEmail(email: String, password: String) {
        authError = nil
        log.error("email sign-in attempt for \(email, privacy: .private)")
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.authError = self?.friendlyError(error, context: "Email sign-in")
                } else {
                    self?.authMethod = "email"
                    log.error("email sign-in success: uid=\(result?.user.uid ?? "", privacy: .public)")
                }
            }
        }
    }

    func signUpWithEmail(email: String, password: String, name: String) {
        authError = nil
        log.error("email sign-up attempt for \(email, privacy: .private)")
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.authError = self?.friendlyError(error, context: "Email sign-up")
                } else if let user = result?.user {
                    let changeRequest = user.createProfileChangeRequest()
                    changeRequest.displayName = name
                    changeRequest.commitChanges { error in
                        if let error = error {
                            log.error("failed to set display name — \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    self?.authMethod = "email"
                    log.error("email sign-up success: uid=\(user.uid, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Anonymous (Young Users 12-15)

    func signInAnonymously(name: String, pin: String) {
        authError = nil
        log.error("anonymous sign-in attempt for \(name, privacy: .private)")
        Auth.auth().signInAnonymously { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.authError = self?.friendlyError(error, context: "Anonymous sign-in")
                } else if let user = result?.user {
                    let changeRequest = user.createProfileChangeRequest()
                    changeRequest.displayName = name
                    changeRequest.commitChanges { error in
                        if let error = error {
                            log.error("failed to set display name — \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    self?.authMethod = "pin"
                    log.error("anonymous sign-in success: uid=\(user.uid, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() {
        authError = nil
        log.error("Google Sign-In: starting")

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            authError = "Google Sign-In configuration error."
            log.error("Google Sign-In: BLOCKED — no Firebase clientID. FirebaseApp configured=\(FirebaseApp.app() != nil, privacy: .public); this is the line that was invisible on 17 Sep")
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // On macOS, we need to get the presenting window
        guard let window = NSApplication.shared.keyWindow else {
            authError = "Could not find app window for Google Sign-In."
            log.error("Google Sign-In: BLOCKED — no key window")
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: window) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    let nsError = error as NSError
                    // Don't show error for user cancellation
                    if nsError.code == GIDSignInError.canceled.rawValue {
                        log.error("Google Sign-In: cancelled by the founder")
                        return
                    }
                    self?.authError = self?.friendlyError(error, context: "Google Sign-In")
                    return
                }

                guard let user = result?.user, let idToken = user.idToken?.tokenString else {
                    self?.authError = "Google Sign-In failed. Could not get credentials."
                    log.error("Google Sign-In: BLOCKED — no user or idToken returned")
                    return
                }

                let credential = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: user.accessToken.tokenString
                )

                Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.authError = self?.friendlyError(error, context: "Google Sign-In Firebase")
                        } else if let firebaseUser = authResult?.user {
                            self?.authMethod = "google"
                            log.error("Google Sign-In success: uid=\(firebaseUser.uid, privacy: .public)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            authMethod = nil
            authError = nil
            isGuestMode = false
            log.error("sign out success")
        } catch {
            authError = error.localizedDescription
            log.error("sign out FAILED — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Password Reset

    /// Sends a reset email. `completion(true)` only on a real send — so the view's
    /// green confirmation can't fire on failure; `completion(false)` surfaces a
    /// friendly error. Success never writes to `authError`.
    func sendPasswordReset(email: String, completion: ((Bool) -> Void)? = nil) {
        authError = nil
        Auth.auth().sendPasswordReset(withEmail: email) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.authError = self?.friendlyError(error, context: "Password reset")
                    completion?(false)
                } else {
                    completion?(true)
                }
            }
        }
    }

}
