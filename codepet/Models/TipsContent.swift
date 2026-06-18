import Foundation
import SwiftUI

/// A pet-specialized agentic-coding skill tile shown in the Tips tab.
struct TipSkillTile {
    let icon: String   // SF Symbol name
    let title: L10n
    let hint: L10n
}

/// State shown next to each setup row.
enum TipSetupState: String {
    case done, warning, missing

    /// SF Symbol for the status indicator.
    var icon: String {
        switch self {
        case .done:    return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .missing: return "circle"
        }
    }

    // NOTE: `var color: Color` is defined in TipsMockupView.swift as an
    // extension on TipSetupState (maps done→green, warning→orange, missing→muted).
    // Do not redeclare here.
}

/// A pet-specialized "Your setup" row.
struct TipSetupItem {
    let title: L10n
    let status: L10n
    let state: TipSetupState
    let actionLabel: L10n?
}

/// Tech-stack tags used to match readings to projects.
enum ProjectTag: String, Codable, CaseIterable {
    // Platform / language
    case swiftUI       // .swift files + SwiftUI imports
    case uiKit         // .swift + UIKit / Storyboard
    case react         // package.json with react dep
    case vue           // package.json with vue dep
    case angular       // angular.json
    case python        // .py files, requirements.txt, pyproject.toml
    case nodeBackend   // package.json + server-like deps (express, fastify, etc.)
    case goLang        // go.mod
    case rust          // Cargo.toml

    // Infrastructure / services
    case firebase      // GoogleService-Info.plist, firebase.json
    case docker        // Dockerfile, docker-compose.yml
    case ci            // .github/workflows, .gitlab-ci.yml, Jenkinsfile
    case database      // prisma, knex, sequelize, Core Data, .sql files
    case api           // REST/GraphQL patterns (openapi.yaml, schema.graphql)
    case testing       // XCTest, jest, pytest, test directories
    case mobile        // iOS/Android project markers
}

/// What a project is ABOUT (its domain), independent of its tech stack. Lets
/// same-tech projects (e.g. two SwiftUI apps) get different reading based on
/// what they actually build. Inferred from the project path + brief.
enum ProjectDomain: String, Codable, CaseIterable {
    case finance        // money, budget, expense, banking, payments, crypto
    case health         // fitness, workout, yoga, wellness, habits, meditation
    case ecommerce      // shop, store, cart, checkout, retail
    case productivity   // todo, tasks, notes, calendar, planner, journal
    case games          // game, arcade, puzzle, player, levels, score
    case social         // chat, messaging, feed, community, posts
    case education      // courses, quizzes, lessons, students, tutoring
    case content        // blog, cms, news, media, portfolio
}

/// A pet-specialized "Recommended reading" entry.
struct TipReadingItem {
    let title: L10n
    let author: String   // proper noun, language-neutral
    let kind: L10n
    let why: L10n
    /// Optional URL to open in the browser. nil = no "Open" action.
    let url: String?
    /// Tech-stack tags for project-aware matching. Empty = universal.
    let tags: [ProjectTag]
    /// Domain tags (what the project is about). Empty = domain-agnostic — most
    /// general engineering/design books are. A domain match is weighted higher
    /// than a tech match so same-tech projects surface different top picks.
    let domains: [ProjectDomain]
    /// Lifecycle stages this reading is relevant for. Used to surface
    /// business/marketing books at the right moment (e.g. validation books at
    /// `.idea`, growth books at `.growth`). Empty = relevant at every stage.
    let stages: [ProjectStage]
    /// Which health pillar this reading speaks to. Empty = general. Lets the
    /// matcher surface business/growth books independently of the tech stack.
    let pillars: [HealthPillar]

    init(
        title: L10n,
        author: String,
        kind: L10n,
        why: L10n,
        url: String? = nil,
        tags: [ProjectTag] = [],
        domains: [ProjectDomain] = [],
        stages: [ProjectStage] = [],
        pillars: [HealthPillar] = []
    ) {
        self.title = title
        self.author = author
        self.kind = kind
        self.why = why
        self.url = url
        self.tags = tags
        self.domains = domains
        self.stages = stages
        self.pillars = pillars
    }
}

/// Per-pet content for the Tips tab. Each pet represents a discipline, and
/// the Tips section dives deep into that discipline.
///
/// Lookup pattern: `TipsContent.tipSkillsByPet[appState.activeChar] ?? defaultTiles`.
/// Pet without an entry falls back to the original default tiles in the view.
struct TipsContent {

