import XCTest
@testable import codepet

/// Guards that a demo project is a WHOLE company, not Codepet's fixture with a name swapped.
///
/// The `DemoProject` seam exists so a second company can be demoed without find-replace. One
/// surface never moved behind it: `MockChat.departmentReply` hardcoded Codepet's eight replies,
/// so arming a department chip on Murror produced a specialist naming tasks that are not on
/// Murror's board and telling the founder to say "run competitors" — a phrase matching no
/// Murror title, so the router fell through and drafted something unrelated.
///
/// These assert the properties that make a project self-consistent, for EVERY project, so a
/// third one cannot ship half-converted.
final class DemoProjectParityTests: XCTestCase {

    private var projects: [DemoProject] { DemoProject.all }

    /// **The guard that would have caught the bug.** Every task title a department reply bolds
    /// must exist on that project's own board.
    func testDepartmentRepliesOnlyNameTasksOnTheirOwnBoard() {
        for p in projects {
            let titles = Set(p.tasks.map(\.title))
            for (dept, reply) in p.departmentReplies {
                // Bolded task names are the claim being made: **Ship an email capture**.
                let bolded = reply.components(separatedBy: "**")
                    .enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
                for name in bolded where name.count > 12 {
                    XCTAssertTrue(titles.contains(name),
                                  "\(p.id)/\(dept) names \"\(name)\", which is not on its board")
                }
            }
        }
    }

    /// Every department with a runnable task should have something to say when its chip is armed.
    func testEveryDepartmentOnTheBoardHasAReply() {
        for p in projects {
            let depts = Set(p.tasks.compactMap(\.dept))
            for d in depts {
                XCTAssertNotNil(p.departmentReplies[d],
                                "\(p.id) has \(d) tasks but no \(d) chip reply")
            }
        }
    }

    /// A `who: .you` task that is still OPEN, or the "needs you" landing card, the `needsYou`
    /// roadmap state and the walkthrough's "Work only you can do" chapter have nothing to show.
    /// Murror shipped without one and that beat silently no-opped.
    func testEveryProjectHasAnOpenFounderOnlyTask() {
        for p in projects {
            XCTAssertTrue(p.tasks.contains { $0.who == .you && !$0.done },
                          "\(p.id) has no OPEN founder-only task — the 'work only you can do' "
                          + "surfaces render nothing")
        }
    }

    /// No unsubstituted tokens can reach a founder's screen.
    func testNoReplyLeaksATemplateToken() {
        for p in projects {
            for (dept, reply) in p.departmentReplies {
                XCTAssertFalse(reply.contains("{{"), "\(p.id)/\(dept) leaks a token")
            }
        }
    }

    /// The empty-table trap: `deliverable(for:)` used `deliverables[count - 1]`, which traps on
    /// index -1 rather than degrading.
    func testDeliverableLookupSurvivesAnEmptyTable() {
        let bare = DemoProject(id: "bare", brief: CompanyBrief(), tasks: [], deliverables: [],
                               roomFrames: { _ in [] })
        XCTAssertFalse(bare.deliverable(for: "anything").body.isEmpty,
                       "an empty table must degrade, not trap")
    }
}
