// codepet/Views/Copilot/DepartmentPicker.swift
import SwiftUI

/// The composer's department control, as a popover.
///
/// **Why not a `Menu`.** A `Menu`'s rows flatten to `(title, image)`, so a selected row's
/// checkmark takes the image slot and the pet's sprite is dropped — on the one row whose
/// pet is about to speak, while the composer chip below still showed that face. Neither
/// that nor grouping two departments under one portrait can be expressed in a native
/// `Menu` at any price. That constraint, not taste, is why this is a popover.
///
/// Every decision here is made by a pure function elsewhere — `DepartmentPickerRows` for
/// the grouping, `DepartmentPickerFocus` for the keyboard, `DepartmentChipState` for the
/// three chip treatments. This file only draws them.
struct DepartmentPicker: View {

    let armed: Department?
    let suggested: Department?
    let lang: AppLanguage
    let onPick: (Department) -> Void
    let onAnyone: () -> Void

    @State private var focus: PickerFocus = .anyone

    // `DepartmentPickerFocus` and its .onMoveCommand/.onKeyPress wiring below were
    // always correct — nothing was ever making the VStack focusable, so AppKit never
    // routed arrow keys or Return to it. `.focusable(true)` alone would still leave
    // the popover waiting for a click before the keyboard worked; binding this
    // FocusState and setting it in `.onAppear` (alongside the existing seeded
    // `focus`) makes the popover open already holding keyboard focus.
    @FocusState private var keyboardFocused: Bool

    private var rows: [PetRow] { DepartmentPickerRows.rows }

