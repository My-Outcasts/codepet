// codepet/Views/Support/SupportView.swift
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Support (web SupportModal.tsx): a message form that writes to the Firestore
/// `support` collection. Self-contained; fail-soft.
struct SupportView: View {
    @Environment(\.uiLanguage) private var lang
    @State private var message = ""
    @State private var sent = false
    @State private var sending = false

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(lang == .vi ? "Hỗ trợ" : "Support")
                    .font(CodepetTheme.title()).foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi ? "Có vướng mắc? Nhắn cho chúng tôi."
                                 : "Hit a snag or have a question? Send us a message.")
                    .font(CodepetTheme.subtitle()).foregroundColor(CodepetTheme.mutedText)

                if sent {
                    Text(lang == .vi ? "Đã gửi — cảm ơn bạn! Chúng tôi sẽ phản hồi qua email."
                                     : "Sent — thank you! We'll reply by email.")
                        .font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.accentTeal)
                } else {
                    TextEditor(text: $message)
                        .font(CodepetTheme.inter(13)).frame(minHeight: 140)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(CodepetTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CodepetTheme.hairline, lineWidth: 1))
                    Button { Task { await send() } } label: {
                        Text(sending ? (lang == .vi ? "Đang gửi…" : "Sending…")
                                     : (lang == .vi ? "Gửi" : "Send"))
                            .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(canSend ? CodepetTheme.accentPurple : CodepetTheme.mutedText))
                    }
                    .buttonStyle(.plain).disabled(!canSend)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func send() async {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        let payload: [String: Any] = [
            "message": text,
            "uid": Auth.auth().currentUser?.uid ?? "",
            "email": Auth.auth().currentUser?.email ?? "",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        _ = try? await Firestore.firestore().collection("support").addDocument(data: payload)
        sending = false
        sent = true
    }
}
