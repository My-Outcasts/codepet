// codepetTests/DemoProjectMurrorTests.swift
import XCTest
@testable import codepet

/// Guards on the Murror demo company.
///
/// The claim this suite exists to hold is **"all eight pets are runnable the moment the demo
/// opens"**. That is not a property of any single task — it is a property of the dependency
/// graph, and `RoadmapEngine` is the only thing that can confirm it. So these assert THROUGH the
/// engine rather than reading fields and inferring, which is the mistake that made four earlier
/// conclusions in this codebase wrong.
final class DemoProjectMurrorTests: XCTestCase {

    private var murror: DemoProject { DemoProject.murror }
    /// Every task still open — INCLUDING the founder-only one. Named `open` because that is
    /// what it is; it was called `runnable`, which conflated "not done" with "Codepet can do
    /// it" and made the suite assert a proxy for its own headline claim.
    private var open: [RoadmapTask] { murror.tasks.filter { !$0.done } }

    /// The eight the DEMO is about: open, and the engine says Codepet can do them now. This is
    /// the set "all eight pets runnable at once" actually refers to.
    private var codepetRunnable: [RoadmapTask] {
        open.filter { RoadmapEngine.status(for: $0, in: murror.tasks) == .codepetCanDo }
    }

    override func tearDown() {
        PrototypeMode.store.removeObject(forKey: DemoProject.key)
        PrototypeMode.store.removeObject(forKey: DemoProject.launchKey)
        super.tearDown()
    }

    // MARK: - The board

    func testBriefIsMurror() {
        XCTAssertEqual(murror.id, "murror")
        XCTAssertEqual(murror.brief.projectName, "Murror")
        XCTAssertEqual(murror.brief.oneLiner, "AI that brings people closer.")
    }

    func testBoardIsEighteenTasks() {
        XCTAssertEqual(murror.tasks.count, 18)
        XCTAssertEqual(open.count, 9, "eight Codepet can do, plus one that is the founder's")
        XCTAssertEqual(codepetRunnable.count, 8)
    }

    /// The invariant behind "all eight runnable": `RoadmapEngine.depsSatisfied` blocks a task
    /// whose prerequisite is not `done`. Adding a dep on an open task would silently un-run a
    /// pet, and the roster would look identical either way.
    func testEveryRunnableDependsOnlyOnDoneTasks() {
        let byId = Dictionary(uniqueKeysWithValues: murror.tasks.map { ($0.id, $0) })
        for task in codepetRunnable {
            for dep in task.dependsOn {
                guard let prereq = byId[dep] else {
                    return XCTFail("\(task.id) depends on '\(dep)', which is not in the fixture")
                }
                XCTAssertTrue(prereq.done,
                              "\(task.id) depends on \(dep), which is not done — so \(task.id) is blocked")
            }
        }
    }

    func testAllEightRosterDepartmentsHaveExactlyOneRunnable() {
        let byDept = Dictionary(grouping: codepetRunnable) { $0.dept ?? "" }
        XCTAssertEqual(Set(byDept.keys), Set(DepartmentCatalog.roster.map(\.key)))
        for (dept, tasks) in byDept {
            XCTAssertEqual(tasks.count, 1, "\(dept) has \(tasks.count) runnable tasks, expected 1")
        }
    }

    /// The founder-only task is deliberately NOT one of the eight — it is the one thing on this
    /// board Codepet must refuse to do, and the surfaces that show that need it to exist.
    func testTheFounderOnlyTaskIsOpenAndNotRunnableByCodepet() throws {
        let mine = try XCTUnwrap(murror.tasks.first { $0.who == .you && !$0.done })
        XCTAssertEqual(mine.id, "mur-clinician")
        XCTAssertEqual(RoadmapEngine.status(for: mine, in: murror.tasks), .needsYou)
        XCTAssertFalse(codepetRunnable.contains { $0.id == mine.id })
    }

