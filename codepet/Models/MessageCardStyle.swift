// codepet/Models/MessageCardStyle.swift
import SwiftUI

/// The six interactive message-card kinds and their single semantic hue.
/// Pure + testable. `producing` and plain-text messages are NOT cards (nil).
enum MessageCardKind { case draft, interview, setupSuggestion, firstRunAction, noted, navChip }

enum MessageCardStyle {
    /// Which card kind a message is, from its payload. nil for a producing
    /// placeholder or a plain-text message. Precedence (for the pathological
    /// multi-payload case, and to pin test behaviour):
    /// draft > interview > setupSuggestion > firstRunAction > noted > navChip.
    static func kind(for m: CopilotMessage) -> MessageCardKind? {
        if m.producing { return nil }
        if m.draft != nil { return .draft }
        if m.interview != nil { return .interview }
        if m.setupSuggestion != nil { return .setupSuggestion }
        if m.firstRunAction != nil { return .firstRunAction }
        if let noted = m.noted, !noted.isEmpty { return .noted }
        if m.navChip != nil { return .navChip }
        return nil
    }

    /// The single hue that carries the card's meaning. Gold = a decision is owed.
    static func hue(for kind: MessageCardKind, companionAccent: Color) -> Color {
        switch kind {
        case .draft:           return CodepetTheme.accentGold
        case .interview:       return CodepetTheme.accentBlue
        case .setupSuggestion: return CodepetTheme.accentTeal
        case .firstRunAction:  return companionAccent
        case .noted:           return CodepetTheme.mutedText
        case .navChip:         return CodepetTheme.hairline
        }
    }
}
