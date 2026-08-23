// codepet/Models/AttachmentBudget.swift
import Foundation

/// **How much attachment one request may carry, and what to say when it can't.**
///
/// This exists because the constraint that actually bites is not the one
/// `ChatAttachment.maxBytes` describes. `maxBytes` is 8 MB **per file, before
/// base64**; `ChatAttachment.max` is 3 files. Three of them is ~24 MB raw, which is
/// **~32 MB once base64 inflates it by 4/3** — and `companyChat` runs on Cloud Run
/// gen2, whose HTTP request ceiling is 32 MiB. A request over that is rejected by the
/// infrastructure: the founder gets a bare 413, `handleCompanyChat` never runs, so
/// there is nothing in `functions:log`, and the backend's own drop table (which is
/// how every *other* bad attachment explains itself) never sees the request either.
/// A failure with no observable cause anywhere is worse than a smaller cap.
///
/// So the binding constraint here is **total base64 bytes across the whole request**,
/// which is what the transport actually measures, and it is set well under the
/// ceiling to leave room for the prompt, the context block, the history text and the
/// JSON framing that ride alongside.
///
/// **Why the history matters too.** `functions/`'s `ATTACHMENT_REPLAY_WINDOW = 6`
/// bounds how far back the backend will *replay* an attachment into the model's
/// messages — it does not bound the body the client sends. A client that put its
/// base64 on all 20 history turns would ship megabytes the backend then discards, and
/// two 19 MB turns in a row would 413 while each one on its own looked fine. So
/// `replay(_:alongside:)` mirrors that window on this side and trims to the same
/// total, making the request size a function of one number instead of two.
enum AttachmentBudget {

    /// Total base64 bytes one request may carry — the new attachments plus every
    /// replayed history attachment. ~20 MB against a 32 MiB transport ceiling: the
    /// headroom is the prompt, the grounding context, up to 20 turns of history text
    /// and the JSON framing, none of which is measured here.
    static let maxTotalBase64Bytes = 20 * 1024 * 1024

    /// Mirrors `ATTACHMENT_REPLAY_WINDOW` in `functions/src/companyChatCore.ts`.
    /// Sending base64 on an older turn is paid for on the wire and then dropped by
    /// the backend, so the two numbers must not drift.
    static let replayWindow = 6

    /// Base64 is ASCII, so the encoded string's byte count IS what goes on the wire.
    /// Measured on `data` rather than derived from `byteCount` because `byteCount` is
    /// the pre-encode size and the 4/3 inflation is exactly the factor that made the
    /// old cap wrong.
    static func base64Bytes(_ list: [ChatAttachment]) -> Int {
        list.reduce(0) { $0 + $1.data.utf8.count }
    }

    /// Why a file was turned away. Two reasons, because they need two sentences: one
    /// is fixed by removing a pill, the other by attaching something smaller.
    enum Reason: Equatable {
        case tooMany
        case overBudget
    }

    struct Admission: Equatable {
        var accepted: [ChatAttachment]
        /// Filenames, in the order the founder picked them, so the notice can name them.
        var refused: [String]
        /// The reason for the FIRST refusal — and in a mixed pick that is always the
        /// size one, as a consequence rather than as a rule.
        ///
        /// It was written as a rule (`|| refuse == .overBudget`, so a later `.overBudget`
        /// overwrote an earlier `.tooMany`) and that clause was **unreachable**: `count`
        /// only ever rises, so once one candidate is refused for count every later one is
        /// too, before the size branch is even evaluated. Deleting it changed no test
        /// result at all, which is the definition of a guard that guards nothing. Gone.
        var reason: Reason?
    }