    /// The end-to-end claim: the engine itself says every one of the eight is runnable.
    func testEveryRunnableIsCodepetCanDo() {
        for task in codepetRunnable {
            XCTAssertEqual(RoadmapEngine.status(for: task, in: murror.tasks), .codepetCanDo,
                           "\(task.id) (\(task.dept ?? "no dept")) is not runnable")
        }
    }

    /// A task tagged with a pet-less department — `product` is the one in the catalog — would
    /// render a roster card with no pet to speak for it.
    func testEveryMurrorDeptHasAPet() {
        for task in murror.tasks {
            let dept = task.dept ?? ""
            XCTAssertNotNil(DepartmentCompanions.companionId(for: dept),
                            "\(task.id) is tagged '\(dept)', which has no pet")
        }
    }

    func testFindPhaseIsComplete() {
        let find = murror.tasks.filter { $0.phase == .find }
        XCTAssertFalse(find.isEmpty)
        XCTAssertTrue(find.allSatisfy(\.done), "the mid-flight start state needs .find complete")
    }

    /// An unapproved draft is the one thing that still closes the phase window
    /// (`RoadmapGating.awaitsApproval`), and one here would block everything behind it
    /// regardless of the dependency graph.
    func testNoTaskIsDrafted() {
        XCTAssertTrue(murror.tasks.allSatisfy { !$0.drafted })
    }

    /// Every phase must be open — proof that nothing is window-blocked, as distinct from
    /// dependency-blocked.
    func testEveryPopulatedPhaseIsOpen() {
        let open = RoadmapGating.openPhases(murror.tasks)
        for phase in Set(murror.tasks.map(\.phase)) {
            XCTAssertTrue(open.contains(phase), "\(phase.rawValue) is not open")
        }
    }

    // MARK: - What the pets produce

    /// Eight tasks, eight different viewers — so the demo walks eight of the twelve without any
    /// task having been chosen to fill a slot.
    func testEveryRunnableResolvesToADistinctKind() {
        let kinds = codepetRunnable.map { murror.deliverable(for: $0.title).kind }
        XCTAssertEqual(kinds.count, 8)
        XCTAssertEqual(Set(kinds).count, 8, "kinds collide: \(kinds.sorted())")
    }

    /// Every kind named must be a real `DeliverableKind`, or the viewer falls through to the
    /// plain-text default and the card looks broken rather than wrong.
    func testEveryKindIsARealDeliverableKind() {
        for entry in murror.deliverables {
            XCTAssertNotNil(DeliverableKind(rawValue: entry.kind), "'\(entry.kind)' is not a kind")
        }
    }

    func testCatchAllIsLastAndKeywordless() {
        XCTAssertEqual(murror.deliverables.last?.keywords, [])
    }

    /// `"email capture"` has to be matched before anything looser, and each task must reach its
    /// own entry rather than a neighbour's.
    func testEachTaskReachesItsOwnDeliverable() {
        let expected: [(String, String)] = [
            ("Build the Murror landing page", "site"),
            ("Design the first-run flow", "screens"),
            ("Decide what free and paid mean", "sheet"),
            ("Ship an email capture", "checklist"),
            ("Find the first 20 users", "dms"),
            ("Answer the first questions", "doc"),
            ("Write the launch checklist", "plan"),
            ("Draft the privacy policy", "legal"),
        ]
        for (title, kind) in expected {
            XCTAssertEqual(murror.deliverable(for: title).kind, kind, "'\(title)' resolved wrongly")
        }
    }

    // MARK: - The website

    /// `SitePayload.init(from:)` hard-decodes six anchor fields and throws when any is absent,
    /// so this fails the moment the fixture would render a broken page.
    func testSitePayloadDecodes() throws {
        let entry = murror.deliverable(for: "Build the Murror landing page")
        XCTAssertEqual(entry.kind, "site")
        let json = try XCTUnwrap(entry.payloadJSON)
        let payload = try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
        let site = try XCTUnwrap(payload.site, "the site payload did not decode")
        XCTAssertEqual(site.brand, "Murror")
        XCTAssertEqual(site.headline, "AI that brings people")
        XCTAssertEqual(site.headlineHi, "closer")
        XCTAssertEqual(site.steps.count, 3)
        XCTAssertEqual(site.features.count, 4)
        XCTAssertFalse(site.finalCta.isEmpty)
    }

