import Foundation
import os

/// Runs one virtual company meeting on the founder's OWN Claude Code, as a drop-in for
/// `VirtualCompanyClient.run`.
///
/// Same signature, same `VirtualCompanyEvent` stream, same frames — because the sidecar
/// emits the Cloud Function's exact SSE shape and this reuses `VirtualCompanyEvent.from`
/// to decode it. So swapping transports is an `init` argument on `CompanyStore`, not a
/// change to any card in the room.
///
/// **No API key is involved and no token is handled.** The sidecar spawns `claude`, which
/// reads its own credential from the Keychain. Codepet only moves bytes.
///
/// **A local meeting leaves no server-side record.** The cloud path writes a blackboard to
/// `company_runs`; there is nothing to write to from here, so what the founder rendered is
/// all there is. Worth knowing before someone goes looking for a run that was never stored.
enum LocalVirtualCompanyStreamer {

    static let log = Logger(subsystem: "app.murror.codepet", category: "LocalVirtualCompany")

    /// Dev override for the sidecar's location, for the reason `LocalChatStreamer` records:
    /// the bundled copy is gitignored build output, so a fresh checkout has none until
    /// `scripts/build-sidecar.sh` has run.
    static let sidecarPathKey = "cp_claudeVCSidecarPath"

    static func resolveSidecarPath(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        if let bundled = bundle.path(forResource: "vcSidecar", ofType: "js"), fileExists(bundled) {
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

    /// One DTO for both transports: `VirtualCompanyRequest` already encodes to the Cloud
    /// Function's wire shape, and the sidecar validates it with the same validator the
    /// handler uses. So there is one body and no second mapping to drift.
    static func encode(_ req: VirtualCompanyRequest) throws -> Data {
        try JSONEncoder().encode(req)
    }

    /// Run the meeting. Mirrors `VirtualCompanyClient.run`'s signature so it can be injected
    /// as `vcRunner` without touching a call site.
    static func run(_ req: VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        AsyncThrowingStream<VirtualCompanyEvent, Error> { continuation in
            guard let sidecar = resolveSidecarPath() else {
                log.error("no vc sidecar on disk — a local meeting cannot run")
                continuation.finish(throwing: VirtualCompanyRunError.malformedResponse)
                return
            }

            let body: Data
            do {
                body = try encode(req)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            // A login shell so the founder's PATH resolves `node`, and the credential
            // variables stripped for the reason `LoginShellRunner` records: under `-p` a
            // present key outranks the subscription, so a key exported in their profile
            // would bill the API account this transport exists to stop using. The sidecar
            // strips them again on each `claude` it spawns.
            let shell = LoginShellRunner.loginShells
                .first { FileManager.default.fileExists(atPath: $0) } ?? "/bin/zsh"
            var env = LoginShellRunner.scrubbedEnvironment(ProcessInfo.processInfo.environment)
            // Reaches the blackboard's owner field only, and the blackboard is never written
            // locally — but a run that recorded the wrong founder would be worse than one
            // that records nothing.
            if let companyId = LocalTransportRouter.activeCompanyId {
                env["CODEPET_COMPANY_ID"] = companyId
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: shell)
            proc.arguments = ["-lc", "node \"\(sidecar)\""]
            proc.environment = env

            let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            proc.standardInput = inPipe

            // Parser state and the tail of a partial line, touched only on this queue so the
            // frame order the founder sees matches the order the sidecar wrote. A meeting's
            // frames are ORDER-SENSITIVE in a way chat's are not: `agent_start` before
            // `agent_position`, `conflicts` before `negotiation_round`, `brief` last.
            let queue = DispatchQueue(label: "app.murror.codepet.local-vc")
            var parser = SSEParser()
            var pending = ""

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                queue.async {
                    pending += String(data: chunk, encoding: .utf8) ?? ""
                    // Keep the trailing partial line: a frame split across two reads must not
                    // dispatch early, or its `data:` arrives truncated — and half a position
                    // is a decode failure, not a shorter position.
                    var lines = pending.components(separatedBy: "\n")
                    pending = lines.removeLast()
                    for frame in parser.feedLines(lines) {
                        if let event = VirtualCompanyEvent.from(frame: frame) {
                            continuation.yield(event)
                        }
                    }
                }
            }

            proc.terminationHandler = { p in
                queue.async {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    // A final frame with no trailing newline would otherwise be stranded in
                    // `pending` — and here that frame is usually `done`, without which the
                    // room never leaves its running state.
                    if !pending.isEmpty {
                        for frame in parser.feedLines([pending, ""]) {
                            if let event = VirtualCompanyEvent.from(frame: frame) {
                                continuation.yield(event)
                            }
                        }
                    }
                    if p.terminationStatus != 0 {
                        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                         encoding: .utf8) ?? ""
                        log.error("vc sidecar exited \(p.terminationStatus, privacy: .public): \(err, privacy: .public)")
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
                log.error("could not launch vc sidecar: \(String(describing: error), privacy: .public)")
                continuation.finish(throwing: error)
            }
        }
    }
}
