// codepet/Services/ChatThreadArchive.swift
import Foundation
import os

/// Where the company chat's thread list lives between launches.
///
/// Until 2026-09-25 it lived nowhere: `CompanyStore.threads` was in-memory only ("Level 1"), so
/// RECENT was empty after every relaunch while the CODE tab — `SessionChatStore`, a per-account
/// file — kept its history. This follows that store: a local JSON file per account, never
/// Firestore, because the company doc is capped at 1 MiB and already carries `teamRuns`.
protocol ChatThreadArchiving {
    func load(uid: String) -> [ChatThread]
    func save(_ threads: [ChatThread], uid: String)
}

/// Used under XCTest (see `CompanyStore.defaultThreadArchive`): 30-odd suites hydrate a store
/// as `"u"`, and a real archive would write their transcripts into the founder's home folder.
struct NullChatThreadArchive: ChatThreadArchiving {
    func load(uid: String) -> [ChatThread] { [] }
    func save(_ threads: [ChatThread], uid: String) {}
}

struct FileChatThreadArchive: ChatThreadArchiving {
    var root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codepet/accounts")

    private static let log = Logger(subsystem: "app.murror.codepet", category: "ChatThreadArchive")
    /// Serial, so two saves land in the order they were made.
    private static let io = DispatchQueue(label: "app.murror.codepet.ChatThreadArchive.io", qos: .utility)

    func fileURL(uid: String) -> URL {
        // A uid is Firebase's `[A-Za-z0-9]`; anything else is stripped so it cannot leave `root`.
        let safe = uid.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return root.appendingPathComponent(safe.isEmpty ? "unknown" : safe).appendingPathComponent("company_chats.json")
    }

    func load(uid: String) -> [ChatThread] {
        let url = fileURL(uid: uid)
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try Self.decoder.decode([StoredThread].self, from: data).map(\.thread)
        } catch {
            // Keep the unreadable file rather than let the next save overwrite it.
            Self.log.error("chat threads did not decode, kept aside: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))"))
            return []
        }
    }

    func save(_ threads: [ChatThread], uid: String) {
        let url = fileURL(uid: uid)
        guard let data = try? Self.encoder.encode(threads.map(StoredThread.init)) else { return }
        Self.io.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                Self.log.error("chat threads not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Blocks until every queued save has hit the disk — for tests.
    static func drain() { io.sync {} }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d }()
}

// MARK: - What is stored

struct StoredThread: Codable {
    let id: String
    let title: String?
    let createdAt: Date
    let updatedAt: Date
    let kind: ChatThreadKind
    let messages: [StoredMessage]

    init(_ t: ChatThread) {
        id = t.id; title = t.title; createdAt = t.createdAt; updatedAt = t.updatedAt; kind = t.kind
        messages = t.messages.compactMap(StoredMessage.init)
    }

    var thread: ChatThread {
        ChatThread(id: id, title: title, messages: messages.map(\.message), createdAt: createdAt,
                   updatedAt: updatedAt, kind: kind)
    }
}

/// The part of a `CopilotMessage` that still means something after a relaunch: what was said,
/// the draft and whether it was approved, how it was made, and what it built on.
///
/// Deliberately dropped: every offer and prompt that only works while its turn is live (chain
/// offer, run/roadmap proposal, grant button, interview question, first-run action, tour offer)
/// and the room's live state. A room is kept as its conclusion, in text — its seats and the
/// argument are not, since `VirtualCompanyRunState` is a stream accumulator, not a record.
struct StoredMessage: Codable {
    let id: String
    let fromFounder: Bool
    let createdAt: Date
    let text: String
    let draft: Deliverable?
    let draftApproved: Bool
    /// "Updated in your Library" rather than "Added" — a revision that replaced an item.
    /// Optional so a file written before this field still decodes.
    let draftReplacedItem: Bool?
    let companionId: String?
    let deptName: String?
    let execSteps: [ExecStep]?
    let upstream: [UpstreamWork]?
    let navChip: NavAction?
    let noted: [RememberedFact]?
    let founderAsk: String?
    let teamRunId: String?

    /// nil for a message with nothing left to show once its live parts are dropped (a producing
    /// row, a room that never concluded, an empty placeholder).
    init?(_ m: CopilotMessage) {
        guard !m.producing else { return nil }
        var text = m.text
        if let brief = m.vcRun?.brief, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = brief.recommendation
        }
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || m.draft != nil || m.navChip != nil || !(m.noted ?? []).isEmpty || m.teamRunId != nil
        guard hasContent else { return nil }
        id = m.id; fromFounder = m.role == .me; createdAt = m.createdAt; self.text = text
        draft = m.draft; draftApproved = m.draftApproved
        draftReplacedItem = m.draftReplacedItem ? true : nil
        companionId = m.companionId; deptName = m.deptName
        execSteps = m.execSteps; upstream = m.upstream
        navChip = m.navChip; noted = m.noted; founderAsk = m.founderAsk; teamRunId = m.teamRunId
    }

    var message: CopilotMessage {
        var m = CopilotMessage(id: id, role: fromFounder ? .me : .companion, createdAt: createdAt, text: text,
                               draft: draft, draftApproved: draftApproved, navChip: navChip, noted: noted,
                               companionId: companionId, deptName: deptName, execSteps: execSteps,
                               upstream: upstream, founderAsk: founderAsk, teamRunId: teamRunId)
        m.draftReplacedItem = draftReplacedItem ?? false
        return m
    }
}
