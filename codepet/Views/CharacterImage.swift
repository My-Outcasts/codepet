import SwiftUI

/// Reusable character image view — displays the character PNG from asset catalog.
/// Replaces all 🐾 emoji placeholders with actual character artwork.
struct CharacterImage: View {
    let characterId: String
    let size: CGFloat

    init(_ characterId: String, size: CGFloat = 40) {
        self.characterId = characterId
        self.size = size
    }

    private var imageName: String { "char-\(characterId)" }

    var body: some View {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(PetCharacter.starters, id: \.self) { charId in
            CharacterImage(charId, size: 60)
        }
    }
    .padding()
}
