// codepetTests/CommitSlugTests.swift
import XCTest
@testable import codepet

final class CommitSlugTests: XCTestCase {
    func test_make_lowercasesAndHyphenates() {
        XCTAssertEqual(CommitSlug.make(from: "Add Landing Page Copy"), "add-landing-page-copy")
    }
    func test_make_stripsPunctuationAndCollapsesSpaces() {
        XCTAssertFalse(CommitSlug.make(from: "Fix: the  bug!!").contains(" "))
    }
    func test_make_nonEmptyForEmptyInput() {
        XCTAssertFalse(CommitSlug.make(from: "").isEmpty)
    }
}
