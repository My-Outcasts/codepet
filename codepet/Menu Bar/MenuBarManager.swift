import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    private var character: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Pet Header
            HStack(spacing: 8) {
                CharacterImage(character.id, size: 24)
                    .petBreathing()

                VStack(alignment: .leading, spacing: 1) {
                    Text(character.name)
                        .font(.pixelSystem(size: 13, weight: .bold))
                    Text(character.badge)
                        .font(.pixelSystem(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

            Divider()

            // Stats
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(Color(hex: "#7B6BD8"))
                        .font(.pixelSystem(size: 11))
                    Text("Energy")
                        .font(.pixelSystem(size: 12))
                    Spacer()
                    Text("\(appState.petEnergy)/100")
                        .font(.pixelSystem(size: 11, design: .monospaced))
                }

                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(Color(hex: "#7B6BD8"))
                        .font(.pixelSystem(size: 11))
                    Text("Streak")
                        .font(.pixelSystem(size: 12))
                    Spacer()
                    Text("\(appState.streak) days")
                        .font(.pixelSystem(size: 11, design: .monospaced))
                }

                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(Color(hex: "#7B6BD8"))
                        .font(.pixelSystem(size: 11))
                    Text("XP")
                        .font(.pixelSystem(size: 12))
                    Spacer()
                    Text("\(appState.totalXP)")
                        .font(.pixelSystem(size: 11, design: .monospaced))
                }

                HStack {
                    Image(systemName: "medal.fill")
                        .foregroundColor(Color(hex: "#7B6BD8"))
                        .font(.pixelSystem(size: 11))
                    Text("Level")
                        .font(.pixelSystem(size: 12))
                    Spacer()
                    Text("\(appState.userLevel)")
                        .font(.pixelSystem(size: 11, design: .monospaced))
                }
            }

            Divider()

            // Quick Actions
            Button(action: {
                appState.selectedTab = .sessions
                NSApplication.shared.activate(ignoringOtherApps: true)
            }) {
                HStack {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(Color(hex: "#7B6BD8"))
                    Text("Start Challenge")
                    Spacer()
                }
            }

            Button(action: {
                appState.selectedTab = .skills
                NSApplication.shared.activate(ignoringOtherApps: true)
            }) {
                HStack {
                    Image(systemName: "book.circle.fill")
                        .foregroundColor(Color(hex: "#7B6BD8"))
                    Text("View Skills")
                    Spacer()
                }
            }

            Divider()

            Button("Quit CodePet") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 260)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
