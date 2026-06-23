import Foundation

/// Deterministic, evidence-grounded copy for a milestone moment. Templated
/// client-side (not a model call) so the celebratory sentence can never drift
/// past what the data actually supports — the honesty bar from the spec. Pure,
/// so it's trivially testable.
enum MilestoneCopy {

    struct Text { let headline: String; let body: String }

    /// Build the headline + body for a risen trajectory. `body` weaves in the
    /// real `earlierGrowthCount` so the claim is anchored, not generic.
    static func text(for t: Trajectory, vietnamese: Bool) -> Text {
        let n = t.earlierGrowthCount
        switch AgencySignal.Signal(rawValue: t.signal.lowercased()) {
        case .verification:
            return vietnamese
                ? Text(headline: "Bạn đã bắt đầu kiểm tra kết quả của AI.",
                       body: "Lúc đầu, việc xem AI đã đổi gì rất dễ bị bỏ qua. Nó là điểm yếu trong \(n) buổi đầu của bạn. Hai tuần gần đây bạn đã đọc kỹ thay đổi và thử lại trước khi đi tiếp. Đó là một thay đổi thật trong cách bạn làm, không chỉ là thứ bạn làm ra.")
                : Text(headline: "You've started checking the AI's work.",
                       body: "When we started, checking what the AI changed was easy to skip. It came up as a growth edge in \(n) of your early sessions. Over the last two weeks you've been reading the diffs and testing before moving on. That's a real shift in how you build, not just what you built.")
        case .scoping:
            return vietnamese
                ? Text(headline: "Bạn đã biết chia việc thành những phần vừa cỡ.",
                       body: "Lúc đầu bạn hay yêu cầu quá nhiều thứ cùng lúc và mọi thứ rối lên. Nó là điểm yếu trong \(n) buổi đầu. Gần đây bạn chia việc thành các bước rõ ràng. Đó là một thay đổi thật trong cách bạn làm.")
                : Text(headline: "You've started breaking work into the right-size pieces.",
                       body: "Early on, you'd ask for a lot at once and things got tangled. It came up as a growth edge in \(n) of your early sessions. Lately you've been splitting work into clear steps and tackling them one at a time. That's a real shift in how you build.")
        case .prompting:
            return vietnamese
                ? Text(headline: "Cách bạn ra lệnh cho AI đã sắc hơn.",
                       body: "Lúc đầu các yêu cầu còn mơ hồ và phải thử vài lần. Nó là điểm yếu trong \(n) buổi đầu. Gần đây bạn mô tả rõ điều mình muốn ngay từ lần đầu. Đó là một thay đổi thật trong cách bạn làm việc với AI.")
                : Text(headline: "Your prompts have gotten sharper.",
                       body: "Early on, your asks were vague and took a few tries to land. It came up as a growth edge in \(n) of your early sessions. Lately you've been describing what you want clearly the first time. That's a real shift in how you work with AI.")
        case .direction:
            return vietnamese
                ? Text(headline: "Bạn đã biết dẫn dắt thay vì làm theo.",
                       body: "Lúc đầu bạn nhận bất cứ thứ gì AI đưa ra. Nó là điểm yếu trong \(n) buổi đầu. Gần đây bạn chủ động dẫn dắt và phản biện nó. Đó là một thay đổi thật trong cách bạn làm.")
                : Text(headline: "You've started steering, not just accepting.",
                       body: "Early on, you'd take whatever the AI produced. It came up as a growth edge in \(n) of your early sessions. Lately you've been directing it and pushing back when something's off. That's a real shift in how you build.")
        case .iteration:
            return vietnamese
                ? Text(headline: "Bạn xoay xở tốt hơn khi mọi thứ đi chệch.",
                       body: "Lúc đầu, một bước sai có thể làm bạn khựng lại. Nó là điểm yếu trong \(n) buổi đầu. Gần đây bạn tự điều chỉnh và gỡ bí một mình. Đó là một thay đổi thật trong cách bạn làm.")
                : Text(headline: "You've gotten better at recovering when things go sideways.",
                       body: "Early on, a wrong turn could stall you. It came up as a growth edge in \(n) of your early sessions. Lately you've been adjusting and getting unstuck on your own. That's a real shift in how you work.")
        case .context:
            return vietnamese
                ? Text(headline: "Bạn đã biết đưa đúng ngữ cảnh ngay từ đầu.",
                       body: "Lúc đầu AI hay trật vì thiếu đúng tệp. Nó là điểm yếu trong \(n) buổi đầu. Gần đây bạn chỉ cho nó đúng thứ quan trọng trước. Đó là một thay đổi thật trong cách bạn làm.")
                : Text(headline: "You've started giving the AI the right context up front.",
                       body: "Early on, the AI often missed because it lacked the right files. It came up as a growth edge in \(n) of your early sessions. Lately you've been pointing it at what matters first. That's a real shift in how you build.")
        case .none:
            return vietnamese
                ? Text(headline: "Bạn đã tiến bộ rõ trong cách làm việc với AI.",
                       body: "Một thói quen từng là điểm yếu trong \(n) buổi đầu giờ đã trở thành thế mạnh của bạn. Đó là một thay đổi thật trong cách bạn làm.")
                : Text(headline: "You've leveled up how you work with AI.",
                       body: "A habit that was a growth edge in \(n) of your early sessions has become a strength. That's a real shift in how you build, not just what you built.")
        }
    }
}
