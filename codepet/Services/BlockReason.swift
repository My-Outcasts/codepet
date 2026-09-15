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
    /// founder one. Almost always `scripts/build-sidecar.sh` was not run.
    case sidecarMissing
    /// A build was asked for with no project folder linked to this session.
    case noFolderLinked

    var founderText: String {
        switch self {
        case .notGranted:
            return "Codepet needs permission to use your Claude plan. Turn it on in Settings."
        case .claudeCodeMissing:
            return "Codepet runs on Claude Code. Install it, then try again."
        case .sidecarMissing:
            return "Codepet can't reach its local runner on this Mac."
        case .noFolderLinked:
            return "Link a project folder to this session before building."
        }
    }

    var founderTextVi: String {
        switch self {
        case .notGranted:
            return "Codepet cần quyền dùng gói Claude của bạn. Bật trong Cài đặt."
        case .claudeCodeMissing:
            return "Codepet chạy trên Claude Code. Hãy cài đặt rồi thử lại."
        case .sidecarMissing:
            return "Codepet không tìm thấy trình chạy cục bộ trên máy này."
        case .noFolderLinked:
            return "Hãy liên kết thư mục dự án cho phiên này trước khi build."
        }
    }
}
