// codepet/Services/CompanyData.swift
import Foundation
import FirebaseFirestore

/// The companies/{uid} Firestore document (mirrors the web CompanyDoc:
/// lib/firebase/schema.ts). Departments + library live in subcollections
/// (loaded in later phases); this phase reads the top-level doc only.
struct CompanyDoc: Codable {
    var brief: CompanyBrief?
    var stage: String?
    var companionId: String?
    var onboardedAt: String?   // ISO-8601 string (JSON-safe; not a Firestore Timestamp)
    var tasks: [RoadmapTask]?  // JSON-safe (strings/enums-as-string/bools/arrays)
    var library: [Deliverable]?  // JSON-safe (strings/enum-as-string/optional strings)
}

/// Reads companies/{uid} and maps it to CompanyState. Mirrors
/// lib/firebase/companyData.ts. Fail-soft: missing doc / error → .empty.
enum CompanyData {
    /// Pure mapping — testable without Firestore.
    static func state(from doc: CompanyDoc?) -> CompanyState {
        guard let doc = doc else { return .empty }
        return CompanyState(
            brief: doc.brief ?? CompanyBrief(),
            departments: [],
            library: doc.library ?? [],
            stage: doc.stage.flatMap { ProjectStage(rawValue: $0) } ?? .idea,
            companionId: doc.companionId ?? "byte",
            onboardedAt: doc.onboardedAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            tasks: doc.tasks ?? []
        )
    }

    /// Pure Firestore payload for a brief write — testable without Firestore.
    static func briefPayload(_ brief: CompanyBrief, onboardedAt: String) -> [String: Any] {
        var payload: [String: Any] = ["onboardedAt": onboardedAt]
        if let data = try? JSONEncoder().encode(brief),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload["brief"] = dict
        }
        return payload
    }

    /// Write companies/{uid} (brief + onboardedAt), merge. Fail-soft: false on error.
    /// First native write to companies/{uid}.
    static func saveBrief(companyId: String, brief: CompanyBrief) async -> Bool {
        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(briefPayload(brief, onboardedAt: iso), merge: true)
            return true
        } catch {
            return false
        }
    }

    /// Pure Firestore payload for a tasks write — testable without Firestore.
    static func tasksPayload(_ tasks: [RoadmapTask]) -> [String: Any] {
        if let data = try? JSONEncoder().encode(tasks),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return ["tasks": arr]
        }
        return ["tasks": []]
    }

    /// Write companies/{uid}.tasks, merge. Fail-soft: false on error.
    static func saveTasks(companyId: String, tasks: [RoadmapTask]) async -> Bool {
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(tasksPayload(tasks), merge: true)
            return true
        } catch {
            return false
        }
    }

    /// Fetch the generated roadmap for a company. FAIL-OPEN placeholder: returns `[]`
    /// until the `scaffoldRoadmap` Cloud Function is aligned to the RoadmapTask shape
    /// (phase/dependencies) and deployed (needs node 22). `generateRoadmap` treats `[]`
    /// as "no change", so the board stays empty rather than clearing existing tasks.
    static func fetchRoadmap(brief: CompanyBrief) async -> [RoadmapTask] {
        []
    }

    /// Load companies/{uid} from Firestore; fail-soft to .empty. Decodes via
    /// JSONSerialization → JSONDecoder (no FirebaseFirestoreSwift dependency;
    /// the doc holds only strings/nested strings, which are JSON-safe).
    /// Heads-up: a non-JSON-representable Firestore type (e.g. `Timestamp`,
    /// `GeoPoint`, `DocumentReference`) added to `CompanyDoc` would throw in
    /// `JSONSerialization.data`/`JSONDecoder.decode` here and silently
    /// fail-soft to `.empty` — convert such fields to a JSON-safe
    /// representation (e.g. epoch seconds) before adding them to the doc.
    static func load(companyId: String) async -> CompanyState {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("companies").document(companyId).getDocument()
            guard let dict = snap.data() else { return .empty }
            let data = try JSONSerialization.data(withJSONObject: dict)
            let doc = try JSONDecoder().decode(CompanyDoc.self, from: data)
            return state(from: doc)
        } catch {
            return .empty
        }
    }
}
