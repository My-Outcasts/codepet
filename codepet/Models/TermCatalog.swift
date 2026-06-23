import Foundation

/// One recognizable coding term plus the lowercased patterns that signal it in
/// the user's real code/events. This is the detection vocabulary for the
/// project-aware Dictionary — distinct from the static teaching content in
/// `DictionaryContent`. The cloud function writes the actual card; the catalog
/// only decides WHICH terms showed up in the user's work.
struct CatalogTerm {
    /// Canonical display token sent to the server, e.g. "OAuth", "async / await".
    let canonical: String
    /// Topic group hint (matches the server's topic enum).
    let topicHint: String   // "frameworks" | "patterns" | "tools" | "language" | "web" | "concepts"
    /// Lowercased match patterns (the canonical token plus aliases/abbreviations).
    let patterns: [String]
}

/// The recognizable-term vocabulary. Deliberately high-signal: common things a
/// beginner building with AI actually meets, biased toward terms whose presence
/// in code is unambiguous. Grows over time; keep patterns specific enough that
/// a bare substring match rarely misfires.
enum TermCatalog {

    static let terms: [CatalogTerm] = [
        // web
        .init(canonical: "OAuth", topicHint: "web", patterns: ["oauth", "oauth2", "signinwithapple", "signinwithgoogle", "aswebauthenticationsession"]),
        .init(canonical: "JWT", topicHint: "web", patterns: ["jwt", "json web token", "bearer token"]),
        .init(canonical: "API", topicHint: "web", patterns: ["api", "rest api", "endpoint"]),
        .init(canonical: "webhook", topicHint: "web", patterns: ["webhook", "webhooks"]),
        .init(canonical: "HTTP request", topicHint: "web", patterns: ["urlsession", "fetch(", "httprequest", "urlrequest", "axios"]),
        .init(canonical: "CORS", topicHint: "web", patterns: ["cors", "cross-origin"]),

        // patterns
        .init(canonical: "async / await", topicHint: "patterns", patterns: ["async", "await", "async/await"]),
        .init(canonical: "MVVM", topicHint: "patterns", patterns: ["mvvm", "viewmodel"]),
        .init(canonical: "dependency injection", topicHint: "patterns", patterns: ["dependency injection", "@environmentobject", "@inject"]),
        .init(canonical: "closure", topicHint: "patterns", patterns: ["closure", "completion handler", "callback"]),
        .init(canonical: "error handling", topicHint: "patterns", patterns: ["try/catch", "do {", "do catch", "throws", "try await", "catch {"]),
        .init(canonical: "optional", topicHint: "patterns", patterns: ["optional", "guard let", "if let", "?? "]),

        // language
        .init(canonical: "protocol", topicHint: "language", patterns: ["protocol "]),
        .init(canonical: "enum", topicHint: "language", patterns: ["enum "]),
        .init(canonical: "generics", topicHint: "language", patterns: ["generic", "<t>", "<element>"]),
        .init(canonical: "struct", topicHint: "language", patterns: ["struct "]),

        // frameworks
        .init(canonical: "SwiftUI", topicHint: "frameworks", patterns: ["swiftui", "some view", "@state", "@binding"]),
        .init(canonical: "Firebase", topicHint: "frameworks", patterns: ["firebase", "firestore", "firebaseauth"]),
        .init(canonical: "Combine", topicHint: "frameworks", patterns: ["combine", "@published", "observableobject", "passthroughsubject"]),
        .init(canonical: "React", topicHint: "frameworks", patterns: ["react", "usestate", "useeffect", "jsx"]),
        .init(canonical: "Node", topicHint: "frameworks", patterns: ["node", "express", "npm "]),

        // tools
        .init(canonical: "git", topicHint: "tools", patterns: ["git ", "git commit", "git push", ".gitignore"]),
        .init(canonical: "environment variable", topicHint: "tools", patterns: [".env", "process.env", "environment variable", "env var", "secrets["]),
        .init(canonical: "package manager", topicHint: "tools", patterns: ["package.json", "podfile", "package.resolved", "requirements.txt", "swift package"]),
        .init(canonical: "the terminal", topicHint: "tools", patterns: ["bash:", "terminal", "command line"]),

        // concepts
        .init(canonical: "state", topicHint: "concepts", patterns: ["state management", "@state", "usestate"]),
        .init(canonical: "caching", topicHint: "concepts", patterns: ["cache", "caching", "ttl"]),
        .init(canonical: "validation", topicHint: "concepts", patterns: ["validate", "validation", "isvalid"]),
    ]
}
