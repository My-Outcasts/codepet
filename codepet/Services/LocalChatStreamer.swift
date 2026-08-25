import Foundation
import os

/// Runs one chat turn on the founder's OWN Claude Code, as a drop-in for
/// `CompanyChatClient.sendStream`.
///
/// Same signature, same `CompanyChatStreamEvent` stream, same frames — because the sidecar
/// emits the Cloud Function's exact SSE shape and this reuses
/// `CompanyChatClient.handleStreamFrame` to decode it. So swapping transports is an
/// `init` argument on `CompanyStore`, not a change to any consumer.
///
/// **No API key is involved and no token is handled.** The sidecar spawns `claude`, which
/// reads its own credential from the Keychain. Codepet only moves bytes.
enum LocalChatStreamer {

    static let log = Logger(subsystem: "app.murror.codepet", category: "LocalChat")

    /// Dev override for the compiled sidecar's location. `functions/lib` is gitignored, so
    /// a checkout has no sidecar until `npm run build` has run — which is exactly why this
    /// is a settable path rather than a hardcoded one.
    static let sidecarPathKey = "cp_claudeSidecarPath"

    /// Where the compiled sidecar is, or nil when this build cannot reach one.
    ///
    /// Bundle resource first so a shipped app never depends on a developer's checkout;
    /// the override second so a developer can point at their build tree. Returning nil
    /// rather than a guess matters: the caller has to decide what to tell the founder, and
    /// "the local path is unavailable" is a different message from "the run failed".
    static func resolveSidecarPath(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        if let bundled = bundle.path(forResource: "chatSidecar", ofType: "js"), fileExists(bundled) {
            return bundled
        }
        if let override = defaults.string(forKey: sidecarPathKey),
           !override.isEmpty,
           fileExists(override) {
            return override
        }
        return nil
    }

    /// Whether a local turn can even be attempted. Deliberately does NOT check for
    /// `claude` itself — that is `ClaudeCodeEnvironment`'s job and it costs a subprocess,
    /// so the two questions stay separate and the caller asks both.
    static func isAvailable(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> Bool {
        resolveSidecarPath(defaults: defaults, bundle: bundle) != nil
    }

    /// The request body the sidecar reads, which is byte-for-byte the body the Cloud
    /// Function reads — `CompanyChatRequest` already encodes to the CF's wire shape, so
    /// there is one DTO and no second mapping to drift.
    static func encode(_ req: CompanyChatRequest) throws -> Data {
        try JSONEncoder().encode(req)
    }

    /// Run the turn. Mirrors `CompanyChatClient.sendStream`'s signature so it can be
    /// injected as `chatStreamer` without touching a call site.
    static func sendStream(_ req: CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let sidecar = resolveSidecarPath() else {
                log.error("no sidecar on disk — local chat unavailable")
                continuation.finish(throwing: CompanyChatStreamError.malformedResponse)
                return
            }

            let body: Data
            do {
                body = try encode(req)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            // A login shell so the founder's PATH resolves `node`, for the same reason
            // `LoginShellRunner` uses one: an app launched from Finder inherits none of
            // their profile. Credential variables are stripped for the reason recorded
            // there too — under `-p` a present key outranks the subscription, and the
            // sidecar strips them again on its own child.
            let shell = LoginShellRunner.loginShells
                .first { FileManager.default.fileExists(atPath: $0) } ?? "/bin/zsh"
            var env = ProcessInfo.processInfo.environment
            for key in LoginShellRunner.strippedEnvironmentKeys { env.removeValue(forKey: key) }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: shell)
            proc.arguments = ["-lc", "node \"\(sidecar)\""]
            proc.environment = env

            let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            proc.standardInput = inPipe

            // Parser state and the tail of a partial line, touched only on this queue so
            // the frame order the founder sees matches the order the sidecar wrote.
            let queue = DispatchQueue(label: "app.murror.codepet.local-chat")
            var parser = SSEParser()
            var pending = ""
            var failed = false

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                queue.async {
                    guard !failed else { return }
                    pending += String(data: chunk, encoding: .utf8) ?? ""
                    // Keep the trailing partial line: a frame split across two reads must
                    // not dispatch early, or its `data:` arrives truncated.
                    var lines = pending.components(separatedBy: "\n")
                    pending = lines.removeLast()
                    for frame in parser.feedLines(lines) {
                        do {
                            try CompanyChatClient.handleStreamFrame(frame: frame, continuation: continuation)
                        } catch {
                            failed = true
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                }
            }

            proc.terminationHandler = { p in
                queue.async {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    guard !failed else { return }
                    // A `done` frame with no trailing newline would otherwise be stranded
                    // in `pending`, and a missing `done` makes the store fall back to the
                    // non-streaming sender and REPLACE text the founder already watched.
                    if !pending.isEmpty {
                        for frame in parser.feedLines([pending, ""]) {
                            try? CompanyChatClient.handleStreamFrame(frame: frame, continuation: continuation)
                        }
                    }
                    if p.terminationStatus != 0 {
                        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                         encoding: .utf8) ?? ""
                        log.error("sidecar exited \(p.terminationStatus, privacy: .public): \(err, privacy: .public)")
                    }
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                if proc.isRunning { proc.terminate() }
            }

            do {
                try proc.run()
                inPipe.fileHandleForWriting.write(body)
                inPipe.fileHandleForWriting.closeFile()
            } catch {
                log.error("could not launch sidecar: \(String(describing: error), privacy: .public)")
                continuation.finish(throwing: error)
            }
        }
    }
}
