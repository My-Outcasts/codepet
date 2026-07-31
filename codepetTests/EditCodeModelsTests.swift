// codepetTests/EditCodeModelsTests.swift
import XCTest
@testable import codepet

final class EditCodeModelsTests: XCTestCase {
    // EditCodePlanner: multi-file or bash ⇒ preview; single simple ⇒ no preview.
    func test_needsPreview_multiFile() {
        XCTAssertTrue(EditCodePlanner.needsPreview(plannedFiles: 2, needsBash: false))
    }
    func test_needsPreview_bash() {
        XCTAssertTrue(EditCodePlanner.needsPreview(plannedFiles: 1, needsBash: true))
    }
    func test_needsPreview_singleSimple() {
        XCTAssertFalse(EditCodePlanner.needsPreview(plannedFiles: 1, needsBash: false))
    }
    // Routing: engineering + linked ⇒ route.
    func test_shouldRoute_engAndLinked() {
        let eng = DepartmentCatalog.all.first { $0.key == "eng" }
        XCTAssertTrue(EditCodeRouting.shouldRoute(department: eng, projectLinked: true))
    }
    func test_shouldRoute_notLinked() {
        let eng = DepartmentCatalog.all.first { $0.key == "eng" }
        XCTAssertFalse(EditCodeRouting.shouldRoute(department: eng, projectLinked: false))
    }
    func test_shouldRoute_nonEng() {
        let mkt = DepartmentCatalog.all.first { $0.key != "eng" }
        XCTAssertFalse(EditCodeRouting.shouldRoute(department: mkt, projectLinked: true))
    }
}
