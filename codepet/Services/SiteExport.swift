// codepet/Services/SiteExport.swift
import Foundation
import AppKit

/// Writing a produced landing page somewhere a browser can open it.
///
/// **Why this exists.** `SiteViewer` rendered the page in an in-app `WKWebView` from an HTML
/// string and never wrote it anywhere, so a founder could look at their own landing page inside
/// a dock column or copy raw markup, and could not open it in a browser. There was no
/// `NSWorkspace.shared.open` anywhere near the deliverable path.
///
/// Split from the view so the naming and the failure path are testable without `NSWorkspace`
/// and without launching a browser. `openInBrowser` still makes the real `NSWorkspace` call —
/// that is untestable by nature — but `browserTarget` (Chrome vs. the system default) is a pure
/// decision a test can drive without touching `NSWorkspace` or launching anything.
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

    // MARK: - Choosing a browser

    /// Where "Open in browser" actually opens: Google Chrome by name, or the founder's system
    /// default. The founder asked for Chrome specifically, not "whichever browser is default" —
    /// but Chrome is not guaranteed to be installed, and a button that silently does nothing when
    /// it is absent is worse than one that opens the wrong browser.
    enum BrowserTarget: Equatable {
        /// Open with this specific application (Chrome's `NSWorkspace`-resolved URL).
        case named(URL)
        /// Chrome could not be resolved; fall back to `NSWorkspace.shared.open(url)`.
        case systemDefault
    }

    /// **Pure**, and that is the whole point of splitting it out. Whether Chrome is installed is
    /// an `NSWorkspace` question, so the answer (`chromeAppURL`) is passed in rather than asked
    /// for here — the caller does the one line of `NSWorkspace.shared.urlForApplication(withBundleIdentifier:
    /// "com.google.Chrome")`, and this function only decides what to do with the result. That
    /// keeps "Chrome present vs. absent" testable without launching anything.
    static func browserTarget(chromeAppURL: URL?) -> BrowserTarget {
        chromeAppURL.map(BrowserTarget.named) ?? .systemDefault
    }

    /// Writes `html` to this deliverable's stable file, then opens it — the one impure entry
    /// point shared by every call site (the Library's site viewer and the chat draft card), so
    /// the write-then-open sequence exists once. Still fail-soft: throws instead of trapping, and
    /// callers already have an `openFailed` flag they flip on catch.
    @MainActor
    static func openInBrowser(html: String, deliverableId: String) throws {
        let url = fileURL(forDeliverableId: deliverableId)
        try write(html: html, to: url)
        switch browserTarget(chromeAppURL: NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.google.Chrome")) {
        case .named(let chromeURL):
            NSWorkspace.shared.open([url], withApplicationAt: chromeURL,
                                     configuration: NSWorkspace.OpenConfiguration())
        case .systemDefault:
            NSWorkspace.shared.open(url)
        }
    }
}
