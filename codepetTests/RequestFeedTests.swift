import Speech
import XCTest
@testable import codepet

/// `SpeechListener.RequestFeed` — the box the audio tap feeds, and the staleness test
/// every recognition callback goes through.
///
/// **Why this file may construct a Speech type when nothing else may.**
/// `SFSpeechAudioBufferRecognitionRequest` is not `SFSpeechRecognizer`: it needs no
/// recognizer, no audio engine and no microphone — it is a buffer sink with a couple of
/// flags. Constructing one is the only way to pin the *identity* half of the feed with
/// real objects, and identity is what stops turn N's transcript arriving as turn N+1's
/// `onPartial` after a `renew()`. No recognizer is created, no task is started, no
/// buffer is appended, and nothing here touches audio hardware.
///
/// It matters because `renew()` — now called at every turn boundary, not just at the
/// ~1 minute limit — depends entirely on the retired request stopping being "current".
/// If `isCurrent` ever answered yes for a retired request, the cancelled task's late
/// callback would be treated as live and deliver the previous turn's words again.
final class RequestFeedTests: XCTestCase {

    func testOnlyTheRequestMostRecentlyInstalledIsCurrent() {
        let feed = SpeechListener.RequestFeed()
        let first = SFSpeechAudioBufferRecognitionRequest()
        let second = SFSpeechAudioBufferRecognitionRequest()

        XCTAssertFalse(feed.isCurrent(first), "an empty feed claimed a request")

        feed.replace(with: first)
        XCTAssertTrue(feed.isCurrent(first))
        XCTAssertFalse(feed.isCurrent(second))

        // What `renew()` does: the retiring request must stop being current the moment
        // the fresh one is installed, or its cancellation callback acts on the new turn.
        feed.replace(with: second)
        XCTAssertFalse(feed.isCurrent(first),
                       "a retired request stayed current, so its late callback speaks for the new turn")
        XCTAssertTrue(feed.isCurrent(second))
    }

    /// `endAudio()` is `stop()`'s half of it: close the request and stop feeding
    /// anything. Idempotent, because `stop()` is unconditional and doubles as the
    /// rollback for a half-configured graph.
    func testEndAudioRetiresTheRequestAndIsIdempotent() {
        let feed = SpeechListener.RequestFeed()
        let request = SFSpeechAudioBufferRecognitionRequest()
        feed.replace(with: request)

        feed.endAudio()
        XCTAssertFalse(feed.isCurrent(request),
                       "a closed request was still being fed")
        feed.endAudio()
        XCTAssertFalse(feed.isCurrent(request))

        // And it can be reused afterwards — `start()` after `stop()` is ordinary.
        let next = SFSpeechAudioBufferRecognitionRequest()
        feed.replace(with: next)
        XCTAssertTrue(feed.isCurrent(next))
    }

    /// `replace(with: nil)` is not `endAudio()`: nothing is closed, but nothing is fed
    /// either. Kept apart so a future caller cannot reach for the wrong one.
    func testReplacingWithNilLeavesNothingCurrent() {
        let feed = SpeechListener.RequestFeed()
        let request = SFSpeechAudioBufferRecognitionRequest()
        feed.replace(with: request)
        feed.replace(with: nil)
        XCTAssertFalse(feed.isCurrent(request))
    }
}
