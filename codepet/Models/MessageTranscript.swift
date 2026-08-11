// codepet/Models/MessageTranscript.swift
import Foundation

/// Serializes one chat message for the clipboard.
///
/// Copy used to send `message.text` straight to the pasteboard. That is correct only for
/// a plain-text reply: a draft-card, exec-log, room or proposal reply carries its content
/// in a payload and frequently has a blank `text` — `textBubble` renders `EmptyView()` for
/// exactly that case. Once the action row appears on those branches, copying `text` would
/// return "". So this reads the payloads in the same precedence order `CopilotBubble.content`
/// renders them, and text (when present) always leads, because that is what is on screen.
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

        if let proposal = m.runProposal { out.append(proposal.line(lang)) }
        if let proposal = m.roadmapProposal { out.append(proposal.line(lang)) }
        if let gap = m.interview {
            out.append(EnrichInterview.question(for: gap, language: lang).ask)
        }

        return out
    }
}