    static let tipSkillsByPet: [String: [TipSkillTile]] = [

        // Crash — Backend Dev (tough-love hype)
        "crash": [
            TipSkillTile(
                icon: "arrow.clockwise",
                title: L10n(vi: "Endpoint idempotent", en: "Idempotent endpoints"),
                hint: L10n(
                    vi: "Để agent làm POST an toàn khi retry — rồi bắt nó chứng minh: gọi lại đúng request hai lần và kiểm tra không có gì bị tính đôi.",
                    en: "Have the agent make POST safe to retry — then make it prove it: replay the same call twice and check nothing doubles."
                )
            ),
            TipSkillTile(
                icon: "server.rack",
                title: L10n(vi: "Transaction trong DB", en: "Database transactions"),
                hint: L10n(
                    vi: "Bảo agent bọc thao tác ghi nhiều bước — rồi đọc diff để chắc rằng một lỗi giữa chừng không để lại dữ liệu nửa vời.",
                    en: "Tell the agent to wrap the multi-step write — then read the diff to confirm a mid-way failure can't leave data half-baked."
                )
            ),
            TipSkillTile(
                icon: "clock.arrow.circlepath",
                title: L10n(vi: "Background job", en: "Background jobs"),
                hint: L10n(
                    vi: "Để agent đẩy việc chậm vào queue — bạn là người quyết việc nào 'chậm' đến mức không được bắt người dùng đợi.",
                    en: "Have the agent move the slow work to a queue — you decide what counts as 'slow' enough to never block a user."
                )
            ),
            TipSkillTile(
                icon: "gauge.high",
                title: L10n(vi: "Rate limit cho API", en: "API rate limiting"),
                hint: L10n(
                    vi: "Để agent thêm rate limit — rồi tự tông vào nó bằng một script chạy loạn trước khi kẻ xấu làm điều đó.",
                    en: "Let the agent add the limiter — then try to break it with a runaway script before an attacker does."
                )
            ),
            TipSkillTile(
                icon: "macbook.and.iphone",
                title: L10n(vi: "Responsive layout", en: "Responsive layout"),
                hint: L10n(
                    vi: "Để agent dựng layout cho cả điện thoại lẫn máy tính — rồi tự kéo co cửa sổ và bắt những chỗ vỡ.",
                    en: "Have the agent build the phone and desktop layouts — then resize the window yourself and catch what breaks."
                )
            ),
            TipSkillTile(
                icon: "speedometer",
                title: L10n(vi: "Hiệu năng", en: "Performance"),
                hint: L10n(
                    vi: "Bảo agent profile và tối ưu — nhưng tự đo trước và sau. Tin số liệu, đừng tin cảm giác.",
                    en: "Ask the agent to profile and optimize — but measure before and after yourself. Numbers, not vibes."
                )
            ),
        ],

        // Nova — Frontend Dev (fiery / fast)
        "nova": [
            TipSkillTile(
                icon: "square.on.square",
                title: L10n(vi: "Ghép component", en: "Component composition"),
                hint: L10n(
                    vi: "Bảo agent tách ra những mảnh tái sử dụng được — rồi soi chỗ ghép: bạn có dùng lại được không, hay nó chỉ chia nhỏ file cho có?",
                    en: "Get the agent to extract reusable pieces — then review the seams: would you actually reuse them, or did it just split files?"
                )
            ),
            TipSkillTile(
                icon: "exclamationmark.triangle",
                title: L10n(vi: "Loading & error state", en: "Loading & error states"),
                hint: L10n(
                    vi: "Bắt agent xử lý mọi nhánh async — rồi tự kiểm fallback bằng cách ngắt mạng giữa chừng.",
                    en: "Make the agent handle every async path — then check the fallbacks yourself by killing the network mid-load."
                )
            ),
            TipSkillTile(
                icon: "checkmark.rectangle.stack",
                title: L10n(vi: "UX kiểm tra form", en: "Form validation UX"),
                hint: L10n(
                    vi: "Để agent kiểm tra ngay khi người dùng gõ — bạn là người quyết khi nào 'hữu ích' biến thành 'khó tính'.",
                    en: "Have the agent validate as the user types — you're the one who decides where 'helpful' turns into 'pedantic'."
                )
            ),
            TipSkillTile(
                icon: "figure.walk",
                title: L10n(vi: "Cơ bản về Accessibility", en: "Accessibility basics"),
                hint: L10n(
                    vi: "Bảo agent lo điều hướng bàn phím, độ tương phản, alt text — rồi tự tab qua từng phần, không đụng tới chuột.",
                    en: "Ask the agent for keyboard nav, contrast, and alt text — then tab through it yourself with the mouse untouched."
                )
            ),
            TipSkillTile(
                icon: "macbook.and.iphone",
                title: L10n(vi: "Responsive layout", en: "Responsive layout"),
                hint: L10n(
                    vi: "Để agent dựng layout cho cả điện thoại lẫn máy tính — rồi tự kéo co cửa sổ và bắt những chỗ vỡ.",
                    en: "Have the agent build the phone and desktop layouts — then resize the window yourself and catch what breaks."
                )
            ),
            TipSkillTile(
                icon: "speedometer",
                title: L10n(vi: "Hiệu năng", en: "Performance"),
                hint: L10n(
                    vi: "Bảo agent profile và tối ưu — nhưng tự đo trước và sau. Tin số liệu, đừng tin cảm giác.",
                    en: "Ask the agent to profile and optimize — but measure before and after yourself. Numbers, not vibes."
                )
            ),
        ],

        // Luna — Designer / UX-UI (warm / creative)
        "luna": [
            TipSkillTile(
                icon: "ruler",
                title: L10n(vi: "Khoảng cách & nhịp", en: "Spacing & rhythm"),
                hint: L10n(
                    vi: "Đưa agent thang 4 hoặc 8px và bắt nó tuân theo — rồi rà màn hình tìm cái giá trị duy nhất lọt lưới.",
                    en: "Give the agent a 4 or 8 px scale and make it stick to it — then scan the screen for the one value that escaped."
                )
            ),
            TipSkillTile(
                icon: "textformat.size",
                title: L10n(vi: "Hệ phân cấp font chữ", en: "Type hierarchy"),
                hint: L10n(
                    vi: "Ra lệnh cho agent: tối đa ba size. Rồi nhìn lại — to, vừa, nhỏ có thực sự dẫn mắt bạn đi không?",
                    en: "Tell the agent: three sizes max. Then read the result — did big, medium, small actually guide your eye?"
                )
            ),
            TipSkillTile(
                icon: "circle.lefthalf.filled",
                title: L10n(vi: "Độ tương phản màu", en: "Color contrast"),
                hint: L10n(
                    vi: "Để agent đạt 4.5:1 cho chữ thân bài — rồi tự chạy số, đừng tin con mắt trên màn hình xịn của bạn.",
                    en: "Have the agent hit 4.5:1 on body text — then run the numbers, don't trust how it looks on your nice monitor."
                )
            ),
            TipSkillTile(
                icon: "tray",
                title: L10n(vi: "Trạng thái rỗng", en: "Empty states"),
                hint: L10n(
                    vi: "Bảo agent thiết kế view rỗng kỹ như view đầy — bạn kiểm xem nó có bị làm cho qua loa không.",
                    en: "Ask the agent to design the zero-item view as carefully as the full one — you check it's not an afterthought."
                )
            ),
            TipSkillTile(
                icon: "macbook.and.iphone",
                title: L10n(vi: "Responsive layout", en: "Responsive layout"),
                hint: L10n(
                    vi: "Để agent dựng layout cho cả điện thoại lẫn máy tính — rồi tự kéo co cửa sổ và bắt những chỗ vỡ.",
                    en: "Have the agent build the phone and desktop layouts — then resize the window yourself and catch what breaks."
                )
            ),
            TipSkillTile(
                icon: "speedometer",
                title: L10n(vi: "Hiệu năng", en: "Performance"),
                hint: L10n(
                    vi: "Bảo agent profile và tối ưu — nhưng tự đo trước và sau. Tin số liệu, đừng tin cảm giác.",
                    en: "Ask the agent to profile and optimize — but measure before and after yourself. Numbers, not vibes."
                )
            ),
        ],

        // Sage — Product Owner (zen / methodical)
        "sage": [
            TipSkillTile(
                icon: "checkmark.seal",
                title: L10n(vi: "Định nghĩa \"xong\", không phải tính năng", en: "Define done, not features"),
                hint: L10n(
                    vi: "Spec cho agent phần bằng chứng, không phải phần việc — \"xong\" là thứ nó kiểm chứng được, không phải thứ bạn mong.",
                    en: "Spec the agent the proof, not the work — 'done' is something it can verify, not something you hope for."
                )
            ),
            TipSkillTile(
                icon: "person.text.rectangle",
                title: L10n(vi: "User story", en: "User stories"),
                hint: L10n(
                    vi: "Đưa agent đủ [ai] / [muốn] / [để] — bỏ mất chữ \"để\" là nó sẽ chăm chỉ làm sai thứ bạn cần.",
                    en: "Hand the agent the [who] / [want] / [so] — drop the 'so' and it'll happily build the wrong thing well."
                )
            ),
            TipSkillTile(
                icon: "scissors",
                title: L10n(vi: "Cắt scope, không cắt chất lượng", en: "Cut scope, not quality"),
                hint: L10n(
                    vi: "Khi hết giờ, bảo agent bỏ tính năng nào — đừng bao giờ bảo nó cắt góc chất lượng.",
                    en: "When time's short, tell the agent which features to drop — never which corners to cut."
                )
            ),
            TipSkillTile(
                icon: "person.3",
                title: L10n(vi: "Sắp xếp các bên liên quan", en: "Stakeholder triage"),
                hint: L10n(
                    vi: "Cho agent biết ai quyết, ai khuyên, ai chỉ được báo — bối cảnh nó không đoán được, nhưng sẽ hành động dựa vào.",
                    en: "Tell the agent who decides, who advises, who's just informed — context it can't guess but will act on."
                )
            ),
            TipSkillTile(
                icon: "macbook.and.iphone",
                title: L10n(vi: "Responsive layout", en: "Responsive layout"),
                hint: L10n(
                    vi: "Để agent dựng layout cho cả điện thoại lẫn máy tính — rồi tự kéo co cửa sổ và bắt những chỗ vỡ.",
                    en: "Have the agent build the phone and desktop layouts — then resize the window yourself and catch what breaks."
                )
            ),
            TipSkillTile(
                icon: "speedometer",
                title: L10n(vi: "Hiệu năng", en: "Performance"),
                hint: L10n(
                    vi: "Bảo agent profile và tối ưu — nhưng tự đo trước và sau. Tin số liệu, đừng tin cảm giác.",
                    en: "Ask the agent to profile and optimize — but measure before and after yourself. Numbers, not vibes."
                )
            ),
        ],

        // Glitch — DevOps (punk / rebel)
        "glitch": [
            TipSkillTile(
                icon: "doc.text.below.ecg",
                title: L10n(vi: "Hạ tầng dạng code", en: "Infra as code"),
                hint: L10n(
                    vi: "Bắt agent viết hạ tầng tái tạo được từ repo — rồi xoá sạch và dựng lại để chứng minh đó không phải một điều ước.",
                    en: "Make the agent write infra you can reproduce from the repo — then tear it down and rebuild to prove it wasn't a wish."
                )
            ),
            TipSkillTile(
                icon: "arrow.triangle.2.circlepath",
                title: L10n(vi: "Pipeline CI/CD", en: "CI/CD pipelines"),
                hint: L10n(
                    vi: "Để agent dựng pipeline — nhưng bạn giữ luật: đỏ trên main thì không gì đi tiếp đến khi xanh trở lại.",
                    en: "Have the agent wire the pipeline — but you hold the rule: red on main, nothing moves until it's green."
                )
            ),
            TipSkillTile(
                icon: "list.bullet.indent",
                title: L10n(vi: "Log > metric > alert", en: "Logs > metrics > alerts"),
                hint: L10n(
                    vi: "Để agent log khắp nơi — bạn chọn danh sách ngắn những thứ đáng đánh thức ai đó lúc 3 giờ sáng.",
                    en: "Let the agent add logging everywhere — you decide the short list worth waking someone at 3am."
                )
            ),
            TipSkillTile(
                icon: "exclamationmark.triangle.fill",
                title: L10n(vi: "Diễn tập phục hồi sự cố", en: "Disaster recovery drills"),
                hint: L10n(
                    vi: "Bảo agent viết kịch bản phục hồi — rồi diễn tập thật, vì prod sẽ hỏng đúng lúc bạn đang ngủ.",
                    en: "Ask the agent to script the recovery — then actually run the drill, because prod will fail while you're asleep."
                )
            ),
            TipSkillTile(
                icon: "macbook.and.iphone",
                title: L10n(vi: "Responsive layout", en: "Responsive layout"),
                hint: L10n(
                    vi: "Để agent dựng layout cho cả điện thoại lẫn máy tính — rồi tự kéo co cửa sổ và bắt những chỗ vỡ.",
                    en: "Have the agent build the phone and desktop layouts — then resize the window yourself and catch what breaks."
                )
            ),
            TipSkillTile(
                icon: "speedometer",
                title: L10n(vi: "Hiệu năng", en: "Performance"),
                hint: L10n(
                    vi: "Bảo agent profile và tối ưu — nhưng tự đo trước và sau. Tin số liệu, đừng tin cảm giác.",
                    en: "Ask the agent to profile and optimize — but measure before and after yourself. Numbers, not vibes."
                )
            ),
        ],

        // Byte — Data / ML (glitchy / fragments)
        "byte": [
            TipSkillTile(
                icon: "square.grid.3x3",
                title: L10n(vi: "Chất lượng dữ liệu trước", en: "Data quality first"),
                hint: L10n(
                    vi: "Hướng agent vào dữ liệu trước khi vào model — 80% thắng lợi nằm ở việc dọn sạch cái bạn đưa cho nó.",
                    en: "Point the agent at the data before the model — 80% of the win is cleaning what you feed it."
                )
            ),
            TipSkillTile(
                icon: "chart.line.uptrend.xyaxis",
                title: L10n(vi: "Kỷ luật train / val / test", en: "Train / val / test discipline"),
                hint: L10n(
                    vi: "Để agent chia ba bộ — và cấm nó đụng vào test cho đến cuối. Nhìn lén sớm là gian lận.",
                    en: "Have the agent split three ways — and forbid it from touching test until the end. Early peeking is cheating."
                )
            ),
            TipSkillTile(
                icon: "chart.bar.xaxis",
                title: L10n(vi: "Đánh giá vượt qua accuracy", en: "Eval beyond accuracy"),
                hint: L10n(
                    vi: "Bắt agent báo cáo precision, recall, F1, AUC — chỉ mỗi accuracy sẽ nói dối bạn trên dữ liệu mất cân bằng.",
                    en: "Make the agent report precision, recall, F1, AUC — accuracy alone will lie to you on imbalanced data."
                )
            ),
            TipSkillTile(
                icon: "drop.fill",
                title: L10n(vi: "Pipeline đặc trưng", en: "Feature pipelines"),
                hint: L10n(
                    vi: "Để agent làm feature tái tạo được — không dựng lại được thì cũng không tin được kết quả nó đưa.",
                    en: "Have the agent make features reproducible — if you can't rebuild them, you can't trust the result it gave you."
                )
            ),
            TipSkillTile(
                icon: "macbook.and.iphone",
                title: L10n(vi: "Responsive layout", en: "Responsive layout"),
                hint: L10n(
                    vi: "Để agent dựng layout cho cả điện thoại lẫn máy tính — rồi tự kéo co cửa sổ và bắt những chỗ vỡ.",
                    en: "Have the agent build the phone and desktop layouts — then resize the window yourself and catch what breaks."
                )
            ),
            TipSkillTile(
                icon: "speedometer",
                title: L10n(vi: "Hiệu năng", en: "Performance"),
                hint: L10n(
                    vi: "Bảo agent profile và tối ưu — nhưng tự đo trước và sau. Tin số liệu, đừng tin cảm giác.",
                    en: "Ask the agent to profile and optimize — but measure before and after yourself. Numbers, not vibes."
                )
            ),
        ],

        // Null — Mobile Dev (chaotic / silly)
        "null": [
            TipSkillTile(
                icon: "battery.50",
                title: L10n(vi: "Ý thức về pin & mạng", en: "Battery & network awareness"),
                hint: L10n(
                    vi: "Để agent giảm tối đa việc nền và call mạng — rồi tự canh pin; cả hai đều bào mòn niềm tin.",
                    en: "Have the agent minimize background work and network calls — then watch the battery yourself; both drain trust."
                )
            ),
            TipSkillTile(
                icon: "bell.badge",
                title: L10n(vi: "Phép tắc push notification", en: "Push notification etiquette"),
                hint: L10n(
                    vi: "Bảo agent chỉ thông báo khi việc đó là về NGƯỜI DÙNG — bạn là bộ lọc chặn spam marketing.",
                    en: "Tell the agent to notify only when it's about THE USER — you are the filter against marketing spam."
                )
            ),
            TipSkillTile(
                icon: "wifi.slash",
                title: L10n(vi: "Pattern offline-first", en: "Offline-first patterns"),
                hint: L10n(
                    vi: "Để agent giả định mất mạng và thiết kế cho điều đó — rồi tự test ở chế độ máy bay, không phải trên wifi.",
                    en: "Have the agent assume the network is gone and design for it — then test it in airplane mode, not on wifi."
                )
            ),
            TipSkillTile(
                icon: "shippingbox",
                title: L10n(vi: "Kỷ luật kích thước app", en: "App size discipline"),
                hint: L10n(
                    vi: "Bảo agent bỏ asset thừa và lazy-load — bạn canh số MB, vì mỗi megabyte là một rào cản tải về.",
                    en: "Ask the agent to strip assets and lazy-load — you watch the MB count, because every megabyte is a download barrier."
                )
            ),
            TipSkillTile(
                icon: "macbook.and.iphone",
                title: L10n(vi: "Responsive layout", en: "Responsive layout"),
                hint: L10n(
                    vi: "Để agent dựng layout cho cả điện thoại lẫn máy tính — rồi tự kéo co cửa sổ và bắt những chỗ vỡ.",
                    en: "Have the agent build the phone and desktop layouts — then resize the window yourself and catch what breaks."
                )
            ),
            TipSkillTile(
                icon: "speedometer",
                title: L10n(vi: "Hiệu năng", en: "Performance"),
                hint: L10n(
                    vi: "Bảo agent profile và tối ưu — nhưng tự đo trước và sau. Tin số liệu, đừng tin cảm giác.",
                    en: "Ask the agent to profile and optimize — but measure before and after yourself. Numbers, not vibes."
                )
            ),
        ],
    ]