    /// A suggestion is only ever live when nothing is armed — the same rule
    /// `DepartmentChipState.of` applies, kept here so the Anyone row's checkmark agrees
    /// with the chips below it.
    private var shown: Department? { armed ?? suggested }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            anyoneRow
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                petRow(row, at: index)
            }
        }
        .padding(.vertical, 10)
        .frame(width: 326)
        // Precedent: OnboardingStageSlider.swift puts `.focusable(true)` immediately
        // above its own `.onMoveCommand` — same fix, same reason: without it AppKit
        // has nothing to deliver arrow/Return events to.
        .focusable(true)
        .focused($keyboardFocused)
        .onMoveCommand { direction in
            switch direction {
            case .up:    focus = DepartmentPickerFocus.up(from: focus, rows: rows)
            case .down:  focus = DepartmentPickerFocus.down(from: focus, rows: rows)
            case .left:  focus = DepartmentPickerFocus.left(from: focus, rows: rows)
            case .right: focus = DepartmentPickerFocus.right(from: focus, rows: rows)
            @unknown default: break
            }
        }
        // Return acts on whatever the arrows landed on. No `.onExitCommand` here on
        // purpose: `.popover` already dismisses on Esc, and overriding it would turn
        // "close without deciding" into "clear the department", which is a different act.
        .onKeyPress(.return) {
            if let dep = DepartmentPickerFocus.department(at: focus, rows: rows) {
                onPick(dep)
            } else {
                onAnyone()
            }
            return .handled
        }
        // Open with the keyboard already on whatever is current, so the first arrow press
        // moves from the founder's actual selection rather than from the top of the list.
        .onAppear {
            focus = shown.map { DepartmentPickerFocus.locate($0, in: rows) } ?? .anyone
            keyboardFocused = true
        }
    }

    private var anyoneRow: some View {
        Button {
            onAnyone()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(DepartmentMenu.anyoneLabel(lang))
                        .font(CodepetTheme.inter(13.5, weight: .semibold))
                        .foregroundColor(CodepetTheme.bodyText)
                    Text(DepartmentMenu.anyoneDetail(lang))
                        .font(CodepetTheme.inter(11.5))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                Spacer(minLength: 0)
                if shown == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(CodepetTheme.bodyText)
                }
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .hoverAffordance(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .background(focusRing(focus == .anyone))
        // Chips already say which department is current via `.isSelected` — the
        // Anyone row is the fourth possible answer and needs the same trait when
        // it is the one in effect (`shown == nil`).
        .accessibilityAddTraits(shown == nil ? [.isSelected] : [])
    }

    private func petRow(_ row: PetRow, at index: Int) -> some View {
        HStack(spacing: 10) {
            // The chips below already announce the full "Nova · Marketing" —
            // the row's own decorative sprite would otherwise be read again as
            // an unlabelled image ahead of it.
            CharacterImage(row.petId, size: 20)
                .accessibilityHidden(true)
            Text(row.petName)
                .font(CodepetTheme.inter(13.5, weight: .medium))
                .foregroundColor(CodepetTheme.bodyText)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                ForEach(Array(row.departments.enumerated()), id: \.element.key) { slot, dep in
                    chip(dep, petId: row.petId, focused: focus == .chip(pet: index, dept: slot))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
    }

    private func chip(_ dep: Department, petId: String, focused: Bool) -> some View {
        let state = DepartmentChipState.of(dep, armed: armed, suggested: suggested)
        let petColor = PetCharacter.all[petId]?.color ?? dep.accent
        return Button {
            onPick(dep)
        } label: {
            Text(dep.name)
                .font(CodepetTheme.inter(12, weight: state == .picked ? .semibold : .regular))
                .foregroundColor(chipForeground(state, petColor: petColor))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(chipBackground(state, petColor: petColor))
                .overlay(chipBorder(state, petColor: petColor))
                .overlay(focusRing(focused, shape: RoundedRectangle(cornerRadius: 6)))
                // A native `Menu` highlighted the hovered row for free; the popover's
                // rows are plain buttons and gave a mouse user no signal at all.
                .hoverAffordance(RoundedRectangle(cornerRadius: 6), accent: petColor)
        }
        .buttonStyle(.plain)
        // The row splits the pet's name from the department visually, but a screen
        // reader must still hear the string the reply is signed with — `rowTitle` stays
        // the single source of truth for "Nova · Marketing".
        .accessibilityLabel(DepartmentMenu.rowTitle(dep))
        .accessibilityAddTraits(state == .picked ? [.isButton, .isSelected] : [.isButton])
    }

    private func chipForeground(_ state: DepartmentChipState, petColor: Color) -> Color {
        switch state {
        case .idle:      return CodepetTheme.mutedText
        case .suggested: return petColor
        case .picked:    return .white
        }
    }

    @ViewBuilder
    private func chipBackground(_ state: DepartmentChipState, petColor: Color) -> some View {
        switch state {
        case .idle:      Color.clear
        case .suggested: RoundedRectangle(cornerRadius: 6).fill(petColor.opacity(0.09))
        // `.picked` is the only state that puts white text directly on the raw pet
        // color, so it is the only one that needs darkening — idle and suggested
        // keep the pet hue at full strength, untouched.
        case .picked:    RoundedRectangle(cornerRadius: 6).fill(petColor.darkenedForPickedChipText())
        }
    }

    @ViewBuilder
    private func chipBorder(_ state: DepartmentChipState, petColor: Color) -> some View {
        switch state {
        case .idle:
            RoundedRectangle(cornerRadius: 6)
                .stroke(CodepetTheme.hairline, lineWidth: 1)
        case .suggested:
            // The same dashed language the composer chip already uses for a guess, so
            // one grammar covers both controls instead of the two contradicting.
            RoundedRectangle(cornerRadius: 6)
                .stroke(petColor, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .picked:
            EmptyView()
        }
    }

    private func focusRing(_ on: Bool) -> some View {
        focusRing(on, shape: RoundedRectangle(cornerRadius: 6))
    }

    /// **Inset, and not `Color.accentColor`.** Drawn flush at 2pt in the system accent, this
    /// ring sat exactly on the chip's own border and painted over it — which erased the
    /// DASHED stroke that distinguishes a guess from a pick. Rendered and compared, a
    /// focused suggested chip and a focused picked chip differed only in fill and text
    /// colour, so the spec's shape-not-colour rule was defeated on precisely the chip the
    /// keyboard was on. `.strokeBorder` insets the ring inside the shape instead of
    /// straddling it, leaving the dashed border visible underneath.
    ///
    /// The colour is the app's accent rather than the system's: every other mark in this
    /// popover is either a pet's colour or a theme token, and system blue read as the
    /// loudest thing on screen.
    private func focusRing<S: InsettableShape>(_ on: Bool, shape: S) -> some View {
        shape
            .inset(by: 2)
            .strokeBorder(on ? CodepetTheme.accentPurple : .clear, lineWidth: 2)
    }
}

private extension Color {
    /// WCAG AA text-contrast floor for normal-weight text.
    static let wcagAATextContrast: Double = 4.5

    /// Darken `self` — by uniformly scaling its sRGB channels toward black, which
    /// lowers brightness while leaving hue and saturation alone — until white text
    /// drawn on top clears the WCAG AA floor (4.5:1).
    ///
    /// Measured before this fix: white on the raw pet color was ≈2.33:1 for nova
    /// (`#FF8C00`), and every one of the six pet colors failed the same 4.5:1 floor
    /// the same way — none of them is dark enough on its own to carry white text.
    /// Only the `.picked` chip fill needs this; idle and suggested chips never put
    /// white on the raw hue. Deriving the darkened fill here, from the same
    /// relative-luminance math the WCAG spec defines, means a future pet's color is
    /// automatically corrected instead of needing a seventh hardcoded value.
    func darkenedForPickedChipText() -> Color {
        guard let base = NSColor(self).usingColorSpace(.sRGB) else { return self }
        let r = Double(base.redComponent)
        let g = Double(base.greenComponent)
        let b = Double(base.blueComponent)
        var scale = 1.0
        while scale > 0.05 {
            if Color.contrastWithWhite(r: r * scale, g: g * scale, b: b * scale) >= Color.wcagAATextContrast {
                break
            }
            scale -= 0.01
        }
        return Color(red: r * scale, green: g * scale, blue: b * scale)
    }

    private static func contrastWithWhite(r: Double, g: Double, b: Double) -> Double {
        // WCAG contrast ratio: (L_lighter + 0.05) / (L_darker + 0.05). White's own
        // relative luminance is 1.0, so it is always the lighter of the two here.
        (1.0 + 0.05) / (relativeLuminance(r: r, g: g, b: b) + 0.05)
    }

    /// WCAG relative luminance, sRGB coefficients (0.2126 / 0.7152 / 0.0722) over
    /// gamma-decoded channels.
    private static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
