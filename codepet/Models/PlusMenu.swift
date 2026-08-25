// codepet/Models/PlusMenu.swift
import Foundation

/// The `+` menu's contents — spec §5.
///
/// **What the `+` is for.** One question: what does this turn get to see, and how
/// hard should it work. It previously held three prompt starters that are already
/// cards on the empty hero, plus the room, plus the department leftovers — its own
/// doc comment defended it as "a quick-actions menu (NOT a file picker)", which
/// describes a control with no idea what it is for.
///
/// Codepet's answer to "what does it see" is not files. It is the company: the
/// Library, the roadmap, what Codepet knows, the linked folder.
///
/// **Every row carries a description** (§7.7). ChatGPT captions every row; Claude
/// captions none. ChatGPT is right, and this repo has the evidence — the founder
/// had to ask what `Convene the room · ~10 credits` meant. The room's caption is
/// deliberately NOT duplicated here: it comes from `RoomOffer.detail(_:)`, which
/// already holds exactly that sentence. Two copies is how a menu and its help tag
/// drift apart.
enum PlusMenu {

    /// Enough to recognise last week's work without turning a menu into a file
    /// browser. `Browse Library…` is the row for everything older.
    static let libraryRecentCap = 8

    /// Newest first. `createdAt` is ISO-8601 so a lexicographic sort is
    /// chronological; nil sorts last, because legacy deliverables predate the field
    /// and an undated document is not evidence of being new.
    static func recentLibrary(_ library: [Deliverable]) -> [Deliverable] {
        Array(library.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
                     .prefix(libraryRecentCap))
    }

    /// Open tasks in roadmap order. Order is not re-derived here: the roadmap's own
    /// sequence is what the founder reads on the board, and a menu that sorted
    /// differently would be a second opinion about what comes next.
    static func openTasks(_ tasks: [RoadmapTask]) -> [RoadmapTask] {
        tasks.filter { !$0.done }
    }

    // MARK: - Section headers

    static func bringInLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "MANG VÀO" : "BRING SOMETHING IN"
    }

    static func goDeeperLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "ĐI SÂU HƠN" : "GO DEEPER"
    }

    // MARK: - Rows

    static func attachLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Đính kèm tệp hoặc ảnh" : "Attach a file or image"
    }

    static func attachDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Ảnh chụp màn hình, PDF, ghi chú" : "Screenshots, PDFs, notes"
    }

    /// Shown instead of the detail when the pill row is full, because "nothing
    /// happened when I clicked" is the worst version of a cap.
    static func attachFullDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Đã có 3 — bỏ một cái trước" : "3 already attached — remove one first"
    }

    static func libraryLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Từ Thư viện" : "From your Library"
    }

    static func libraryDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Dựa trên những gì bạn đã làm xong"
                    : "Ground this answer in work you've shipped"
    }

    static func browseLibraryLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mở Thư viện…" : "Browse Library…"
    }

    static func taskLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Một việc trên lộ trình" : "A roadmap task"
    }

    static func taskDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Ghim việc bạn đang làm" : "Pin what you're working on"
    }

    static func openRoadmapLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mở Lộ trình…" : "Open Roadmap…"
    }

    /// The Second Brain, as the switch that already gates it.
    /// `FounderPrefs.memoryEnabled` is the real control over whether decisions reach
    /// the model; a fact-PICKER here would be new machinery in front of an existing
    /// boolean.
    static func knowsLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Những gì Codepet biết" : "What Codepet knows"
    }

    static func knowsDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Cho phép dùng các quyết định đã lưu"
                    : "Let it use your saved decisions"
    }

    /// Names the folder. A row reading only "Linked folder" makes the founder open it
    /// to find out which folder the agent is about to touch.
    static func folderLabel(_ lang: AppLanguage, path: String?) -> String {
        guard let path, !path.isEmpty else {
            return lang == .vi ? "Liên kết một thư mục…" : "Link a folder…"
        }
        let name = Project.nameFromPath(path)
        return lang == .vi ? "Thư mục — \(name)" : "Linked folder — \(name)"
    }

    static func folderDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Thư mục mà tác nhân được phép sửa"
                    : "The folder the agent may touch"
    }

    static func changeFolderLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Đổi…" : "Change…"
    }

    static func openEnvironmentLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mở Môi trường" : "Open Environment"
    }

    static func webSearchLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Tìm trên web" : "Web search"
    }

    static func webSearchDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Cho phép tra cứu khi trả lời"
                    : "Let it look things up as it answers"
    }

    /// Codepet's answer to Claude's three separate Skills / Connectors / Add plugins
    /// doors. `Toolkit` already has all three categories with real `ConnectorAuth`,
    /// and turning a connector on mid-sentence is a trip to a settings page — it
    /// should look like one rather than wear a menu costume.
    static func setupLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Cài đặt kỹ năng & kết nối…" : "Set up skills & connectors…"
    }

    static func setupDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mở Môi trường" : "Opens Environment"
    }
}
