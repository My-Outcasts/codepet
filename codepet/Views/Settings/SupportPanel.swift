// codepet/Views/Settings/SupportPanel.swift
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Support, lifted from the retired `SupportView`: a message form that writes to the
/// Firestore `feedback` collection.
///
/// The real view was never a mailto link — it was this form — so the form moves across
/// whole, including the payload shape (`FeatureFeedbackManager`'s, because that is the
/// one the security rule accepts) and the fail-soft states. `sent` is only set after the
/// write actually returns, so the panel never claims a delivery it didn't get.
struct SupportPanel: View {
    @Environment(\.uiLanguage) private var lang

    @State private var message = ""
    @State private var sent = false
    @State private var sending = false
    @State private var failed = false

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupLabel(lang == .vi ? "Nhắn cho chúng tôi" : "Message us")
            SettingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    if sent {
                        Text(lang == .vi ? "Đã gửi — cảm ơn bạn! Chúng tôi sẽ phản hồi qua email."
                                         : "Sent — thank you! We'll reply by email.")
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.accentTeal)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        if failed {
                            Text(lang == .vi ? "Không gửi được — thử lại nhé."
                                             : "Couldn't send — please try again.")
                                .font(CodepetTheme.inter(12))
                                .foregroundColor(CodepetTheme.accentOrange)
                        }
                        Text(lang == .vi ? "Có vướng mắc, hay có câu hỏi? Kể cho chúng tôi nghe."
                                         : "Hit a snag or have a question? Tell us what happened.")
                            .font(CodepetTheme.inter(11))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        TextEditor(text: $message)
                            .font(CodepetTheme.inter(13))
                            .scrollContentBackground(.hidden)   // hide TextEditor's opaque default backing
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: CodepetTheme.inputRadius)
                                .fill(CodepetTheme.hairline.opacity(0.5)))
                            .overlay(RoundedRectangle(cornerRadius: CodepetTheme.inputRadius)
                                .stroke(CodepetTheme.hairline, lineWidth: 1))
                        HStack {
                            Spacer()
                            // The ink is picked from whichever fill is actually drawn, so
                            // the disabled grey pill stays legible too — the retired
                            // SupportView hardcoded white and got away with it only
                            // because both fills happen to be dark in light mode.
                            let fill = canSend ? CodepetTheme.accentPurple : CodepetTheme.mutedText
                            Button { Task { await send() } } label: {
                                Text(sending ? (lang == .vi ? "Đang gửi…" : "Sending…")
                                             : (lang == .vi ? "Gửi" : "Send"))
                                    .font(CodepetTheme.inter(12, weight: .semibold))
                                    .foregroundColor(CodepetTheme.onAccent(fill))
                                    .padding(.horizontal, 16).padding(.vertical, 7)
                                    .background(Capsule().fill(fill))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSend)
                        }
                    }
                }
                .padding(.vertical, 14)
            }
        }
    }

    private func send() async {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true; failed = false
        // The `feedback` collection is the one with a granted security rule; the payload
        // is shaped like FeatureFeedbackManager's so the rule accepts it.
        var payload: [String: Any] = [
            "feature": "support",
            "rating": 0,
            "comment": text,
            "userId": Auth.auth().currentUser?.uid ?? "anonymous",
            "platform": "macos",
            "timestamp": FieldValue.serverTimestamp(),
        ]
        if let email = Auth.auth().currentUser?.email, !email.isEmpty { payload["email"] = email }
        do {
            _ = try await Firestore.firestore().collection("feedback").addDocument(data: payload)
            sending = false; sent = true      // only claim success once the write returns
        } catch {
            sending = false; failed = true
        }
    }
}
