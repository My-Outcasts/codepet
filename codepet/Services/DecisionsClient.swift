// codepet/Services/DecisionsClient.swift
import Foundation
import os

/// The approved deliverable's high-signal fields sent to extractDecisions.
struct ApprovedDeliverableDTO: Encodable {
    let title: String
    let dept: String
    let type: String
    let out: String
}

/// Extracts decisions from an approved deliverable. FAIL-OPEN: any error → [].
/// The caller (CompanyStore.rememberFromApproval) does the merge + persist.
///
/// It runs on the founder's own Claude Code or not at all — `extractDecisions` spent the
/// Anthropic key Codepet no longer holds, so there is nothing to fall back to.
enum DecisionsClient {

    private struct DecisionOnRecord: Encodable { let topic: String; let statement: String }
    private struct Request: Encodable { let deliverable: ApprovedDeliverableDTO; let existing_decisions: [DecisionOnRecord] }
    private struct Response: Decodable { let decisions: [ExtractedDecision] }

    static func extract(_ deliverable: ApprovedDeliverableDTO, existing: [DecisionEntry]) async -> [ExtractedDecision] {
        let onRecord = existing.map { DecisionOnRecord(topic: $0.topic, statement: $0.statement) }
        // Fail-open stays fail-open — `[]` costs a Second Brain entry, never the approval that
        // already happened — but the reason is logged.
        switch LocalTransportRouter.forOneShot() {
        case .local:
            do {
                let body = try JSONEncoder().encode(
                    Request(deliverable: deliverable, existing_decisions: onRecord))
                let out = try await LocalOneShotRunner.run(op: "extractDecisions", body: body)
                return try JSONDecoder().decode(Response.self, from: out).decisions
            } catch {
                LocalTransportRouter.log.error(
                    "local extractDecisions failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        case .blocked(let reason):
            LocalTransportRouter.log.error(
                "extractDecisions blocked: \(String(describing: reason), privacy: .public)")
            return []
        }
    }
}
