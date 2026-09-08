// codepet/Views/Library/DeliverableExporter.swift
import AppKit
import Foundation
import UniformTypeIdentifiers

/// Saves a deliverable's files to disk.
///
/// Lives beside the viewers because it is the same kind of thing `AttachmentPicker` is: the
/// one place an AppKit panel is allowed to exist, so no view has to know about AppKit. All
/// the rendering happens in `DeliverableExport`, which is pure and fully tested; this file
/// is the panel plus the write.
///
/// **The app writes and never uploads.** There is no network call here and there must not be
/// one: export is the founder moving their own work to their own disk.
enum DeliverableExporter {

    /// Write files into a directory the founder chose, returning where each landed.
    ///
    /// Split out from `save(_:)` so it is testable — the panel is the only part a test
    /// cannot drive, which is the limit `AttachmentPicker` already records for its own.
    ///
    /// Never overwrites: a repeat becomes `plan-2.md`. This is the rule for a SET, which the
    /// founder picks as a directory with no per-file prompt — the only place the panel cannot
    /// ask. A single file goes through `NSSavePanel`, which asks Replace/Cancel itself, and
    /// that is left alone deliberately (founder decision, 8 Sep): a founder who types a name
    /// should get that name or an explicit prompt, not a silently different file.
    /// A name is reduced to its last path component first, so nothing can be written
    /// outside the chosen directory.
    ///
    /// A throw here can happen after some files have already landed — `PartialWrite` carries
    /// how many, so a caller can tell a partial export from a clean failure instead of
    /// reporting a partial run as a plain success.
    ///
    /// `.` and `..` are rejected explicitly, falling back to the same default name used for
    /// an empty name, rather than trusted to `lastPathComponent` — `lastPathComponent` of
    /// `".."` IS `".."`, and `directory.appendingPathComponent("..")` resolves to the PARENT
    /// of the chosen directory. Today the collision loop in `unusedURL` happens to rename that
    /// away before anything is written, but that is safety by accident, not by design — and
    /// **the app is not sandboxed** (`codepet/codepet.entitlements` has `app-sandbox` = false),
    /// so there is no second line of defence if the loop's behaviour ever changes.
    static func write(_ files: [ExportFile], to directory: URL) throws -> [URL] {
        var out: [URL] = []
        for f in files {
            let raw = (f.name as NSString).lastPathComponent
            let safe = (raw.isEmpty || raw == "." || raw == "..") ? "deliverable" : raw
            let url = try unusedURL(in: directory, name: safe)
            do {
                try f.data.write(to: url, options: .atomic)
            } catch {
                throw PartialWrite(landed: out.count, underlying: error)
            }
            out.append(url)
        }
        return out
    }

    /// Thrown by `write(_:to:)` when the directory rejects a write partway through a set —
    /// a read-only volume, a full disk (the app is not sandboxed, so there is no sandbox
    /// denial to blame). `landed` is how many files were already written before the one that
    /// failed, so `save(_:)` never reports a partial export as a clean success.
    struct PartialWrite: Error {
        let landed: Int
        let underlying: Error
    }

    /// What `save(_:)` did, so the founder is told the difference between "you cancelled"
    /// (say nothing) and "the write failed" (say so) rather than both reading as silence.
    enum Outcome: Equatable {
        case saved
        case cancelled
        /// A write failed. `landed` is how many files made it to disk first — 0 for the
        /// single-file path, where nothing is ever partial.
        case failed(landed: Int)
    }

    private static func unusedURL(in directory: URL, name: String) throws -> URL {
        let fm = FileManager.default
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(name)
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            n += 1
            let next = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            candidate = directory.appendingPathComponent(next)
        }
        return candidate
    }

    /// Ask the founder where to put it, then write — and say what happened.
    ///
    /// One file gets a save panel with the name pre-filled; several get a directory picker,
    /// because `dms` and `calendar` produce a set and asking once per file would be four
    /// panels for one press.
    ///
    /// Cancelling the panel is `.cancelled`, not `.failed` — the founder changed their mind,
    /// which is not an error and must not be shown as one. Only an actual write failure (a
    /// read-only volume, a full disk — the app is not sandboxed, so there is no sandbox
    /// denial to blame) is `.failed`. Before this the write used `try?` and discarded the
    /// result either way, so a press that failed for real looked exactly like one that
    /// succeeded — the same silent-success shape this app has already paid for once
    /// (`SiteViewer.openFailed`).
    @MainActor
    @discardableResult
    static func save(_ d: Deliverable) -> Outcome {
        let files = DeliverableExport.files(for: d)
        guard !files.isEmpty else { return .cancelled }

        if files.count == 1 {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = files[0].name
            panel.prompt = "Export"
            panel.message = "Save \(d.title)"
            // Preserve (or re-append) the real extension even if the founder edits the name
            // field and drops it — otherwise a `.csv` saved without its suffix opens in
            // nothing. Left unrestricted if the extension does not map to a known type,
            // rather than guessing one.
            let ext = (files[0].name as NSString).pathExtension
            if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
                panel.allowedContentTypes = [type]
            }
            guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
            do {
                try files[0].data.write(to: url, options: .atomic)
                return .saved
            } catch {
                return .failed(landed: 0)
            }
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Save \(files.count) files from \(d.title)"
        guard panel.runModal() == .OK, let dir = panel.url else { return .cancelled }
        do {
            _ = try write(files, to: dir)
            return .saved
        } catch let partial as PartialWrite {
            return .failed(landed: partial.landed)
        } catch {
            return .failed(landed: 0)
        }
    }
}
