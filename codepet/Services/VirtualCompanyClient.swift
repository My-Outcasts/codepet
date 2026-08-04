// codepet/Services/VirtualCompanyClient.swift
import Foundation
import FirebaseAuth

/// Non-SSE error body. The endpoint answers 400/401/405/429/503 as plain JSON
/// without opening a stream — see the contract's error table.
struct VCErrorBody: Codable, Equatable {
    let error: String
    let detail: String?
    let resetAt: String?
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case error, detail, limit
        case resetAt = "reset_at"
    }
}

enum VirtualCompanyRunError: Error, Equatable {
    case notSignedIn
    case http(status: Int, body: VCErrorBody?)
    case malformedResponse
}

/// The only thing in the app that talks to `virtualCompanyRun`.
///
/// Deliberately shaped like `CompanyChatClient.sendStream`: a plain enum with
/// static functions, `URLSession.bytes(for:)` fed through the shared `SSEParser`,
/// and injectable `session` / `authTokenProvider` so tests exercise the decoding
/// with no network. Carrying no actor isolation also keeps its tests clear of the
/// Xcode 26.2 isolated-deinit teardown bug.
enum VirtualCompanyClient {

    static let endpoint = URL(string:
        "https://us-central1-devpet-8f4b1.cloudfunctions.net/virtualCompanyRun")!

    static func run(
        _ req: VirtualCompanyRequest,
        session: URLSession = .shared,
        authTokenProvider: (() async throws -> String)? = nil
    ) -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        let capturedSession = session
        let capturedToken = authTokenProvider ?? {
            guard let token = try? await Auth.auth().currentUser?.getIDToken() else {
                throw VirtualCompanyRunError.notSignedIn
            }
            return token
        }

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let token = try await capturedToken()

                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = try JSONEncoder().encode(req)

                    let (bytes, response) = try await capturedSession.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw VirtualCompanyRunError.malformedResponse
                    }

                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw VirtualCompanyRunError.http(
                            status: http.statusCode,
                            body: try? JSONDecoder().decode(VCErrorBody.self, from: data))
                    }

                    var parser = SSEParser()
                    var lineBuffer: [UInt8] = []
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer.removeAll(keepingCapacity: true)
                            for frame in parser.feedLines([line]) {
                                if let event = VirtualCompanyEvent.from(frame: frame) {
                                    continuation.yield(event)
                                }
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    if !lineBuffer.isEmpty {
                        let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                        for frame in parser.feedLines([line]) {
                            if let event = VirtualCompanyEvent.from(frame: frame) {
                                continuation.yield(event)
                            }
                        }
                    }
                    // The server always ends a frame with a blank line, but flush
                    // anyway so a missing trailing newline cannot swallow the last one.
                    for frame in parser.feedLines([""]) {
                        if let event = VirtualCompanyEvent.from(frame: frame) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
