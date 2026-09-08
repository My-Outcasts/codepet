// codepet/Views/Library/DeliverableExporter.swift
import AppKit
import Foundation

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
    /// Never overwrites. A repeat export becomes `plan-2.md`, because the founder pressing
    /// Export twice is asking for a second copy, not asking to destroy the first.
    /// A name is reduced to its last path component first, so nothing can be written
    /// outside the chosen directory.
    static func write(_ files: [ExportFile], to directory: URL) throws -> [URL] {
        var out: [URL] = []
        for f in files {
            let safe = (f.name as NSString).lastPathComponent
            let url = try unusedURL(in: directory, name: safe.isEmpty ? "deliverable" : safe)
            try f.data.write(to: url)
            out.append(url)
        }
        return out
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

    /// Ask the founder where to put it, then write.
    ///
    /// One file gets a save panel with the name pre-filled; several get a directory picker,
    /// because `dms` and `calendar` produce a set and asking once per file would be four
    /// panels for one press.
    @MainActor
    static func save(_ d: Deliverable) {
        let files = DeliverableExport.files(for: d)
        guard !files.isEmpty else { return }

        if files.count == 1 {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = files[0].name
            panel.prompt = "Export"
            panel.message = "Save \(d.title)"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? files[0].data.write(to: url)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Save \(files.count) files from \(d.title)"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        _ = try? write(files, to: dir)
    }
}
