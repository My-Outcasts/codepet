import SwiftUI

/// The one tinted-card construction shared by every interactive chat payload.
/// Only the hue varies (see MessageCardStyle): hue @12% over surface, a same-hue
/// 1pt border, smooth radius 12, uniform padding — matching the redesign's card
/// style. Left-aligned, fills the column width; callers add their own trailing
/// Spacer if they want the card to hug the leading edge.
struct MessageCard<Content: View>: View {
    let hue: Color
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hue.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hue.opacity(0.9), lineWidth: 1))
    }
}
