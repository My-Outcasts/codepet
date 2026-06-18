import XCTest
@testable import codepet

final class SSEParserTests: XCTestCase {

    func testParsesSingleDeltaFrame() {
        var parser = SSEParser()
        let frames = parser.feedLines([
            "event: delta",
            "data: {\"text\":\"hi\"}",
            ""
        ])
        XCTAssertEqual(frames, [SSEFrame(event: "delta", data: "{\"text\":\"hi\"}")])
    }

    func testIgnoresCommentsAndUnknownFields() {
        var parser = SSEParser()
        let frames = parser.feedLines([
            ": keep-alive comment",
            "id: 123",
            "event: delta",
            "data: {\"text\":\"x\"}",
            ""
        ])
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.event, "delta")
    }

    func testJoinsMultiLineData() {
        var parser = SSEParser()
        let frames = parser.feedLines([
            "event: done",
            "data: line1",
            "data: line2",
            ""
        ])
        XCTAssertEqual(frames, [SSEFrame(event: "done", data: "line1\nline2")])
    }

    func testEmitsMultipleFrames() {
        var parser = SSEParser()
        let frames = parser.feedLines([
            "event: delta",
            "data: a",
            "",
            "event: delta",
            "data: b",
            "",
            "event: done",
            "data: {}",
            ""
        ])
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames.map(\.event), ["delta", "delta", "done"])
        XCTAssertEqual(frames.map(\.data), ["a", "b", "{}"])
    }

    func testDefaultsEventToMessageWhenAbsent() {
        var parser = SSEParser()
        let frames = parser.feedLines([
            "data: hi",
            ""
        ])
        XCTAssertEqual(frames, [SSEFrame(event: "message", data: "hi")])
    }

    func testStripsLeadingSpaceAfterColon() {
        // Per the SSE spec, a single space after the colon is stripped.
        var parser = SSEParser()
        let frames = parser.feedLines([
            "event:delta",
            "data:no-space",
            ""
        ])
        XCTAssertEqual(frames, [SSEFrame(event: "delta", data: "no-space")])
    }
}
