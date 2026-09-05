// codepet/Services/SiteExport.swift
import Foundation

/// Writing a produced landing page somewhere a browser can open it.
///
/// **Why this exists.** `SiteViewer` rendered the page in an in-app `WKWebView` from an HTML
/// string and never wrote it anywhere, so a founder could look at their own landing page inside
/// a dock column or copy raw markup, and could not open it in a browser. There was no
/// `NSWorkspace.shared.open` anywhere near the deliverable path.
///
/// Split from the view so the naming and the failure path are testable without `NSWorkspace`
/// and without launching a browser. The view keeps only the `open` call, which is untestable by
/// nature and is therefore the only untested line.
///
/// **The boundary, stated plainly:** this produces a `file://` URL. That is a real browser page
/// — URL bar, zoom, devtools, print-to-PDF — and it is **not shareable with anyone**. A hosted
/// `https://` link is a separate project needing storage, a URL scheme, and a decision about
/// whether an unapproved draft is publicly reachable. Nothing here may imply otherwise.
enum SiteExport {

    /// A stable per-deliverable location in the temp directory.
    ///
    /// **Derived from the id, not random and not timestamped**, so opening the same page twice
    /// replaces one file instead of accumulating them, and a browser reload after a Redo shows
    /// the current draft rather than a stale one.
    ///
    /// **Sanitised, because an id is only a `String`.** Ids are UUIDs in production and
    /// `demo-mur-site` in fixtures, and nothing in the type system stops a future one carrying a
    /// path separator. Anything outside a safe set becomes `-`, so the result cannot climb out
    /// of the temp directory. An empty id still yields a valid filename.
    static func fileURL(forDeliverableId id: String) -> URL {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let safe = String(id.map { allowed.contains($0) ? $0 : "-" })
        let name = safe.isEmpty ? "site" : safe
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("codepet-site-\(name)")
            .appendingPathExtension("html")
    }

    /// Write the page, replacing whatever was there.
    ///
    /// Throws rather than trapping: a founder pressing a button must never crash the app, and
    /// the caller turns this into a visible message instead.
    static func write(html: String, to url: URL) throws {
        try Data(html.utf8).write(to: url, options: .atomic)
    }
}
