// codepet/Managers/AuthErrorMessage.swift
import Foundation

/// What a sign-in error says to the founder — the mapping `AuthManager` uses, pulled out so tests
/// call the real thing rather than a hand-copied mirror of a private method.
///
/// **Why network errors name their cause now (1 Oct 2026).** A tester reported Google sign-in
/// failing with "Network error. Check your internet connection" on a Mac whose internet worked.
/// Firebase's 17020 is a wrapper: the system error underneath says what actually happened — DNS
/// blocked, a timeout, a VPN or antivirus intercepting TLS, a wrong clock — and both the message
/// and the persisted log dropped it. The message now names the cause and carries its code, so a
/// screenshot is enough to diagnose the next one.
enum AuthErrorMessage {

    /// Firebase Auth's error domain. The 17xxx table below is only read for errors from here.
    static let firebaseAuthDomain = "FIRAuthErrorDomain"

    static func friendly(_ error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == firebaseAuthDomain else { return error.localizedDescription }
        switch ns.code {
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
            return network(urlErrorCode(in: ns))
        case 17999:
            return "Connection error. Please check your internet and try again."
        default:
            return error.localizedDescription
        }
    }

    /// The network failure, said by its cause. Unknown or absent causes keep the original sentence,
    /// plus the code when there is one — never a worse message than before.
    static func network(_ code: Int?) -> String {
        guard let code else { return "Network error. Check your internet connection and try again." }
        switch code {
        case -1200, -1202, -1203, -1205, -1206:
            return "A VPN, antivirus or proxy on this Mac blocked the secure connection to Google (code \(code)). Turn it off or allow Codepet, then try again."
        case -1201, -1204:
            return "This Mac's date and time look wrong, so the secure connection to Google failed (code \(code)). Set the date and time automatically, then try again."
        case -1003, -1004, -1006:
            return "This Mac can't reach Google's sign-in servers (code \(code)). A VPN, firewall or DNS filter may be blocking them."
        case -1009, -1020:
            return "You're offline (code \(code)). Connect to the internet and try again."
        case -1001:
            return "Google's sign-in servers didn't answer in time (code \(code)). Try again in a moment."
        default:
            return "Network error (code \(code)). Check your internet connection and try again."
        }
    }

    /// The first `NSURLErrorDomain` code anywhere down the `NSUnderlyingErrorKey` chain.
    static func urlErrorCode(in error: NSError) -> Int? {
        var current: NSError? = error
        var depth = 0
        while let e = current, depth < 8 {
            if e.domain == NSURLErrorDomain { return e.code }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return nil
    }

    /// "FIRAuthErrorDomain:17020 > NSURLErrorDomain:-1200" — domains and codes only, so it can be
    /// logged publicly: no email, no message text, nothing personal.
    static func chain(_ error: NSError) -> String {
        var parts: [String] = []
        var current: NSError? = error
        while let e = current, parts.count < 8 {
            parts.append("\(e.domain):\(e.code)")
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return parts.joined(separator: " > ")
    }
}
