// codepetTests/MessageFeedbackPayloadTests.swift
import XCTest
@testable import codepet

/// The payload has to satisfy `firestore.rules:37-43`, which is the only thing standing
/// between a thumb and a silent write failure in production. These assertions ARE the rule:
/// `rating is int` in 1...5 and `feature is string`. If someone switches rating to a Bool
/// or empties feature, these go red here rather than failing at the Firestore boundary
/// where nothing surfaces to the founder.
final class MessageFeedbackPayloadTests: XCTestCase {

    private func build(_ vote: MessageVote) -> [String: Any] {
        MessageFeedbackPayload.build(vote: vote, messageId: "m1", threadId: "t1",
                                     companionId: "glitch", deptName: "Engineering",
                                     userId: "u1", authMethod: "google",
                                     displayName: "Mona", pet: "byte",
                                     appVersion: "1.2", build: "42")
    }

    func testThumbUpIsRatingFive() {
        XCTAssertEqual(build(.up)["rating"] as? Int, 5)
    }

    func testThumbDownIsRatingOne() {
        XCTAssertEqual(build(.down)["rating"] as? Int, 1)
    }

    /// The rule reads `request.resource.data.rating is int`. A Bool would be rejected.
    func testRatingSatisfiesTheFirestoreRule() {
        for vote in [MessageVote.up, .down] {
            guard let rating = build(vote)["rating"] as? Int else {
                return XCTFail("rating must be an Int — the rule reads `rating is int`")
            }
            XCTAssertTrue((1...5).contains(rating))
        }
    }

    func testFeatureIsANonEmptyStringDistinctFromCompanionChat() {
        let feature = build(.up)["feature"] as? String
        XCTAssertEqual(feature, "chatMessage")
        XCTAssertNotEqual(feature, FeedbackFeature.companionChat.rawValue,
                          "thumbs must not pollute the 5-face companionChat stats")
    }

    func testPayloadCarriesTheMessageAndThreadIdentity() {
        let data = build(.up)
        XCTAssertEqual(data["messageId"] as? String, "m1")
        XCTAssertEqual(data["threadId"] as? String, "t1")
        XCTAssertEqual(data["companionId"] as? String, "glitch")
        XCTAssertEqual(data["deptName"] as? String, "Engineering")
    }

    func testPayloadCarriesTheSameIdentityFieldsAsTheExistingToast() {
        let data = build(.up)
        XCTAssertEqual(data["userId"] as? String, "u1")
        XCTAssertEqual(data["authMethod"] as? String, "google")
        XCTAssertEqual(data["displayName"] as? String, "Mona")
        XCTAssertEqual(data["pet"] as? String, "byte")
        XCTAssertEqual(data["appVersion"] as? String, "1.2")
        XCTAssertEqual(data["build"] as? String, "42")
        XCTAssertEqual(data["platform"] as? String, "macos")
    }

    func testNilCompanionAndDeptAreOmittedRatherThanWrittenAsNull() {
        let data = MessageFeedbackPayload.build(vote: .up, messageId: "m1", threadId: "t1",
                                                companionId: nil, deptName: nil,
                                                userId: "u1", authMethod: "guest",
                                                displayName: "Mona", pet: "byte",
                                                appVersion: "1.2", build: "42")
        XCTAssertNil(data["companionId"])
        XCTAssertNil(data["deptName"])
    }

    /// `activeThreadId` stays nil until the first `flushActiveThread()`, and the first-run
    /// greeting is appended without flushing (`CompanyStore.swift:315-320`), so a thumb on
    /// that greeting reaches `build` with `threadId: ""`. The rule denies `update`
    /// (`firestore.rules:42`), so a written `""` could never be corrected — it must be
    /// omitted rather than written, the same as a nil companion/dept.
    func testEmptyThreadIdIsOmittedRatherThanWrittenAsEmptyString() {
        let data = MessageFeedbackPayload.build(vote: .up, messageId: "m1", threadId: "",
                                                companionId: "glitch", deptName: "Engineering",
                                                userId: "u1", authMethod: "guest",
                                                displayName: "Mona", pet: "byte",
                                                appVersion: "1.2", build: "42")
        XCTAssertNil(data["threadId"])
    }

    func testChatMessageFeatureExists() {
        XCTAssertEqual(FeedbackFeature.chatMessage.rawValue, "chatMessage")
    }
}
