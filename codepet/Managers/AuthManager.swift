import SwiftUI
import Combine
import FirebaseAuth
import FirebaseCore
import GoogleSignIn


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
                    print("[Auth] User signed in: \(user.uid), anonymous: \(user.isAnonymous), name: \(user.displayName ?? "nil")")
                } else {
                    print("[Auth] User signed out")
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

        print("[Auth] \(context) error — domain: \(domain), code: \(code), description: \(error.localizedDescription)")
        print("[Auth] Full error: \(nsError)")

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
        print("[Auth] Attempting email sign-in for: \(email)")
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.authError = self?.friendlyError(error, context: "Email sign-in")
                } else {
                    self?.authMethod = "email"
                    print("[Auth] Email sign-in success: \(result?.user.uid ?? "")")
                }
            }
        }
    }

    func signUpWithEmail(email: String, password: String, name: String) {
        authError = nil
        print("[Auth] Attempting email sign-up for: \(email)")
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.authError = self?.friendlyError(error, context: "Email sign-up")
                } else if let user = result?.user {
                    let changeRequest = user.createProfileChangeRequest()
                    changeRequest.displayName = name
                    changeRequest.commitChanges { error in
                        if let error = error {
                            print("[Auth] Failed to set display name: \(error.localizedDescription)")
                        }
                    }
                    self?.authMethod = "email"
                    print("[Auth] Email sign-up success: \(user.uid)")
                }
            }
        }
    }

    // MARK: - Anonymous (Young Users 12-15)

    func signInAnonymously(name: String, pin: String) {
        authError = nil
        print("[Auth] Attempting anonymous sign-in for: \(name)")
        Auth.auth().signInAnonymously { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.authError = self?.friendlyError(error, context: "Anonymous sign-in")
                } else if let user = result?.user {
                    let changeRequest = user.createProfileChangeRequest()
                    changeRequest.displayName = name
                    changeRequest.commitChanges { error in
                        if let error = error {
                            print("[Auth] Failed to set display name: \(error.localizedDescription)")
                        }
                    }
                    self?.authMethod = "pin"
                    print("[Auth] Anonymous sign-in success: \(user.uid)")
                }
            }
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() {
        authError = nil
        print("[Auth] Starting Google Sign-In...")

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            authError = "Google Sign-In configuration error."
            print("[Auth] No Firebase clientID found")
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // On macOS, we need to get the presenting window
        guard let window = NSApplication.shared.keyWindow else {
            authError = "Could not find app window for Google Sign-In."
            print("[Auth] No key window found")
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: window) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    let nsError = error as NSError
                    // Don't show error for user cancellation
                    if nsError.code == GIDSignInError.canceled.rawValue {
                        print("[Auth] Google Sign-In cancelled by user")
                        return
                    }
                    self?.authError = self?.friendlyError(error, context: "Google Sign-In")
                    return
                }

                guard let user = result?.user, let idToken = user.idToken?.tokenString else {
                    self?.authError = "Google Sign-In failed. Could not get credentials."
                    print("[Auth] No user or idToken from Google Sign-In")
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
                            print("[Auth] Google Sign-In success: \(firebaseUser.uid)")
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
            print("[Auth] Sign out success")
        } catch {
            authError = error.localizedDescription
            print("[Auth] Sign out error: \(error.localizedDescription)")
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
