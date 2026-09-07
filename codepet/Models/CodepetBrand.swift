import Foundation

/// The product's name and who is speaking when no pet does.
///
/// The founder talks to **Codepet**. The pets — byte, nova, crash, luna, sage, glitch, null —
/// are department characters that appear when one of them does a department's work. Every
/// surface that addresses the founder says Codepet; a pet's name belongs to the moment that pet
/// is working. Stated Aug 5, after a build where a general reply was signed "Glitch" because it
/// happened to be the chosen companion.
///
/// Not localised: it is a proper noun in both languages.
enum CodepetBrand {
    static let name = "Codepet"

    /// Who is speaking, by name: the pet that did the work, or the product when no pet did.
    ///
    /// One home because this rule was duplicated at four sites and the copies drifted. Every
    /// one of them read `PetCharacter.all[…]?.name ?? "Codepet"`, which was correct only while
    /// the `byte` character was itself DISPLAYED as "Codepet" — the fallback was unreachable,
    /// so the literal was decoration rather than behaviour. Renaming byte to "Byte" on 26 Aug
    /// turned every such site into a run card that called the product by a department pet's
    /// name. Resolving from `CodepetBrand` rather than from a character is what makes the
    /// host's name independent of the cast.
    static func speakerName(companionId: String?) -> String {
        PetCharacter.all[companionId ?? ""]?.name ?? name
    }

    /// The header a message shows, or nil when the product itself is speaking.
    ///
    /// **nil rather than "Codepet".** The founder talks to the product, so it does not
    /// announce itself on every turn. A pet's name is what makes the moment it works read as
    /// different — and it only does that if the ordinary turn carries no name at all. Founder
    /// call, 6 Sep, after watching every day-one reply sign itself "Codepet".
    ///
    /// Distinct from `speakerName`, which must always yield a word: the transcript export names
    /// a speaker even for an ordinary turn. This one answers "does a row render", which is a
    /// different question and is allowed to say no.
    static func header(companionId: String?, deptName: String?) -> String? {
        guard let id = companionId, let pet = PetCharacter.all[id] else { return nil }
        guard let dept = deptName, !dept.isEmpty else { return pet.name }
        return "\(pet.name) · \(dept)"
    }
}
