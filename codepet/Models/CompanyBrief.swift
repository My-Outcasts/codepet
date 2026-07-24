// codepet/Models/CompanyBrief.swift
import Foundation

/// The founder's structured, self-described brief for a single project.
/// Verbatim port of the web app's `CompanyBrief` (lib/firebase/schema.ts). All
/// fields optional; a memberwise init lets call sites build partial briefs.
struct CompanyBrief: Codable, Hashable, Equatable {
    var founderName: String?
    var role: String?
    var tech: String?
    /// Free-text lifecycle stage from the onboarding slider (e.g. "Idea",
    /// "Building"). Distinct from `Project.stage` (the health-engine enum).
    var stage: String?
    var projectName: String?
    /// One-sentence description of the product (highest-signal field).
    var oneLiner: String?
    /// byte's enriched read of the product, when inputs were rich enough.
    var summary: String?
    /// Free-form details: pitch, README, PRD notes, anything pasted.
    var notes: String?
    /// Website / repo / Figma link.
    var link: String?
    /// Product categories (e.g. "Web app", "SaaS", "Dev tool").
    var categories: [String]?
    /// Who the product is for (target user / customer).
    var audience: String?

    init(founderName: String? = nil, role: String? = nil, tech: String? = nil,
         stage: String? = nil, projectName: String? = nil, oneLiner: String? = nil,
         summary: String? = nil, notes: String? = nil, link: String? = nil,
         categories: [String]? = nil, audience: String? = nil) {
        self.founderName = founderName; self.role = role; self.tech = tech
        self.stage = stage; self.projectName = projectName; self.oneLiner = oneLiner
        self.summary = summary; self.notes = notes; self.link = link
        self.categories = categories; self.audience = audience
    }

    /// True when the brief carries any founder-supplied signal. Mirrors the web
    /// gating check (`Object.keys(brief).length > 0`): any non-empty field counts.
    var hasAnySignal: Bool {
        func s(_ v: String?) -> Bool {
            guard let v else { return false }
            return !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return s(founderName) || s(role) || s(tech) || s(stage)
            || s(projectName) || s(oneLiner) || s(summary) || s(notes)
            || s(link) || s(audience)
            || !(categories?.isEmpty ?? true)
    }
}
