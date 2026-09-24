import XCTest
@testable import codepet

/// `DeliverableMarkdown.render` is a pure function from a deliverable + a Team Build step's
/// department/instruction to a Markdown string — the same reason `DeliverableExportTests`
/// tests `DeliverableExport` this way: nothing here needs a view or a store.
final class DeliverableMarkdownTests: XCTestCase {

    /// Some payload fixtures are DECODED from JSON rather than constructed — `SitePayload`,
    /// `CalendarItem`/`CalendarWeek` and `Screen` each declare their own `init(from decoder:)`,
    /// which suppresses Swift's memberwise initialiser (see `DeliverableExportTests`'s note on
    /// the same fact). The wire payload is flat, so this decodes straight into
    /// `DeliverablePayload`, matching how these arrive in production.
    private func payload(json: String) throws -> DeliverablePayload {
        try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
    }

    func testPlainBodyIsKeptUnderATitleAndHeader() {
        let d = Deliverable(kind: .doc, title: "Positioning", body: "Office workers 25-35.")
        let md = DeliverableMarkdown.render(d, dept: "Marketing", instruction: "Write positioning")
        XCTAssertTrue(md.hasPrefix("# Positioning"))
        XCTAssertTrue(md.contains("**Department:** Marketing"))
        XCTAssertTrue(md.contains("**Asked for:** Write positioning"))
        XCTAssertTrue(md.contains("Office workers 25-35."))
    }

    func testChecklistPayloadRendersEveryItemWithItsDoneState() {
        let d = Deliverable(kind: .checklist, title: "Launch checklist", body: "Checklist body",
                             payload: DeliverablePayload(items: [
                                ChecklistItem(t: "Register the domain", done: true),
                                ChecklistItem(t: "Configure DNS", done: false),
                             ]))
        let md = DeliverableMarkdown.render(d, dept: "Engineering", instruction: "Prep the launch checklist")
        XCTAssertTrue(md.contains("- [x] Register the domain"))
        XCTAssertTrue(md.contains("- [ ] Configure DNS"))
    }

    func testDocPayloadRendersCallSectionsAndNext() {
        let d = Deliverable(kind: .doc, title: "Stack", body: "ignored for doc",
                             payload: DeliverablePayload(
                                call: "Run on-device where the entry can stay.",
                                sections: [DocSection(h: "Why", p: "Privacy is the product.")],
                                next: ["Measure recall past 3k entries"]))
        let md = DeliverableMarkdown.render(d, dept: "Engineering", instruction: "Recommend a stack")
        XCTAssertTrue(md.contains("Run on-device where the entry can stay."))
        XCTAssertTrue(md.contains("## Why"))
        XCTAssertTrue(md.contains("Privacy is the product."))
        XCTAssertTrue(md.contains("## Next"))
        XCTAssertTrue(md.contains("- Measure recall past 3k entries"))
    }

    func testPlanPayloadRendersGoalStepsChangesVerifyAndRisks() {
        let d = Deliverable(kind: .plan, title: "Auth plan", body: "ignored for plan",
                             payload: DeliverablePayload(
                                goal: "Ship email/password auth",
                                steps: ["Add login screen", "Add signup screen"],
                                changes: [PlanChange(area: "Auth", edit: "Add JWT session handling")],
                                verify: ["Login round-trips a real session"],
                                risks: "Token leakage if stored in plain UserDefaults"))
        let md = DeliverableMarkdown.render(d, dept: "Engineering", instruction: "Plan the auth work")
        XCTAssertTrue(md.contains("## Goal"))
        XCTAssertTrue(md.contains("Ship email/password auth"))
        XCTAssertTrue(md.contains("## Steps"))
        XCTAssertTrue(md.contains("1. Add login screen"))
        XCTAssertTrue(md.contains("2. Add signup screen"))
        XCTAssertTrue(md.contains("## Changes"))
        XCTAssertTrue(md.contains("Auth"))
        XCTAssertTrue(md.contains("Add JWT session handling"))
        XCTAssertTrue(md.contains("## Verify"))
        XCTAssertTrue(md.contains("Login round-trips a real session"))
        XCTAssertTrue(md.contains("## Risks"))
        XCTAssertTrue(md.contains("Token leakage if stored in plain UserDefaults"))
    }

    func testDmsPayloadRendersEveryMessageWithItsNameAndNote() {
        let d = Deliverable(kind: .dms, title: "Outreach", body: "ignored for dms",
                             payload: DeliverablePayload(messages: [
                                DmMessage(name: "Alex", note: "Early adopter in the target segment",
                                          msg: "Hey Alex, we're building something you might like."),
                             ]))
        let md = DeliverableMarkdown.render(d, dept: "Sales", instruction: "Draft outreach DMs")
        XCTAssertTrue(md.contains("### Alex"))
        XCTAssertTrue(md.contains("Early adopter in the target segment"))
        XCTAssertTrue(md.contains("Hey Alex, we're building something you might like."))
    }

    func testCalendarPayloadRendersEveryWeekAndItem() throws {
        let p = try payload(json: """
        {"weeks":[{"label":"Week 1","items":[{"day":"Mon","kind":"Post","body":"Launch teaser thread"}]}]}
        """)
        let d = Deliverable(kind: .calendar, title: "Content calendar", body: "ignored for calendar", payload: p)
        let md = DeliverableMarkdown.render(d, dept: "Marketing", instruction: "Plan the launch content")
        XCTAssertTrue(md.contains("## Week 1"))
        XCTAssertTrue(md.contains("Mon"))
        XCTAssertTrue(md.contains("Post"))
        XCTAssertTrue(md.contains("Launch teaser thread"))
    }

