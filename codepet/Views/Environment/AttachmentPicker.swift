// codepet/Views/Environment/AttachmentPicker.swift
import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Turns a file the founder chose into a `ChatAttachment` — spec §7.2.
///
/// Lives beside `ProjectLinker` because it is the same kind of thing: the one place
/// an `NSOpenPanel` is allowed to exist, so no view has to know about AppKit.
///
/// **Everything here is client-side.** No network, no Anthropic call, no Firebase.
/// The downscale is where the cost of an attachment is actually decided, and it
/// happens on this side of the wire — which is why tuning it never needs a deploy.
enum AttachmentPicker {

    /// Open the panel and encode whatever the founder picked, dropping anything we
    /// cannot honour rather than half-accepting it.
    ///
    /// Returns only the files that survived: an unsupported extension, an unreadable
    /// file, or one over `ChatAttachment.maxBytes` is skipped. `rejected` names them
    /// so the caller can say so instead of the founder wondering where her file went.
    static func pickAndEncode(limit: Int) -> (attachments: [ChatAttachment], rejected: [String]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = limit > 1
        panel.allowedContentTypes = ChatAttachment.allowedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.prompt = "Attach"
        panel.message = "Screenshots, PDFs, and text files. Images are resized before sending."

        guard panel.runModal() == .OK else { return ([], []) }

        var out: [ChatAttachment] = []
        var rejected: [String] = []
        for url in panel.urls.prefix(limit) {
            if let a = encode(url) { out.append(a) } else { rejected.append(url.lastPathComponent) }
        }
        return (out, rejected)
    }

    /// Encode one file. `nil` for anything we cannot honour — see `pickAndEncode`.
    ///
    /// Exposed rather than private so a future test can drive it from a fixture URL
    /// without an `NSOpenPanel`, which is the only part of this file a test can't run.
    static func encode(_ url: URL) -> ChatAttachment? {
        let ext = url.pathExtension
        guard let kind = ChatAttachment.kind(forPathExtension: ext) else { return nil }
        guard let raw = try? Data(contentsOf: url) else { return nil }

        // The cap is on the ORIGINAL bytes for text and pdf. An image is measured
        // after downscaling, because downscaling is exactly what makes an oversized
        // screenshot acceptable — rejecting it before we shrink it would refuse the
        // most common attachment there is.
        let payload: Data
        // **The declared media type has to describe the bytes we END UP with.**
        // `downscaledImageData` re-encodes every non-JPEG source as PNG, so a resized
        // .webp or .gif is PNG bytes — and it was being declared `image/webp` /
        // `image/gif`, a header that contradicts its own payload. Both are legal values,
        // so nothing drops it here or in `functions/`; it fails at the API, on a turn
        // that looks ordinary from every log we own.
        var mediaType = ChatAttachment.mediaType(for: kind, pathExtension: ext)
        switch kind {
        case .image:
            if let smaller = downscaledImageData(raw, pathExtension: ext) {
                payload = smaller
                mediaType = ChatAttachment.downscaledMediaType(pathExtension: ext)
            } else {
                payload = raw   // already small enough, or undecodable — original bytes, original type
            }
        case .pdf, .text:
            payload = raw
        }
        guard payload.count <= ChatAttachment.maxBytes else { return nil }

        return ChatAttachment(
            // Path plus size: the same file re-picked is the same attachment (so the
            // de-dupe in `adding` catches it), but an edited file is a new one.
            id: "\(url.path)#\(payload.count)",
            kind: kind,
            filename: url.lastPathComponent,
            mediaType: mediaType,
            // `.base64EncodedString()` with no options emits ONE line. Do not pass
            // `.lineLength64Characters` — the API rejects wrapped base64.
            data: payload.base64EncodedString(),
            byteCount: payload.count)
    }

    /// Redraw an image so its long edge is at most `ChatAttachment.imageLongEdge`.
    ///
    /// Returns nil when the image is already small enough or cannot be decoded, in
    /// which case the caller sends the original bytes — a slightly-too-large image
    /// is a cost question, and a dropped attachment is a bug.
    ///
    /// PNG for everything except JPEG sources: re-encoding a photo as PNG can make
    /// it several times larger, which is the opposite of the point.
    private static func downscaledImageData(_ raw: Data, pathExtension ext: String) -> Data? {
        guard let src = NSBitmapImageRep(data: raw) else { return nil }
        let original = CGSize(width: src.pixelsWide, height: src.pixelsHigh)
        let fitted = ChatAttachment.fittedSize(for: original,
                                              longEdge: ChatAttachment.imageLongEdge)
        guard fitted != .zero, fitted != original else { return nil }

        let w = Int(fitted.width), h = Int(fitted.height)
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = src.cgImage else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }

        let rep = NSBitmapImageRep(cgImage: out)
        rep.size = fitted
        let isJPEG = ["jpg", "jpeg"].contains(ext.lowercased())
        return rep.representation(
            using: isJPEG ? .jpeg : .png,
            properties: isJPEG ? [.compressionFactor: 0.82] : [:])
    }
}
