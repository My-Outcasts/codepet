import SwiftUI
import FirebaseAuth

// MARK: - Onboarding Phase

/// Matches web's obPhase: "splash" → "ageGate" → "onboarding" → "interests" → "firstWords" → "app"
enum OnboardingPhase {
    case splash, ageGate, onboarding, interests, firstWords
}

struct OnboardingFlow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @State private var phase: OnboardingPhase = .ageGate
    @State private var obStep: Int = 0 // 0-5 within onboarding phase
    @State private var recommendedChar: String = "luna"
    @State private var showFullChooser: Bool = false
    @State private var selectedChar: String = ""

    var body: some View {
        ZStack {
            Color(hex: "#F7F5FC").ignoresSafeArea()

            switch phase {
            case .splash:
                // No longer used — main SplashView handles this
                EmptyView()

            case .ageGate:
                AgeGatePhase(onNext: {
                    SoundManager.shared.playNextStep()
                    withAnimation(.easeInOut(duration: 0.4)) { phase = .onboarding }
                })

            case .onboarding:
                OnboardingSteps(
                    obStep: $obStep,
                    recommendedChar: $recommendedChar,
                    showFullChooser: $showFullChooser,
                    onCharSelected: { charId in
                        selectedChar = charId
                        SoundManager.shared.playCharSelect()
                        withAnimation(.easeInOut(duration: 0.4)) { phase = .interests }
                    }
                )

            case .interests:
                InterestsPhase(onContinue: {
                    SoundManager.shared.playNextStep()
                    withAnimation(.easeInOut(duration: 0.4)) { phase = .firstWords }
                })

            case .firstWords:
                FirstWordsPhase(characterId: selectedChar, onLaunch: {
                    appState.activeChar = selectedChar
                    SoundManager.shared.playLevelUp()
                    SoundManager.shared.setPhase("home")
                    appState.onboardingComplete = true
                    // Save to cloud so returning users skip onboarding
                    if let uid = authManager.currentUser?.uid {
                        CloudSyncService().saveToCloud(userId: uid, appState: appState)
                    }
                }, onBack: {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .onboarding }
                })
            }
        }
        .onAppear {
            SoundManager.shared.setPhase("onboarding")
        }
    }
}

// MARK: - Splash Phase (Character Parade)

struct SplashPhase: View {
    let onStart: () -> Void
    @State private var showLogo = false
    @State private var showTag = false
    @State private var showButton = false
    @State private var showChars = false

    let charColors = ["#E04040", "#8B7BE8", "#20B090", "#5B8DEF", "#FF8C00", "#E0508C", "#888884", "#80C830"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Floating speech bubbles above characters
            ZStack {
                SplashBubble(text: "Let's build!", xOffset: -110, showDelay: 1.5, show: showChars)
                SplashBubble(text: "Ready to learn?", xOffset: 40, showDelay: 2.0, show: showChars)
                SplashBubble(text: "I'll break it first", xOffset: 120, showDelay: 2.5, show: showChars)
            }
            .frame(height: 40)
            .padding(.bottom, 4)

            // Character parade — centered, with per-character idle animations
            HStack(spacing: 6) {
                ForEach(Array(PetCharacter.starters.enumerated()), id: \.element) { index, charId in
                    if let char = PetCharacter.all[charId] {
                        VStack(spacing: 4) {
                            CharacterImage(charId, size: charId == "luna" ? 56 : 40)
                                .charIdle(charId)
                                .petBreathing()
                                .shadow(color: char.color.opacity(0.3), radius: 6, y: 2)
                        }
                        .opacity(showChars ? 1 : 0)
                        .offset(y: showChars ? 0 : 20)
                        .animation(
                            .spring(response: 0.7, dampingFraction: 0.8)
                                .delay(0.3 + Double(index) * 0.08),
                            value: showChars
                        )
                    }
                }
            }
            .padding(.bottom, 12)

            // Ground shadow
            Ellipse()
                .fill(Color.black.opacity(0.05))
                .frame(width: 320, height: 8)
                .opacity(showChars ? 1 : 0)

            // Pixel-art logo
            Image("codepet-text-logo")
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: 320)
                .overlay(alignment: .bottom) {
                    // Gradient underline
                    LinearGradient(colors: [Color(hex: "#534AB7"), Color(hex: "#7B6BD8"), Color(hex: "#E04040"), Color(hex: "#6EAE5E")], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 4)
                        .cornerRadius(2)
                        .opacity(0.5)
                        .offset(y: 6)
                }
            .opacity(showLogo ? 1 : 0)
            .scaleEffect(showLogo ? 1 : 0.9)
            .padding(.top, 32)

