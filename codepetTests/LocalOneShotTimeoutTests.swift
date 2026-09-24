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

    func testDefaultIsThreeMinutes() {
        XCTAssertEqual(LocalOneShotRunner.defaultTimeout, 180)
    }
}
