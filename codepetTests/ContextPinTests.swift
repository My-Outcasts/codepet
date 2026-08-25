import XCTest
@testable import codepet

/// The pin is a value type with three rules worth protecting: it is namespaced by
/// case, it de-dupes, and it caps. All three are here because the alternative to
/// each one is a real defect — a task id colliding with a deliverable id, the same
/// document pinned twice, or a founder pinning her whole Library into one prompt.
final class ContextPinTests: XCTestCase {

    func testIdIsNamespacedByCase() {
        // Deliverable ids and task ids come from different collections. Without the
        // namespace, a collision would make one pin silently replace the other.
        let d = ContextPin.deliverable(id: "abc", title: "Pricing page")
        let t = ContextPin.task(id: "abc", title: "Ship billing")
        XCTAssertNotEqual(d.id, t.id)
        XCTAssertEqual(d.id, "deliverable:abc")
        XCTAssertEqual(t.id, "task:abc")
    }

    func testAddingTheSamePinTwiceIsANoOp() {
        let pin = ContextPin.deliverable(id: "abc", title: "Pricing page")
        let once = ContextPin.adding(pin, to: [])
        let twice = ContextPin.adding(pin, to: once)
        XCTAssertEqual(twice.count, 1, "the same deliverable pinned twice is two pills and two grounding blocks")
    }

    func testAddingStopsAtTheCap() {
        // The cap matches selectPriorWork's own max: 3 and keeps the pill row to one
        // line at the 380pt dock width.
        var pins: [ContextPin] = []
        for i in 0..<10 {
            pins = ContextPin.adding(.task(id: "t\(i)", title: "Task \(i)"), to: pins)
        }
        XCTAssertEqual(pins.count, ContextPin.max)
        XCTAssertEqual(ContextPin.max, 3)
        XCTAssertEqual(pins.first?.title, "Task 0", "the cap must drop the NEW pin, not silently evict the founder's first choice")
    }

    func testRemovingTakesOutOnlyThatPin() {
        let a = ContextPin.deliverable(id: "a", title: "A")
        let b = ContextPin.task(id: "b", title: "B")
        let left = ContextPin.removing(a, from: [a, b])
        XCTAssertEqual(left, [b])
    }

    func testDeliverableIdIsNilForATask() {
        // Task 2's exclusion set is built from this. A task leaking into it would
        // silently drop a Library entry from the automatic prior-work block.
        XCTAssertEqual(ContextPin.deliverable(id: "abc", title: "A").deliverableId, "abc")
        XCTAssertNil(ContextPin.task(id: "abc", title: "B").deliverableId)
    }
}
