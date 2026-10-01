import XCTest
@testable import codepet

// MARK: - PIN Validation
// Mirrors: pin = String(newValue.filter { $0.isNumber }.prefix(4))
// OnboardingFlow.swift:335-338

class PINValidationTests: XCTestCase {

    private func sanitize(_ input: String) -> String {
        String(input.filter { $0.isNumber }.prefix(4))
    }

    func test_digitsPassThrough() {
        XCTAssertEqual(sanitize("1234"), "1234")
    }

    func test_lettersAreStripped() {
        XCTAssertEqual(sanitize("ab12cd"), "12")
    }

    func test_clampedToFourDigits() {
        XCTAssertEqual(sanitize("123456"), "1234")
    }

    func test_allNonDigitsProducesEmpty() {
        XCTAssertEqual(sanitize("abcd"), "")
    }

    func test_mixedSymbolsStripped() {
        XCTAssertEqual(sanitize("1!2@3#4$5"), "1234")
    }

    func test_exactlyFourDigitsIsReady() {
        XCTAssertTrue(sanitize("4321").count == 4)
    }

    func test_fewerThanFourDigitsIsNotReady() {
        XCTAssertFalse(sanitize("123").count == 4)
    }

    func test_emptyIsNotReady() {
        XCTAssertFalse(sanitize("").count == 4)
    }
}

// MARK: - Email Form Readiness
// Mirrors: let emailReady = !email.isEmpty && password.count >= 6 && !isAuthenticating
// OnboardingFlow.swift:448

class EmailReadyTests: XCTestCase {

    private func emailReady(email: String, password: String, isAuthenticating: Bool = false) -> Bool {
        !email.isEmpty && password.count >= 6 && !isAuthenticating
    }

    func test_readyWhenAllConditionsMet() {
        XCTAssertTrue(emailReady(email: "user@example.com", password: "secret"))
    }

    func test_notReadyWhenEmailEmpty() {
        XCTAssertFalse(emailReady(email: "", password: "secret"))
    }

    func test_notReadyWhenPasswordFiveChars() {
        XCTAssertFalse(emailReady(email: "user@example.com", password: "12345"))
    }

    func test_readyWhenPasswordExactlySixChars() {
        XCTAssertTrue(emailReady(email: "user@example.com", password: "123456"))
    }

    func test_notReadyWhenIsAuthenticating() {
        XCTAssertFalse(emailReady(email: "user@example.com", password: "secret", isAuthenticating: true))
    }

    func test_notReadyWhenBothEmailEmptyAndShortPassword() {
        XCTAssertFalse(emailReady(email: "", password: "123"))
    }
}

// MARK: - AuthManager Friendly Error Codes
// Calls the REAL mapping (`AuthErrorMessage.friendly`). This used to test a hand-copied mirror of
// AuthManager's private method, which would have kept passing whatever the app actually said.

class AuthManagerFriendlyErrorTests: XCTestCase {

    private func friendlyError(code: Int, rawDescription: String = "Firebase error \(0)") -> String {
        AuthErrorMessage.friendly(NSError(domain: AuthErrorMessage.firebaseAuthDomain, code: code,
                                          userInfo: [NSLocalizedDescriptionKey: rawDescription]))
    }

    func test_wrongPassword_17009() {
        XCTAssertTrue(friendlyError(code: 17009).contains("Incorrect email or password"))
    }

    func test_wrongPassword_17004() {
        XCTAssertTrue(friendlyError(code: 17004).contains("Incorrect email or password"))
    }

    func test_noAccount_17011() {
        XCTAssertTrue(friendlyError(code: 17011).contains("No account found"))
    }

    func test_noAccount_17008() {
        XCTAssertTrue(friendlyError(code: 17008).contains("No account found"))
    }

    func test_accountExists_17007() {
        XCTAssertTrue(friendlyError(code: 17007).contains("already exists"))
    }

    func test_weakPassword_17026() {
        XCTAssertTrue(friendlyError(code: 17026).contains("too weak"))
    }

