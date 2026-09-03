import SwiftUI

/// Reusable character image view — displays the character PNG from asset catalog.
/// Replaces all 🐾 emoji placeholders with actual character artwork.
///
/// **Smooth downscaling here is deliberate, not an omission.** `CLAUDE.md` says pixel
/// art always uses nearest-neighbour, and that rule is about UPSCALING, where nearest
/// is the difference between crisp pixels and blur. A row like `DepartmentPicker`'s
/// draws this at `size: 20` against source art around 421pt — a ~20× reduction, where
/// nearest would sample one pixel in twenty and can drop a 4px eye entirely, while the
/// default smooth scaling preserves the impression of the face. Do not add
/// `.interpolation(.none)` to a small `CharacterImage`; that is correct for upscaling
/// and wrong for this.
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
