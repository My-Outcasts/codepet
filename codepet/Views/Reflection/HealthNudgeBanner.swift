import SwiftUI

/// A gentle banner that slides down from the top of the Reflection tab
/// when the pet wants to remind the user to take a break.
struct HealthNudgeBanner: View {
    @EnvironmentObject var appState: AppState
    let nudge: HealthNudge
    let onDismiss: () -> Void

    private var pet: PetCharacter? {
        PetCharacter.all[appState.activeChar]
    }

    private var petName: String {
        pet?.name ?? "Pet"
    }

    private var petColor: Color {
        pet?.color ?? ReflectionTheme.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Pet avatar
            PetAvatar(mood: .calm, size: 40)

            VStack(alignment: .leading, spacing: 6) {
                // Eyebrow
                HStack(spacing: 6) {
                    Text(petName.uppercased())
                        .font(ReflectionTheme.sans(10, weight: .semibold))
                        .tracking(1.0)
                        .foregroundColor(petColor)
                    Text("·")
                        .foregroundColor(ReflectionTheme.mutedText)
                    Text(nudge.emoji + " " + nudge.title)
                        .font(ReflectionTheme.sans(10, weight: .medium))
                        .foregroundColor(ReflectionTheme.secondaryText)
                }

                // Message
                Text(nudge.message)
                    .font(ReflectionTheme.sans(13))
                    .foregroundColor(ReflectionTheme.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Time badge
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("\(nudge.minutesElapsed) min in this session")
                        .font(ReflectionTheme.sans(11))
                }
                .foregroundColor(ReflectionTheme.mutedText)
                .padding(.top, 2)
            }

            Spacer()

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ReflectionTheme.mutedText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0xFD / 255, green: 0xF7 / 255, blue: 0xE7 / 255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0xEF / 255, green: 0x9F / 255, blue: 0x27 / 255).opacity(0.25), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
