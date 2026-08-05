import Foundation

/// What a run says it is doing, per kind of work.
///
/// The web tailors this (`lib/helpers.ts → buildLog`) and native did not: one generic
/// four-line script served all thirteen `DeliverableKind`s, so generating a PLAN said
/// "Matching your tone and past decisions" — true of a doc, wrong for a checklist, and the
/// founder's actual complaint. Each script here describes what the run is genuinely asked to
/// do for that shape of work, and every one ends on the deliverable arriving.
///
/// Two departures from the reference, both deliberate (founder call, Aug 5 — "structure yes,
/// invented numbers no"):
///
/// 1. No fabricated specifics. The web's build script prints `editing Analytics.swift +11 −4`
///    (derived from the task title's length), `218 tests passed` (a constant) and
///    `localhost:3001` (hardcoded). Native's coding run has REAL file paths and real added and
///    removed line counts from `ClaudeCodeRunner.FileDiff`, so its terminal rows are built from
///    those — see `CodingRunCoordinator`. A company task that produces a doc has no tool
///    activity to report, so it gets no terminal rows at all rather than invented ones.
/// 2. The kind is INFERRED, because native cannot know it yet. The web's task model carries a
///    type; `RoadmapTask` does not, and the deliverable's real kind is decided by the Cloud
///    Function during the run. So this reads the department and the title, which is honest
///    enough — the steps describe what the run was ASKED for, and are written to stay true even
///    if the CF returns a different kind. The durable fix is a `kind` on the roadmap task, and
///    that belongs to the generator.
enum ExecScript {

    /// The shapes of work that read differently enough to deserve their own script. Named for
    /// the web's `type` values so the two products stay comparable.
    enum Shape: Equatable {
        case plan       // a checklist / sequence of steps the founder will run  (web: prep)
        case site       // a page or site
        case screens    // a flow, laid out
        case sheet      // a model or projection
        case code       // work on the founder's own repo                        (web: build)
        case doc        // the default: written work
    }

    /// Infer the shape from what the client knows before the run: the department and the title.
    /// Order matters — the title is the stronger signal, so it is read first, and `code` only
    /// wins from the department when nothing in the title says otherwise.
    static func shape(title: String, dept: String?) -> Shape {
        let t = title.lowercased()
        func any(_ words: [String]) -> Bool { words.contains { t.contains($0) } }

        if any(["plan", "checklist", "roadmap", "sequence", "kế hoạch", "danh sách"]) { return .plan }
        if any(["landing", "website", "site", "web page", "trang web"]) { return .site }
        if any(["screen", "onboarding flow", "wireframe", "mockup", "màn hình"]) { return .screens }
        if any(["pricing", "model", "projection", "forecast", "budget", "unit economics", "bảng"]) { return .sheet }
        if any(["refactor", "fix", "implement", "ship", "deploy", "migrate", "endpoint", "api"]) { return .code }
        if dept == "eng" { return .code }
        return .doc
    }

    /// The script for one run. `context` is the brief line — it names the decisions already on
    /// record when there are any, which is the one number here that is real.
    static func steps(title: String, dept: String?, deptName: String?,
                      decisionCount: Int, language: AppLanguage) -> [ExecStep] {
        let vi = language == .vi
        let L: (String) -> ExecStep = { ExecStep(label: $0) }
        let CK: (String) -> ExecStep = { ExecStep(label: $0, kind: .checkpoint) }

        let brief = decisionCount > 0
            ? (vi ? "Đọc brief — sứ mệnh, khách hàng, giọng điệu (và \(decisionCount) quyết định)"
                  : "Reading your brief — mission, audience, your voice (+ \(decisionCount) decisions)")
            : (vi ? "Đọc brief — sứ mệnh, khách hàng, giọng điệu của bạn"
                  : "Reading your brief — mission, audience, your voice")
        let playbook = deptName.map { d in
            vi ? "Vận dụng cẩm nang \(d)" : "Pulling in the \(d) playbook"
        }
        let delivering = vi ? "Viết sản phẩm cho bạn ↓" : "Writing the deliverable ↓"

        var out: [ExecStep] = [L(brief)]
        if let playbook { out.append(L(playbook)) }

        switch shape(title: title, dept: dept) {
        case .plan:
            out += [
                L(vi ? "Xác định đúng các bước bạn cần làm" : "Working out the exact steps you'll need to run"),
                CK(vi ? "Điểm kiểm: đối chiếu với giai đoạn hiện tại của lộ trình"
                      : "Checkpoint — cross-checked against your roadmap stage"),
                L(vi ? "Sắp thứ tự để không việc nào chặn việc sau"
                     : "Sequencing them so nothing blocks later"),
                L(vi ? "Viết checklist cho bạn ↓" : "Writing the checklist for you ↓"),
            ]
        case .site:
            out += [
                L(vi ? "Dựng khung trang — nav · hero · cách hoạt động · tính năng · CTA"
                     : "Outlining the page — nav · hero · how-it-works · features · CTA"),
                L(vi ? "Lấy ngữ cảnh thương hiệu — màu, giọng điệu, định vị ra mắt"
                     : "Pulling brand context — palette, voice, the launch positioning"),
                CK(vi ? "Điểm kiểm: đối chiếu với brief — thông điệp, CTA, giọng điệu"
                      : "Checkpoint — verified against the brief: message, CTA, tone"),
                L(delivering),
            ]
        case .screens:
            out += [
                L(vi ? "Sắp bố cục luồng — từ lúc mở đến lúc thấy giá trị"
                     : "Laying out the flow — from open to first value"),
                L(vi ? "Viết nội dung cho từng bước" : "Writing the copy for each step"),
                CK(vi ? "Điểm kiểm: soi từng màn hình theo mục tiêu"
                      : "Checkpoint — checked each screen against the goal"),
                L(delivering),
            ]
        case .sheet:
            out += [
                L(vi ? "Thu thập đầu vào — giá, chuyển đổi, những gì đã biết"
                     : "Pulling the inputs — price, conversion, what you already know"),
                L(vi ? "Dựng mô hình — người dùng trả tiền → MRR → ARR"
                     : "Building the projection — paid users → MRR → ARR"),
                CK(vi ? "Điểm kiểm: thử mô hình ở nhiều mức giá"
                      : "Checkpoint — stress-tested across the price band"),
                L(delivering),
            ]
        case .code:
            out += [
                L(vi ? "Đọc ngữ cảnh dự án — CLAUDE.md, brief, code của bạn"
                     : "Reading project context — CLAUDE.md, your brief, your code"),
                L(vi ? "Soạn thay đổi và cách kiểm chứng nó"
                     : "Drafting the change and a way to verify it"),
                CK(vi ? "Điểm kiểm: thay đổi này có làm đúng điều đã nói"
                      : "Checkpoint — the change does what we said it would"),
                L(delivering),
            ]
        case .doc:
            out += [
                L(vi ? "Soạn \(title) …" : "Drafting \(title) …"),
                CK(vi ? "Điểm kiểm: soi lại các tuyên bố so với sản phẩm của bạn"
                      : "Checkpoint — sanity-checked claims against your product"),
                L(vi ? "Chia thành các phần và thêm một hai biến thể"
                     : "Shaping it into sections and adding a variant or two"),
                L(delivering),
            ]
        }
        return out
    }
}
