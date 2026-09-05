// codepet/Services/MockVirtualCompany.swift
#if DEBUG
import Foundation

/// A room, without the network.
///
/// `VirtualCompanyClient` was the ONE client with no mock path — the single thing
/// that still reached the wire when every other call was stubbed. So convening under
/// `-CODEPET_MOCK_CHAT` or the autoplay walkthrough spent on the live
/// `virtualCompanyRun` (~$0.20 a room), unattended, while every surface around it
/// claimed to be free. It goes in at `CompanyStore.vcRunner`, the seam that already
/// existed for exactly this and that `codeRunner` uses the same way.
///
/// **The frames are wire JSON, decoded by the real `VirtualCompanyEvent.from(frame:)`.**
/// Constructing the events directly would have been shorter, but most of the payload
/// structs declare `init(from:)` and so have no memberwise init — and going around
/// the decoder is the wrong shortcut anyway: a fixture built from Swift values cannot
/// catch a renamed wire key, while this one fails loudly the moment the contract and
/// the client disagree. `docs/superpowers/specs/virtual-company-sse-contract.md` is
/// the authority for every key below.
///
/// **Written against that contract's nine rendering rules**, which `CLAUDE.md` records
/// a previous plan's sample code violating in five places. The two that bite a FIXTURE
/// hardest:
///
/// - **Rule 8: no artificial delay or fake typing.** The temptation in a demo is to
///   space the frames so the room looks like it is thinking. "Users detect it and lose
///   trust" — so every frame is yielded at once and the room arrives whole. The thing
///   worth watching is the disagreement, not a progress bar.
/// - **Rule 2: never collapse the positions into one "we agree" paragraph.**
///   Consensus is what a fixture fakes most easily, and `runSynthesis` throws on a
///   brief that buries dissent server-side. So this room genuinely disagrees: Finance
///   hard-blocks, Marketing pushes, Engineering owns the date — and it ends
///   `unresolved: true`, which rule 6 calls a valid outcome rather than an error.
enum MockVirtualCompany {

    /// Drop-in for `VirtualCompanyClient.run`.
    static func run(_ req: VirtualCompanyRequest)
        -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        AsyncThrowingStream { continuation in
            for frame in frames(ask: req.request) {
                // A frame that will not decode is dropped by `from(frame:)` and logged
                // by it. That is the same tolerance a live run has, and it means a
                // contract drift shows up as a missing card rather than a crash.
                if let event = VirtualCompanyEvent.from(frame: frame) {
                    continuation.yield(event)
                }
            }
            continuation.finish()
        }
    }

    /// Exposed so a test can assert every frame decodes — the whole value of building the
    /// fixture on the wire format rather than on Swift values.
    ///
    /// The frames themselves moved to `DemoProject`: they are a property of the demo COMPANY,
    /// not of this client, and Codepet's room could only ever argue about Codepet's paywall.
    static func frames(ask: String) -> [SSEFrame] { DemoProject.current.roomFrames(ask) }
}
#endif
