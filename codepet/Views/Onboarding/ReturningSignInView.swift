// codepet/Views/Onboarding/ReturningSignInView.swift
import SwiftUI

/// Returning-user sign-in — faithful port of the web `SignIn` (dark cosmic
/// auth.jpg world + a light rise-in card). Google + email/password, with the
/// two native-only extras the web lacks: forgot-password and a guest escape.
/// View-layer only — all AuthManager wiring is preserved.
struct ReturningSignInView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isAuthenticating = false
    @State private var resetSent = false
    @State private var isSignUp = false
    @State private var appear = false
    @State private var kenBurns = false
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case name, email, password }
    private var emailReady: Bool { !email.isEmpty && password.count >= 6 && !isAuthenticating }

    var body: some View {
        ZStack {
            Color(hex: "#0a0818").ignoresSafeArea()
            GeometryReader { geo in
                Image("auth")
                    .resizable().interpolation(.high).scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(kenBurns ? 1.08 : 1.0)
                    .clipped()
            }
            .ignoresSafeArea()
            RadialGradient(colors: [Color(hex: "#080618").opacity(0.34), Color(hex: "#080618").opacity(0.74)],
                           center: .center, startRadius: 0, endRadius: 640)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                card
                Button("Continue without signing in →") {
                    authManager.authError = nil
                    authManager.isGuestMode = true
                }
                .font(CodepetTheme.body(13))
                .foregroundColor(.white.opacity(0.7))
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 394)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)
            .padding(24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 34).repeatForever(autoreverses: true)) { kenBurns = true }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Codepet")
                .font(.pixelSystem(size: 30, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(isSignUp ? "Create your company." : "Sign in to your company.")
                .font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.mutedText)
                .padding(.top, 9)

            if let error = authManager.authError, !error.contains("reset email sent") {
                Text(error)
                    .font(CodepetTheme.body(13)).foregroundColor(CodepetTheme.accentPink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            // Google
            Button { authManager.signInWithGoogle() } label: {
                Text("Continue with Google")
                    .font(CodepetTheme.body(14)).fontWeight(.medium)
                    .foregroundColor(CodepetTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.top, 22)

            // or
            HStack(spacing: 12) {
                Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
                Text("or").font(CodepetTheme.body(12)).foregroundColor(OnboardingContent.Palette.faint)
                Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
            }
            .padding(.vertical, 18)

            // form
            VStack(spacing: 10) {
                if isSignUp { field("Your name", text: $name, id: .name) }
                field("Email", text: $email, id: .email, isEmail: true)
                field("Password", text: $password, id: .password, secure: true)
            }

            // forgot password (sign-in only) + reset confirmation
            if !isSignUp {
                HStack {
                    Spacer()
                    Button("Forgot password?") {
                        guard !email.isEmpty else {
                            authManager.authError = "Enter your email above first."
                            return
                        }
                        authManager.sendPasswordReset(email: email)
                        resetSent = true
                    }
                    .font(CodepetTheme.body(12)).foregroundColor(OnboardingContent.Palette.faint)
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            if resetSent {
                Text("Password reset email sent! Check your inbox.")
                    .font(CodepetTheme.body(11)).foregroundColor(Color(hex: "#20B090"))
                    .padding(.top, 6)
            }

            // submit
            Button { submit() } label: {
                HStack(spacing: 8) {
                    if isAuthenticating { ProgressView().controlSize(.small) }
                    Text(isAuthenticating ? "Signing in…" : (isSignUp ? "Create company" : "Sign in"))
                        .font(CodepetTheme.body(14)).fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.accentPurple))
                .opacity(emailReady ? 1 : 0.6)
            }
            .buttonStyle(.plain).disabled(!emailReady).padding(.top, 14)

            // toggle mode
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSignUp.toggle(); resetSent = false; authManager.authError = nil
                }
            } label: {
                Text(isSignUp ? "Already have an account? Sign in" : "New here? Create a company")
                    .font(CodepetTheme.body(13)).foregroundColor(CodepetTheme.mutedText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain).padding(.top, 18)
        }
        .padding(EdgeInsets(top: 34, leading: 32, bottom: 28, trailing: 32))
        .background(RoundedRectangle(cornerRadius: 20).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.55), lineWidth: 1))
        .shadow(color: Color(hex: "#06031c").opacity(0.5), radius: 35, y: 24)
    }

    private func field(_ placeholder: String, text: Binding<String>, id: Field,
                       secure: Bool = false, isEmail: Bool = false) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) }
            else { TextField(placeholder, text: text) }
        }
        .textFieldStyle(.plain)
        .textContentType(isEmail ? .emailAddress : nil)
        .font(CodepetTheme.body(14))
        .focused($focus, equals: id)
        .frame(minHeight: 46)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(OnboardingContent.Palette.surface2))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(focus == id ? OnboardingContent.Palette.accentLine : CodepetTheme.hairline,
                    lineWidth: focus == id ? 2 : 1))
    }

    private func submit() {
        isAuthenticating = true
        authManager.authError = nil
        if isSignUp {
            authManager.signUpWithEmail(email: email, password: password,
                                        name: name.isEmpty ? appState.displayName : name)
        } else {
            authManager.signInWithEmail(email: email, password: password)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { isAuthenticating = false }
    }
}