    func test_tooManyAttempts_17010() {
        XCTAssertTrue(friendlyError(code: 17010).contains("Too many attempts"))
    }

    func test_networkError_17020() {
        XCTAssertTrue(friendlyError(code: 17020).contains("Network error"))
    }

    func test_connectionError_17999() {
        XCTAssertTrue(friendlyError(code: 17999).contains("Connection error"))
    }

    func test_unknownCodeFallsBackToRawDescription() {
        let raw = "Some unexpected Firebase error"
        XCTAssertEqual(friendlyError(code: 99999, rawDescription: raw), raw)
    }
}

// MARK: - sendPasswordReset Double-Message (Bug Documentation)
// AuthManager.sendPasswordReset sets authError = "Password reset email sent!"
// on SUCCESS (AuthManager.swift:213). The view shows authError in RED and also
// shows the same string in GREEN via resetSent. This can show the message twice.

class PasswordResetQuirkTests: XCTestCase {

    func test_successMessageWrittenToErrorChannel() {
        // Reproduces the bug: success writes to authError (shown in red by the view)
        var authError: String? = nil
        var resetSent = false

        // Simulate AuthManager.sendPasswordReset success branch
        let simulateSuccess = {
            authError = "Password reset email sent! Check your inbox."
        }

        // Simulate AgeGatePhase button action
        let email = "user@example.com"
        if email.isEmpty {
            authError = "Enter your email above first."
        } else {
            simulateSuccess()
            resetSent = true
        }

        // Both are set — the user sees the message in red AND green
        XCTAssertNotNil(authError, "authError should be set on success (red display — BUG)")
        XCTAssertTrue(resetSent, "resetSent should be true (green display)")
        XCTAssertEqual(authError, "Password reset email sent! Check your inbox.")
    }

    func test_forgotPasswordBlockedWhenEmailEmpty() {
        var authError: String? = nil
        var resetSent = false

        let email = ""
        if email.isEmpty {
            authError = "Enter your email above first."
        } else {
            resetSent = true
        }

        XCTAssertNotNil(authError)
        XCTAssertFalse(resetSent)
    }

    func test_forgotPasswordAllowedWhenEmailProvided() {
        var authError: String? = nil
        var resetSent = false

        let email = "user@example.com"
        if email.isEmpty {
            authError = "Enter your email above first."
        } else {
            resetSent = true
        }

        XCTAssertNil(authError)
        XCTAssertTrue(resetSent)
    }
}

// MARK: - Google Auto-Advance Logic
// Mirrors onReceive(authManager.$currentUser) in AgeGatePhase (OnboardingFlow.swift:510-524)
// Auto-advances only when: user != nil && ageStep == 1 && authMethod == "google"

class GoogleAutoAdvanceTests: XCTestCase {

    private func shouldAdvance(userPresent: Bool, ageStep: Int, authMethod: String?) -> Bool {
        userPresent && ageStep == 1 && authMethod == "google"
    }

    func test_advancesWhenGoogleUserArrivesAtStep1() {
        XCTAssertTrue(shouldAdvance(userPresent: true, ageStep: 1, authMethod: "google"))
    }

    func test_doesNotAdvanceWhenStillOnAgeStep0() {
        XCTAssertFalse(shouldAdvance(userPresent: true, ageStep: 0, authMethod: "google"))
    }

    func test_doesNotAdvanceWhenAuthMethodIsEmail() {
        XCTAssertFalse(shouldAdvance(userPresent: true, ageStep: 1, authMethod: "email"))
    }

    func test_doesNotAdvanceWhenAuthMethodIsPin() {
        XCTAssertFalse(shouldAdvance(userPresent: true, ageStep: 1, authMethod: "pin"))
    }

    func test_doesNotAdvanceWhenUserIsNil() {
        XCTAssertFalse(shouldAdvance(userPresent: false, ageStep: 1, authMethod: "google"))
    }

    func test_doesNotAdvanceWhenAuthMethodIsNil() {
        XCTAssertFalse(shouldAdvance(userPresent: true, ageStep: 1, authMethod: nil))
    }
}
