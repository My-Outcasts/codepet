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
            library: [],
            stage: doc.stage.flatMap { ProjectStage(rawValue: $0) } ?? .idea,
            companionId: doc.companionId ?? "byte",
            onboardedAt: doc.onboardedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
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
