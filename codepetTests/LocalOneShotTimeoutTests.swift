import XCTest
@testable import codepet

/// A hung CLI call used to be unbounded: `run` waited on the process forever. A Team Build
/// chains several of them, so one hang would freeze the whole run with no way to say why.
final class LocalOneShotTimeoutTests: XCTestCase {
    func testAHungProcessIsKilledAndReportedAsATimeout() async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["5"]
        let started = Date()
        do {
            _ = try await LocalOneShotRunner.runProcess(p, stdin: Data(), timeout: 0.3, label: "test")
            XCTFail("a 5s sleep must not finish inside a 0.3s timeout")
        } catch let f as LocalOneShotRunner.Failure {
            XCTAssertEqual(f, .timedOut(seconds: 0))
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "the process was not killed")
    }

    func testAFastProcessReturnsItsStdout() async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/echo")
        p.arguments = ["{\"ok\":true}"]
        let out = try await LocalOneShotRunner.runProcess(p, stdin: Data(), timeout: 5, label: "test")
        XCTAssertEqual(String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), "{\"ok\":true}")
    }

    /// Stop on a Team Build cancels the department step's Task. Before this, cancelling only
    /// discarded the result: the node -> claude pair kept running on the founder's plan for up
    /// to 180 s. Cancellation must end the process, and say so with CancellationError.
    nonisolated func testCancellingTheTaskTerminatesTheProcess() async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        // 3 s, not longer: without the fix the sleep simply runs out, so the failure shows up
        // as an assertion (wrong error, too slow) rather than a hung test.
        p.arguments = ["3"]
        let started = Date()
        let task = Task.detached {
            try await LocalOneShotRunner.runProcess(p, stdin: Data(), timeout: 60, label: "test")
        }
        // Give it time to launch, so the cancel lands on a running process.
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(p.isRunning, "precondition: the sleep should be running")
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled run must not return a result")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "cancellation did not end the process")
        XCTAssertFalse(p.isRunning, "the process outlived the cancellation")
    }

    /// Cancelled before the process ever launched: it must not launch at all.
    nonisolated func testATaskCancelledBeforeLaunchNeverRunsTheProcess() async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["3"]
        let task = Task.detached {
            // Spin until the cancel has landed, so runProcess is entered already cancelled.
            while !Task.isCancelled { await Task.yield() }
            return try await LocalOneShotRunner.runProcess(p, stdin: Data(), timeout: 60, label: "test")
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled run must not return a result")
        } catch is CancellationError {
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertFalse(p.isRunning)
        XCTAssertEqual(p.processIdentifier, 0, "the process was launched after cancellation")
    }

    func testDefaultIsThreeMinutes() {
        XCTAssertEqual(LocalOneShotRunner.defaultTimeout, 180)
    }
}
