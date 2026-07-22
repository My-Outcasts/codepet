// codepet/Services/CompanyChatClient.swift
import Foundation
import FirebaseAuth

/// One prior chat turn sent to the CF as history.
struct ChatTurnDTO: Codable, Equatable {
    let role: String   // "me" | "companion"
    let text: String
}

/// Request body for the companyChat Cloud Function.
struct CompanyChatRequest: Codable {
    let companyId: String?
    let language: String
    let companionId: String
    let context: String
    let history: [ChatTurnDTO]
    let userMessage: String

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case language
        case companionId = "companion_id"
        case context
        case history
        case userMessage = "user_message"
    }
}

/// Response body from the companyChat Cloud Function.
struct CompanyChatResponse: Codable {
    let reply: String
    let runTaskId: String?

    enum CodingKeys: String, CodingKey {
        case reply
        case runTaskId = "run_task_id"
    }
}

/// A companion reply — text plus an optional "run this task" action (byte's run_task).
struct CompanyChatReply: Equatable {
    let text: String
    let runTaskId: String?
}

/// Fail-open client for the (planned) companyChat Cloud Function. Returns the reply
/// on 200, `nil` on any error / non-200 / unreachable — callers never handle throws.
/// The CF is authored + deployed separately (node-22 bundle, like scaffoldRoadmap);
/// until then this returns nil and the chat shows an honest offline message.
enum CompanyChatClient {
    static let endpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/companyChat")!

    static func send(_ req: CompanyChatRequest) async -> CompanyChatReply? {
        guard let token = try? await Auth.auth().currentUser?.getIDToken() else { return nil }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        urlRequest.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CompanyChatResponse.self, from: data)
        else { return nil }
        let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return nil }
        return CompanyChatReply(text: reply, runTaskId: decoded.runTaskId)
    }
}
