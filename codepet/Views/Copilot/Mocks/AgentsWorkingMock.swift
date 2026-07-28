import SwiftUI

#if DEBUG
#Preview("Agents · working in parallel") {
    let base = Date(timeIntervalSince1970: 0)
    let runs = [
        AgentRun(companionId: "byte", deptName: "Engineering",
                 taskTitle: "Building the waitlist API",
                 steps: [
                    ExecStep(label: "Scaffold the route", done: true),
                    ExecStep(label: "Define the schema", done: true),
                    ExecStep(label: "Write the handler", done: false),
                    ExecStep(label: "Add tests", done: false),
                 ],
                 status: .working, startedAt: base),
        AgentRun(companionId: "luna", deptName: "Design",
                 taskTitle: "Landing hero visual pass",
                 steps: [
                    ExecStep(label: "Moodboard", done: true),
                    ExecStep(label: "Layout", done: false),
                    ExecStep(label: "Typography", done: false),
                 ],
                 status: .working, startedAt: base),
        AgentRun(companionId: "sage", deptName: "Legal",
                 taskTitle: "Privacy policy draft",
                 steps: [ExecStep(label: "Draft clauses", done: true)],
                 status: .done, startedAt: base),
    ]
    return ScrollView {
        AgentsWorkingRow(runs: runs, now: Date(timeIntervalSince1970: 134))
            .frame(maxWidth: 760)
            .padding(.horizontal, 24).padding(.vertical, 40)
    }
    .frame(width: 900, height: 700)
    .background(ChatBackdrop())
    .environmentObject(CompanyStore())
    .environment(\.uiLanguage, .en)
}
#endif