    func testSheetPayloadRendersATableWithEveryInputAndTheSummary() {
        let d = Deliverable(kind: .sheet, title: "Pricing model", body: "ignored for sheet",
                             payload: DeliverablePayload(sheet: SheetPayload(
                                price: SheetInput(val: 49, min: 10, max: 99, step: 1),
                                waitlist: SheetInput(val: 500, min: 0, max: 5000, step: 50),
                                conversion: SheetInput(val: 5, min: 1, max: 20, step: 1),
                                churn: SheetInput(val: 3, min: 1, max: 10, step: 1),
                                summary: "At these defaults the model clears break-even in month two.")))
        let md = DeliverableMarkdown.render(d, dept: "Finance", instruction: "Build the pricing model")
        XCTAssertTrue(md.contains("| Input | Value | Min | Max | Step |"))
        XCTAssertTrue(md.contains("| Price | 49 | 10 | 99 | 1 |"))
        XCTAssertTrue(md.contains("| Waitlist | 500 | 0 | 5000 | 50 |"))
        XCTAssertTrue(md.contains("| Conversion | 5 | 1 | 20 | 1 |"))
        XCTAssertTrue(md.contains("| Churn | 3 | 1 | 10 | 1 |"))
        XCTAssertTrue(md.contains("At these defaults the model clears break-even in month two."))
    }

    /// Every copy field `SitePayload` has (`Models/Deliverable.swift:57-84`), each given a
    /// distinct value, so a field the renderer drops shows up as a missing assert rather than
    /// hiding behind another field's coincidentally-matching text. `accent` is excluded — it is
    /// a colour, not copy, and `DeliverableMarkdown` never reads it.
    func testSitePayloadRendersEveryCopyField() throws {
        let p = try payload(json: """
        {
          "title": "Acme Landing",
          "brand": "Acme",
          "kicker": "Now in beta",
          "headline": "Ship faster",
          "headlineHi": "than ever",
          "sub": "Acme helps you ship faster than ever.",
          "ctaPrimary": "Get started",
          "ctaSecondary": "See a demo",
          "howEyebrow": "The process",
          "howTitle": "How it works",
          "steps": [{"h": "Connect your repo", "p": "Point Acme at your codebase."}],
          "featEyebrow": "Why Acme",
          "featTitle": "Built for speed",
          "features": [{"h": "Fast setup", "p": "Up and running in minutes."}],
          "quote": "Acme cut our release cycle in half.",
          "quoteBy": "Jordan, CTO at Beta Co",
          "finalTitle": "Ready?",
          "finalSub": "Start shipping today.",
          "finalCta": "Join now",
          "footNote": "No credit card required."
        }
        """)
        let d = Deliverable(kind: .site, title: "Landing page", body: "ignored for site", payload: p)
        let md = DeliverableMarkdown.render(d, dept: "Design", instruction: "Write the landing page copy")
        XCTAssertTrue(md.contains("Acme Landing"))
        XCTAssertTrue(md.contains("Acme"))
        XCTAssertTrue(md.contains("Now in beta"))
        XCTAssertTrue(md.contains("Ship faster"))
        XCTAssertTrue(md.contains("than ever"))
        XCTAssertTrue(md.contains("Acme helps you ship faster than ever."))
        XCTAssertTrue(md.contains("Get started"))
        XCTAssertTrue(md.contains("See a demo"))
        XCTAssertTrue(md.contains("The process"))
        XCTAssertTrue(md.contains("How it works"))
        XCTAssertTrue(md.contains("Connect your repo"))
        XCTAssertTrue(md.contains("Point Acme at your codebase."))
        XCTAssertTrue(md.contains("Why Acme"))
        XCTAssertTrue(md.contains("Built for speed"))
        XCTAssertTrue(md.contains("Fast setup"))
        XCTAssertTrue(md.contains("Up and running in minutes."))
        XCTAssertTrue(md.contains("Acme cut our release cycle in half."))
        XCTAssertTrue(md.contains("Jordan, CTO at Beta Co"))
        XCTAssertTrue(md.contains("Ready?"))
        XCTAssertTrue(md.contains("Start shipping today."))
        XCTAssertTrue(md.contains("Join now"))
        XCTAssertTrue(md.contains("No credit card required."))
    }

    func testScreensPayloadRendersEveryScreenWithItsCopy() throws {
        let p = try payload(json: """
        {"screens":[{"name":"Onboarding","time":"0:00","kick":"Welcome","title":"Get started",
                     "sub":"Set up your account","art":"connect","cta":"Continue","note":"Takes 2 minutes"}]}
        """)
        let d = Deliverable(kind: .screens, title: "Onboarding flow", body: "ignored for screens", payload: p)
        let md = DeliverableMarkdown.render(d, dept: "Design", instruction: "Design the onboarding screens")
        XCTAssertTrue(md.contains("### Onboarding (0:00)"))
        XCTAssertTrue(md.contains("Welcome"))
        XCTAssertTrue(md.contains("Get started"))
        XCTAssertTrue(md.contains("Set up your account"))
        XCTAssertTrue(md.contains("Continue"))
        XCTAssertTrue(md.contains("Takes 2 minutes"))
    }

    func testNilPayloadJustOutputsTheBodyWithNoNotesHeading() {
        let d = Deliverable(kind: .post, title: "Launch post", body: "We just shipped v1.")
        let md = DeliverableMarkdown.render(d, dept: "Marketing", instruction: "Write the launch post")
        XCTAssertFalse(md.contains("## Notes"))
        XCTAssertTrue(md.hasSuffix("We just shipped v1."))
    }
}
