// codepet/Services/DecisionsClient.swift
import Foundation
import os
import FirebaseAuth

/// The approved deliverable's high-signal fields sent to extractDecisions.
struct ApprovedDeliverableDTO: Encodable {
    let title: String
    let dept: String
    let type: String
    let out: String
}

/// Calls the stateless `extractDecisions` Cloud Function. FAIL-OPEN: any error → [].
/// The caller (CompanyStore.rememberFromApproval) does the merge + persist.
enum DecisionsClient {
    private static let endpoint =
        URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/extractDecisions")!

    private struct DecisionOnRecord: Encodable { let topic: String; let statement: String }
    private struct Request: Encodable { let deliverable: ApprovedDeliverableDTO; let existing_decisions: [DecisionOnRecord] }
    private struct Response: Decodable { let decisions: [ExtractedDecision] }

    static func extract(_ deliverable: ApprovedDeliverableDTO, existing: [DecisionEntry]) async -> [ExtractedDecision] {
        let onRecordLocal = existing.map { DecisionOnRecord(topic: $0.topic, statement: $0.statement) }
        // The founder's own Claude Code first, when they granted it. Fail-open stays
        // fail-open — `[]` costs a Second Brain entry, never the approval that already
        // happened — but the reason is logged. It never falls through to the Cloud Function.
        switch LocalTransportRouter.forOneShot() {
        case .local, .localUnavailable:
            do {
                let body = try JSONEncoder().encode(
                    Request(deliverable: deliverable, existing_decisions: onRecordLocal))
                let out = try await LocalOneShotRunner.run(op: "extractDecisions", body: body)
                return try JSONDecoder().decode(Response.self, from: out).decisions
            } catch {
                LocalTransportRouter.log.error(
                    "local extractDecisions failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        case .cloud:
            break
        }
        guard let token = try? await Auth.auth().currentUser?.getIDToken() else { return [] }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let onRecord = existing.map { DecisionOnRecord(topic: $0.topic, statement: $0.statement) }
        guard let body = try? JSONEncoder().encode(Request(deliverable: deliverable, existing_decisions: onRecord)) else { return [] }
        req.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return [] }
        return decoded.decisions
    }
}
