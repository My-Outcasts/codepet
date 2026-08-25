// codepet/Models/ChatAttachment.swift
import CoreGraphics
import Foundation

/// What kind of thing the founder attached, which decides the content block it
/// becomes on the wire: `image` and `pdf` are base64 blocks, `text` is inlined as
/// text (no block type exists for a source file, and none is needed).
enum AttachmentKind: String, Equatable {
    case image, pdf, text
}

/// A file the founder attached to the next message — spec §7.
///
/// **Wired (22 Aug).** `CompanyChatRequest.attachments` and `ChatTurnDTO.attachments`
/// carry this to `companyChat`, which turns it into image/document content blocks
/// (`fe2e767`, `a75570c`) and replays it across the last `ATTACHMENT_REPLAY_WINDOW`
/// history entries. The wire shape is `AttachmentDTO`, not this type — see there for
/// why, and for the `media_type` spelling that silently decides whether any of it
/// happens.
///
/// **Why base64 lives in this type.** The client has no Anthropic key (deployed
/// functions read it from Secret Manager), so the Files API is unreachable from
/// Swift and every byte has to ride the request it belongs to. That makes the
/// encoded payload part of the attachment's identity rather than something fetched
/// later, and it makes the downscale cap below a product decision rather than an
/// implementation detail.
struct ChatAttachment: Identifiable, Equatable {
    let id: String
    let kind: AttachmentKind
    let filename: String
    /// The IANA type the API validates against — see `mediaType(for:pathExtension:)`.
    let mediaType: String
    /// Base64, no newlines. The API rejects wrapped base64.
    let data: String
    /// Size BEFORE encoding — for the cap, and for what the pill shows.
    let byteCount: Int

    /// Matches `ContextPin.max`: both are "things riding the next message", and two
    /// different ceilings for one pill row would be arbitrary.
    static let max = 3

    /// Per file, before base64 — a sanity limit, and **no longer the binding one.**
    ///
    /// Its old comment read "the API's request ceiling is 32MB and base64 adds ~33%, so
    /// three 8MB files still fit with room for the prompt", and the arithmetic in that
    /// sentence disproves it: 3 × 8 MB raw is 24 MB, which base64 inflates to ~32 MB —
    /// ON the Cloud Run gen2 ceiling, not under it, with nothing left for the prompt.
    /// Over the line the founder gets a bare 413 that never reaches the function, so
    /// there is no log line and no drop-table entry to explain it.
    ///
    /// The real ceiling is total ENCODED bytes across the whole request, because that is
    /// what the transport measures — `AttachmentBudget.maxTotalBase64Bytes`. This stays
    /// as a per-file guard so one absurd file is refused before it is even encoded.
    static let maxBytes = 8 * 1024 * 1024

    /// **Sonnet 5's high-resolution long edge.** `CHAT_MODEL` in
    /// `functions/src/companyChat.ts` is `claude-sonnet-5`, the first Sonnet in the
    /// high-res tier, which reads up to 2576px on the long edge at ~4784 image
    /// tokens. Sending more pixels than this pays for detail the model discards;
    /// sending fewer throws away fidelity the founder attached the file to show us.
    static let imageLongEdge: CGFloat = 2576

    /// Fit `original` inside `longEdge`, preserving aspect ratio, **never upscaling**.
    ///
    /// Upscaling a 400px screenshot to 2576 buys no detail and multiplies its token
    /// cost by ~40×, so a small image is returned untouched. A zero or negative size
    /// returns `.zero` rather than a NaN that would reach the encoder.
    static func fittedSize(for original: CGSize, longEdge: CGFloat) -> CGSize {
        let w = original.width, h = original.height
        guard w > 0, h > 0, longEdge > 0 else { return .zero }
        let longest = Swift.max(w, h)
        guard longest > longEdge else { return original }   // never upscale
        let scale = longEdge / longest
        return CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
    }

    /// **The media type of an image AFTER it has been downscaled**, which is not always
    /// the media type of the file the founder picked.
    ///
    /// `AttachmentPicker.downscaledImageData` re-encodes everything that is not a JPEG
    /// as PNG (re-encoding a photo as PNG can multiply its size, so JPEG sources stay
    /// JPEG). A resized `.webp` or `.gif` is therefore PNG bytes — and declaring those
    /// as `image/webp` sends the API a header that contradicts the payload. Both are in
    /// the four types the backend accepts, so nothing is dropped client-side or
    /// server-side; the mismatch surfaces at the API as a failed turn with no local
    /// trace, which is the same silent class as the `media_type` spelling.
    ///
    /// Only called when a downscale actually happened. An untouched file keeps
    /// `mediaType(for:pathExtension:)`.
    static func downscaledMediaType(pathExtension ext: String) -> String {
        ["jpg", "jpeg"].contains(ext.lowercased()) ? "image/jpeg" : "image/png"
    }

    /// nil for an extension we don't handle — deliberately, rather than defaulting
    /// to `.text`. Base64-ing a `.sketch` as text would send the founder's binary
    /// into the prompt as mojibake and bill her for it.
    static func kind(forPathExtension ext: String) -> AttachmentKind? {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp":
            return .image
        case "pdf":
            return .pdf
        case "md", "markdown", "txt", "csv", "json", "yml", "yaml",
             "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "sh":
            return .text
        default:
            return nil
        }
    }

    /// Every extension the picker offers. Derived from `kind(forPathExtension:)`
    /// rather than listed twice — a picker that accepts a type the encoder rejects
    /// is a file chosen and then silently dropped.
    static let allowedExtensions: [String] = [
        "png", "jpg", "jpeg", "gif", "webp",
        "pdf",
        "md", "markdown", "txt", "csv", "json", "yml", "yaml",
        "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "sh",
    ]

    /// The IANA media type. This is what the API validates, and a mismatch is a 400
    /// the founder experiences as "attachment failed" with nothing explaining why —
    /// so `.jpg` must map to `image/jpeg`, not `image/jpg`.
    static func mediaType(for kind: AttachmentKind, pathExtension ext: String) -> String {
        switch kind {
        case .pdf:
            return "application/pdf"
        case .text:
            return "text/plain"
        case .image:
            switch ext.lowercased() {
            case "jpg", "jpeg": return "image/jpeg"
            case "gif":         return "image/gif"
            case "webp":        return "image/webp"
            default:            return "image/png"
            }
        }
    }

    var icon: String {
        switch kind {
        case .image: return "photo"
        case .pdf:   return "doc.richtext"
        case .text:  return "doc.plaintext"
        }
    }

    /// The pill's gloss — the kind, not the byte count. A founder who just chose the
    /// file knows what it is; what she can't see is whether we took it.
    var gloss: String {
        switch kind {
        case .image: return "IMG"
        case .pdf:   return "PDF"
        case .text:  return "TXT"
        }
    }

    static func adding(_ a: ChatAttachment, to list: [ChatAttachment]) -> [ChatAttachment] {
        guard !list.contains(where: { $0.id == a.id }) else { return list }
        guard list.count < max else { return list }
        return list + [a]
    }

    static func removing(_ a: ChatAttachment, from list: [ChatAttachment]) -> [ChatAttachment] {
        list.filter { $0.id != a.id }
    }
}
