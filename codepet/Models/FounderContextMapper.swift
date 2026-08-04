// codepet/Models/FounderContextMapper.swift
import Foundation

/// Builds the `founder` object the Virtual Company endpoint expects out of the
/// brief the app already holds.
///
/// Constraints matter more than they look: measured against the real backend,
/// departments produce concrete hard blockers when constraints are present and
/// noticeably vaguer positions when they are not. They are gathered by the
/// interview in Task 8, never invented here.
enum FounderContextMapper {

    static func founder(from brief: CompanyBrief) -> VCFounder {
        VCFounder(profile: profile(from: brief),
                  stage: stage(from: brief),
                  constraints: constraints(from: brief))
    }

    /// Joins the non-blank parts with " · ". Never returns "" — the endpoint
    /// answers HTTP 400 on a missing profile or stage.
    private static func join(_ parts: [String?], fallback: String) -> String {
        let kept = parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return kept.isEmpty ? fallback : kept.joined(separator: " · ")
    }

    private static func profile(from brief: CompanyBrief) -> String {
        join([brief.role, brief.tech, brief.founderName],
             fallback: "Solo founder. Nothing else on record yet.")
    }

    /// Runway rides along in `stage`: the contract has no field for it, and stage
    /// is where the backend's own fixture puts "4 months of runway".
    private static func stage(from brief: CompanyBrief) -> String {
        join([brief.stage, brief.traction, brief.runway, brief.oneLiner, brief.goal],
             fallback: "Stage not on record yet.")
    }

    private static func constraints(from brief: CompanyBrief) -> [String] {
        (brief.constraints ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
