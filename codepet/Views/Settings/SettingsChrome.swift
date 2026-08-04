// codepet/Views/Settings/SettingsChrome.swift
import SwiftUI

/// The settings modal's row vocabulary, defined once so nine panels cannot drift.
///
/// Every row is: label + optional description + exactly ONE right-aligned control.
/// A dropdown for three or more options, a toggle for binary, a button for an action.
/// Inter throughout — the pixel font belongs to the logo, sprites and game chrome.

/// Panel title + the muted line under it.
struct SettingsPanelHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CodepetTheme.inter(22, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(subtitle)
                .font(CodepetTheme.inter(13))
                .foregroundColor(CodepetTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The small uppercase-free group caption above a card ("Profile", "Appearance").
struct SettingsGroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(CodepetTheme.inter(13, weight: .medium))
            .foregroundColor(CodepetTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Replaces `Divider()` to ensure row separators track `CodepetTheme` instead of using the system
/// separator colour, keeping separators visually consistent with the group's `CodepetTheme.hairline` border.
struct SettingsDivider: View {
    /// `.horizontal` (the default, so every row call site stays `SettingsDivider()`) draws
    /// the 1pt rule BETWEEN stacked rows. `.vertical` draws the 1pt column rule between the
    /// modal's rail and its panel — an outer `.frame` cannot rotate the horizontal one,
    /// because the fixed 1pt height wins over anything the parent proposes.
    var axis: Axis = .horizontal

    var body: some View {
        CodepetTheme.hairline
            .frame(width:  axis == .vertical   ? 1 : nil,
                   height: axis == .horizontal ? 1 : nil)
    }
}

/// A bordered card holding rows. Rows separate themselves with `SettingsDivider()`.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius)
                    .fill(CodepetTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius)
                    .stroke(CodepetTheme.hairline, lineWidth: 1)
            )
    }
}

/// label + optional description on the left, one control on the right.
struct SettingsRow<Control: View>: View {
    let label: String
    var description: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(CodepetTheme.inter(13, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                if let description {
                    Text(description)
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 12)
    }
}

/// A row whose action is destructive: `accentOrange` label on the button, never a red
/// literal, and the caller owns confirmation.
struct SettingsDestructiveRow: View {
    let label: String
    var description: String? = nil
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        SettingsRow(label: label, description: description) {
            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(CodepetTheme.accentOrange)
        }
    }
}
