// codepet/Services/RunTaskClient.swift
import Foundation
import os
import FirebaseAuth

/// Request body for the runTask Cloud Function.
struct RunTaskRequest: Codable {
    let companyId: String?
    let language: String
    let companionId: String
    let context: String
    let taskId: String
    let taskTitle: String
    let taskDetail: String
    /// Set only on a revise re-run (chip tap or free-form redo-with-note): the
    /// instruction to apply ("Make it shorter", etc). `nil` on a blind redo/first run.
    var reviseNote: String? = nil
    /// The current draft body, sent alongside `reviseNote` so the CF revises in
    /// place instead of regenerating from scratch. `nil` on a blind redo/first run.
    var current: String? = nil
    /// The owning department of the task being run (a `DepartmentCatalog` key), so the
    /// deliverable is produced with that department's expertise rather than generic
    /// company context. nil for a legacy dept-less task, which omits the key entirely.
    ///
    /// A run has always been performed BY a department — `taskSpecialist` shows its pet on
    /// the execute log and on the draft — and until now that was the only thing the
    /// department affected. The prompt never learned which department it was writing for.
    var deptKey: String? = nil

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case language
        case companionId = "companion_id"
        case context
        case taskId = "task_id"
        case taskTitle = "task_title"
        case taskDetail = "task_detail"
        case reviseNote = "revise_note"
        case current
        case deptKey = "dept_key"
    }
}

/// Response body from the runTask Cloud Function — a deliverable as kind + markdown.
struct RunTaskResponse: Codable {
    let kind: String
    let title: String
    let body: String
    var payload: DeliverablePayload?
}

/// Fail-open client for the (planned) runTask Cloud Function. Returns the decoded
/// response on 200, `nil` on any error / non-200 / unreachable — callers never handle
/// throws. The CF is authored + deployed separately (node-22 bundle, like companyChat);
/// until then this returns nil and the run surfaces an honest error.
enum RunTaskClient {
    static let endpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/runTask")!

    static func run(_ req: RunTaskRequest) async -> RunTaskResponse? {
        #if DEBUG
        if MockChat.enabled { return await MockChat.runResult(req) }
        #endif
        // The founder's own Claude Code first, when they granted it. Fail-open is preserved
        // (`nil` is what the caller turns into an honest error on the card), but the reason
        // is LOGGED — a run that silently produced nothing is the hardest failure here to
        // diagnose. It never falls through to the Cloud Function: that would spend the API
        // key the grant exists to stop spending.
        switch OneShotTransportRouter.transport() {
        case .local, .localUnavailable:
            do {
                let body = try JSONEncoder().encode(req)
                let out = try await LocalOneShotRunner.run(op: "runTask", body: body)
                return try JSONDecoder().decode(RunTaskResponse.self, from: out)
            } catch {
                OneShotTransportRouter.log.error(
                    "local runTask failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        case .cloud:
            break
        }
        guard let token = try? await Auth.auth().currentUser?.getIDToken() else { return nil }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        urlRequest.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(RunTaskResponse.self, from: data)
        else { return nil }
        return decoded
    }
}
