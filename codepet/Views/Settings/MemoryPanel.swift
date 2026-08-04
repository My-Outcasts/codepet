// codepet/Views/Settings/MemoryPanel.swift
import SwiftUI

/// What the founder's team remembers about their company, and how to forget it. Closes the
/// product's biggest trust gap: until now a fact recorded by `remember_fact` was invisible
/// and permanent.
///
/// Two stores, deliberately treated differently. Facts the team was TOLD are listed in full
/// and deletable one by one, because that is the half the founder authored and the half they
/// have a right to take back. Coding activity is DERIVED from sessions — nobody typed it, so
/// per-row editing would be theatre; it gets a read-only summary and one Reset.
///
/// The facts list is deliberately unfiltered. `company.decisions` also holds entries the
/// `extractDecisions` function wrote (`source` distinguishes them from chat ones), and all of
/// them ground the prompt — showing only the chat-remembered ones would let a panel titled
/// "What your team knows" claim a completeness it does not have.
///
/// Holds a local draft of the switch rather than binding it straight to `companyStore`, same
/// as `AISettingsPanel` and `NotificationsPanel`: `updateFounderPrefs` only updates
/// `company.founderPrefs` AFTER its Firestore await returns, so a directly-bound `Toggle`
/// visibly snapped back to the old position for the length of that round trip. The draft also
/// drives the dimming below, so the two halves of the panel fade the moment the switch moves.
struct MemoryPanel: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @ObservedObject private var petMemory = PetMemoryStore.shared

    @State private var confirmReset = false
    @State private var memoryEnabled = true
    @State private var loaded = false

    /// The REAL store, verified against the tree: the chat tool `remember_fact` flows through
    /// `CompanyStore.handleRemember` → `Decisions.mergeDecisions` → this array, persisted by
    /// the existing `decisionsSaver`. There is no separate "facts" collection.
    private var facts: [DecisionEntry] { companyStore.company.decisions }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    label: lang == .vi ? "Bật ghi nhớ" : "Enable memory",
                    description: lang == .vi
                        ? "Cho đội của bạn dùng những gì đã học về công ty bạn."
                        : "Let your team personalise using what they've learned about your company."
                ) {
                    Toggle("", isOn: $memoryEnabled)
                        .labelsHidden()
                }
            }

            SettingsGroupLabel(lang == .vi ? "Điều đội bạn biết" : "What your team knows")
            SettingsGroup {
                if facts.isEmpty {
                    SettingsRow(
                        label: lang == .vi ? "Chưa có gì." : "Nothing yet.",
                        description: lang == .vi
                            ? "Những gì bạn kể trong chat sẽ hiện ở đây."
                            : "What you tell your team in chat shows up here."
                    ) { EmptyView() }
                } else {
                    // Indexed rather than keyed by `topic`: a document written before the
                    // topic-keyed merge existed can still hold two rows with one topic, and
                    // a duplicated ForEach id silently drops rows from a trust surface.
                    ForEach(Array(facts.enumerated()), id: \.offset) { idx, fact in
                        if idx > 0 { SettingsDivider() }
                        SettingsRow(label: fact.statement, description: fact.topic) {
                            Button { Task { await companyStore.forgetDecision(fact) } } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(CodepetTheme.accentOrange)
                            }
                            .buttonStyle(.plain)
                            .help(lang == .vi ? "Xoá khỏi bộ nhớ" : "Forget this")
                        }
                    }
                }
            }
            // Dimmed, not hidden, while memory is off: the founder still needs to see what is
            // on record (and still be able to delete it) — the switch only stops it being used.
            .opacity(memoryEnabled ? 1 : 0.55)

            SettingsGroupLabel(lang == .vi ? "Hoạt động lập trình" : "Coding activity")
            SettingsGroup {
                SettingsRow(
                    label: MemoryDigest.codingActivityLine(memories: petMemory.memories, lang: lang),
                    description: lang == .vi
                        ? "Suy ra từ các phiên của bạn, không phải bạn nhập."
                        : "Derived from your sessions, not something you typed."
                ) {
                    Button(lang == .vi ? "Đặt lại" : "Reset") { confirmReset = true }
                        .buttonStyle(.plain)
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentOrange)
                }
            }
            .opacity(memoryEnabled ? 1 : 0.55)
        }
        // Seeded once. Seeding a `false` moves the draft, so `onChange` below fires on first
        // appearance — `updateFounderPrefs` sees a change that changes nothing and returns
        // without writing, so this costs no Firestore round trip.
        .onAppear {
            guard !loaded else { return }
            memoryEnabled = companyStore.company.founderPrefs.memoryEnabled
            loaded = true
        }
        // Commits ONLY `memoryEnabled`, onto whatever the current preferences are — never a
        // whole struct captured here — so a notifications or style commit still in flight
        // keeps its own field instead of being reverted by this one. See
        // `CompanyStore.updateFounderPrefs`.
        .onChange(of: memoryEnabled) { _, on in
            guard loaded else { return }
            Task { await companyStore.updateFounderPrefs { $0.memoryEnabled = on } }
        }
        // Same confirmation idiom as `AdvancedPanel`'s sign-out: a Reset clears every
        // project's streak and session count, and nothing brings them back.
        .confirmationDialog(
            lang == .vi ? "Đặt lại hoạt động lập trình?" : "Reset coding activity?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button(lang == .vi ? "Đặt lại" : "Reset", role: .destructive) {
                petMemory.resetAll()
            }
            Button(lang == .vi ? "Huỷ" : "Cancel", role: .cancel) { }
        } message: {
            Text(lang == .vi
                 ? "Xoá số phiên và chuỗi ngày của mọi dự án. Không thể hoàn tác."
                 : "Clears every project's session count and streak. This can't be undone.")
        }
    }
}
