// codepetTests/CompanyDataLibraryTests.swift
import XCTest
@testable import codepet

final class CompanyDataLibraryTests: XCTestCase {
    func testStateMapsLibrary() {
        let d = Deliverable(id: "d1", kind: .plan, title: "Plan", body: "x")
        let s = CompanyData.state(from: CompanyDoc(brief: CompanyBrief(), stage: nil,
                                                   companionId: nil, onboardedAt: nil, tasks: nil, library: [d]))
        XCTAssertEqual(s.library.map(\.id), ["d1"])
        let empty = CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil,
                                                       onboardedAt: nil, tasks: nil, library: nil))
        XCTAssertEqual(empty.library, [])
    }
}
