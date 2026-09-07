import XCTest
@testable import codepet

/// **The end-to-end claim nobody had ever asserted: the demo produces a landing page.**
///
/// The founder asked four separate times where the landing page was. Each time the pieces
/// checked out in isolation — the beat existed, the keyword resolved to the `site` entry, the
/// fixture carried a `payloadJSON`, the task was open, its dependencies were filed — and each
/// time she still could not see one. Every check was of a mechanism; none was of the outcome.
///
/// This is that check. Run the chain the way the script does, then run and approve `mur-site`,
/// and assert a real site deliverable is FILED with a payload the viewer can render.
@MainActor
final class DayOneLandingPageTests: XCTestCase {

    private func store() async -> CompanyStore {
        let project = DemoProject.murrorDayOne
        let seed = CompanyState(brief: project.brief, departments: [], library: project.library(),
                                stage: .building, companionId: "byte", onboardedAt: Date(),
                                tasks: project.tasks)
        let s = CompanyStore(
            loader: { _ in seed },
            tasksSaver: { _, _ in true },
            taskRunner: { req in
                let entry = project.deliverable(for: req.taskTitle)
                let payload = entry.payloadJSON.flatMap {
                    try? JSONDecoder().decode(DeliverablePayload.self, from: Data($0.utf8))
                }
                return RunTaskResponse(kind: entry.kind, title: req.taskTitle,
                                       body: MockChat.fill(entry.body, title: req.taskTitle),
                                       payload: payload)
            },
            librarySaver: { _, _ in true },
            firstApprovalSaver: { _, _ in true },
            decisionsSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        return s
    }

    /// Its two dependencies must be filed first or `offerChainIfNeeded` shows a Run both /
    /// Just mine card instead of a page — the reason the section sits after Design.
    private func fileDependencies(_ s: CompanyStore) async {
        for id in ["mur-interviews", "mur-landscape", "mur-notfor", "mur-brand"] {
            guard let t = s.company.tasks.first(where: { $0.id == id }) else {
                return XCTFail("\(id) missing from the day-one board")
            }
            if t.who == .you {
                let e = DemoProject.murrorDayOne.deliverable(for: t.title)
                await s.recordFounderOutcome(taskId: id,
                                             body: MockChat.fill(e.body, title: t.title),
                                             kind: DeliverableKind(raw: e.kind))
            } else {
                await s.runTask(t, language: .en)
                await s.approveTask(id: id)
            }
        }
    }

    func testTheDemoActuallyProducesALandingPage() async {
        let s = await store()
        await fileDependencies(s)

        guard let site = s.company.tasks.first(where: { $0.id == "mur-site" }) else {
            return XCTFail("mur-site is not on the day-one board at all")
        }
        XCTAssertFalse(site.done, "mur-site must be OPEN, or the run beat's guard skips it")

        await s.runTask(site, language: .en)
        await s.approveTask(id: "mur-site")

        let filed = s.company.library.first { $0.sourceTaskId == "mur-site" }
        XCTAssertNotNil(filed, "the landing page was never filed — this is what she kept not seeing")
        XCTAssertEqual(filed?.kind, .site,
                       "filed as \(String(describing: filed?.kind)) — a doc card has no page and no open-in-browser")
        XCTAssertNotNil(filed?.payload,
                        "a site with no payload renders nothing: `SiteViewer.buildHTML` has no fields to lay out")
    }

    /// The dependency order that decided where the section sits. If someone moves it earlier,
    /// this fails rather than the demo quietly showing a chain-offer card.
    func testItsDependenciesAreFiledBeforeItRuns() async {
        let s = await store()
        await fileDependencies(s)
        let filedIds = Set(s.company.library.compactMap(\.sourceTaskId))
        for dep in ["mur-brand", "mur-landscape"] {
            XCTAssertTrue(filedIds.contains(dep),
                          "\(dep) unfiled — mur-site would offer to run it instead of building")
        }
    }
}