            // Tagline
            VStack(spacing: 4) {
                Text("Your AI coding companions are waiting.")
                    .font(.pixelSystem(size: 15))
                    .foregroundColor(Color(hex: "#888888"))
                Text("7 characters. 16 skills. One journey.")
                    .font(.pixelSystem(size: 13))
                    .foregroundColor(Color(hex: "#BBBBBB"))
            }
            .opacity(showTag ? 1 : 0)
            .offset(y: showTag ? 0 : 10)
            .padding(.top, 14)

            // "Meet Your Pet" button
            Button(action: onStart) {
                Text("Meet Your Pet →")
                    .font(.pixelSystem(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 52)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [Color(hex: "#2D2B26"), Color(hex: "#3D3B36")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .cornerRadius(28)
                    .shadow(color: Color(hex: "#2D2B26").opacity(0.3), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .opacity(showButton ? 1 : 0)
            .scaleEffect(showButton ? 1 : 0.9)
            .padding(.top, 32)

            Spacer()

            // Bottom color bar
            HStack(spacing: 0) {
                ForEach(charColors, id: \.self) { hex in
                    Rectangle()
                        .fill(Color(hex: hex).opacity(0.4))
                }
            }
            .frame(height: 3)
            .opacity(showButton ? 1 : 0)

            Text("v1.0 · made with vibes")
                .font(.pixelSystem(size: 10))
                .foregroundColor(Color(hex: "#D0CCC4"))
                .padding(.bottom, 12)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.3)) { showChars = true }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(1.2)) { showLogo = true }
            withAnimation(.easeOut(duration: 0.6).delay(1.8)) { showTag = true }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(2.4)) { showButton = true }
        }
    }
}

// MARK: - Single Speech Bubble (compiler-friendly)

struct SplashBubble: View {
    let text: String
    let xOffset: CGFloat
    let showDelay: Double
    let show: Bool

    @State private var visible = false
    @State private var floating = false

    var body: some View {
        Text(text)
            .font(.pixelSystem(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )
            .offset(x: xOffset, y: floating ? -4 : 4)
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.8)
            .onChange(of: show) { newValue in
                if newValue {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(showDelay)) {
                        visible = true
                    }
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(showDelay + 1.0)) {
                        floating = true
                    }
                }
            }
    }
}

// MARK: - Age Gate Phase

struct AgeGatePhase: View {
    let onNext: () -> Void
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @State private var ageStep: Int = 0 // 0=age, 1=sign-in
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var pin: String = ""
    @State private var isSignUp: Bool = true
    @State private var isAuthenticating: Bool = false
    @State private var resetSent: Bool = false

    let ageOptions = [
        ("12-15", "🌱", "Young Explorer"),
        ("16-19", "⚡", "Rising Builder"),
        ("20-25", "🚀", "Full Speed"),
        ("26-30", "💫", "Veteran Maker"),
    ]

    private var isYoung: Bool { appState.userAge == "12-15" }

