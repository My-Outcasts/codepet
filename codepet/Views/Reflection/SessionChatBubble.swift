import SwiftUI

struct SessionChatBubble: View {
    @EnvironmentObject var appState: AppState

    let onTap: () -> Void

    @State private var float = false

    private var pet: PetCharacter? { PetCharacter.all[appState.activeChar] }
    private var petColor: Color { pet?.color ?? CodepetTheme.accentPurple }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Tinted to the active character so the chat button matches
                // whoever you're coding with. Solid character color + a soft
                // top-left sheen for a glossy, on-brand look.
                Circle()
                    .fill(petColor)
                    .overlay(
                        Circle().fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    )

                if let pet = pet {
                    Image(pet.imageName)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(10)
                }
            }
            .frame(width: 56, height: 56)
            .codepetShadow(CodepetTheme.Shadow(
                color: petColor.opacity(0.45),
                radius: 16, x: 0, y: 6
            ))
            .offset(y: float ? -4 : 0)
        }
        .buttonStyle(.plain)
        .onAppear { startAnimations() }
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            float = true
        }
    }
}
