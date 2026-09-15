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

    /// A frame that arrives in two pieces must not dispatch early, and must not lose the
    /// half it already has.
    ///
    /// **Nothing covered this before.** Every other case here hands over one complete batch
    /// in a single `feedLines` call, so the parser's state between calls went untested; the
    /// only thing proving it was an SSE chunk split mid-frame over HTTP, in a transport that
    /// no longer exists. `LocalChatStreamer` depends on exactly this — it keeps the trailing
    /// partial line in `pending` and feeds whole lines as they complete, so a parser that
    /// reset between feeds would truncate a `data:` line and hand the founder half a reply.
    func testHoldsAFrameAcrossSeparateFeeds() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feedLines(["event: delta"]), [],
                       "no blank line yet — nothing may dispatch")
        XCTAssertEqual(parser.feedLines(["data: {\"text\":\"Hello\"}"]), [],
                       "still no blank line — nothing may dispatch")
        XCTAssertEqual(parser.feedLines([""]),
                       [SSEFrame(event: "delta", data: "{\"text\":\"Hello\"}")],
                       "the frame built across three feeds arrived truncated or not at all")
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
