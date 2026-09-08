// codepet/Views/Copilot/MessageAttachments.swift
import AppKit
import SwiftUI

/// What the founder's own bubble draws when she attached something to that turn.
///
/// **This exists because `CopilotMessage.attachments` had no reader.** The field was
/// written by `CompanyStore.sendMessage` and read back by the same method to rebuild
/// `history[].attachments`, so the model's memory of an image worked — while the founder's
/// transcript showed her a bare sentence and no sign of the three screenshots she had just
/// sent (reported 8 Sep, with a recording). The round trip was correct on the wire and
/// invisible on screen.
///
/// Lives in its own file rather than in `CopilotChatView.swift`, which is already 2,700
/// lines: a strip, a cache and a chip are one job, and the bubble only needs to ask for it.

/// Which attachments can be previewed and which can only be named.
///
/// Pure and separated from the view because it is the part with a rule in it. An image has
/// pixels to show; a PDF or a `.swift` file has nothing to preview and stays a chip — the
/// same division `renderTurn` makes on the backend, for the same reason.
enum MessageAttachmentLayout {

    struct Split: Equatable {
        /// Images, in the order she picked them. The strip must not reshuffle her order.
        let previews: [ChatAttachment]
        /// Everything else — named, not shown.
        let chips: [ChatAttachment]

        /// Whether there is anything at all to draw. Gates the whole strip, so it counts
        /// chips too: a turn carrying only a PDF still has something to show her.
        var isEmpty: Bool { previews.isEmpty && chips.isEmpty }
    }

    static func split(_ attachments: [ChatAttachment]) -> Split {
        Split(previews: attachments.filter { $0.kind == .image },
              chips: attachments.filter { $0.kind != .image })
    }
}

/// Decoded thumbnails, one decode per attachment for the life of the view.
///
/// **The decode is the expensive part and `body` is the hot path.** `ChatAttachment.data` is
/// base64 of an image up to `imageLongEdge` (2576px) — decoding that on every SwiftUI body
/// evaluation is the same per-frame cost class as the dock divider that repainted on every
/// drag frame. So the bytes are decoded once, **resampled down to thumbnail size**, and the
/// full-resolution rep is dropped: holding three 2576px reps per message would be ~60MB of
/// live pixels for a bubble showing three 72pt squares.
///
/// Keyed on `ChatAttachment.id` — `path#byteCount` — so a file edited and re-picked is a
/// different key and gets re-decoded. Keying on `filename` would serve the stale pixels.
@MainActor
final class AttachmentThumbnailCache {

    /// Generous enough for a 72pt square on a 2x display with room to grow, small enough
    /// that a full transcript of them is cheap.
    static let thumbnailLongEdge: CGFloat = 200

    private var decoded: [String: NSImage] = [:]
    /// Attachments already tried and refused, so undecodable bytes are not re-attempted on
    /// every body evaluation — the failing path has to be memoized too, or it is the very
    /// per-frame cost this cache exists to remove.
    private var failed: Set<String> = []

    /// The thumbnail, or nil when there is nothing an image decoder will accept — in which
    /// case the strip falls back to a chip, which still tells her the file was sent.
    func image(for attachment: ChatAttachment) -> NSImage? {
        if let hit = decoded[attachment.id] { return hit }
        if failed.contains(attachment.id) { return nil }
        guard let made = Self.decode(attachment) else {
            failed.insert(attachment.id)
            return nil
        }
        decoded[attachment.id] = made
        return made
    }

    private static func decode(_ a: ChatAttachment) -> NSImage? {
        guard a.kind == .image,
              let raw = Data(base64Encoded: a.data),
              let rep = NSBitmapImageRep(data: raw),
              rep.pixelsWide > 0, rep.pixelsHigh > 0,
              let cg = rep.cgImage else { return nil }

        // Reuses the picker's own fitter, so "never upscale" holds here too: a 40px favicon
        // stays 40px rather than being blown up to 200 and looking broken.
        let fitted = ChatAttachment.fittedSize(
            for: CGSize(width: rep.pixelsWide, height: rep.pixelsHigh),
            longEdge: thumbnailLongEdge)
        let w = Int(fitted.width), h = Int(fitted.height)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: fitted)
    }
}

/// The row of thumbnails and chips above the founder's words.
///
/// Right-aligned and sitting ABOVE the text, which is the order the model receives the turn
/// in — `renderTurn` puts media blocks before the question, because the question is about
/// the picture. The transcript reading the same way is not a coincidence worth breaking.
struct MessageAttachmentStrip: View {
    let attachments: [ChatAttachment]

    /// Per-bubble, which is the right scope: these attachments belong to this one message,
    /// and the cache dies with the row. Held in `@State` so it survives re-evaluation
    /// rather than being rebuilt (and re-decoding everything) on every pass.
    @State private var cache = AttachmentThumbnailCache()

    /// Tall enough to recognise a screenshot, short enough that three fit the 380pt dock.
    private let thumbHeight: CGFloat = 72

    var body: some View {
        let split = MessageAttachmentLayout.split(attachments)
        if !split.isEmpty {
            HStack(alignment: .bottom, spacing: 6) {
                Spacer(minLength: 24)
                ForEach(split.previews) { att in
                    if let image = cache.image(for: att) {
                        thumbnail(image, name: att.filename)
                    } else {
                        // Decoded to nothing — name it rather than showing a torn box.
                        chip(att)
                    }
                }
                ForEach(split.chips) { att in chip(att) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func thumbnail(_ image: NSImage, name: String) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(height: thumbHeight)
            // A wide screenshot would otherwise push the whole row off the left edge.
            .frame(maxWidth: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CodepetTokens.cardEdge))
            .help(name)
    }

    /// The composer's pill vocabulary, minus the remove button — a sent attachment is a
    /// record, not something she can still take back.
    private func chip(_ att: ChatAttachment) -> some View {
        HStack(spacing: 4) {
            Image(systemName: att.icon).font(.system(size: 9))
            Text(att.filename)
                .font(CodepetTheme.inter(CodepetType.subheadline, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            Text(att.gloss)
                .font(CodepetTheme.inter(9, weight: .medium))
                .foregroundColor(CodepetTokens.faint)
        }
        .foregroundColor(CodepetTheme.mutedText)
        .padding(.horizontal, 8).frame(height: 22)
        .background(Capsule().fill(CodepetTokens.well))
        .overlay(Capsule().stroke(CodepetTokens.cardEdge))
        .frame(maxWidth: 210)
        .help(att.filename)
    }
}