    // MARK: - Setup section per pet

    static let tipSetupByPet: [String: [TipSetupItem]] = [
        "crash": [
            TipSetupItem(
                title: L10n(vi: "Database Postgres", en: "Postgres database"),
                status: L10n(vi: "Đã kết nối · schema prod đồng bộ", en: "Connected · prod schema synced"),
                state: .done, actionLabel: nil
            ),
            TipSetupItem(
                title: L10n(vi: "Lớp cache Redis", en: "Redis cache layer"),
                status: L10n(vi: "Tỉ lệ hit 47% — cần kiểm tra", en: "Hit ratio 47% — investigate"),
                state: .warning, actionLabel: L10n(vi: "Tinh chỉnh", en: "Tune")
            ),
            TipSetupItem(
                title: L10n(vi: "Queue cho job nền", en: "Background job queue"),
                status: L10n(vi: "Chưa cấu hình — đang block-and-wait", en: "Not configured — block-and-wait"),
                state: .missing, actionLabel: L10n(vi: "Cài đặt", en: "Set up")
            ),
            TipSetupItem(
                title: L10n(vi: "Giám sát API", en: "API monitoring"),
                status: L10n(vi: "Chưa nối dashboard latency", en: "No latency dashboard wired"),
                state: .missing, actionLabel: L10n(vi: "Nối ngay", en: "Wire it")
            ),
        ],
        "nova": [
            TipSetupItem(
                title: L10n(vi: "Storybook", en: "Storybook"),
                status: L10n(vi: "Đang chạy · đã ghi nhận 4 component", en: "Running · 4 components catalogued"),
                state: .done, actionLabel: nil
            ),
            TipSetupItem(
                title: L10n(vi: "Lighthouse CI", en: "Lighthouse CI"),
                status: L10n(vi: "LCP 3.2s — vượt ngưỡng", en: "LCP 3.2s — over budget"),
                state: .warning, actionLabel: L10n(vi: "Tối ưu", en: "Optimize")
            ),
            TipSetupItem(
                title: L10n(vi: "Bộ test hồi quy hình ảnh", en: "Visual regression suite"),
                status: L10n(vi: "Chưa có ảnh baseline", en: "No screenshot baseline"),
                state: .missing, actionLabel: L10n(vi: "Chụp", en: "Capture")
            ),
            TipSetupItem(
                title: L10n(vi: "Bundle analyzer", en: "Bundle analyzer"),
                status: L10n(vi: "Lần chạy gần nhất: chưa từng", en: "Last run: never"),
                state: .missing, actionLabel: L10n(vi: "Chạy ngay", en: "Run now")
            ),
        ],
        "luna": [
            TipSetupItem(
                title: L10n(vi: "Thư viện Figma", en: "Figma library"),
                status: L10n(vi: "Đã liên kết · 47 component", en: "Linked · 47 components"),
                state: .done, actionLabel: nil
            ),
            TipSetupItem(
                title: L10n(vi: "Xuất design token", en: "Design tokens export"),
                status: L10n(vi: "Lệch · 3 token bị trôi", en: "Out of sync · 3 tokens drifted"),
                state: .warning, actionLabel: L10n(vi: "Đồng bộ lại", en: "Re-sync")
            ),
            TipSetupItem(
                title: L10n(vi: "Kiểm tra Accessibility", en: "Accessibility audit"),
                status: L10n(vi: "Chu kỳ này chưa check WCAG", en: "No WCAG check this cycle"),
                state: .missing, actionLabel: L10n(vi: "Kiểm tra", en: "Audit")
            ),
            TipSetupItem(
                title: L10n(vi: "Hướng dẫn giọng điệu thương hiệu", en: "Brand voice guide"),
                status: L10n(vi: "Doc về tone chưa được viết", en: "Tone doc not written"),
                state: .missing, actionLabel: L10n(vi: "Phác thảo", en: "Draft")
            ),
        ],
        "sage": [
            TipSetupItem(
                title: L10n(vi: "Doc đặc tả sản phẩm", en: "Product spec doc"),
                status: L10n(vi: "Đã liên kết · cập nhật hôm qua", en: "Linked · last updated yesterday"),
                state: .done, actionLabel: nil
            ),
            TipSetupItem(
                title: L10n(vi: "Metric ngôi sao Bắc Đẩu", en: "North-star metric"),
                status: L10n(vi: "Đã định nghĩa nhưng chưa đo", en: "Defined but not instrumented"),
                state: .warning, actionLabel: L10n(vi: "Đo lường", en: "Instrument")
            ),
            TipSetupItem(
                title: L10n(vi: "Nhật ký nghiên cứu người dùng", en: "User research log"),
                status: L10n(vi: "0 phỏng vấn quý này", en: "0 interviews this quarter"),
                state: .missing, actionLabel: L10n(vi: "Lên lịch", en: "Schedule")
            ),
            TipSetupItem(
                title: L10n(vi: "Snapshot roadmap", en: "Roadmap snapshot"),
                status: L10n(vi: "Chưa có bản công khai", en: "No public version"),
                state: .missing, actionLabel: L10n(vi: "Công bố", en: "Publish")
            ),
        ],
        "glitch": [
            TipSetupItem(
                title: L10n(vi: "Trạng thái Terraform", en: "Terraform state"),
                status: L10n(vi: "Backend S3 · đã khoá", en: "S3 backend · locked"),
                state: .done, actionLabel: nil
            ),
            TipSetupItem(
                title: L10n(vi: "Pipeline CI", en: "CI pipeline"),
                status: L10n(vi: "Trung bình 14m — vượt mức 10m", en: "Avg 14m — over 10m budget"),
                state: .warning, actionLabel: L10n(vi: "Profile", en: "Profile")
            ),
            TipSetupItem(
                title: L10n(vi: "Runbook on-call", en: "On-call runbook"),
                status: L10n(vi: "Trống · không có kịch bản sự cố", en: "Empty · no incident playbook"),
                state: .missing, actionLabel: L10n(vi: "Viết", en: "Write")
            ),
            TipSetupItem(
                title: L10n(vi: "Lịch diễn tập chaos", en: "Chaos drill schedule"),
                status: L10n(vi: "Diễn tập gần nhất: chưa từng", en: "Last drill: never"),
                state: .missing, actionLabel: L10n(vi: "Lên kế hoạch", en: "Plan")
            ),
        ],
        "byte": [
            TipSetupItem(
                title: L10n(vi: "Theo dõi thí nghiệm", en: "Experiment tracker"),
                status: L10n(vi: "MLflow · ghi nhận 23 lần chạy", en: "MLflow · 23 runs logged"),
                state: .done, actionLabel: nil
            ),
            TipSetupItem(
                title: L10n(vi: "Versioning dữ liệu", en: "Data versioning"),
                status: L10n(vi: "DVC cũ · commit gần nhất 9 ngày trước", en: "DVC stale · last commit 9d ago"),
                state: .warning, actionLabel: L10n(vi: "Snapshot lại", en: "Re-snapshot")
            ),
            TipSetupItem(
                title: L10n(vi: "Feature store", en: "Feature store"),
                status: L10n(vi: "Feature bị tính lại theo từng notebook", en: "Features re-derived per notebook"),
                state: .missing, actionLabel: L10n(vi: "Tập trung hoá", en: "Centralize")
            ),
            TipSetupItem(
                title: L10n(vi: "Giám sát model", en: "Model monitoring"),
                status: L10n(vi: "Chưa có alert về drift trên prod", en: "No drift alerts in prod"),
                state: .missing, actionLabel: L10n(vi: "Nối alert", en: "Wire alerts")
            ),
        ],
        "null": [
            TipSetupItem(
                title: L10n(vi: "Crashlytics", en: "Crashlytics"),
                status: L10n(vi: "Đã kết nối · 99.7% không crash", en: "Connected · 99.7% crash-free"),
                state: .done, actionLabel: nil
            ),
            TipSetupItem(
                title: L10n(vi: "Ngân sách kích thước app", en: "App size budget"),
                status: L10n(vi: "82MB — vượt ngân sách 8MB", en: "82MB — 8MB over budget"),
                state: .warning, actionLabel: L10n(vi: "Cắt giảm", en: "Trim")
            ),
            TipSetupItem(
                title: L10n(vi: "Audit tác vụ nền", en: "Background task audit"),
                status: L10n(vi: "Chưa đo mức tiêu hao", en: "No drain measurement"),
                state: .missing, actionLabel: L10n(vi: "Đo lường", en: "Measure")
            ),
            TipSetupItem(
                title: L10n(vi: "Lớp cache offline", en: "Offline cache layer"),
                status: L10n(vi: "Chiến lược cache còn trống", en: "Empty cache strategy"),
                state: .missing, actionLabel: L10n(vi: "Định nghĩa", en: "Define")
            ),
        ],
    ]