    /// Every structured payload in the table must decode into the field its kind reads. A
    /// payload that fails to decode leaves the viewer empty and says nothing about why — the
    /// `dms` shape was wrong on the first draft of this fixture for exactly that reason.
    func testEveryStructuredPayloadDecodesIntoItsOwnField() throws {
        for entry in murror.deliverables where entry.payloadJSON != nil {
            let json = try XCTUnwrap(entry.payloadJSON)
            let p = try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
            switch entry.kind {
            case "site":    XCTAssertNotNil(p.site, "site payload did not decode")
            case "screens": XCTAssertNotNil(p.screens, "screens payload did not decode")
            case "sheet":   XCTAssertNotNil(p.sheet, "sheet payload did not decode")
            case "dms":     XCTAssertNotNil(p.messages, "dms payload did not decode")
            default:        XCTFail("\(entry.kind) carries a payload with no assertion here")
            }
        }
    }

    /// Only `art` values `connect` / `session` / `recap` draw a real illustration; anything
    /// else hits `artStandIn`'s default and renders a questionmark box.
    func testScreenArtValuesAreRenderable() throws {
        let entry = murror.deliverable(for: "Design the first-run flow")
        let json = try XCTUnwrap(entry.payloadJSON)
        let p = try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
        let screens = try XCTUnwrap(p.screens?.screens)
        XCTAssertFalse(screens.isEmpty)
        for s in screens {
            XCTAssertTrue(["connect", "session", "recap"].contains(s.art),
                          "art '\(s.art)' renders a placeholder box")
        }
    }

    /// `buildHTML` paints `accent` behind white text in three places, and `safeHex` validates
    /// hex SYNTAX rather than contrast — so nothing else in the codebase would catch a brand
    /// colour that renders white-on-pale. Murror's warm gold (#ffecb4) is exactly that trap.
    func testSiteAccentIsDarkEnoughForWhiteText() throws {
        let entry = murror.deliverable(for: "Build the Murror landing page")
        let json = try XCTUnwrap(entry.payloadJSON)
        let p = try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
        let hex = try XCTUnwrap(p.site?.accent)
        XCTAssertLessThan(try relativeLuminance(hex), 0.4,
                          "\(hex) is too light to sit behind white text")
    }

    /// Decode is not render. This drives the actual `SitePayload → String` path the WKWebView
    /// loads, so a payload that decodes but renders an empty page still fails here.
    ///
    /// Also the only way to see the page from a machine where Screen Recording is denied:
    /// set `CODEPET_DUMP_SITE=/tmp/murror-site.html` and open the result.
    func testSiteRendersRealHTML() throws {
        let entry = murror.deliverable(for: "Build the Murror landing page")
        let json = try XCTUnwrap(entry.payloadJSON)
        let p = try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
        let site = try XCTUnwrap(p.site)
        let html = SiteViewer.buildHTML(site)

        // Written every run, and the path LOGGED rather than assumed. `xcodebuild` does not
        // forward the parent environment to a unit-test host — a `CODEPET_DUMP_SITE` env gate
        // and a `TEST_RUNNER_`-prefixed build setting both silently wrote nothing — so the
        // trigger is removed rather than made conditional on something that does not arrive.
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("murror-site.html")
        try? html.write(to: out, atomically: true, encoding: .utf8)
        NSLog("[murror-site] %d bytes → %@", html.utf8.count, out.path)

        XCTAssertTrue(html.hasPrefix("<!"), "not a document")
        // The accent reaches the stylesheet, so the CTA really is navy rather than the fallback.
        XCTAssertTrue(html.contains("#0a1430"), "the accent never reached the CSS")
        XCTAssertFalse(html.contains("#7c3aed"), "safeHex fell back — the accent was rejected")
        // Content, not just chrome.
        XCTAssertTrue(html.contains("AI that brings people"))
        XCTAssertTrue(html.contains("THE CONNECTION PRACTICE"))
        XCTAssertTrue(html.contains("Name what you feel"))
        XCTAssertTrue(html.contains("Private by design"))
        XCTAssertTrue(html.contains("Open Murror"))
        XCTAssertTrue(html.contains("Made by MURROR"))
        // Every optional section actually rendered rather than being skipped as empty.
        for id in ["id=\"how\"", "id=\"features\""] {
            XCTAssertTrue(html.contains(id), "section \(id) did not render")
        }
        XCTAssertFalse(html.contains("{{product}}"), "an unfilled token reached the page")
    }

