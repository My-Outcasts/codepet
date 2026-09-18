// codepet/Models/TourScript.swift
import Foundation

/// What "Show me around" says.
///
/// **A script, not a model call, for the same reason the greeting is one.** Chat is
/// `.claudeOnly` (`BlockedOffer.Surface`) and `ChatTransportRouter.transport` blocks on the
/// grant, so a tour that asked the model would answer a brand-new founder with the grant wall.
/// A button whose first press returns an error teaches her the app is broken, at the one moment
/// she has no other evidence.
///
/// **It ends by handing off to shipped work.** The chip goes to Roadmap, where
/// `OverviewIntroSheet` already auto-shows once per account with the phase briefing and "How to
/// read this map". Re-describing that here would be two copies of one explanation — and that
/// sheet currently never fires for a founder who stays in chat, which this closes as a side
/// effect.
///
/// Outside any `@MainActor ObservableObject` — landmine 3.
enum TourScript {

    /// The chip on the greeting that offers the tour.
    static func offerLabel(lang: AppLanguage) -> String {
        lang == .vi ? "Dẫn mình đi một vòng" : "Show me around"
    }

    /// Only the destinations `AppView.from(navDestination:)` can resolve are named —
    /// "roadmap", "tasks", "library", "company"/"department". `environment` is deliberately
    /// left out: it is tooling, not part of understanding what Codepet does for you.
    static func message(language: AppLanguage) -> String {
        language == .vi
            ? """
              Đây là bố cục của chỗ này. Chỗ mình đang nói chuyện là Chat — hỏi mình bất cứ điều \
              gì, hoặc bảo mình chạy việc gì đó.

              Lộ trình là kế hoạch của bạn, theo từng giai đoạn. Nhiệm vụ là cùng phần việc đó \
              nhưng ở dạng danh sách để chạy. Thư viện giữ mọi sản phẩm sau khi bạn duyệt. Và \
              Các bộ phận là đội của bạn — mỗi bộ phận tự viết phần việc của mình.

              Bắt đầu từ lộ trình thì dễ nhất — nó là bản đồ cho mọi thứ còn lại.
              """
            : """
              Here's the shape of the place. Chat is where we're talking now — ask me anything, \
              or tell me to run something.

              Roadmap is your plan, phase by phase. Tasks is the same work as a list you can run. \
              Library keeps every deliverable once you approve it. And Departments is your team — \
              each one writes its own work.

              Start with the roadmap; it's the map for everything else.
              """
    }

    /// Where the tour sends her. `nil` target: "roadmap" is not a department, and
    /// `activateNav` only reads `target` for `destination == "department"`.
    static func chip() -> NavAction { NavAction(destination: "roadmap", target: nil) }
}
