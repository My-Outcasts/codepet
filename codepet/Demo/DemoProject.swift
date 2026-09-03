// codepet/Demo/DemoProject.swift
#if DEBUG
import Foundation

/// One canned deliverable a demo project's pet can produce.
///
/// `payloadJSON` is nil for every kind whose viewer reads markdown, and set for the structured
/// ones (`.site`, `.screens`). It stays a JSON STRING rather than a decoded value because that
/// is the exact shape the Cloud Function puts on the wire: a payload built from Swift values
/// could be a shape the decoder rejects, and several payload types declare `init(from:)` and so
/// have no memberwise init anyway. Same reasoning as `LibraryFixtures`.
struct DemoDeliverable {
    /// Matched against the LOWERCASED task title; first entry with any match wins, so specific
    /// keywords must be ordered ahead of general ones. `"email capture"` before `"email"`.
    let keywords: [String]
    /// A `DeliverableKind` rawValue.
    let kind: String
    /// Markdown. May contain `{{product}}` (the project name) and `{{title}}` (the task title).
    let body: String
    let payloadJSON: String?

    init(keywords: [String], kind: String, body: String, payloadJSON: String? = nil) {
        self.keywords = keywords
        self.kind = kind
        self.body = body
        self.payloadJSON = payloadJSON
    }
}

/// A whole demo company: the brief, the board, what each pet produces, and the room.
///
/// **Why this exists.** Prototype mode could already show the whole product on fixtures, but it
/// could not show a *project* — every fixture read was a literal inside `MockChat`, so the demo
/// was Codepet demoing Codepet. `MockChat.productName` substitutes the project NAME through a
/// `{{product}}` token, but every word around the token stayed Codepet's ("the AI cofounder that
/// runs your company's busywork", "For solo founders drowning in scattered docs"). Point that at
/// another company and it reads as find-replace — which is precisely the conclusion the token's
/// own doc comment says it exists to prevent.
///
/// So the content moves behind a value, and there are two of them. `.codepet` carries what the
/// fixtures said before this type existed, verbatim, which is what lets every pre-existing suite
/// pass unedited.
struct DemoProject {
    let id: String
    let brief: CompanyBrief
    let tasks: [RoadmapTask]
    let deliverables: [DemoDeliverable]

    /// **A function of the ask, not a stored array.** `MockVirtualCompany.frames(ask:)` encodes
    /// the founder's own question into `real_question`, and that has to survive quoting — an ask
    /// containing a quote mark would otherwise produce invalid JSON and silently drop the routing
    /// frame, which is the whole room. Flattening this to `[SSEFrame]` would lose that.
    let roomFrames: (String) -> [SSEFrame]

    /// First entry whose keyword appears in the title.
    ///
    /// Falls back to the LAST entry, which is why every project's table must end with a
    /// catch-all: a title matching nothing would otherwise have no deliverable at all, and the
    /// run card would render empty rather than wrong.
    func deliverable(for title: String) -> DemoDeliverable {
        let t = title.lowercased()
        return deliverables.first { d in d.keywords.contains { t.contains($0) } }
            ?? deliverables[deliverables.count - 1]
    }

    // MARK: - Selection

    /// Forced from the command line: `-CODEPET_DEMO_PROJECT murror`.
    static let launchKey = "CODEPET_DEMO_PROJECT"
    /// The persisted preference, consulted only when no launch argument is present.
    static let key = "cp_demoProject"

    /// `current` falls back to `.codepet` for any id not present, so an unknown selection is
    /// inert rather than empty.
    static var all: [DemoProject] { [.codepet, .murror] }

    /// **Read through `PrototypeMode.store`, never `UserDefaults.standard`.**
    ///
    /// That property is already redirected to a scratch suite, wiped on creation, whenever
    /// `XCTestConfigurationFilePath` is set — the fix for issue #117, where the XCTest host
    /// sharing the app's defaults domain meant a founder clicking the prototype toggle changed
    /// what the test target exercised, and a green run told nobody.
    ///
    /// This is a SECOND prototype-mode preference, so it is a second chance to make the same
    /// mistake. Reusing the one seam means the isolation is inherited rather than
    /// re-implemented — and re-implementing it is exactly how the two would drift.
    ///
    /// A launch argument wins because `NSArgumentDomain` outranks every preference file. That is
    /// the same precedence `PrototypeMode.launchKeys` relies on, and it means the demo cannot be
    /// left half-selected between a flag and a stored value.
    static var current: DemoProject {
        let chosen = PrototypeMode.store.string(forKey: launchKey)
            ?? PrototypeMode.store.string(forKey: key)
        return all.first { $0.id == chosen } ?? .codepet
    }

    /// An unknown id is IGNORED rather than stored-and-resolved-to-nothing: `current` falls back
    /// to `.codepet`, so a typo in the launch argument shows the default demo instead of an empty
    /// company.
    static func select(_ id: String) {
        PrototypeMode.store.set(id, forKey: key)
    }

    /// The founder's own question goes into `real_question`, so it has to survive quoting.
    /// Encoded rather than interpolated — moved here from `MockVirtualCompany` so both demo
    /// projects' room frames can use it.
    static func json(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }
}
#endif
