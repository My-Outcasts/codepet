// codepet/Models/RoomRecord.swift
import Foundation

/// The side panel a landed room opens into (CP-032), and the chips that open it.
///
/// A landed room kept four disclosure bars in the chat — "What each department said", "Who was
/// in the room, and why", "How they negotiated", "What could make this wrong" — and each one
/// opened several screens of text inline, under the answer. The chat now keeps the answer and a
/// row of department chips; everything else is in the panel, in three tabs.
enum RoomRecordTab: String, CaseIterable, Identifiable {
    case stances, disagreements, record
    var id: String { rawValue }

    func title(_ state: VirtualCompanyRunState, lang: AppLanguage) -> String {
        let vi = lang == .vi
        switch self {
        case .stances:
            return (vi ? "Lập trường" : "Stances") + " · \(state.agents.count)"
        case .disagreements:
            return vi ? "Bất đồng" : "Disagreements"
        case .record:
            let n = state.negotiationRounds.count
            let base = vi ? "Toàn bộ biên bản" : "Full record"
            guard n > 0 else { return base }
            return base + (vi ? " · \(n) vòng" : " · \(n) round\(n == 1 ? "" : "s")")
        }
    }
}

enum RoomRecord {
    enum Outcome: Equatable { case agreed, withConditions, against, noAnswer }

    struct Chip: Equatable {
        let agentId: String
        let meta: VCAgentMeta
        let outcome: Outcome
    }

    /// One chip per department in the room, in the order they joined, with how it came out.
    static func chips(_ state: VirtualCompanyRunState) -> [Chip] {
        state.agents.map { meta in
            let outcome: Outcome
            switch state.positions[meta.agentId]?.stance {
            case "proceed": outcome = .agreed
            case "proceed_with_conditions": outcome = .withConditions
            case "do_not_proceed": outcome = .against
            default: outcome = .noAnswer
            }
            return Chip(agentId: meta.agentId, meta: meta, outcome: outcome)
        }
    }

    static func linkTitle(_ lang: AppLanguage) -> String {
        lang == .vi ? "Cả đội đã quyết định thế nào ›" : "How the team decided ›"
    }
}

/// Which room's record is open, and on which tab. The id is the room message's.
struct RoomRecordSelection: Identifiable, Equatable {
    let id: String
    var tab: RoomRecordTab
}
