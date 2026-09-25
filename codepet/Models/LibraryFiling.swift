// codepet/Models/LibraryFiling.swift
import Foundation

/// How an approved deliverable enters the Library.
///
/// A first pass is appended. A REVISION — a draft whose `supersedes` names a Library item — replaces
/// that item in place, same `id`, and the version it replaced moves into the item's `versions`.
/// Before this, every Approve appended, so revising one landing page ten times filed ten items
/// (CP-025, found 24 Sep on prod build 3).
///
/// Pure on purpose: `CompanyStore.fileApproval` is the only caller, and the rule is pinned by
/// `LibraryFilingTests` without a store.
enum LibraryFiling {
    /// Earlier versions kept per item. The oldest is dropped past this.
    static let historyCap = 20

    static func file(_ draft: Deliverable, into library: [Deliverable]) -> [Deliverable] {
        guard let target = draft.supersedes else { return library + [draft] }
        guard let i = library.firstIndex(where: { $0.id == target }) else {
            // The item was deleted while the revision was being made. Never drop an approval:
            // file it as a new item, without a link that would point at nothing forever.
            var orphan = draft
            orphan.supersedes = nil
            return library + [orphan]
        }
        var out = library
        out[i] = replacing(out[i], with: draft.title, draft.body, draft.createdAt,
                           draft.kind, draft.payload)
        return out
    }

    /// Make an earlier version current again. The version it replaces is kept, so a restore can be
    /// undone the same way. An index or id that does not exist changes nothing.
    static func restore(versionAt index: Int, of id: String, in library: [Deliverable],
                        now: String) -> [Deliverable] {
        guard let i = library.firstIndex(where: { $0.id == id }),
              let history = library[i].versions, history.indices.contains(index) else { return library }
        let v = history[index]
        var rest = history
        rest.remove(at: index)
        var out = library
        var item = out[i]
        item.versions = rest
        out[i] = replacing(item, with: v.title, v.body, now, v.kind ?? item.kind, v.payload)
        return out
    }

    private static func replacing(_ item: Deliverable, with title: String, _ body: String,
                                  _ createdAt: String?, _ kind: DeliverableKind,
                                  _ payload: DeliverablePayload?) -> Deliverable {
        var next = item
        let old = DeliverableVersion(title: item.title, body: item.body, createdAt: item.createdAt,
                                     kind: item.kind, payload: item.payload)
        next.versions = Array(([old] + (item.versions ?? [])).prefix(historyCap))
        next.title = title
        next.body = body
        next.createdAt = createdAt
        next.kind = kind
        next.payload = payload
        next.supersedes = nil
        return next
    }
}