    var body: some View {
        OnboardingContainer {
            if ageStep == 0 {
                // Age selection
                VStack(spacing: 24) {
                    Text("How old are you?")
                        .font(.pixelSystem(size: 32, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26"))

                    Text("We personalize your experience based on your age.")
                        .font(.pixelSystem(size: 14))
                        .foregroundColor(Color(hex: "#666666"))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(ageOptions, id: \.0) { age, icon, label in
                            let selected = appState.userAge == age
                            Button {
                                SoundManager.shared.playTap()
                                appState.userAge = appState.userAge == age ? "" : age
                            } label: {
                                VStack(spacing: 8) {
                                    Text(icon).font(.pixelSystem(size: 28))
                                    Text(age).fontWeight(.bold).foregroundColor(Color(hex: "#2D2B26"))
                                    Text(label).font(.pixelSystem(size: 12)).foregroundColor(Color(hex: "#888888"))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(selected ? Color(hex: "#2D2B26").opacity(0.08) : Color.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(selected ? Color(hex: "#7B6BD8") : Color(hex: "#E0DBEF"), lineWidth: selected ? 2 : 1)
                                        )
                                        .shadow(color: selected ? Color(hex: "#7B6BD8").opacity(0.15) : Color.black.opacity(0.04), radius: selected ? 8 : 3, y: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ObNextButton(label: "Next →", ready: !appState.userAge.isEmpty) {
                        SoundManager.shared.playNextStep()
                        withAnimation(.easeInOut(duration: 0.3)) { ageStep = 1 }
                    }
                }
                .padding(.horizontal, 24)
                .fadeUp()
            } else {
                // Sign-in step
                VStack(spacing: 16) {
                    Text(isYoung ? "Create your profile" : "Save your journey")
                        .font(.pixelSystem(size: 28, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26"))

                    Text(isYoung
                         ? "No email needed! Your profile is saved on this device."
                         : "Sign in to sync your progress across devices.")
                        .font(.pixelSystem(size: 14))
                        .foregroundColor(Color(hex: "#666666"))
                        .multilineTextAlignment(.center)



                    if isYoung {
                        // Young user: PIN-based local auth
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Create a 4-digit PIN")
                                .font(.pixelSystem(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#888888"))
                            SecureField("1234", text: $pin)
                                .textFieldStyle(.roundedBorder)
                                .font(.pixelSystem(size: 14))
                                .onChange(of: pin) { oldValue, newValue in
                                    // Limit to 4 digits
                                    pin = String(newValue.filter { $0.isNumber }.prefix(4))
                                }
                        }
                        .padding(.horizontal, 8)

                        // Create profile button
                        ObNextButton(label: isAuthenticating ? "Creating..." : "Create Profile →", ready: pin.count == 4 && !isAuthenticating) {
                            isAuthenticating = true
                            authManager.signInAnonymously(name: appState.displayName, pin: pin)
                            // Wait briefly for auth to complete, then proceed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isAuthenticating = false
                                SoundManager.shared.playNextStep()
                                onNext()
                            }
                        }
                    } else {
                        // Older user: Social sign-in + Email

                        // Sign in with Google
                        Button(action: {
                            authManager.signInWithGoogle()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill")
                                    .font(.pixelSystem(size: 16))
                                Text("Sign in with Google")
                                    .font(.pixelSystem(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#E0E0E0"), lineWidth: 1))
                                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                            )
                            .foregroundColor(Color(hex: "#1F2937"))
                        }
                        .buttonStyle(.plain)

                        // Divider
                        HStack {
                            Rectangle().fill(Color(hex: "#E0DBEF")).frame(height: 1)
                            Text("or")
                                .font(.pixelSystem(size: 11))
                                .foregroundColor(Color(hex: "#AAAAAA"))
                            Rectangle().fill(Color(hex: "#E0DBEF")).frame(height: 1)
                        }
                        .padding(.vertical, 4)

                        // Email fields
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.pixelSystem(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#888888"))
                            TextField("you@example.com", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .font(.pixelSystem(size: 14))
                                .textContentType(.emailAddress)
                        }
                        .padding(.horizontal, 8)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.pixelSystem(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#888888"))
                            SecureField("At least 6 characters", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .font(.pixelSystem(size: 14))
                        }
                        .padding(.horizontal, 8)

                        // Toggle sign-in / sign-up + forgot password
                        HStack {
                            Button(isSignUp ? "Already have an account? Sign in" : "New here? Create an account") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSignUp.toggle()
                                    resetSent = false
                                    authManager.authError = nil
                                }
                            }
                            .font(.pixelSystem(size: 12))
                            .foregroundColor(Color(hex: "#7B6BD8"))
                            .buttonStyle(.plain)

                            if !isSignUp {
                                Spacer()
                                Button("Forgot password?") {
                                    guard !email.isEmpty else {
                                        authManager.authError = "Enter your email above first."
                                        return
                                    }
                                    authManager.sendPasswordReset(email: email)
                                    resetSent = true
                                }
                                .font(.pixelSystem(size: 12))
                                .foregroundColor(Color(hex: "#B0A898"))
                                .buttonStyle(.plain)
                            }
                        }

                        // Reset confirmation
                        if resetSent {
                            Text("Password reset email sent! Check your inbox.")
                                .font(.pixelSystem(size: 11))
                                .foregroundColor(Color(hex: "#20B090"))
                                .multilineTextAlignment(.center)
                        }

                        // Email auth button
                        let emailReady = !email.isEmpty && password.count >= 6 && !isAuthenticating
                        Button(action: {
                            isAuthenticating = true
                            authManager.authError = nil
                            if isSignUp {
                                authManager.signUpWithEmail(email: email, password: password, name: appState.displayName)
                            } else {
                                authManager.signInWithEmail(email: email, password: password)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                isAuthenticating = false
                                if authManager.authError == nil {
                                    SoundManager.shared.playNextStep()
                                    onNext()
                                }
                            }
                        }) {
                            HStack(spacing: 10) {
                                if isAuthenticating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "envelope.fill")
                                }
                                Text(isAuthenticating ? "Signing in..." : (isSignUp ? "Create Account" : "Sign In with Email"))
                                    .font(.pixelSystem(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(emailReady ? Color(hex: "#7B6BD8") : Color(hex: "#D0CDE0"))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(!emailReady)
                    }

                    // Error message
                    if let error = authManager.authError {
                        Text(error)
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(Color(hex: "#E04040"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    // Skip button
                    Button("Skip for now →") {
                        SoundManager.shared.playNextStep()
                        onNext()
                    }
                    .font(.pixelSystem(size: 13))
                    .foregroundColor(Color(hex: "#B0A898"))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .fadeUp()
            }
        }
        // Auto-advance when social sign-in succeeds (fires when currentUser changes)
        .onReceive(authManager.$currentUser) { user in
            if user != nil && ageStep == 1 && authManager.authMethod == "google" {
                if !appState.displayName.isEmpty, let user = user, (user.displayName == nil || user.displayName!.isEmpty) {
                    let changeRequest = user.createProfileChangeRequest()
                    changeRequest.displayName = appState.displayName
                    changeRequest.commitChanges { _ in }
                }
                SoundManager.shared.playNextStep()
                onNext()
            }
        }
        // Also auto-advance when user is ALREADY signed in via Google when they reach step 1
        // (happens when a new Google account signs in from ReturningSignInView, triggering a
        // resetForNewUser() which shows OnboardingFlow while the user is already authenticated)
        .onChange(of: ageStep) { _, newStep in
            if newStep == 1, authManager.currentUser != nil, authManager.authMethod == "google" {
                SoundManager.shared.playNextStep()
                onNext()
            }
        }
    }
}

// MARK: - Onboarding Steps (6 steps: Who → Drives → Goal → Experience → Daily Goal → Recommendation)

struct OnboardingSteps: View {
    @EnvironmentObject var appState: AppState
    @Binding var obStep: Int
    @Binding var recommendedChar: String
    @Binding var showFullChooser: Bool
    let onCharSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == obStep ? Color(hex: "#2D2B26") : (i < obStep ? Color.black.opacity(0.3) : Color.black.opacity(0.1)))
                        .frame(width: i == obStep ? 40 : 28, height: 4)
                        .animation(.easeOut(duration: 0.3), value: obStep)
                }
            }
            .padding(.top, 24)

            // Step content — each step uses OnboardingContainer internally
            Group {
                switch obStep {
                case 0: WhoAreYouCard(onNext: { goStep(1) })
                case 1: WhatDrivesYouCard(onNext: { goStep(2) })
                case 2: WhatsYourGoalCard(onNext: { goStep(3) })
                case 3: ExperienceLevelCard(onNext: { goStep(4) })
                case 4: DailyGoalCard(onNext: { goStep(5) })
                case 5: RecommendationCard(
                    recommendedChar: recommendedChar,
                    showFullChooser: $showFullChooser,
                    onConfirm: { charId in onCharSelected(charId) }
                )
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.35), value: obStep)
        }
    }

    private func goStep(_ n: Int) {
        SoundManager.shared.playNextStep()
        if n == 3 {
            // After goal step, compute recommendation
            recommendedChar = CharacterRecommender.recommend(
                who: appState.obWho, desire: appState.obDesire, goal: appState.obGoal
            )
        }
        obStep = n
    }
}

// MARK: - Step 1: Who are you?

struct WhoAreYouCard: View {
    let onNext: () -> Void
    @EnvironmentObject var appState: AppState

    let personas: [(id: String, icon: String, name: String, desc: String)] = [
        ("beginner", "🌱", "Curious Beginner", "Never built an app, but I've seen it done and I want to try."),
        ("idea", "💡", "The Idea Person", "I have ideas. Lots of them. I just need to make one of them real."),
        ("builder", "⚡", "The Side Builder", "I have a job. I'm building something on the side and I want to move faster."),
        ("creative", "🎨", "The Creative", "Designer, writer, or maker. I want to build tools for my own work."),
    ]

    var body: some View {
        OnboardingContainer {
            VStack(spacing: 20) {
                StepLabel(step: 1, total: 6)
                ObTitle("Who are ", accent: "you?")
                ObSubtitle("Pick the one that feels most like you right now.")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(personas, id: \.id) { p in
                        PersonaCard(
                            icon: p.icon, name: p.name, desc: p.desc,
                            selected: appState.obWho == p.id
                        ) {
                            SoundManager.shared.playTap()
                            appState.obWho = appState.obWho == p.id ? "" : p.id
                        }
                    }
                }

                ObNextButton(label: "Next →", ready: !appState.obWho.isEmpty, action: onNext)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Step 2: What drives you?

struct WhatDrivesYouCard: View {
    let onNext: () -> Void
    @EnvironmentObject var appState: AppState

    let desires: [(id: String, icon: String, text: String, sub: String)] = [
        ("prove", "🏆", "Build something I can show people", "Proof that I actually made something real"),
        ("autonomous", "🔓", "Stop relying on others for things I can learn", "I want to be independent — no waiting, no expensive devs"),
        ("mastery", "🧠", "Understand what's happening, not just copy-paste", "I want to actually learn — not just get things done"),
        ("speed", "🚀", "Ship fast — iterate and figure it out later", "Done is better than perfect. I just want to launch."),
    ]

    var body: some View {
        OnboardingContainer {
            VStack(spacing: 20) {
                StepLabel(step: 2, total: 6)
                ObTitle("What ", accent: "drives", suffix: " you?")
                ObSubtitle("What would make this feel worth it?")

                VStack(spacing: 10) {
                    ForEach(desires, id: \.id) { d in
                        OptionTile(icon: d.icon, text: d.text, sub: d.sub, selected: appState.obDesire == d.id) {
                            SoundManager.shared.playTap()
                            appState.obDesire = appState.obDesire == d.id ? "" : d.id
                        }
                    }
                }

                ObNextButton(label: "Next →", ready: !appState.obDesire.isEmpty, action: onNext)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Step 3: What's your goal?

struct WhatsYourGoalCard: View {
    let onNext: () -> Void
    @EnvironmentObject var appState: AppState

    let goals: [(id: String, icon: String, text: String, sub: String)] = [
        ("launch", "🎯", "Launch my first app", "Something live that real people can use"),
        ("portfolio", "📁", "Build a portfolio project", "Something I'm proud to show off to others"),
        ("automate", "⚙️", "Automate something in my workflow", "Build a tool that saves me time every week"),
        ("levelup", "📈", "Become a confident vibe coder", "I want to understand AI coding deeply, not just use it"),
    ]

    var body: some View {
        OnboardingContainer {
            VStack(spacing: 20) {
                StepLabel(step: 3, total: 6)
                ObTitle("What's your ", accent: "goal?")
                ObSubtitle("Where do you want to be in 30 days?")

                VStack(spacing: 10) {
                    ForEach(goals, id: \.id) { g in
                        OptionTile(icon: g.icon, text: g.text, sub: g.sub, selected: appState.obGoal == g.id) {
                            SoundManager.shared.playTap()
                            appState.obGoal = appState.obGoal == g.id ? "" : g.id
                        }
                    }
                }

                ObNextButton(label: "See my match →", ready: !appState.obGoal.isEmpty, action: onNext)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Step 4: Experience Level

struct ExperienceLevelCard: View {
    let onNext: () -> Void
    @EnvironmentObject var appState: AppState

    let levels: [(id: String, icon: String, text: String, sub: String)] = [
        ("beginner", "🌱", "Just Starting", "New to coding, learning the basics"),
        ("intermediate", "⚡", "Getting Comfortable", "Built a few projects, know fundamentals"),
        ("advanced", "🔥", "Building Confidently", "Ship projects regularly, want to go deeper"),
    ]

    var body: some View {
        OnboardingContainer {
            VStack(spacing: 20) {
                StepLabel(step: 4, total: 6)
                ObTitle("What's your ", accent: "experience", suffix: " level?")
                ObSubtitle("This helps us set the right difficulty.")

                VStack(spacing: 10) {
                    ForEach(levels, id: \.id) { l in
                        OptionTile(icon: l.icon, text: l.text, sub: l.sub, selected: appState.skillLevel == l.id) {
                            SoundManager.shared.playTap()
                            appState.skillLevel = appState.skillLevel == l.id ? "" : l.id
                        }
                    }
                }

                ObNextButton(label: "Next →", ready: !appState.skillLevel.isEmpty, action: onNext)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Step 5: Daily Goal

struct DailyGoalCard: View {
    let onNext: () -> Void
    @EnvironmentObject var appState: AppState

    let goals: [(id: Int, icon: String, text: String, sub: String)] = [
        (5, "☕", "5 min / day", "A quick daily spark"),
        (15, "🎯", "15 min / day", "Steady progress"),
        (30, "🚀", "30 min / day", "Serious growth mode"),
    ]

    var body: some View {
        OnboardingContainer {
            VStack(spacing: 20) {
                StepLabel(step: 5, total: 6)
                ObTitle("Set your daily ", accent: "goal")
                ObSubtitle("How much time can you commit each day?")

                VStack(spacing: 10) {
                    ForEach(goals, id: \.id) { g in
                        OptionTile(icon: g.icon, text: g.text, sub: g.sub, selected: appState.dailyGoalMinutes == g.id) {
                            SoundManager.shared.playTap()
                            appState.dailyGoalMinutes = appState.dailyGoalMinutes == g.id ? 0 : g.id
                        }
                    }
                }

                ObNextButton(label: "Next →", ready: appState.dailyGoalMinutes > 0, action: onNext)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Step 6: Recommendation

struct RecommendationCard: View {
    let recommendedChar: String
    @Binding var showFullChooser: Bool
    let onConfirm: (String) -> Void
    @State private var chosen: String = ""

    private var activeChar: String { chosen.isEmpty ? recommendedChar : chosen }
    private var char: PetCharacter { PetCharacter.all[activeChar] ?? PetCharacter.all["luna"]! }
    private var rec: (why: String, reason: String) { CharacterRecommender.reasons[activeChar] ?? ("Your companion", "") }

    var body: some View {
        OnboardingContainer {
            VStack(spacing: 20) {
                Text("YOUR RECOMMENDED COMPANION")
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#999999"))
                    .tracking(1.5)

                // Character card — pet is the hero, info sits below
                VStack(spacing: 18) {
                    ZStack {
                        // Soft radial glow behind the pet
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [char.color.opacity(0.28), char.color.opacity(0.0)],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 140
                                )
                            )
                            .frame(width: 260, height: 260)

                        CharacterImage(activeChar, size: 200)
                            .charIdle(activeChar)
                            .petBreathing()
                            .pulseGlow(color: char.color)
                    }
                    .frame(height: 240)

                    VStack(spacing: 6) {
                        Text(rec.why)
                            .font(.pixelSystem(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "#7B6BD8"))
                            .textCase(.uppercase)
                            .tracking(1.2)

                        Text(char.name)
                            .font(.pixelSystem(size: 32, weight: .bold))
                            .foregroundColor(char.color)

                        Text(char.badge)
                            .font(.pixelSystem(size: 13))
                            .foregroundColor(Color(hex: "#999999"))

                        Text(rec.reason)
                            .font(.pixelSystem(size: 14))
                            .foregroundColor(Color(hex: "#555555"))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.top, 8)
                            .padding(.horizontal, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 24)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(char.color, lineWidth: 2))
                        .shadow(color: char.color.opacity(0.18), radius: 20, y: 6)
                )
                .fadeUp()

                // Confirm button
                ObNextButton(label: "Start with \(char.name) →", ready: true) {
                    onConfirm(activeChar)
                }

                // "Choose different" toggle
                Button(action: { withAnimation { showFullChooser.toggle() } }) {
                    Text("Choose a different companion")
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(Color(hex: "#999999"))
                        .underline()
                }
                .buttonStyle(.plain)

                // Full character grid — bigger tiles, pet as the hero
                if showFullChooser {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(PetCharacter.starters, id: \.self) { charId in
                            if let c = PetCharacter.all[charId] {
                                let isActive = activeChar == charId
                                Button {
                                    SoundManager.shared.playCharSelect()
                                    chosen = charId
                                } label: {
                                    VStack(spacing: 10) {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    RadialGradient(
                                                        colors: [c.color.opacity(isActive ? 0.28 : 0.14), c.color.opacity(0.0)],
                                                        center: .center,
                                                        startRadius: 6,
                                                        endRadius: 80
                                                    )
                                                )
                                                .frame(width: 140, height: 140)

                                            CharacterImage(charId, size: 96)
                                                .charIdle(charId)
                                                .petBreathing()
                                        }
                                        .frame(height: 130)

                                        VStack(spacing: 3) {
                                            Text(c.name)
                                                .font(.pixelSystem(size: 17, weight: .bold))
                                                .foregroundColor(c.color)
                                            Text(c.badge.replacingOccurrences(of: "The ", with: ""))
                                                .font(.pixelSystem(size: 10, weight: .semibold))
                                                .foregroundColor(Color(hex: "#999999"))
                                                .textCase(.uppercase)
                                                .tracking(0.8)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 22)
                                            .fill(isActive ? c.color.opacity(0.10) : Color.white)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 22)
                                                    .stroke(isActive ? c.color : Color(hex: "#E0DBEF"), lineWidth: isActive ? 2.5 : 1)
                                            )
                                            .shadow(color: isActive ? c.color.opacity(0.2) : .black.opacity(0.05), radius: isActive ? 10 : 6, y: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Interests Phase

struct InterestsPhase: View {
    let onContinue: () -> Void
    @EnvironmentObject var appState: AppState

    let interests: [(id: String, icon: String, name: String, desc: String)] = [
        ("web-apps", "🌐", "Web Apps", "Dashboards, portfolios, SaaS tools"),
        ("games", "🎮", "Games", "Browser games, interactive experiences"),
        ("data", "📊", "Data & Analytics", "Charts, reports, data pipelines"),
        ("creative", "🎨", "Creative Tools", "Design tools, editors, generators"),
        ("mobile", "📱", "Mobile Apps", "iOS, Android, cross-platform"),
        ("ecommerce", "🛒", "E-commerce", "Stores, carts, payment flows"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text("What do you want to build?")
                        .font(.pixelSystem(size: 26, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26"))

                    Text("Pick 2-3 topics that excite you. This helps us customize your challenges.")
                        .font(.pixelSystem(size: 14))
                        .foregroundColor(Color(hex: "#888888"))
                        .multilineTextAlignment(.center)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(interests, id: \.id) { item in
                            let selected = appState.userInterests.contains(item.id)
                            Button {
                                SoundManager.shared.playTap()
                                if selected {
                                    appState.userInterests.removeAll { $0 == item.id }
                                } else {
                                    appState.userInterests.append(item.id)
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Text(item.icon).font(.pixelSystem(size: 28))
                                    Text(item.name)
                                        .font(.pixelSystem(size: 14, weight: .bold))
                                        .foregroundColor(Color(hex: "#2D2B26"))
                                    Text(item.desc)
                                        .font(.pixelSystem(size: 11))
                                        .foregroundColor(Color(hex: "#999999"))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(selected ? Color(hex: "#2D2B26").opacity(0.08) : Color.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(selected ? Color(hex: "#7B6BD8") : Color(hex: "#E0DBEF"), lineWidth: selected ? 2 : 1)
                                        )
                                        .shadow(color: selected ? Color(hex: "#7B6BD8").opacity(0.15) : .black.opacity(0.04), radius: selected ? 8 : 3, y: 2)
                                )
                                .overlay(alignment: .topTrailing) {
                                    if selected {
                                        Circle()
                                            .fill(Color(hex: "#7B6BD8"))
                                            .frame(width: 24, height: 24)
                                            .overlay(Text("✓").font(.pixelSystem(size: 14, weight: .bold)).foregroundColor(.white))
                                            .offset(x: -8, y: 8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ObNextButton(label: "Continue →", ready: !appState.userInterests.isEmpty, action: onContinue)
                }
                .padding(36)
                .frame(maxWidth: 520)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
        .popIn()
    }
}

// MARK: - First Words Phase

struct FirstWordsPhase: View {
    let characterId: String
    let onLaunch: () -> Void
    let onBack: () -> Void

    private var char: PetCharacter { PetCharacter.all[characterId] ?? PetCharacter.all["luna"]! }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Character — hero-sized with radial glow
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [char.color.opacity(0.3), char.color.opacity(0.0)],
                                center: .center,
                                startRadius: 10,
                                endRadius: 150
                            )
                        )
                        .frame(width: 280, height: 280)

                    CharacterImage(characterId, size: 220)
                        .charIdle(characterId)
                        .petBreathing()
                        .pulseGlow(color: char.color)
                }
                .frame(height: 260)

                Text(char.name)
                    .font(.pixelSystem(size: 30, weight: .bold))
                    .foregroundColor(char.color)

                Text(char.badge)
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#999999"))
                    .tracking(0.5)

                // First words speech
                Text(char.firstWords)
                    .font(.pixelSystem(size: 16, design: .default))
                    .italic()
                    .foregroundColor(Color(hex: "#2D2B26"))
                    .lineSpacing(6)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#F7F5FC"))
                    )
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(char.color)
                            .frame(width: 3)
                            .cornerRadius(2)
                    }
                    .padding(.vertical, 4)

                // Launch button
                Button(action: onLaunch) {
                    Text("Let's go →")
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#2D2B26"))
                        .cornerRadius(24)
                }
                .buttonStyle(.plain)

                // Back button
                Button(action: onBack) {
                    Text("← Change companion")
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(Color(hex: "#999999"))
                }
                .buttonStyle(.plain)
            }
            .padding(36)
            .frame(maxWidth: 540)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
            )
        }
        .popIn()
    }
}

// MARK: - Centered Container

/// Constrains onboarding content to a comfortable reading width, centered on screen.
struct OnboardingContainer<Content: View>: View {
    let maxW: CGFloat
    @ViewBuilder let content: Content

    init(maxWidth: CGFloat = 520, @ViewBuilder content: () -> Content) {
        self.maxW = maxWidth
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: maxW)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height) // vertically centers when content is short
                    .padding(.vertical, 20)
            }
        }
    }
}

// MARK: - Shared Components

struct StepLabel: View {
    let step: Int
    let total: Int

    var body: some View {
        Text("STEP \(step) OF \(total)")
            .font(.pixelSystem(size: 11, weight: .bold))
            .foregroundColor(Color(hex: "#999999"))
            .tracking(1.5)
    }
}

struct ObTitle: View {
    let before: String
    let accent: String
    let after: String

    init(_ before: String, accent: String, suffix: String = "") {
        self.before = before
        self.accent = accent
        self.after = suffix
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(before)
                .font(.pixelSystem(size: 28, weight: .bold))
                .foregroundColor(Color(hex: "#2D2B26"))
            Text(accent)
                .font(.pixelSystem(size: 28, weight: .bold))
                .foregroundColor(Color(hex: "#7B6BD8"))
                .italic()
            if !after.isEmpty {
                Text(after)
                    .font(.pixelSystem(size: 28, weight: .bold))
                    .foregroundColor(Color(hex: "#2D2B26"))
            }
        }
    }
}

struct ObSubtitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.pixelSystem(size: 13))
            .foregroundColor(Color(hex: "#555555"))
            .multilineTextAlignment(.center)
    }
}

struct ObNextButton: View {
    let label: String
    let ready: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard ready else { return }
            action()
        }) {
            Text(label)
                .font(.pixelSystem(size: 14, weight: .bold))
                .foregroundColor(ready ? .white : Color(hex: "#B0A898"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(ready ? Color(hex: "#2D2B26") : Color(hex: "#E0DDD6"))
                )
        }
        .buttonStyle(.plain)
        .opacity(ready ? 1 : 0.6)
        .padding(.top, 8)
    }
}

struct PersonaCard: View {
    let icon: String
    let name: String
    let desc: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(icon).font(.pixelSystem(size: 28))
                Text(name)
                    .font(.pixelSystem(size: 15, weight: .bold))
                    .foregroundColor(selected ? .white : Color(hex: "#2D2B26"))
                Text(desc)
                    .font(.pixelSystem(size: 11))
                    .foregroundColor(selected ? .white.opacity(0.65) : Color(hex: "#888888"))
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(selected ? Color(hex: "#2D2B26") : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(selected ? Color(hex: "#2D2B26") : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct OptionTile: View {
    let icon: String
    let text: String
    let sub: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(icon).font(.pixelSystem(size: 22))

                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(selected ? .white : Color(hex: "#2D2B26"))
                    Text(sub)
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(selected ? .white.opacity(0.55) : Color(hex: "#999999"))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? Color(hex: "#2D2B26") : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(selected ? Color(hex: "#2D2B26") : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingFlow()
        .environmentObject(AppState())
        .environmentObject(AuthManager())
}
