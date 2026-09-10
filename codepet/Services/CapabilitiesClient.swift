// Which skills the backend implements. One unauthenticated GET — see the note on
// the `capabilities` function: the payload is a static constant with no founder
// data, which is what lets the Environment tab resolve its state on first paint.
import Foundation

enum CapabilitiesClient {

    static let endpoint = URL(
        string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/capabilities")!

    private struct Payload: Decodable { let skills: [String] }

    /// The implemented skill ids, or `nil` when the manifest could not be read.
    ///
    /// `nil` and an empty set are deliberately different returns. Empty means the
    /// backend implements nothing; `nil` means we do not know, and the caller must
    /// substitute `Toolkit.bundledBuiltSkills` rather than render every skill as
    /// unbuilt on a dropped connection.
    static func fetch() async -> Set<String>? {
        guard let (data, response) = try? await URLSession.shared.data(from: endpoint),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        return Set(payload.skills)
    }
}