    private func relativeLuminance(_ hex: String) throws -> Double {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let n = try XCTUnwrap(UInt32(digits, radix: 16))
        func channel(_ raw: UInt32) -> Double {
            let c = Double(raw) / 255.0
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((n >> 16) & 0xFF)
             + 0.7152 * channel((n >> 8) & 0xFF)
             + 0.0722 * channel(n & 0xFF)
    }

    // MARK: - The room

    /// The whole value of building the fixture on the wire format: a renamed key shows up here
    /// rather than as a missing card in the app.
    func testEveryRoomFrameDecodes() {
        let frames = murror.roomFrames("Should we ship emotion detection before a clinician reviews it?")
        XCTAssertFalse(frames.isEmpty)
        for frame in frames {
            XCTAssertNotNil(VirtualCompanyEvent.from(frame: frame),
                            "frame '\(frame.event)' did not decode")
        }
    }

    /// Contract rule 2: never collapse the positions into consensus. Consensus is what a fixture
    /// fakes most easily, so the room must still be unresolved at the end.
    func testRoomDoesNotResolve() throws {
        let frames = murror.roomFrames("anything")
        let brief = try XCTUnwrap(frames.first { $0.event == "brief" })
        XCTAssertTrue(brief.data.contains("\"unresolved\":true"))
    }

    func testRoomConvenesFourDepartmentsIncludingSupportAndLegal() {
        let frames = murror.roomFrames("anything")
        XCTAssertEqual(frames.filter { $0.event == "agent_position" }.count, 4)
        for dept in ["legal", "design", "support", "eng"] {
            XCTAssertTrue(frames.contains {
                $0.event == "agent_position" && $0.data.contains("\"department_key\":\"\(dept)\"")
            }, "\(dept) has no position in the room")
        }
    }

    /// Rule 2 again, from the other side: a room where nobody blocks is a room that agreed.
    func testRoomHasAHardBlocker() {
        let frames = murror.roomFrames("anything")
        XCTAssertTrue(frames.contains { $0.event == "conflicts" && $0.data.contains("BLOCKER") })
        XCTAssertTrue(frames.contains {
            $0.event == "agent_position" && $0.data.contains("\"stance\":\"do_not_proceed\"")
        })
    }

    /// The ask is encoded into `real_question`, so a quote mark must not produce invalid JSON
    /// and silently drop the routing frame — which is the whole room.
    func testRoomSurvivesAQuotedAsk() throws {
        let frames = murror.roomFrames("do we ship \"emotion detection\" now?")
        let routing = try XCTUnwrap(frames.first { $0.event == "routing" })
        XCTAssertNotNil(VirtualCompanyEvent.from(frame: routing),
                        "a quoted ask broke the routing frame")
    }

    /// Nothing was spent. A fixture reporting a dollar figure would be inventing a charge in the
    /// one place the founder checks for real ones.
    func testRoomReportsZeroCost() throws {
        let frames = murror.roomFrames("anything")
        let telemetry = try XCTUnwrap(frames.first { $0.event == "telemetry" })
        XCTAssertTrue(telemetry.data.contains("\"cost_estimate_usd\":0"))
    }

    /// The contract is explicit that the devil's advocate must not wear a department colour.
    func testDevilsAdvocateHasNoDepartment() throws {
        let frames = murror.roomFrames("anything")
        let da = try XCTUnwrap(frames.first { $0.event == "devils_advocate" })
        XCTAssertTrue(da.data.contains("\"department_key\":null"))
    }

    // MARK: - End to end

    /// The one mechanism change: `runResult` hardcoded `payload: nil`, which is why no run could
    /// ever produce a website.
    func testRunResultCarriesTheSitePayload() async {
        DemoProject.select("murror")
        let req = RunTaskRequest(companyId: nil, language: "en", companionId: "nova",
                                 context: "", taskId: "mur-site",
                                 taskTitle: "Build the Murror landing page",
                                 taskDetail: "")
        let res = await MockChat.runResult(req)
        XCTAssertEqual(res?.kind, "site")
        XCTAssertNotNil(res?.payload?.site, "the run produced no site payload")
        XCTAssertEqual(res?.payload?.site?.brand, "Murror")
    }

    /// Selecting Murror must actually change the company `CompanyData.load` hands back.
    func testSelectingMurrorChangesTheCompany() {
        DemoProject.select("murror")
        XCTAssertEqual(MockChat.company().brief.projectName, "Murror")
        XCTAssertEqual(MockChat.roadmap().count, 18)
        XCTAssertEqual(MockChat.productName, "Murror")
    }

    /// **The board said Murror and the greeting said Codepet.**
    ///
    /// `flowBrief` exists so a re-hydrate does not replace the project the founder typed in
    /// the cold open, and it silently outranked the demo-project selection. With
    /// `CODEPET_MOCK_FLOW` persisted from an earlier session, launching
    /// `-CODEPET_DEMO_PROJECT murror` produced Murror's tasks under "What should we build for
    /// Codepet today?" — reported from the app as "why don't I see any changes at all?",
    /// because the project name is the most visible thing on screen and it had not changed.
    ///
    /// The board was never wrong, which is what made it confusing: `roadmap()` read the demo
    /// project and `company().brief` did not.
    func testAStaleFlowBriefDoesNotOverrideTheSelectedProject() {
        DemoProject.select("murror")
        var stale = CompanyBrief()
        stale.projectName = "Codepet"
        MockChat.flowBrief = stale
        MockChat.flowBriefProject = "codepet"
        defer { MockChat.flowBrief = nil; MockChat.flowBriefProject = nil }

        XCTAssertEqual(MockChat.company().brief.projectName, "Murror",
                       "a brief captured under Codepet outranked an explicit Murror selection")
        XCTAssertEqual(MockChat.productName, "Murror")
    }

    /// The other direction must keep working: a brief captured under THIS project still wins,
    /// or the flow demo would forget what the founder typed on the next hydrate.
    func testAFlowBriefForTheSelectedProjectStillWins() {
        DemoProject.select("murror")
        var typed = CompanyBrief()
        typed.projectName = "Murror Labs"
        MockChat.flowBrief = typed
        MockChat.flowBriefProject = "murror"
        defer { MockChat.flowBrief = nil; MockChat.flowBriefProject = nil }

        XCTAssertEqual(MockChat.company().brief.projectName, "Murror Labs")
        XCTAssertEqual(MockChat.productName, "Murror Labs")
    }

    /// A capture from before the project was stamped has no project to compare against, so it
    /// keeps its old precedence rather than being silently discarded.
    func testAnUnstampedFlowBriefKeepsItsOldPrecedence() {
        DemoProject.select("murror")
        var legacy = CompanyBrief()
        legacy.projectName = "Something Typed"
        MockChat.flowBrief = legacy
        MockChat.flowBriefProject = nil
        defer { MockChat.flowBrief = nil }

        XCTAssertEqual(MockChat.company().brief.projectName, "Something Typed")
    }

    /// `{{product}}` must resolve to Murror, not to Codepet, in Murror's own copy.
    func testProductTokenFillsWithMurror() {
        DemoProject.select("murror")
        let filled = MockChat.fill(murror.deliverable(for: "Draft the privacy policy").body)
        XCTAssertTrue(filled.contains("Murror"))
        XCTAssertFalse(filled.contains("{{product}}"))
    }
}