    /// Decide which of `candidates` may join `current`.
    ///
    /// Both caps are applied here rather than in the composer, so the store can apply
    /// the identical rule at the wire and a caller that never went through the
    /// composer still cannot build a 413.
    /// `limit` is a parameter with the production default rather than a hard reference
    /// to the constant, so a test can pin the ARITHMETIC in bytes instead of allocating
    /// 20 MB of base64 to reach the edge. `AttachmentSendTests` still exercises the real
    /// constant once at the store boundary, because a rule only tested at a fake limit
    /// proves the maths and not the wiring.
    static func admit(_ candidates: [ChatAttachment],
                      to current: [ChatAttachment],
                      limit: Int = maxTotalBase64Bytes) -> Admission {
        var accepted: [ChatAttachment] = []
        var refused: [String] = []
        var reason: Reason?
        var total = base64Bytes(current)
        var count = current.count

        for c in candidates {
            let refuse: Reason?
            if count >= ChatAttachment.max {
                refuse = .tooMany
            } else if total + c.data.utf8.count > limit {
                refuse = .overBudget
            } else {
                refuse = nil
            }
            guard let refuse else {
                accepted.append(c)
                total += c.data.utf8.count
                count += 1
                continue
            }
            refused.append(c.filename)
            if reason == nil { reason = refuse }
        }
        return Admission(accepted: accepted, refused: refused, reason: reason)
    }

    /// Which history turns keep their attachments on the wire.
    ///
    /// `history` is one entry per history turn, oldest first, holding whatever that
    /// turn was sent with (empty for most). `outgoing` is this turn's attachments,
    /// which are charged against the same total and are never trimmed here — this
    /// message's own file is the one the founder is looking at, so a past screenshot
    /// is what gives way.
    ///
    /// Trimming stops at the first turn that does not fit and drops everything older
    /// with it, rather than skipping one and keeping the next: a hole in the middle of
    /// the replay window would make "the model can still see it" depend on file sizes
    /// several turns apart.
    static func replay(_ history: [[ChatAttachment]],
                       alongside outgoing: [ChatAttachment],
                       limit: Int = maxTotalBase64Bytes) -> [[ChatAttachment]] {
        var out = [[ChatAttachment]](repeating: [], count: history.count)
        var total = base64Bytes(outgoing)
        let floor = Swift.max(0, history.count - replayWindow)
        var i = history.count - 1
        while i >= floor {
            let bytes = base64Bytes(history[i])
            if bytes == 0 { i -= 1; continue }
            if total + bytes > limit { break }
            out[i] = history[i]
            total += bytes
            i -= 1
        }
        return out
    }

    /// What the composer says when a pick was turned away — nil when it wasn't.
    ///
    /// The megabyte figure is derived from `maxTotalBase64Bytes` rather than typed, so
    /// the copy cannot outlive a change to the cap.
    static func refusalMessage(_ admission: Admission, _ lang: AppLanguage) -> String? {
        guard let reason = admission.reason, !admission.refused.isEmpty else { return nil }
        let names = admission.refused.joined(separator: ", ")
        let mb = maxTotalBase64Bytes / (1024 * 1024)
        switch reason {
        case .overBudget:
            return lang == .vi
                ? "\(names) quá lớn — mỗi tin nhắn chở được \(mb) MB tệp đính kèm."
                : "\(names) is too big — one message can carry \(mb) MB of attachments."
        case .tooMany:
            return lang == .vi
                ? "\(names) không vừa — mỗi tin nhắn tối đa \(ChatAttachment.max) tệp."
                : "\(names) didn't fit — \(ChatAttachment.max) attachments per message."
        }
    }

    /// What the composer says about files the picker itself could not read — an
    /// extension we do not handle, or a file we failed to open. Separate from
    /// `refusalMessage` because the fix is different: nothing about this one is a cap.
    static func unsupportedMessage(_ names: [String], _ lang: AppLanguage) -> String? {
        guard !names.isEmpty else { return nil }
        let list = names.joined(separator: ", ")
        return lang == .vi
            ? "Codepet chưa đọc được \(list)."
            : "Codepet can't read \(list)."
    }
}
