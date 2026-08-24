// codepet/Models/DepartmentTopics.swift
import Foundation

/// What each department's work SOUNDS like, so a pet can arrive before the founder names it.
///
/// Deliberately separate from `DepartmentCompanions`, which owns the department NAMES and
/// requires them to be addressed. That distinction is the whole safety model: tier 1 fires on
/// "ask finance", tier 2 fires on "runway", and neither can fire on the other's evidence.
///
/// **Nothing here may be a department name.** A name in a lexicon lets tier 2 fire on a bare
/// mention, which is the Aug 10 regression re-entering through the back door.
/// `DepartmentTopicsTests` enforces it.
///
/// **Single-word entries must be ≥3 characters, lowercase, and not stopwords**, because
/// `TextRelevance.tokenize` drops everything else — a shorter entry is dead on arrival and
/// nothing announces it. That is why "ux", "ui" and "ci" are absent despite being obvious
/// vocabulary. Multi-word entries are matched as phrases against the raw text instead and are
/// not subject to that floor.
///
/// `product` has no entry: it has no companion (`DepartmentCatalog.roster` filters it, and its
/// cover art is a byte-identical copy of Engineering's), so scoring it would rank a department
/// that can never be suggested.
enum DepartmentTopics {
    struct Vocabulary {
        let en: [String]
        /// Ships present and empty. Adding Vietnamese is then a data fill, not a refactor —
        /// spec §2.6. A Vietnamese founder sees today's behaviour, which is a no-op rather
        /// than a regression.
        let vi: [String]
    }

    static let map: [String: Vocabulary] = [
        "eng": Vocabulary(en: [
            "api", "backend", "frontend", "database", "schema", "endpoint", "refactor",
            "bug", "crash", "stacktrace", "deploy", "server", "repo", "codebase",
            "migration", "latency", "caching", "authentication", "test suite", "pull request",
        ], vi: []),
        "design": Vocabulary(en: [
            "layout", "typography", "font", "colour", "color", "palette", "spacing",
            "wireframe", "mockup", "icon", "logo", "branding", "visual", "screen",
            "contrast", "accessibility", "empty state", "first run", "onboarding flow",
        ], vi: []),
        "mkt": Vocabulary(en: [
            "launch", "campaign", "seo", "blog", "social", "newsletter", "audience",
            "positioning", "messaging", "brand", "press", "announcement", "growth",
            "landing page", "waitlist", "content calendar", "product hunt",
        ], vi: []),
        "sales": Vocabulary(en: [
            "lead", "leads", "prospect", "outreach", "demo", "deal", "quota", "discount",
            "conversion", "upsell", "cold email", "sales call", "free trial",
        ], vi: []),
        "support": Vocabulary(en: [
            "ticket", "complaint", "refund", "faq", "escalation", "churn",
            "bug report", "help doc", "response time", "user question",
        ], vi: []),
        "fin": Vocabulary(en: [
            "pricing", "price", "runway", "burn", "revenue", "mrr", "arr", "margin",
            "invoice", "invoicing", "budget", "forecast", "investor", "investors",
            "funding", "valuation", "subscription", "billing", "stripe",
            "cash flow", "burn rate", "unit economics",
        ], vi: []),
        "ops": Vocabulary(en: [
            "automation", "workflow", "process", "vendor", "hiring", "integration",
            "infrastructure", "monitoring", "backup", "uptime", "incident",
            "standard operating procedure",
        ], vi: []),
        "legal": Vocabulary(en: [
            "terms", "privacy", "gdpr", "compliance", "contract", "licence", "license",
            "licensing", "trademark", "copyright", "liability", "incorporation", "nda",
            "terms of service", "privacy policy", "data protection",
        ], vi: []),
    ]

    /// The vocabulary for one department in the active language. Empty for an unknown key,
    /// for `product`, and for every key in `.vi` until that table is filled.
    static func terms(for deptKey: String, language: AppLanguage) -> [String] {
        guard let vocab = map[deptKey] else { return [] }
        return language == .vi ? vocab.vi : vocab.en
    }
}
