// codepetTests/FounderOptionsTests.swift
import XCTest
@testable import codepet

/// CP-031: the room's open question as two options the founder picks, with the lock-in naming
/// the pick. The backend sends `founder_options` only when it has exactly two good ones.
final class FounderOptionsTests: XCTestCase {
    private func briefJSON(options: String?) -> Data {
        let opts = options.map { ", \"founder_options\": \($0)" } ?? ""
        return Data("""
        {"recommendation":"Ship one page this week.","confidence":3,"confidence_reason":"c",
         "the_real_disagreement":"d","tradeoff_founder_must_own":"Message test or demand test.",
         "kill_criteria":["k"],"next_action":{"action":"a","owner":"founder"},
         "what_we_dont_know":"u","unresolved":true\(opts)}
        """.utf8)
    }

    private let two = """
    [{"label":"Message test","consequence":"Measure understanding; no pricing questions."},
     {"label":"Demand test","consequence":"Ask the price question; fewer signups."}]
    """

    func testTwoOptionsDecode() throws {
        let b = try JSONDecoder().decode(VCBrief.self, from: briefJSON(options: two))
        XCTAssertEqual(b.founderOptions?.map(\.label), ["Message test", "Demand test"])
        XCTAssertEqual(FounderChoice.options(b)?.count, 2)
    }

    /// An older sidecar (or the cloud path before a deploy) sends no options; the brief still decodes.
    func testABriefWithoutOptionsStillDecodes() throws {
        let b = try JSONDecoder().decode(VCBrief.self, from: briefJSON(options: nil))
        XCTAssertNil(b.founderOptions)
        XCTAssertNil(FounderChoice.options(b), "no options: the card keeps the paragraph")
    }

    /// Anything but exactly two is not an either/or; the card keeps the paragraph.
    func testOnlyExactlyTwoAreOffered() throws {
        let one = #"[{"label":"Message test","consequence":"x"}]"#
        let b = try JSONDecoder().decode(VCBrief.self, from: briefJSON(options: one))
        XCTAssertNil(FounderChoice.options(b))
    }

    func testTheLockInButtonNamesThePick() {
        let o = VCFounderOption(label: "Message test", consequence: "x")
        XCTAssertEqual(FounderChoice.lockInTitle(nil, lang: .en), "Pick one to lock in")
        XCTAssertEqual(FounderChoice.lockInTitle(o, lang: .en), "Lock in: Message test")
        XCTAssertEqual(FounderChoice.lockInTitle(o, lang: .vi), "Chốt: Message test")
    }

    /// The recorded decision is the pick, so later chat turns are grounded on what she chose,
    /// not on the room's recommendation alone.
    func testLockingInAPickRecordsThePick() throws {
        var s = VirtualCompanyRunState()
        s.apply(.runStarted(runId: "r1"))
        let routing = try JSONDecoder().decode(VCRouting.self, from: Data(
            #"{"decision":"multi_agent","agents":["product"],"real_question":"Which test first?","request_type":"DECISION"}"#.utf8))
        s.apply(.routing(routing))
        s.apply(.brief(try JSONDecoder().decode(VCBrief.self, from: briefJSON(options: two))))
        let pick = VCFounderOption(label: "Message test", consequence: "Measure understanding; no pricing questions.")
        let d = try XCTUnwrap(VirtualCompanyDecision.extracted(from: s, runId: "r1", choice: pick))
        XCTAssertEqual(d.topic, "Which test first?")
        XCTAssertEqual(d.statement, "Message test: Measure understanding; no pricing questions.")
        XCTAssertEqual(VirtualCompanyDecision.extracted(from: s, runId: "r1")?.statement, "Ship one page this week.")
    }
}
