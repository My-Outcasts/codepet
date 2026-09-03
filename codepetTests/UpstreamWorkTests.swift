import XCTest
@testable import codepet

/// Guards on outputs feeding forward.
///
/// `mur-site` depends on `mur-brand` and the run passed Nova nothing of Luna's output: no field
/// on the request, no assembly, nowhere in the prompt. The graph gated ORDER and never
/// INFORMATION — the same shape as the fixed bug `runTaskCore.ts:60-63` records, where a run was
/// performed BY a department the prompt was never told about.
final class UpstreamWorkTests: XCTestCase {

    private func filed(_ taskId: String, _ title: String, body: String = "B") -> Deliverable {
        // `kind` before `title` — see `Deliverable.init` in Models/Deliverable.swift.
        Deliverable(id: "d-\(taskId)", kind: .doc, title: title, body: body, sourceTaskId: taskId)
    }

    func testAssemblesInDependsOnOrder() {
        let tasks = DemoProject.murror.tasks
        let site = tasks.first { $0.id == "mur-site" }!   // dependsOn brand, landscape
        let library = [filed("mur-landscape", "Landscape"), filed("mur-brand", "Brand")]
        let up = UpstreamWork.assemble(for: site, in: tasks, library: library)
        XCTAssertEqual(up.map(\.taskTitle), ["Brand", "Landscape"],
                       "must follow dependsOn order, not library order")
    }

    /// A pet and a department name, or the credit on the card cannot say who did the work.
    func testCarriesTheDepartmentAndItsPet() {
        let tasks = DemoProject.murror.tasks
        let site = tasks.first { $0.id == "mur-site" }!
        let up = UpstreamWork.assemble(for: site, in: tasks,
                                       library: [filed("mur-brand", "Brand")])
        XCTAssertEqual(up.first?.deptName, "Design")
        XCTAssertEqual(up.first?.petName, "Luna")
    }

    func testSkipsDependenciesWithNoFiledDeliverable() {
        let tasks = DemoProject.murror.tasks
        let site = tasks.first { $0.id == "mur-site" }!
        let up = UpstreamWork.assemble(for: site, in: tasks, library: [])
        XCTAssertTrue(up.isEmpty, "an unfiled dependency must be absent, not a placeholder")
    }

    func testCapsAtThreeAndClipsBodies() {
        var task = RoadmapTask(id: "x", title: "X", detail: "", phase: .build, who: .draft,
                               dependsOn: ["a", "b", "c", "d", "e"], dept: "mkt")
        let deps = ["a", "b", "c", "d", "e"].map {
            RoadmapTask(id: $0, title: $0.uppercased(), detail: "", phase: .find,
                        who: .draft, done: true, dept: "design")
        }
        let library = deps.map { filed($0.id, $0.title, body: String(repeating: "x", count: 4000)) }
        let up = UpstreamWork.assemble(for: task, in: deps + [task], library: library)
        XCTAssertEqual(up.count, UpstreamWork.cap)
        for item in up { XCTAssertLessThanOrEqual(item.body.count, UpstreamWork.bodyLimit) }
        task.dependsOn = []
        XCTAssertTrue(UpstreamWork.assemble(for: task, in: deps, library: library).isEmpty)
    }

    func testEncodesToTheWireShape() throws {
        let w = UpstreamWork(taskTitle: "Brand", deptName: "Design", petName: "Luna",
                             kind: "doc", body: "B", unapproved: true)
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(w)) as? [String: Any]
        XCTAssertEqual(json?["taskTitle"] as? String, "Brand")
        XCTAssertEqual(json?["petName"] as? String, "Luna")
        XCTAssertEqual(json?["unapproved"] as? Bool, true)
    }

    /// The field has to survive `RunTaskRequest`'s OWN encoding, which is the step the plan
    /// for this task left unguarded.
    ///
    /// `RunTaskRequest` declares an explicit `CodingKeys` (it renames every field to
    /// snake_case for the wire). A stored property missing from that enum is not a compile
    /// error and not a runtime error — it is simply never encoded. So `upstream` could be
    /// assembled correctly, sit on the request correctly, pass `testEncodesToTheWireShape`
    /// correctly, and still reach the Cloud Function as nothing at all. That is the same
    /// silent-drop failure the plan warns about for `ONE_SHOT_OPS`, one layer earlier, and
    /// only a test that encodes the REQUEST can see it.
    func testTheRequestItselfCarriesUpstreamOnTheWire() throws {
        let req = RunTaskRequest(
            companyId: "c", language: "en", companionId: "nova", context: "Murror",
            taskId: "mur-site", taskTitle: "Build the Murror landing page", taskDetail: "",
            deptKey: "mkt",
            upstream: [UpstreamWork(taskTitle: "Brand", deptName: "Design", petName: "Luna",
                                    kind: "doc", body: "B")])
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(req)) as? [String: Any]
        let wire = try XCTUnwrap(json?["upstream"] as? [[String: Any]],
                                 "`upstream` is absent from the encoded request — add it to CodingKeys")
        XCTAssertEqual(wire.count, 1)
        XCTAssertEqual(wire.first?["petName"] as? String, "Luna")
    }

    /// An empty array must not be sent. `buildRunTaskPrompt` branches on the block being
    /// absent, and every ordinary run (a task with no dependencies) is this case — so the
    /// common path has to stay byte-for-byte the shape it was before this field existed.
    func testAnEmptyUpstreamIsOmittedFromTheWire() throws {
        let req = RunTaskRequest(
            companyId: "c", language: "en", companionId: "byte", context: "",
            taskId: "t", taskTitle: "T", taskDetail: "")
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(req)) as? [String: Any]
        XCTAssertNil(json?["upstream"], "a dependency-free run must send no upstream key at all")
    }
}
