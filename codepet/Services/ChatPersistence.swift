// codepet/Services/ChatPersistence.swift
import Foundation
import FirebaseFirestore

/// Persists chat threads to a per-account subcollection —
/// `companies/{uid}/threads/{threadId}` — one doc per thread, so a busy thread
/// only rewrites itself and no single doc approaches Firestore's 1MB limit.
/// Encodes the Codable `ChatThread` via JSONEncoder → JSONSerialization (same
/// path as `CompanyData`'s field writes). All ops are fail-soft.
enum ChatPersistence {
    /// Cap the hydrated Recent list so launch stays cheap; older threads remain
    /// in Firestore but aren't loaded.
    static let loadLimit = 50

    private static func collection(_ companyId: String) -> CollectionReference {
        Firestore.firestore().collection("companies").document(companyId).collection("threads")
    }

    /// Pure — testable without Firestore. The thread is persisted as its
    /// `.persistable` projection (transient run state stripped).
    static func threadPayload(_ thread: ChatThread) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(thread.persistable),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }

    /// Write one thread. Fail-soft: false on error / empty payload.
    static func saveThread(companyId: String, thread: ChatThread) async -> Bool {
        let payload = threadPayload(thread)
        guard !payload.isEmpty else { return false }
        do {
            try await collection(companyId).document(thread.id).setData(payload, merge: true)
            return true
        } catch {
            return false
        }
    }

    /// Delete one thread. Fail-soft.
    static func deleteThread(companyId: String, threadId: String) async -> Bool {
        do {
            try await collection(companyId).document(threadId).delete()
            return true
        } catch {
            return false
        }
    }

    /// Load the most-recent threads (newest first). Fail-soft to []. Decodes each
    /// doc back to a `ChatThread`; a doc that fails to decode is skipped, not fatal.
    static func loadThreads(companyId: String) async -> [ChatThread] {
        do {
            let snap = try await collection(companyId)
                .order(by: "updatedAt", descending: true)
                .limit(to: loadLimit)
                .getDocuments()
            return snap.documents.compactMap { doc in
                guard let data = try? JSONSerialization.data(withJSONObject: doc.data()) else { return nil }
                return try? JSONDecoder().decode(ChatThread.self, from: data)
            }
        } catch {
            return []
        }
    }
}
