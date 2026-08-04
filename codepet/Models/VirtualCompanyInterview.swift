// codepet/Models/VirtualCompanyInterview.swift
import Foundation

/// The two questions that make the room concrete instead of generic.
///
/// It cannot run before the answer it improves. All five phases happen inside one
/// HTTP request, so there is no point at which the client can stop after intake,
/// ask, and resume — and aborting mid-stream would not help either, because the
/// function keeps working after a client disconnect and we would pay for a run we
/// threw away. So the first decision runs thin, the backend says so honestly in
/// `what_we_dont_know`, and this asks afterwards to sharpen every run after it.
enum VirtualCompanyInterview {

    /// Runway first: it is the number that changes a recommendation most.
    static let gaps: [InterviewGap] = [.runway, .constraints]

    static func shouldAsk(state: VirtualCompanyRunState,
                          brief: CompanyBrief,
                          alreadyAsked: Bool) -> Bool {
        guard !alreadyAsked else { return false }
        let onRecord = (brief.constraints ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard onRecord.isEmpty else { return false }
        // Only after a brief actually landed: no interrogation to pay for nothing.
        return state.brief != nil
    }
}
