import SwiftUI

struct SplashView: View {
    var onContinue: (() -> Void)? = nil

    @Environment(\.uiLanguage) private var uiLanguage
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.9
    @State private var showChars = false
    @State private var bounceOffsets: [Double] = Array(repeating: 0, count: 8)

    private let characters = PetCharacter.starters

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let charHeight = max(56, h * 0.11)
            let charSpacing = max(10, w * 0.014)
            let logoWidth = max(220, w * 0.2)
            let underlineWidth = logoWidth * 0.93
            let buttonWidth = max(240, w * 0.22)
            let shadowWidth = charHeight * 8 + charSpacing * 9
            let taglineFont = max(13, h * 0.017)
            let buttonFont = max(15, h * 0.019)

            ZStack {
                Color(hex: "#F5F3FA")
                    .ignoresSafeArea()

                // Soft brand glow behind the cast — adds depth & color without clutter.
                RadialGradient(
                    colors: [Color(hex: "#7B6BD8").opacity(0.16), Color(hex: "#7B6BD8").opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: w * 0.42
                )
                .offset(y: -h * 0.06)
                .ignoresSafeArea()
                .opacity(showChars ? 1 : 0)

                VStack(spacing: 0) {
                    Spacer()

                    // Character row with idle bounce animation
                    HStack(spacing: charSpacing) {
                        ForEach(Array(characters.enumerated()), id: \.element) { index, charId in
                            Image("char-\(charId)")
                                .resizable()
                                .interpolation(.none)
                                .aspectRatio(contentMode: .fit)
                                .frame(height: charHeight)
                                .offset(y: bounceOffsets[index])
                        }
                    }
                    .opacity(showChars ? 1 : 0)
                    .offset(y: showChars ? 0 : 10)

                    // Ground shadow under characters
                    Ellipse()
                        .fill(Color.black.opacity(0.05))
                        .frame(width: shadowWidth, height: 6)
                        .padding(.top, 2)
                        .padding(.bottom, h * 0.03)

                    // Pixel-art logo with gradient underline
                    VStack(spacing: 0) {
                        Image("codepet-text-logo")
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: logoWidth)

                        // Gradient underline directly under logo
                        LinearGradient(
                            colors: [
                                Color(hex: "#534AB7"),
                                Color(hex: "#7B6BD8"),
                                Color(hex: "#E04040"),
                                Color(hex: "#6EAE5E")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: underlineWidth, height: 3)
                        .cornerRadius(1.5)
                        .opacity(0.5)
                        .offset(y: 4)
                    }
                    .padding(.bottom, h * 0.02)

                    // Tagline
                    Text(uiLanguage == .vi ? "Người bạn AI lập trình của bạn đang chờ." : "Your AI coding companions are waiting.")
                        .font(.pixelSystem(size: taglineFont))
                        .foregroundColor(.secondary)
                        .padding(.bottom, h * 0.035)

                    // Meet Your Pet button
                    if let onContinue = onContinue {
                        Button(action: onContinue) {
                            Text(uiLanguage == .vi ? "Gặp Pet Của Bạn" : "Meet Your Pet")
                                .frame(maxWidth: buttonWidth)
                        }
                        .buttonStyle(PixelButtonStyle(
                            fill: Color(hex: "#7B6BD8"),
                            foreground: .white,
                            borderColor: Color(hex: "#2D2664"),
                            paddingH: 18,
                            paddingV: h * 0.018,
                            blockSize: 3,
                            steps: 2,
                            borderWidth: 3,
                            shadowOffset: 4,
                            font: .pixelSystem(size: buttonFont, weight: .semibold)
                        ))
                    }

                    Spacer()

                    // Footer
                    VStack(spacing: 4) {
                        LinearGradient(
                            colors: [
                                Color(hex: "#534AB7"),
                                Color(hex: "#7B6BD8"),
                                Color(hex: "#FF8C00"),
                                Color(hex: "#E04040"),
                                Color(hex: "#6EAE5E")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 2)
                        .cornerRadius(1)
                        .padding(.horizontal, 40)
                        .opacity(0.4)

                        Text("v1.0 · made with vibes")
                            .font(.pixelSystem(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.bottom, 8)
                    }
                }
                .opacity(opacity)
                .scaleEffect(scale)
            }
        }
        .onAppear {
            SoundManager.shared.playSplashIn()
            withAnimation(.easeOut(duration: 0.8)) {
                opacity = 1
                scale = 1
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.4)) {
                showChars = true
            }
            // Start staggered idle bounce for each character
            for i in 0..<characters.count {
                let delay = 1.0 + Double(i) * 0.15
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    startBounce(index: i)
                }
            }
        }
    }

    private func startBounce(index: Int) {
        // Each character gets a slightly different speed for organic feel
        let baseDuration = 0.5 + Double(index % 3) * 0.08
        withAnimation(
            .easeInOut(duration: baseDuration)
            .repeatForever(autoreverses: true)
        ) {
            bounceOffsets[index] = -4
        }
    }

}

#Preview {
    SplashView(onContinue: {})
}
