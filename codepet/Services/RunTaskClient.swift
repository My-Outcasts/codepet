// codepet/Services/RunTaskClient.swift
import Foundation
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

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case language
        case companionId = "companion_id"
        case context
        case taskId = "task_id"
        case taskTitle = "task_title"
        case taskDetail = "task_detail"
    }
}

/// Response body from the runTask Cloud Function — a deliverable as kind + markdown.
struct RunTaskResponse: Codable {
    let kind: String
    let title: String
    let body: String
}

/// Fail-open client for the (planned) runTask Cloud Function. Returns the decoded
/// response on 200, `nil` on any error / non-200 / unreachable — callers never handle
/// throws. The CF is authored + deployed separately (node-22 bundle, like companyChat);
/// until then this returns nil and the run surfaces an honest error.
enum RunTaskClient {
    static let endpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/runTask")!

    static func run(_ req: RunTaskRequest) async -> RunTaskResponse? {
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
