import Foundation
import os

private let log = Logger(subsystem: "app.murror.codepet", category: "TeamPlanClient")

struct TeamPlanRequest: Encodable {
    let language: String
    let request: String
    let brief: VCBrief?
    let company: [String: String]
    let roster: [String]
}

/// Local-only, like every AI path since the key was deleted: no Cloud Function fallback.
enum TeamPlanClient {
    static func decode(_ data: Data) -> WorkPlan? { try? JSONDecoder().decode(WorkPlan.self, from: data) }

    static func plan(_ req: TeamPlanRequest) async -> WorkPlan? {
        switch LocalTransportRouter.forOneShot() {
        case .local(let provider):
            do {
                let body = try JSONEncoder().encode(req)
                let out = try await LocalOneShotRunner.run(op: "planTeamWork", body: body, provider: provider)
                return decode(out)
            } catch {
                log.error("planTeamWork failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        case .blocked(let reason):
            log.error("planTeamWork blocked: \(String(describing: reason), privacy: .public)")
            return nil
        }
    }
}
