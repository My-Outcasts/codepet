// codepet/Services/BlockReason.swift
import Foundation

/// Why a run cannot start on this Mac.
///
/// **One type for both routers.** `LocalTransportRouter` and `ChatTransportRouter` each carried
/// their own `localUnavailable(String)`, and the string was written at each throw site — so the
/// same missing sidecar produced different words depending on which feature reached it first.
///
/// The copy names the FIX rather than the state. A founder cannot act on "not authorised"; she
/// can act on "turn on Codepet's access to your Claude plan in Settings".
enum BlockReason: Equatable {
    /// Signed in, Claude Code present, but this company has not granted it.
    case notGranted
    /// The `claude` CLI is not installed on this Mac.
    case claudeCodeMissing
    /// Granted and installed, but the bundled runner is missing — a build problem, not a
    /// founder one. Almost always `scripts/build-sidecar.sh` was not run before packaging.
    ///
    /// **It still has to offer the founder something.** She cannot run that script; what she
    /// can do is reinstall a correctly-packaged build. Naming the cause without naming a move
    /// is how the other three cases differ from an error dialog.
    case sidecarMissing
    /// A build was asked for with no project folder linked to this session.
    case noFolderLinked
    /// Granted nothing, and we know which plan to ask about. Separate from `notGranted`
    /// because the founder who has a ChatGPT plan and no Claude one is told to grant the
    /// thing she actually owns, rather than being sent to install a competitor.
    case notGrantedProvider(AIProvider)
    /// This surface runs on Claude Code and no other. Chat streaming and the virtual
    /// company meeting are the two: different protocol risk entirely — event framing, and
    /// an MCP tool story Codex's CLI may not have.
    case needsClaudeCode

    /// Convenience so call sites read as prose.
    static func notGrantedFor(_ p: AIProvider) -> BlockReason { .notGrantedProvider(p) }

    var founderText: String {
        switch self {
        case .notGranted:
            return "Codepet needs permission to use your Claude plan. Turn it on in Settings."
        case .claudeCodeMissing:
            return "Codepet runs on Claude Code. Install it, then try again."
        case .sidecarMissing:
            return "Codepet can't reach its local runner on this Mac. Reinstalling Codepet should restore it."
        case .noFolderLinked:
            return "Link a project folder to this session before building."
        case .notGrantedProvider(.claudeCode):
            return "Codepet needs permission to use your Claude plan. Turn it on to continue."
        case .notGrantedProvider(.codex):
            return "Codepet needs permission to use your ChatGPT plan. Turn it on to continue."
        case .needsClaudeCode:
            return "Chat and meetings run on Claude Code. Install it, or switch this company to it."
        }
    }

    var founderTextVi: String {
        switch self {
        case .notGranted:
            return "Codepet cần quyền dùng gói Claude của bạn. Bật trong Cài đặt."
        case .claudeCodeMissing:
            return "Codepet chạy trên Claude Code. Hãy cài đặt rồi thử lại."
        case .sidecarMissing:
            return "Codepet không tìm thấy trình chạy cục bộ trên máy này. Cài đặt lại Codepet sẽ khôi phục nó."
        case .noFolderLinked:
            return "Hãy liên kết thư mục dự án cho phiên này trước khi build."
        case .notGrantedProvider(.claudeCode):
            return "Codepet cần quyền dùng gói Claude của bạn. Hãy bật để tiếp tục."
        case .notGrantedProvider(.codex):
            return "Codepet cần quyền dùng gói ChatGPT của bạn. Hãy bật để tiếp tục."
        case .needsClaudeCode:
            return "Trò chuyện và cuộc họp chạy trên Claude Code. Hãy cài đặt, hoặc chuyển công ty này sang đó."
        }
    }
}
