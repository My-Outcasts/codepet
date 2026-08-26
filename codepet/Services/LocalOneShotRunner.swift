import Foundation
import os

/// Runs one non-streaming Cloud Function on the founder's OWN Claude Code and hands back the
/// bytes that function's HTTP 200 would have carried.
///
/// So a caller decodes the response it already decodes: the sidecar prints the Cloud
/// Function's own body, which means one DTO, one decoder, and no second wire shape to drift.
///
/// **No API key is involved and no token is handled.** The sidecar spawns `claude`, which
/// reads its own credential from the Keychain. Codepet only moves bytes.
enum LocalOneShotRunner {

    static let log = Logger(subsystem: "app.murror.codepet", category: "LocalOneShot")

    /// Dev override for the sidecar's location, for the reason `LocalChatStreamer` records:
    /// the bundled copy is gitignored build output, so a fresh checkout has none until
    /// `scripts/build-sidecar.sh` has run.
    static let sidecarPathKey = "cp_claudeOneShotSidecarPath"

    enum Failure: LocalizedError, Equatable {
        /// No sidecar on disk. Distinct from a failed run: the founder's fix is different.
        case unavailable
        /// The sidecar ran and refused, carrying the reason it printed.
        case refused(error: String, detail: String)
        /// It produced something that is not a response body at all.
        case malformedOutput

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Codepet can't reach its local runner on this Mac."
            case .refused(let error, let detail):
                return detail.isEmpty ? error : "\(error): \(detail)"
            case .malformedOutput:
                return "The local runner answered with something Codepet couldn't read."
            }
        }
    }

    /// Where the compiled one-shot sidecar is, or nil when this build cannot reach one.
    ///
    /// Bundle resource first so a shipped app never depends on a developer's checkout; the
    /// override second so a developer can point at their build tree. Returning nil rather
    /// than a guess matters — the caller has to decide what to tell the founder, and "the
    /// local path is unavailable" is a different message from "the run failed".
    static func resolveSidecarPath(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        if let bundled = bundle.path(forResource: "oneShotSidecar", ofType: "js"), fileExists(bundled) {
            return bundled
        }
        if let override = defaults.string(forKey: sidecarPathKey),
           !override.isEmpty,
           fileExists(override) {
            return override
        }
        return nil
    }

    static func isAvailable(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> Bool {
        resolveSidecarPath(defaults: defaults, bundle: bundle) != nil
    }

    /// The stdin the sidecar reads: the op's name, and the body the Cloud Function takes.
    ///
    /// `body` is pre-encoded rather than generic so the caller reuses the request DTO it
    /// already encodes for the HTTP path — the same anti-drift reason `LocalChatStreamer`
    /// encodes `CompanyChatRequest` itself.
    static func encodeRequest(op: String, body: Data) throws -> Data {
        guard let bodyObject = try? JSONSerialization.jsonObject(with: body) else {
            throw Failure.malformedOutput
        }
        return try JSONSerialization.data(withJSONObject: ["op": op, "body": bodyObject])
    }

    /// Whether the sidecar's output is a refusal rather than a response body.
    ///
    /// It reports failure as `{"error": ..., "detail": ...}`, and no Cloud Function body here
    /// carries a top-level `error` on success — so this is unambiguous, and pure enough to
    /// test without spawning anything.
    static func failure(in data: Data) -> Failure? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformedOutput
        }
        guard let error = object["error"] as? String else { return nil }
        return .refused(error: error, detail: object["detail"] as? String ?? "")
    }

    /// Run one op. Returns the Cloud Function's response body, or throws.
    ///
    /// - Parameters:
    ///   - op: a key in the sidecar's `ONE_SHOT_OPS` registry.
    ///   - body: the JSON body the matching Cloud Function takes.
    static func run(
        op: String,
        body: Data,
        companyId: String? = LocalTransportRouter.activeCompanyId,
        modelPreference: ClaudeCodeModelPreference = ClaudeCodeModelPreference()
    ) async throws -> Data {
        guard let sidecar = resolveSidecarPath() else {
            log.error("no one-shot sidecar on disk — \(op, privacy: .public) cannot run locally")
            throw Failure.unavailable
        }

        let payload = try encodeRequest(op: op, body: body)

        // A login shell so the founder's PATH resolves `node`, and the credential variables
        // stripped for the reason `LoginShellRunner` records: under `-p` a present key
        // outranks the subscription, so a key exported in their profile would bill the API
        // account this whole design exists to stop using. The sidecar strips them again on
        // its own child.
        let shell = LoginShellRunner.loginShells
            .first { FileManager.default.fileExists(atPath: $0) } ?? "/bin/zsh"
        var env = LoginShellRunner.scrubbedEnvironment(ProcessInfo.processInfo.environment)
        // The founder's model choice, as an alias so it tracks the latest of that tier.
        // Absent for `.inherit`, which is what makes the sidecar pass no `--model` at all and
        // leave the decision to their own Claude Code. Same variables chat uses: the pick is
        // "the model Codepet may use on my plan", not a per-feature setting.
        if let companyId {
            if let model = modelPreference.model(companyId).flag {
                env["CODEPET_CHAT_MODEL"] = model
            }
            if let effort = modelPreference.effort(companyId).flag {
                env["CODEPET_CHAT_EFFORT"] = effort
            }
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", "node \"\(sidecar)\""]
        proc.environment = env

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = inPipe

        let out = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            // Read both pipes on background queues BEFORE waiting: a reply larger than the
            // pipe buffer would otherwise deadlock the child against a parent that is only
            // waiting for it to exit.
            let collector = OutputCollector()
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    collector.appendOut(chunk)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    collector.appendErr(chunk)
                }
            }

            proc.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let (stdout, stderr) = collector.drain()
                if stdout.isEmpty {
                    // Nothing on stdout at all: `node` itself never ran, or died before the
                    // sidecar could report. Its stderr is the only real reason available.
                    let reason = String(data: stderr, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    log.error("one-shot \(op, privacy: .public) exited \(p.terminationStatus, privacy: .public): \(reason, privacy: .public)")
                    continuation.resume(throwing: Failure.refused(
                        error: "local_runner_failed",
                        detail: reason.isEmpty ? "the local runner exited \(p.terminationStatus)" : reason))
                    return
                }
                continuation.resume(returning: stdout)
            }

            do {
                try proc.run()
                inPipe.fileHandleForWriting.write(payload)
                inPipe.fileHandleForWriting.closeFile()
            } catch {
                log.error("could not launch one-shot sidecar: \(String(describing: error), privacy: .public)")
                continuation.resume(throwing: error)
            }
        }

        if let failure = failure(in: out) {
            log.error("one-shot \(op, privacy: .public) refused: \(failure.localizedDescription, privacy: .public)")
            throw failure
        }
        return out
    }
}

/// Accumulates two pipes' bytes under a lock, because the readability handlers fire on
/// arbitrary queues and the termination handler reads what they collected.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func appendOut(_ data: Data) { lock.lock(); out.append(data); lock.unlock() }
    func appendErr(_ data: Data) { lock.lock(); err.append(data); lock.unlock() }
    func drain() -> (Data, Data) {
        lock.lock(); defer { lock.unlock() }
        return (out, err)
    }
}
