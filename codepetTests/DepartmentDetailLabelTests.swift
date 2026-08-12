// codepetTests/DepartmentDetailLabelTests.swift
import XCTest
@testable import codepet

/// The section label is the one piece of real logic in the department-detail
/// layout change. `SectionEyebrow` uppercases at render time, so this function
/// must return sentence case — a string that arrives pre-shouted would render
/// correctly and still be wrong the moment the eyebrow is reused elsewhere.
final class DepartmentDetailLabelTests: XCTestCase {

    func testEnglishLabelCountsWhatIsLeftOutOfTheTotal() {
        let label = DepartmentDetailView.tasksLabel(left: 4, total: 6, lang: .en)
        XCTAssertEqual(label, "What needs doing · 4 of 6 left")
    }

    func testVietnameseLabelCountsWhatIsLeftOutOfTheTotal() {
        let label = DepartmentDetailView.tasksLabel(left: 4, total: 6, lang: .vi)
        XCTAssertEqual(label, "Việc cần làm · còn 4/6")
    }

    func testLabelIsSentenceCaseSoTheEyebrowOwnsTheUppercasing() {
        let label = DepartmentDetailView.tasksLabel(left: 1, total: 3, lang: .en)
        XCTAssertNotEqual(label, label.uppercased(),
                          "tasksLabel must not pre-shout; SectionEyebrow uppercases")
    }

    func testEveryTaskDoneStillReadsAsZeroLeft() {
        let label = DepartmentDetailView.tasksLabel(left: 0, total: 6, lang: .en)
        XCTAssertEqual(label, "What needs doing · 0 of 6 left")
    }
}
