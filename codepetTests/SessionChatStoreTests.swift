import XCTest
@testable import codepet

final class SessionChatStoreTests: XCTestCase {

    func testChatMessageRoundTripsThroughCodable() throws {
        let original = ChatMessage(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            role: .pet,
            text: "Hỏi mình về phiên này nhé.",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testThreadRoundTripsThroughCodable() throws {
        let thread = SessionChatThread(
            sessionId: "s1",
            messages: [
                ChatMessage(id: UUID(), role: .user, text: "what happened?", createdAt: Date(timeIntervalSince1970: 1_700_000_001)),
                ChatMessage(id: UUID(), role: .pet, text: "Together we…", createdAt: Date(timeIntervalSince1970: 1_700_000_002))
            ],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
        let data = try JSONEncoder().encode(thread)
        let decoded = try JSONDecoder().decode(SessionChatThread.self, from: data)
        XCTAssertEqual(decoded.sessionId, thread.sessionId)
        XCTAssertEqual(decoded.messages, thread.messages)
        XCTAssertEqual(decoded.updatedAt, thread.updatedAt)
    }

    private func tempFileURL(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
    }

    @MainActor
    func testAppendAndRetrieveMessagesIsolatedPerSession() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SessionChatStore(fileURL: url, saveDebounce: 0)

        let m1 = ChatMessage(id: UUID(), role: .user, text: "a", createdAt: Date())
        let m2 = ChatMessage(id: UUID(), role: .pet, text: "b", createdAt: Date())
        let m3 = ChatMessage(id: UUID(), role: .user, text: "c", createdAt: Date())

        store.append(m1, to: "s1")
        store.append(m2, to: "s1")
        store.append(m3, to: "s2")

        XCTAssertEqual(store.messages(for: "s1").map(\.text), ["a", "b"])
        XCTAssertEqual(store.messages(for: "s2").map(\.text), ["c"])
        XCTAssertEqual(store.messages(for: "s3"), [])
    }

    @MainActor
    func testPersistsAndReloadsFromDisk() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let store = SessionChatStore(fileURL: url, saveDebounce: 0)
            store.append(ChatMessage(id: UUID(), role: .user, text: "hi", createdAt: Date(timeIntervalSince1970: 1)), to: "s1")
            store.flushForTests()
        }

        let store2 = SessionChatStore(fileURL: url, saveDebounce: 0)
        XCTAssertEqual(store2.messages(for: "s1").map(\.text), ["hi"])
    }

    @MainActor
    func testHistorySnapshotReturnsLastNInOrder() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SessionChatStore(fileURL: url, saveDebounce: 0)

        for i in 1...15 {
            store.append(
                ChatMessage(id: UUID(), role: i.isMultiple(of: 2) ? .pet : .user, text: "m\(i)", createdAt: Date(timeIntervalSince1970: TimeInterval(i))),
                to: "s1"
            )
        }

        let snapshot = store.historySnapshot(for: "s1", lastN: 10)
        XCTAssertEqual(snapshot.count, 10)
        XCTAssertEqual(snapshot.first?.text, "m6")
        XCTAssertEqual(snapshot.last?.text, "m15")
    }

    @MainActor
    func testCorruptFileFallsBackToEmptyStore() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try "not valid json".data(using: .utf8)!.write(to: url)

        let store = SessionChatStore(fileURL: url, saveDebounce: 0)
        XCTAssertEqual(store.messages(for: "s1"), [])
    }
}