    // MARK: - Reading pool per pet (expanded, tagged for project matching)

    static let tipReadingPool: [String: [TipReadingItem]] = [

        // ── Crash — Backend Dev ──────────────────────────────────────────
        "crash": [
            TipReadingItem(
                title: L10n(vi: "Designing Data-Intensive Applications", en: "Designing Data-Intensive Applications"),
                author: "Martin Kleppmann",
                kind: L10n(vi: "Sách · 624 trang", en: "Book · 624 pages"),
                why: L10n(
                    vi: "Chương 5–7 về replication & consistency là nền tảng mọi backend đứng trên đó.",
                    en: "Chapters 5–7 on replication & consistency are the foundation every backend ships on."
                ),
                url: "https://dataintensive.net",
                tags: [.nodeBackend, .database, .api]
            ),
            TipReadingItem(
                title: L10n(vi: "The Twelve-Factor App", en: "The Twelve-Factor App"),
                author: "12factor.net",
                kind: L10n(vi: "Bài luận · 30 phút", en: "Essay · 30 min"),
                why: L10n(
                    vi: "Kỷ luật vận hành đứng vững qua mọi stack. Đọc lại mỗi năm một lần.",
                    en: "Operational discipline that holds up across every stack. Re-read once a year."
                ),
                url: "https://12factor.net",
                tags: [.docker, .ci, .nodeBackend, .goLang]
            ),
            TipReadingItem(
                title: L10n(vi: "Firebase in Production", en: "Firebase in Production"),
                author: "Firebase Docs",
                kind: L10n(vi: "Hướng dẫn · 45 phút", en: "Guide · 45 min"),
                why: L10n(
                    vi: "Security rules, composite indexes, offline persistence — ba thứ ai cũng bỏ qua cho đến khi cháy.",
                    en: "Security rules, composite indexes, offline persistence — three things everyone skips until it burns."
                ),
                url: "https://firebase.google.com/docs/firestore/best-practices",
                tags: [.firebase, .mobile, .swiftUI]
            ),
            TipReadingItem(
                title: L10n(vi: "Server-Side Swift with Vapor", en: "Server-Side Swift with Vapor"),
                author: "raywenderlich.com",
                kind: L10n(vi: "Loạt bài · 10 bài", en: "Series · 10 tutorials"),
                why: L10n(
                    vi: "Backend bằng chính ngôn ngữ bạn đang dùng. Ít context-switch hơn.",
                    en: "Backend in the same language you already use. Less context-switching."
                ),
                url: "https://www.kodeco.com/books/server-side-swift-with-vapor",
                tags: [.swiftUI, .api]
            ),
            TipReadingItem(
                title: L10n(vi: "Node.js Best Practices", en: "Node.js Best Practices"),
                author: "Yoni Goldberg et al.",
                kind: L10n(vi: "Repo · 100+ mục", en: "Repo · 100+ items"),
                why: L10n(
                    vi: "Checklist thực chiến cho production Node. Đi thẳng vào error handling và security.",
                    en: "Battle-tested production Node checklist. Jump to error handling and security."
                ),
                url: "https://github.com/goldbergyoni/nodebestpractices",
                tags: [.nodeBackend, .api, .testing]
            ),
            TipReadingItem(
                title: L10n(vi: "Build APIs You Won't Hate", en: "Build APIs You Won't Hate"),
                author: "Phil Sturgeon",
                kind: L10n(vi: "Sách · 260 trang", en: "Book · 260 pages"),
                why: L10n(
                    vi: "Từ naming convention đến versioning. Thực tế hơn bất kỳ spec nào.",
                    en: "From naming conventions to versioning. More practical than any spec."
                ),
                url: "https://apisyouwonthate.com/books/build-apis-you-wont-hate/",
                tags: [.api, .nodeBackend, .goLang, .python]
            ),
        ],

        // ── Nova — Frontend Dev ──────────────────────────────────────────
        "nova": [
            TipReadingItem(
                title: L10n(vi: "Refactoring UI", en: "Refactoring UI"),
                author: "Steve Schoger & Adam Wathan",
                kind: L10n(vi: "Sách · 220 trang", en: "Book · 220 pages"),
                why: L10n(
                    vi: "Gu thẩm mỹ thực tiễn cho engineer. Giải quyết 90% các khoảnh khắc \"sao UI mình trông kỳ vậy\".",
                    en: "Practical taste for engineers. Solves 90% of 'why does my UI look off' moments."
                ),
                url: "https://www.refactoringui.com",
                tags: [.react, .vue, .angular]
            ),
            TipReadingItem(
                title: L10n(vi: "Inclusive Components", en: "Inclusive Components"),
                author: "Heydon Pickering",
                kind: L10n(vi: "Loạt bài · 12 bài luận", en: "Series · 12 essays"),
                why: L10n(
                    vi: "Accessible từ gốc. Mỗi bài luận là một component được làm đúng từ đầu đến cuối.",
                    en: "Accessible by default. Each essay is one component done right end-to-end."
                ),
                url: "https://inclusive-components.design",
                tags: [.react, .vue, .angular]
            ),
            TipReadingItem(
                title: L10n(vi: "SwiftUI Thinking", en: "SwiftUI Thinking"),
                author: "objc.io",
                kind: L10n(vi: "Sách · 350 trang", en: "Book · 350 pages"),
                why: L10n(
                    vi: "Không chỉ API — mà là cách suy nghĩ bằng declarative UI. Layout, state, animation từ gốc.",
                    en: "Not just API — but thinking in declarative UI. Layout, state, animation from first principles."
                ),
                url: "https://www.objc.io/books/thinking-in-swiftui/",
                tags: [.swiftUI]
            ),
            TipReadingItem(
                title: L10n(vi: "React Patterns", en: "React Patterns"),
                author: "reactpatterns.com",
                kind: L10n(vi: "Tham khảo · 15 phút", en: "Reference · 15 min"),
                why: L10n(
                    vi: "Compound components, render props, hooks — các pattern giúp code frontend sạch sẽ.",
                    en: "Compound components, render props, hooks — patterns that keep frontend code clean."
                ),
                url: "https://www.patterns.dev/react",
                tags: [.react]
            ),
            TipReadingItem(
                title: L10n(vi: "Testing Library Guiding Principles", en: "Testing Library Guiding Principles"),
                author: "Kent C. Dodds",
                kind: L10n(vi: "Bài luận · 10 phút", en: "Essay · 10 min"),
                why: L10n(
                    vi: "Test cách người dùng thật sử dụng, không phải test chi tiết cài đặt. Thay đổi cách viết test.",
                    en: "Test how real users interact, not implementation details. Changes how you write tests."
                ),
                url: "https://testing-library.com/docs/guiding-principles",
                tags: [.react, .vue, .testing]
            ),
            TipReadingItem(
                title: L10n(vi: "Human Interface Guidelines", en: "Human Interface Guidelines"),
                author: "Apple",
                kind: L10n(vi: "Tham khảo · đọc khi cần", en: "Reference · read as needed"),
                why: L10n(
                    vi: "Tiêu chuẩn mà Apple dùng khi review app. Navigation, controls, layout — tất cả ở đây.",
                    en: "The standard Apple uses to review your app. Navigation, controls, layout — it's all here."
                ),
                url: "https://developer.apple.com/design/human-interface-guidelines/",
                tags: [.swiftUI, .uiKit, .mobile]
            ),
        ],

        // ── Luna — Designer / UX-UI ─────────────────────────────────────
        "luna": [
            TipReadingItem(
                title: L10n(vi: "The Design of Everyday Things", en: "The Design of Everyday Things"),
                author: "Don Norman",
                kind: L10n(vi: "Sách · 368 trang", en: "Book · 368 pages"),
                why: L10n(
                    vi: "Affordance và signifier — ngôn ngữ giải thích vì sao một thứ thấy đúng hay sai.",
                    en: "Affordances and signifiers — the language of why things feel right or wrong."
                ),
                url: "https://www.nngroup.com/books/design-everyday-things-revised/"
            ),
            TipReadingItem(
                title: L10n(vi: "The Humane Interface", en: "The Humane Interface"),
                author: "Jef Raskin",
                kind: L10n(vi: "Sách · 256 trang", en: "Book · 256 pages"),
                why: L10n(
                    vi: "Cognetics — thiết kế cho sự chú ý của con người, không chỉ cho mắt.",
                    en: "Cognetics — design for human attention, not just human eyes. Surprisingly current."
                ),
                url: "https://en.wikipedia.org/wiki/The_Humane_Interface"
            ),
            TipReadingItem(
                title: L10n(vi: "About Face", en: "About Face"),
                author: "Alan Cooper",
                kind: L10n(vi: "Sách · 720 trang", en: "Book · 720 pages"),
                why: L10n(
                    vi: "Persona, goal-directed design, interaction patterns. Nặng nhưng đáng đọc chương 1-8.",
                    en: "Personas, goal-directed design, interaction patterns. Dense but chapters 1-8 are gold."
                ),
                url: "https://www.wiley.com/en-us/About+Face%3A+The+Essentials+of+Interaction+Design%2C+4th+Edition-p-9781118766576",
                tags: [.mobile, .swiftUI, .react]
            ),
            TipReadingItem(
                title: L10n(vi: "Atomic Design", en: "Atomic Design"),
                author: "Brad Frost",
                kind: L10n(vi: "Sách · miễn phí online", en: "Book · free online"),
                why: L10n(
                    vi: "Atoms → molecules → organisms. Tư duy hệ thống cho design system.",
                    en: "Atoms → molecules → organisms. Systems thinking for design systems."
                ),
                url: "https://atomicdesign.bradfrost.com",
                tags: [.react, .vue, .angular]
            ),
            TipReadingItem(
                title: L10n(vi: "iOS Design Themes", en: "iOS Design Themes"),
                author: "Apple HIG",
                kind: L10n(vi: "Tham khảo · 20 phút", en: "Reference · 20 min"),
                why: L10n(
                    vi: "Clarity, deference, depth — ba nguyên tắc nền tảng cho mọi app Apple.",
                    en: "Clarity, deference, depth — three principles that ground every Apple app."
                ),
                url: "https://developer.apple.com/design/human-interface-guidelines/designing-for-ios",
                tags: [.swiftUI, .uiKit, .mobile]
            ),
            TipReadingItem(
                title: L10n(vi: "Material Design Guidelines", en: "Material Design Guidelines"),
                author: "Google",
                kind: L10n(vi: "Tham khảo · đọc khi cần", en: "Reference · read as needed"),
                why: L10n(
                    vi: "Elevation, motion, color system — nền tảng của Android UI và web apps hiện đại.",
                    en: "Elevation, motion, color system — foundation of Android UI and modern web apps."
                ),
                url: "https://m3.material.io",
                tags: [.react, .vue, .angular, .mobile]
            ),
        ],

        // ── Sage — Product Owner ─────────────────────────────────────────
        "sage": [
            TipReadingItem(
                title: L10n(vi: "Inspired", en: "Inspired"),
                author: "Marty Cagan",
                kind: L10n(vi: "Sách · 368 trang", en: "Book · 368 pages"),
                why: L10n(
                    vi: "Cách các đội sản phẩm thực sự giỏi quyết định xây cái gì. Kinh thánh chống lại nhà-máy-tính-năng.",
                    en: "How great product teams really decide what to build. The anti-feature-factory bible."
                ),
                url: "https://www.svpg.com/inspired-how-to-create-tech-products-customers-love/"
            ),
            TipReadingItem(
                title: L10n(vi: "Continuous Discovery Habits", en: "Continuous Discovery Habits"),
                author: "Teresa Torres",
                kind: L10n(vi: "Sách · 240 trang", en: "Book · 240 pages"),
                why: L10n(
                    vi: "Biến discovery thành thói quen tuần, không phải sự kiện quý. Khung làm việc cụ thể.",
                    en: "Make discovery a weekly habit, not a quarterly event. Concrete framework."
                ),
                url: "https://www.producttalk.org/2021/05/continuous-discovery-habits/"
            ),
            TipReadingItem(
                title: L10n(vi: "Shape Up", en: "Shape Up"),
                author: "Basecamp (Ryan Singer)",
                kind: L10n(vi: "Sách · miễn phí online", en: "Book · free online"),
                why: L10n(
                    vi: "Thay thế Scrum bằng 6-week cycle. Đặc biệt phù hợp đội nhỏ ship nhanh.",
                    en: "Replaces Scrum with 6-week cycles. Especially fits small teams shipping fast."
                ),
                url: "https://basecamp.com/shapeup",
                tags: [.swiftUI, .react, .mobile]
            ),
            TipReadingItem(
                title: L10n(vi: "Lean Analytics", en: "Lean Analytics"),
                author: "Croll & Yoskovitz",
                kind: L10n(vi: "Sách · 440 trang", en: "Book · 440 pages"),
                why: L10n(
                    vi: "Chọn đúng metric cho đúng giai đoạn. Không gì sai bằng tối ưu sai con số.",
                    en: "Right metric for the right stage. Nothing wastes time like optimizing the wrong number."
                ),
                url: "https://leananalyticsbook.com",
                tags: [.api, .database, .firebase]
            ),
            TipReadingItem(
                title: L10n(vi: "The Mom Test", en: "The Mom Test"),
                author: "Rob Fitzpatrick",
                kind: L10n(vi: "Sách · 130 trang", en: "Book · 130 pages"),
                why: L10n(
                    vi: "Hỏi khách hàng mà không tự lừa mình. Ngắn, thực tế, đọc một buổi chiều.",
                    en: "Talk to customers without fooling yourself. Short, practical, one-afternoon read."
                ),
                url: "https://www.momtestbook.com"
            ),
            TipReadingItem(
                title: L10n(vi: "Jobs to be Done", en: "Jobs to be Done"),
                author: "Anthony Ulwick",
                kind: L10n(vi: "Sách · 300 trang", en: "Book · 300 pages"),
                why: L10n(
                    vi: "Người dùng không mua sản phẩm — họ thuê giải pháp. Lý thuyết nền tảng cho product.",
                    en: "Users don't buy products — they hire solutions. The foundational product theory."
                ),
                url: "https://jobs-to-be-done-book.com"
            ),
        ],

        // ── Glitch — DevOps / Infra ──────────────────────────────────────
        "glitch": [
            TipReadingItem(
                title: L10n(vi: "Site Reliability Engineering", en: "Site Reliability Engineering"),
                author: "Google SRE Team",
                kind: L10n(vi: "Sách · 528 trang", en: "Book · 528 pages"),
                why: L10n(
                    vi: "Kinh thánh SRE. Đọc trước phần error budget và toil. Phần còn lại đọc lướt sau.",
                    en: "The SRE bible. Skip to error budgets and toil first. Skim the rest later."
                ),
                url: "https://sre.google/sre-book/table-of-contents/",
                tags: [.docker, .ci, .nodeBackend, .goLang]
            ),
            TipReadingItem(
                title: L10n(vi: "The Phoenix Project", en: "The Phoenix Project"),
                author: "Kim, Behr & Spafford",
                kind: L10n(vi: "Tiểu thuyết · 432 trang", en: "Novel · 432 pages"),
                why: L10n(
                    vi: "DevOps kể dưới dạng câu chuyện. Đọc một lần, bạn sẽ nhận ra cùng mẫu hình ở mọi công ty.",
                    en: "DevOps as a story. Read it once and you'll spot the pattern in every org."
                ),
                url: "https://itrevolution.com/product/the-phoenix-project/"
            ),
            TipReadingItem(
                title: L10n(vi: "Docker Deep Dive", en: "Docker Deep Dive"),
                author: "Nigel Poulton",
                kind: L10n(vi: "Sách · 260 trang", en: "Book · 260 pages"),
                why: L10n(
                    vi: "Từ image đến orchestration. Thực hành nhiều hơn lý thuyết.",
                    en: "From images to orchestration. More hands-on than theory."
                ),
                url: "https://nigelpoulton.com/books/",
                tags: [.docker, .ci]
            ),
            TipReadingItem(
                title: L10n(vi: "GitHub Actions in Action", en: "GitHub Actions in Action"),
                author: "GitHub Docs",
                kind: L10n(vi: "Hướng dẫn · 30 phút", en: "Guide · 30 min"),
                why: L10n(
                    vi: "CI/CD bắt đầu từ đây. Đủ cho test, build, deploy tự động.",
                    en: "CI/CD starts here. Enough for automated test, build, deploy."
                ),
                url: "https://docs.github.com/en/actions/learn-github-actions",
                tags: [.ci, .testing]
            ),
            TipReadingItem(
                title: L10n(vi: "Xcode Cloud", en: "Xcode Cloud"),
                author: "Apple Developer",
                kind: L10n(vi: "Hướng dẫn · 20 phút", en: "Guide · 20 min"),
                why: L10n(
                    vi: "CI/CD được tích hợp sẵn cho dự án Swift. TestFlight deploy tự động.",
                    en: "Built-in CI/CD for Swift projects. Automated TestFlight deployments."
                ),
                url: "https://developer.apple.com/xcode-cloud/",
                tags: [.swiftUI, .uiKit, .ci, .mobile]
            ),
            TipReadingItem(
                title: L10n(vi: "Monitoring with Prometheus & Grafana", en: "Monitoring with Prometheus & Grafana"),
                author: "Prometheus Docs",
                kind: L10n(vi: "Hướng dẫn · 1 giờ", en: "Guide · 1 hour"),
                why: L10n(
                    vi: "Không monitor = không biết gì đang xảy ra. Bắt đầu đo trước khi cần debug.",
                    en: "No monitoring = flying blind. Start measuring before you need to debug."
                ),
                url: "https://prometheus.io/docs/introduction/overview/",
                tags: [.docker, .nodeBackend, .goLang]
            ),
        ],

        // ── Byte — AI/ML ─────────────────────────────────────────────────
        "byte": [
            TipReadingItem(
                title: L10n(vi: "Designing Machine Learning Systems", en: "Designing Machine Learning Systems"),
                author: "Chip Huyen",
                kind: L10n(vi: "Sách · 386 trang", en: "Book · 386 pages"),
                why: L10n(
                    vi: "ML đầu cuối trong production. Bao trùm phần các khoá học bỏ qua — drift, monitoring, ops.",
                    en: "End-to-end ML in production. Covers what courses skip — drift, monitoring, ops."
                ),
                url: "https://www.oreilly.com/library/view/designing-machine-learning/9781098107956/",
                tags: [.python, .docker, .database]
            ),
            TipReadingItem(
                title: L10n(vi: "Hidden Technical Debt in ML Systems", en: "Hidden Technical Debt in ML Systems"),
                author: "Sculley et al.",
                kind: L10n(vi: "Bài báo · 9 trang", en: "Paper · 9 pages"),
                why: L10n(
                    vi: "Đọc lại mỗi sáu tháng. Mỗi lần một phần khác lại bắt đầu thấm.",
                    en: "Re-read every six months. Each time another section starts to land."
                ),
                url: "https://papers.nips.cc/paper/2015/hash/86df7dcfd896fcaf2674f757a2463eba-Abstract.html",
                tags: [.python]
            ),
            TipReadingItem(
                title: L10n(vi: "Prompt Engineering Guide", en: "Prompt Engineering Guide"),
                author: "DAIR.AI",
                kind: L10n(vi: "Tham khảo · đọc khi cần", en: "Reference · read as needed"),
                why: L10n(
                    vi: "Tổng hợp mọi kỹ thuật prompt engineering. Cập nhật thường xuyên.",
                    en: "Comprehensive prompt engineering techniques. Updated regularly."
                ),
                url: "https://www.promptingguide.ai",
                tags: [.python, .nodeBackend, .api]
            ),
            TipReadingItem(
                title: L10n(vi: "Core ML for Swift Developers", en: "Core ML for Swift Developers"),
                author: "Apple Developer",
                kind: L10n(vi: "Hướng dẫn · 30 phút", en: "Guide · 30 min"),
                why: L10n(
                    vi: "Chạy model trên thiết bị — không cần server. Tích hợp trực tiếp vào SwiftUI.",
                    en: "Run models on-device — no server needed. Integrates directly into SwiftUI."
                ),
                url: "https://developer.apple.com/machine-learning/core-ml/",
                tags: [.swiftUI, .mobile]
            ),
            TipReadingItem(
                title: L10n(vi: "Building LLM Apps", en: "Building LLM Apps"),
                author: "Anthropic Docs",
                kind: L10n(vi: "Hướng dẫn · 1 giờ", en: "Guide · 1 hour"),
                why: L10n(
                    vi: "Từ API call đến RAG pipeline. Thực tế hơn mọi tutorial YouTube.",
                    en: "From API calls to RAG pipelines. More practical than any YouTube tutorial."
                ),
                url: "https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/overview",
                tags: [.nodeBackend, .python, .api, .firebase]
            ),
            TipReadingItem(
                title: L10n(vi: "FastAI Practical Deep Learning", en: "FastAI Practical Deep Learning"),
                author: "Jeremy Howard",
                kind: L10n(vi: "Khoá học · miễn phí", en: "Course · free"),
                why: L10n(
                    vi: "Top-down: bắt đầu bằng kết quả, đào sâu dần. Cách nhanh nhất từ zero đến train model.",
                    en: "Top-down: start with results, dig deeper. Fastest path from zero to training models."
                ),
                url: "https://course.fast.ai",
                tags: [.python]
            ),
        ],

        // ── Null — Mobile / Architecture ─────────────────────────────────
        "null": [
            TipReadingItem(
                title: L10n(vi: "iOS App Architecture", en: "iOS App Architecture"),
                author: "Chris Eidhof et al.",
                kind: L10n(vi: "Sách · 232 trang", en: "Book · 232 pages"),
                why: L10n(
                    vi: "Các pattern sống sót qua app 5+ năm. MVVM, coordinator, DI trong thực tế.",
                    en: "Patterns that survive 5+ year apps. MVVM, coordinators, DI in real practice."
                ),
                url: "https://www.objc.io/books/app-architecture/",
                tags: [.swiftUI, .uiKit, .mobile]
            ),
            TipReadingItem(
                title: L10n(vi: "Mobile UX Guidelines", en: "Mobile UX Guidelines"),
                author: "Nielsen Norman Group",
                kind: L10n(vi: "Loạt bài · ~20 bài luận", en: "Series · ~20 essays"),
                why: L10n(
                    vi: "Vùng chạm, cử chỉ, accessibility trên màn hình nhỏ. Tài liệu tham khảo nên bookmark.",
                    en: "Touch targets, gestures, accessibility on small screens. Bookmarkable reference."
                ),
                url: "https://www.nngroup.com/topic/mobile-ux/",
                tags: [.mobile, .swiftUI, .uiKit]
            ),
            TipReadingItem(
                title: L10n(vi: "Clean Architecture", en: "Clean Architecture"),
                author: "Robert C. Martin",
                kind: L10n(vi: "Sách · 432 trang", en: "Book · 432 pages"),
                why: L10n(
                    vi: "Dependency rule, boundaries, use cases. Nguyên tắc sống được qua mọi framework.",
                    en: "Dependency rule, boundaries, use cases. Principles that survive any framework."
                ),
                url: "https://www.oreilly.com/library/view/clean-architecture-a/9780134494272/",
                tags: [.nodeBackend, .goLang, .python, .swiftUI]
            ),
            TipReadingItem(
                title: L10n(vi: "Swift Concurrency by Example", en: "Swift Concurrency by Example"),
                author: "Paul Hudson",
                kind: L10n(vi: "Loạt bài · miễn phí", en: "Series · free"),
                why: L10n(
                    vi: "async/await, actors, structured concurrency. Mỗi pattern có ví dụ chạy được.",
                    en: "async/await, actors, structured concurrency. Each pattern with runnable examples."
                ),
                url: "https://www.hackingwithswift.com/swift/5.5/async-await",
                tags: [.swiftUI, .mobile]
            ),
            TipReadingItem(
                title: L10n(vi: "The Composable Architecture", en: "The Composable Architecture"),
                author: "Point-Free",
                kind: L10n(vi: "Thư viện + video", en: "Library + video series"),
                why: L10n(
                    vi: "State management cho SwiftUI mà scale được. Phức tạp nhưng đáng học.",
                    en: "SwiftUI state management that scales. Complex but worth learning."
                ),
                url: "https://github.com/pointfreeco/swift-composable-architecture",
                tags: [.swiftUI, .mobile, .testing]
            ),
            TipReadingItem(
                title: L10n(vi: "Design Patterns in Swift", en: "Design Patterns in Swift"),
                author: "Refactoring.Guru",
                kind: L10n(vi: "Tham khảo · đọc khi cần", en: "Reference · read as needed"),
                why: L10n(
                    vi: "22 pattern cổ điển với ví dụ Swift. Bookmarkable.",
                    en: "22 classic patterns with Swift examples. Bookmarkable."
                ),
                url: "https://refactoring.guru/design-patterns/swift",
                tags: [.swiftUI, .uiKit]
            ),

            // ── Domain-specific picks (surface only for matching domains) ──
            TipReadingItem(
                title: L10n(vi: "The Psychology of Money", en: "The Psychology of Money"),
                author: "Morgan Housel",
                kind: L10n(vi: "Sách · 256 trang", en: "Book · 256 pages"),
                why: L10n(
                    vi: "App tài chính là thiết kế cho cảm xúc, không chỉ con số. Hiểu người dùng nghĩ gì về tiền.",
                    en: "A money app designs for emotion, not just numbers — understand how people actually feel about money."
                ),
                url: nil,
                tags: [.swiftUI, .mobile],
                domains: [.finance]
            ),
            TipReadingItem(
                title: L10n(vi: "Atomic Habits", en: "Atomic Habits"),
                author: "James Clear",
                kind: L10n(vi: "Sách · 320 trang", en: "Book · 320 pages"),
                why: L10n(
                    vi: "App sức khỏe/thói quen sống nhờ vòng lặp thói quen — cue, streak, phần thưởng. Đây là sách gốc.",
                    en: "Health/habit apps live on the habit loop — cue, streak, reward. This is the source playbook."
                ),
                url: "https://jamesclear.com/atomic-habits",
                tags: [.swiftUI, .mobile],
                domains: [.health]
            ),
            TipReadingItem(
                title: L10n(vi: "E-Commerce UX Research", en: "E-Commerce UX Research"),
                author: "Baymard Institute",
                kind: L10n(vi: "Nghiên cứu · tham khảo", en: "Research · reference"),
                why: L10n(
                    vi: "Hàng nghìn bài test usability về giỏ hàng & checkout. Đừng phát minh lại cách thanh toán.",
                    en: "Thousands of usability tests on cart & checkout. Don't reinvent how people pay."
                ),
                url: "https://baymard.com",
                tags: [.swiftUI, .mobile],
                domains: [.ecommerce]
            ),
            TipReadingItem(
                title: L10n(vi: "The Art of Game Design", en: "The Art of Game Design"),
                author: "Jesse Schell",
                kind: L10n(vi: "Sách · 600 trang", en: "Book · 600 pages"),
                why: L10n(
                    vi: "Bộ 'lenses' để nghĩ về vui, nhịp độ, và phần thưởng. Nền tảng cho mọi app có yếu tố game.",
                    en: "The 'lenses' framework for fun, pacing, and reward — the base for anything game-like."
                ),
                url: nil,
                tags: [.swiftUI, .mobile],
                domains: [.games]
            ),
            TipReadingItem(
                title: L10n(vi: "Getting Things Done", en: "Getting Things Done"),
                author: "David Allen",
                kind: L10n(vi: "Sách · 352 trang", en: "Book · 352 pages"),
                why: L10n(
                    vi: "Mô hình capture → organize → review mà mọi app todo/planner đang hiện thực hóa.",
                    en: "The capture → organize → review model that every todo/planner app is really implementing."
                ),
                url: nil,
                tags: [.swiftUI, .mobile],
                domains: [.productivity]
            ),
        ],
    ]

