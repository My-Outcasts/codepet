import AppKit

/// The one place the coding-agent link flow lives, shared by the Environment
/// "Linked project" section and the chat card's `.noProject` offer (2C-3). It
/// drives the native directory picker + the CLAUDE.md-bootstrap consent, then
/// links via `CompanyStore.linkProject` (2A). Kept out of the views so both call
/// sites use the identical consent rule — we NEVER write a CLAUDE.md without an
/// explicit yes (and `linkProject` itself never clobbers an existing one).
@MainActor
enum ProjectLinker {

    /// Open a directory picker; on pick, run the consent flow and link. Returns
    /// the new link, or nil if the founder cancelled the picker.
    static func pickAndLink(into store: CompanyStore, language: AppLanguage) -> ProjectLink? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = language == .vi ? "Liên kết" : "Link"
        panel.message = language == .vi
            ? "Chọn thư mục dự án cho coding agent"
            : "Choose a project folder for the coding agent"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return link(path: url.path, into: store, language: language)
    }

    /// Link a known path (e.g. a suggestion chip) — still runs the CLAUDE.md
    /// consent prompt when the folder has none.
    @discardableResult
    static func link(path: String, into store: CompanyStore, language: AppLanguage) -> ProjectLink {
        var bootstrap = false
        if !ProjectProbe.probe(path: path).hasClaudeMd {
            let alert = NSAlert()
            alert.messageText = language == .vi ? "Tạo file CLAUDE.md?" : "Create a CLAUDE.md?"
            alert.informativeText = language == .vi
                ? "Mình có thể tạo CLAUDE.md từ brief của bạn để có ngữ cảnh sẵn trong dự án này. Sẽ không đụng tới file đã có."
                : "I can seed a CLAUDE.md from your brief so I have standing context in this project. It won't touch an existing one."
            alert.addButton(withTitle: language == .vi ? "Tạo" : "Create it")
            alert.addButton(withTitle: language == .vi ? "Bỏ qua" : "Skip")
            bootstrap = alert.runModal() == .alertFirstButtonReturn
        }
        return store.linkProject(path: path, bootstrapClaudeMd: bootstrap)
    }
}
