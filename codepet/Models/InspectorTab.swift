// codepet/Models/InspectorTab.swift
import Foundation

/// One thing you are inspecting — spec §5.
///
/// **One tab per OUTPUT, not per run.** That distinction is the whole model: a run
/// is a process and belongs in the work pane; a diff, a draft or a preview is a
/// thing you read, compare and keep open. Tabbing runs would make the panel a
/// history; tabbing outputs makes it a desk.
///
/// Tabs belong to the session, not the app — "a diff you were reading is not global
/// state" — which is why this is a value type held by the surface that owns the
/// session rather than a singleton.
struct InspectorTab: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A code change: the diff, and what it did.
        case review
        /// The files the run touched. Developer's file tree stops being a third
        /// column and becomes a tab (§5).
        case files
    }

    /// Every output has TWO views, and the link flips the same panel between them
    /// rather than opening a second one — Codex's shape, adopted deliberately.
    enum View: Equatable {
        /// What it produced: the rendered doc, or what the change did.
        case result
        /// What produced it: the markdown, or the diff.
        case source
    }

    let id: String
    let kind: Kind
    var title: String
    /// Which view this tab is currently showing.
    var view: View

    /// The view an output OPENS on: the one carrying the decision.
    ///
    /// Spec §5 — "the rendered doc for a deliverable, the diff for a code change".
    /// A code review that opened on a summary would be asking the founder to approve
    /// something they had not been shown.
    static func openingView(for kind: Kind) -> View {
        switch kind {
        case .review: return .source
        case .files:  return .result
        }
    }

    init(id: String, kind: Kind, title: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.view = Self.openingView(for: kind)
    }
}

/// The open tabs for one session.
///
/// Pure so the rules that matter can be asserted without a view: that a second run
/// REPLACES its review tab rather than stacking a new one (a run is not an output),
/// that finishing a run brings Review forward by itself (§5), and that closing the
/// last tab collapses the panel instead of leaving an empty frame.
struct InspectorTabs: Equatable {
    private(set) var tabs: [InspectorTab] = []
    private(set) var activeId: String?

    var isEmpty: Bool { tabs.isEmpty }
    var active: InspectorTab? { tabs.first { $0.id == activeId } }

    /// Opens an output, or brings it forward if it is already open.
    ///
    /// Idempotent on `id` on purpose: a run that re-enters `.reviewing` (a redo, a
    /// second approve pass) must not leave two Review tabs for one change.
    mutating func open(_ tab: InspectorTab, activate: Bool = true) {
        if let i = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[i].title = tab.title
        } else {
            tabs.append(tab)
        }
        if activate { activeId = tab.id }
    }

    mutating func close(_ id: String) {
        tabs.removeAll { $0.id == id }
        if activeId == id { activeId = tabs.last?.id }
    }

    mutating func activate(_ id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeId = id
    }

    /// Flip the active tab between what it produced and what produced it.
    mutating func flip() {
        guard let i = tabs.firstIndex(where: { $0.id == activeId }) else { return }
        tabs[i].view = tabs[i].view == .result ? .source : .result
    }
}
