// codepet/Models/MessageTranscript.swift
import Foundation

/// Serializes one chat message for the clipboard.
///
/// Copy used to send `message.text` straight to the pasteboard. That is correct only for
/// a plain-text reply: a draft-card, exec-log, room, drafted-message or proposal reply
/// carries its content in a payload and frequently has a blank `text` — `textBubble` renders
/// `EmptyView()` for exactly that case. Once the action row appears on those branches, copying
/// `text` would return "". So this reads the payloads in the same precedence order
/// `CopilotBubble.body` renders them, and text (when present) always leads, because that is
/// what is on screen.
///
/// `runProposal`, `roadmapProposal` and `interview` are the exception: their payload sentence
/// (`.line(lang)`, or the interview question) is a FALLBACK, emitted only when `text` is
/// blank. At every real construction site (`CompanyStore.proposeRun`, `handleRoadmapProposal`,
/// `askInterviewGap`) that sentence already IS `m.text` — appending it again would put the
/// same sentence on the clipboard twice. The fallback is a defensive guard and does not imply
/// a real path — no production call site currently produces that shape.
///
/// `drafts` — the messages the companion wrote — are serialized in full: heading (when
/// non-empty) then body, right after the prose, matching where `inlineActions` draws
/// `draftedMessages` on screen. `draft` and `vcRun` are unaffected by the fallback rule: they
/// are always constructed with blank or genuinely additional prose, so their content is
/// separate from `text` and always appended.
///
/// Pure by design: no SwiftUI, no Firebase, no `CompanyStore`. It is the half of the action
/// row that can be tested without the XCTest host that crashes on `@MainActor` deallocation.
enum MessageTranscript {

    /// Plain text for the Copy button.
    static func plain(_ m: CopilotMessage, lang: AppLanguage) -> String {
        blocks(m, lang: lang, markdown: false).joined(separator: "\n\n")
    }

    /// Markdown for the Copy as Markdown button, headed by who said it.
    static func markdown(_ m: CopilotMessage, speaker: String, lang: AppLanguage) -> String {
        (["**\(speaker)**"] + blocks(m, lang: lang, markdown: true))
            .joined(separator: "\n\n")
    }

    // MARK: - Blocks

    private static func blocks(_ m: CopilotMessage, lang: AppLanguage,
                               markdown: Bool) -> [String] {
        var out: [String] = []

        let text = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { out.append(text) }

        for drafted in m.drafts {
            let heading = drafted.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            if !heading.isEmpty { out.append(markdown ? "### \(heading)" : heading) }
            let body = drafted.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { out.append(body) }
            // An email's heading is its subject, so the recipient has no other carrier and
            // rides as its own line — AFTER the body, because that is where the view puts it
            // (`MessageDraftViewer` draws heading + body, then the "To:" line below the card,
            // CopilotChatView:749-758). Emitted before the body it pastes as a header stranded
            // inside the message.
            if drafted.channel == "email",
               let to = drafted.to?.trimmingCharacters(in: .whitespacesAndNewlines),
               !to.isEmpty {
                out.append((lang == .vi ? "Gửi tới: " : "To: ") + to)
            }
        }

        if let draft = m.draft {
            out.append(markdown ? "## \(draft.title)" : draft.title)
            let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { out.append(body) }
        }

        if let run = m.vcRun {
            if let recommendation = run.brief?.recommendation
                .trimmingCharacters(in: .whitespacesAndNewlines), !recommendation.isEmpty {
                out.append(recommendation)
            }
            if markdown {
                for agent in run.agents {
                    guard let dept = agent.departmentKey,
                          let position = run.positions[agent.agentId]?.position
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                          !position.isEmpty else { continue }
                    out.append("**\(dept)** — \(position)")
                }
            }
        }

        if let steps = m.execSteps, !steps.isEmpty {
            out.append(steps.map { step in
                if markdown { return "- [\(step.done ? "x" : " ")] \(step.label)" }
                return "\(step.done ? "✓" : "•") \(step.label)"
            }.joined(separator: "\n"))
        }

        // Fallback only: at every real construction site this sentence already IS `m.text`
        // (`CompanyStore.proposeRun`, `handleRoadmapProposal`, `askInterviewGap`), so emitting
        // it here too would duplicate what's already on screen. This only fires for a message
        // the store built with no reply to carry the sentence.
        if text.isEmpty, let proposal = m.runProposal { out.append(proposal.line(lang)) }
        if text.isEmpty, let proposal = m.roadmapProposal { out.append(proposal.line(lang)) }
        if text.isEmpty, let gap = m.interview {
            out.append(EnrichInterview.question(for: gap, language: lang).ask)
        }

        return out
    }
}