    // MARK: - Business / Marketing reading pool (universal, stage-matched)

    /// Pet-agnostic books on validation, positioning, pricing, launch, and
    /// growth. Unlike `tipReadingPool` (matched by tech stack / domain), these
    /// are matched by the project's lifecycle **stage** — so a project at
    /// `.idea` sees validation books, and one at `.growth` sees retention books.
    /// Surfaced alongside the pet's tech readings in the project folder.
    static let businessReadingPool: [TipReadingItem] = [
        TipReadingItem(
            title: L10n(vi: "The Mom Test", en: "The Mom Test"),
            author: "Rob Fitzpatrick",
            kind: L10n(vi: "Sách · 130 trang", en: "Book · 130 pages"),
            why: L10n(
                vi: "Cách nói chuyện với người dùng để học sự thật, không phải lời khen. Đọc trước khi viết thêm dòng code nào.",
                en: "How to talk to users and learn the truth instead of compliments. Read it before writing more code."
            ),
            url: "http://momtestbook.com/",
            stages: [.idea, .building],
            pillars: [.business]
        ),
        TipReadingItem(
            title: L10n(vi: "The Lean Startup", en: "The Lean Startup"),
            author: "Eric Ries",
            kind: L10n(vi: "Sách · 336 trang", en: "Book · 336 pages"),
            why: L10n(
                vi: "Vòng lặp build–measure–learn: ship nhỏ, đo thật, học nhanh trước khi đốt nhiều thời gian.",
                en: "The build–measure–learn loop: ship small, measure real, learn fast before burning months."
            ),
            url: "http://theleanstartup.com/",
            stages: [.idea, .building],
            pillars: [.business]
        ),
        TipReadingItem(
            title: L10n(vi: "Obviously Awesome", en: "Obviously Awesome"),
            author: "April Dunford",
            kind: L10n(vi: "Sách · 200 trang", en: "Book · 200 pages"),
            why: L10n(
                vi: "Định vị sản phẩm: vì sao 'nó là gì' quan trọng hơn 'nó làm gì'. Nền cho mọi câu marketing.",
                en: "Positioning: why 'what it is' matters more than 'what it does.' The base for every marketing line."
            ),
            url: "https://www.obviouslyawesome.com/",
            stages: [.building, .launch],
            pillars: [.business]
        ),
        TipReadingItem(
            title: L10n(vi: "$100M Offers", en: "$100M Offers"),
            author: "Alex Hormozi",
            kind: L10n(vi: "Sách · 170 trang", en: "Book · 170 pages"),
            why: L10n(
                vi: "Cách dựng một lời chào hàng hấp dẫn đến mức khó từ chối — định giá, bundle, và giá trị cảm nhận.",
                en: "How to build an offer so good people feel stupid saying no — pricing, bundling, perceived value."
            ),
            url: "https://www.acquisition.com/books",
            stages: [.building, .launch],
            pillars: [.business]
        ),
        TipReadingItem(
            title: L10n(vi: "Make", en: "Make"),
            author: "Pieter Levels",
            kind: L10n(vi: "Hướng dẫn · 250 trang", en: "Guide · 250 pages"),
            why: L10n(
                vi: "Sổ tay của indie maker: ship nhanh, kiếm tiền sớm, làm một mình. Rất sát với chỉ-một-người-build.",
                en: "The indie maker's handbook: ship fast, charge early, do it solo. Tailored to building alone."
            ),
            url: "https://makebook.io/",
            stages: [.idea, .building, .launch],
            pillars: [.business, .growth]
        ),
        TipReadingItem(
            title: L10n(vi: "Traction", en: "Traction"),
            author: "Gabriel Weinberg & Justin Mares",
            kind: L10n(vi: "Sách · 240 trang", en: "Book · 240 pages"),
            why: L10n(
                vi: "19 kênh tăng trưởng và khung 'bullseye' để tìm kênh nào thật sự hiệu quả cho bạn.",
                en: "19 growth channels and the 'bullseye' framework for finding which one actually works for you."
            ),
            url: "https://www.goodreads.com/book/show/22091581-traction",
            stages: [.launch, .growth],
            pillars: [.growth]
        ),
        TipReadingItem(
            title: L10n(vi: "Do Things That Don't Scale", en: "Do Things That Don't Scale"),
            author: "Paul Graham",
            kind: L10n(vi: "Bài luận · 20 phút", en: "Essay · 20 min"),
            why: L10n(
                vi: "Vì sao những người dùng đầu tiên đáng để bạn tự tay đi tìm và chăm sóc từng người.",
                en: "Why your first users are worth recruiting and delighting one by one, by hand."
            ),
            url: "https://paulgraham.com/ds.html",
            stages: [.launch],
            pillars: [.growth]
        ),
        TipReadingItem(
            title: L10n(vi: "This Is Marketing", en: "This Is Marketing"),
            author: "Seth Godin",
            kind: L10n(vi: "Sách · 288 trang", en: "Book · 288 pages"),
            why: L10n(
                vi: "Marketing là phục vụ một nhóm nhỏ nhất khả thi thật giỏi — không phải hét to với tất cả mọi người.",
                en: "Marketing as serving the smallest viable audience well — not shouting at everyone."
            ),
            url: "https://seths.blog/2018/11/this-is-marketing/",
            stages: [.launch, .growth],
            pillars: [.growth]
        ),
        TipReadingItem(
            title: L10n(vi: "Hooked", en: "Hooked"),
            author: "Nir Eyal",
            kind: L10n(vi: "Sách · 256 trang", en: "Book · 256 pages"),
            why: L10n(
                vi: "Mô hình trigger → action → reward → investment để xây thói quen giữ người dùng quay lại.",
                en: "The trigger → action → reward → investment model for building habits that bring users back."
            ),
            url: "https://www.nirandfar.com/hooked/",
            stages: [.growth],
            pillars: [.growth]
        ),
    ]

