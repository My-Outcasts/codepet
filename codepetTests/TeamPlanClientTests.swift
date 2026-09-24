import XCTest
@testable import codepet

final class TeamPlanClientTests: XCTestCase {
    func testDecodesTheOpsResponse() {
        let json = #"{"title":"Pants","slug":"pants","summary":"s","projectType":"static landing page","steps":[{"id":"s1","dept":"mkt","title":"Msg","instruction":"i","kind":"doc","dependsOn":[]},{"id":"build","dept":"eng","title":"Build the project","instruction":"","kind":"other","dependsOn":["s1"]}]}"#
        let plan = TeamPlanClient.decode(Data(json.utf8))
        XCTAssertEqual(plan?.steps.map(\.id), ["s1", "build"])
    }
    func testGarbageDecodesToNil() {
        XCTAssertNil(TeamPlanClient.decode(Data("nope".utf8)))
    }
    func testBriefEncodesWithTheKeysTheOpReads() throws {
        let brief = VCBrief(recommendation: "r", confidence: 3, confidenceReason: "c", theRealDisagreement: "d",
                            tradeoffFounderMustOwn: "t", killCriteria: ["k"], nextAction: VCNextAction(action: "a", owner: "o"),
                            whatWeDontKnow: "w", unresolved: false)
        let req = TeamPlanRequest(language: "en", request: "x", brief: brief, company: [:], roster: ["mkt"])
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as! [String: Any]
        let b = obj["brief"] as! [String: Any]
        for key in ["recommendation", "tradeoff_founder_must_own", "kill_criteria", "what_we_dont_know"] {
            XCTAssertNotNil(b[key], "the op reads \(key)")
        }
    }
}
