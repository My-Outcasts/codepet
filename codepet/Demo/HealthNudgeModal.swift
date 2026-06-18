import SwiftUI

/// Full-screen modal that pops up when a health-rhythm stage fires
/// (⌥6/⌥7/⌥8 in Demo Mode). Sits on top of the entire app — separate from
/// the reflection chat log. Demonstrates the "pet as companion" value: the
/// pet interrupting your flow to ask if you should rest.
///
/// Mounted on ContentView via `.overlay`. Visible iff
/// `demoController.activeHealthModal` is non-nil.
struct HealthNudgeModal: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var demoController: DemoScriptController
    @Environment(\.uiLanguage) private var uiLanguage

    let stage: DemoScript.HealthStage

    @State private var petFloat = false
    @State private var didAppear = false
    /// Boot lines play first; only after they finish does the body content
    /// fade in. Lets the user read the `[ OK ]` system observations before
    /// Byte's actual nudge text.
    @State private var bootDone = false

    private var pet: PetCharacter? {
        PetCharacter.all[appState.activeChar]
    }

    private var petColor: Color {
        pet?.color ?? Color(hex: "#7C3AED")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { demoController.dismissHealthModal() }

                card(availableHeight: max(geo.size.height - 80, 320))
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 32)
                    .scaleEffect(didAppear ? 1.0 : 0.85, anchor: .center)
                    .opacity(didAppear ? 1.0 : 0.0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                didAppear = true
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                petFloat = true
            }
        }
    }

    /// `availableHeight` = the height the modal card may occupy. Header +
    /// dismiss bar take a fixed slice; the scrolling content fills the rest.
    private func card(availableHeight: CGFloat) -> some View {
        PixelCard(
            fill: Color(hex: "#FFF1DB"),
            borderColor: Color(hex: "#2D2B26").opacity(0.35),
            shadowOffset: 4,
            borderWidth: 2
        ) {
            VStack(alignment: .leading, spacing: 14) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                HealthBootLines(raw: stage.bootLines(uiLanguage)) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        bootDone = true
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)

                if bootDone {
                    scrollingBody(maxHeight: max(availableHeight - 240, 180))
                        .transition(.opacity)
                }

                dismissBar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            }
        }
    }

    private func scrollingBody(maxHeight: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text(markdown: stage.whatYouWanted(uiLanguage))
                    .font(CodepetTheme.body(18))
                    .foregroundColor(Color(hex: "#2D2B26"))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle()
                    .fill(Color(hex: "#2D2B26").opacity(0.18))
                    .frame(height: 2)
                    .padding(.vertical, 2)

                Text(markdown: stage.whatHappened(uiLanguage))
                    .font(CodepetTheme.body(18))
                    .foregroundColor(Color(hex: "#2D2B26"))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                lessonRow
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18)
        }
        .frame(maxHeight: maxHeight)
    }

    private var header: some View {
        HStack(spacing: 12) {
            petAvatar(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("BYTE")
                        .font(.pixelSystem(size: 10))
                        .tracking(1.0)
                        .foregroundColor(petColor.opacity(0.85))
                    Text("·")
                        .foregroundColor(Color(hex: "#777065"))
                    Text(stage.sidebarLabel(uiLanguage))
                        .font(.pixelSystem(size: 10))
                        .tracking(1.2)
                        .foregroundColor(Color(hex: "#7C3AED"))
                }
                Text(uiLanguage == .vi ? "Sức khoẻ" : "Health")
                    .font(.pixelSystem(size: 9))
                    .tracking(0.8)
                    .foregroundColor(Color(hex: "#777065"))
            }
            Spacer()
            Text(stage.emote)
                .font(.system(size: 28))
        }
    }

    private var lessonRow: some View {
        PixelCard(
            fill: Color(hex: "#FCEBA8"),
            borderColor: Color(hex: "#2D2B26").opacity(0.3),
            shadowOffset: 2,
            blockSize: 3,
            steps: 2,
            borderWidth: 2
        ) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.pixelSystem(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#B6850A"))
                    .padding(.top, 2)
                Text(markdown: stage.lesson(uiLanguage))
                    .font(CodepetTheme.body(16, weight: .medium))
                    .foregroundColor(Color(hex: "#2D2B26"))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dismissBar: some View {
        HStack {
            Spacer()
            Button(action: { demoController.dismissHealthModal() }) {
                Text(uiLanguage == .vi ? "Đóng" : "Close")
            }
            .buttonStyle(PixelButtonStyle(
                fill: Color(hex: "#7C3AED"),
                font: .pixelSystem(size: 12, weight: .semibold)
            ))
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private func petAvatar(size: CGFloat) -> some View {
        ZStack {
            if let pet = pet {
                Image(pet.imageName)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .background(Circle().fill(pet.color.opacity(0.18)))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(pet.color.opacity(0.55), lineWidth: 1.5))
                    .scaleEffect(petFloat ? 1.03 : 0.97)
                    .offset(y: petFloat ? -2 : 2)
                    .shadow(color: pet.color.opacity(0.35), radius: 6, x: 0, y: 3)
            } else {
                Circle()
                    .fill(petColor.opacity(0.2))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }
}