    // MARK: - Pet note bottom (1 string per pet)

    static let tipPetNoteByPet: [String: L10n] = [
        "crash":  L10n(
            vi: "Hôm qua bắt được hai endpoint không có idempotency key. Hôm nay chưa cắn ta, nhưng đến lúc scale lên là cắn. Đáng dành 30 phút dọn lại.",
            en: "Caught two endpoints without idempotency keys yesterday. Won't bite us today, will bite us at scale. Worth a 30-min sweep."
        ),
        "nova":   L10n(
            vi: "Tuần này hai component ship đi mà không có loading state. Người dùng thấy màn hình trắng một nhịp trước khi nội dung hiện. Mỗi cái sửa nhanh thôi.",
            en: "Two components shipped without loading states this week. Users see blank screens for a beat before content. Quick wins on each."
        ),
        "luna":   L10n(
            vi: "Tôi thích empty state mới trên dashboard. Còn nút reset CTA trong settings — màu, độ đậm, vị trí đều đang nói 'đừng chạm tôi'. Đáng để xem lại một lượt.",
            en: "I love the new empty state on the dashboard. The reset CTA in settings, though — color, weight, position all say 'don't tap me.' Worth a pass."
        ),
        "sage":   L10n(
            vi: "Ba trong năm thứ 'phải có' gần nhất không ship được, mà cũng không ai thấy thiếu. Đáng để retro xem tiêu chuẩn ấy được đặt thế nào — và bởi ai.",
            en: "Three of the last five 'must-haves' didn't ship and weren't missed. Worth a retro on how the bar gets set — and by whom."
        ),
        "glitch": L10n(
            vi: "Tuần này ba lần deploy cần chạm tay. Đó là ba bug đang chờ trong khoảng cách giữa 'chạy trên staging' và 'chạy trên prod'.",
            en: "Three deploys this week needed manual touch. That's three bugs waiting in the gap between 'works on staging' and 'works on prod'."
        ),
        "byte":   L10n(
            vi: "Tuần này hai notebook ship đi mà không cố định seed. Kết quả không tái tạo được. Phát hiện của bạn-trong-quá-khứ đã chết cho đến khi bạn chạy lại được.",
            en: "Two notebooks shipped without a fixed seed this week. Results aren't reproducible. Past-you's findings are dead until you can re-run them."
        ),
        "null":   L10n(
            vi: "Tuần này xin quyền push ngay lần mở app đầu tiên — tỉ lệ đồng ý 11%. Thử đợi đến khi đã chứng minh giá trị; thường lên 4 lần.",
            en: "Push permission asked on first launch this week — consent rate 11%. Try waiting until value is proven; usually 4× lift."
        ),
    ]
}
