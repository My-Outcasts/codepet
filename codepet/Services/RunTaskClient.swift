// codepet/Services/RunTaskClient.swift
import Foundation
import os
import FirebaseAuth

/// One upstream department's finished work, travelling with a downstream run.
///
/// **Why this exists.** `mur-site` (Marketing) depends on `mur-brand` (Design), and the run
/// passed Nova nothing of Luna's output: no field on the request, no assembly in the store,
/// nowhere in the prompt to put it. The dependency graph gated ORDER and never INFORMATION —
/// exactly the shape of the already-fixed `deptKey` bug documented on `RunTaskRequest.deptKey`
/// below, where a run was performed BY a department the prompt was never told about.
///
/// Field names stay camelCase, unlike `RunTaskRequest`'s snake_case wire keys, because they
/// are read on the other side by the `UpstreamWork` interface in `runTaskCore.ts` — the two
/// declarations have to agree, and they are diffed against each other by name.
struct UpstreamWork: Codable, Hashable {
    let taskTitle: String
    let deptName: String
    let petName: String
    let kind: String
    let body: String
    /// True when the work was produced by a chained run and not yet approved. Surfaced on the
    /// card rather than hidden — a chain that conceals this is the fixture-lie failure mode.
    var unapproved: Bool = false

    static let cap = 3
    static let bodyLimit = 1500

    /// In `dependsOn` order: the fixture authors that array deliberately, so its order is the
    /// intended precedence rather than an arbitrary notion of "nearest".
    ///
    /// Reads the LIBRARY, so only approved work feeds forward here. A chained run's unapproved
    /// draft is not in the library yet and cannot be — see `CompanyStore.runChained`, which
    /// prepends its own item with `unapproved: true` rather than filing a draft early to make
    /// this function see it.
    static func assemble(for task: RoadmapTask,
                         in tasks: [RoadmapTask],
                         library: [Deliverable]) -> [UpstreamWork] {
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // `cap * 3` bounds the scan, not the result: a task with nine dependencies should not
        // walk the whole library nine times to return three items.
        return task.dependsOn.prefix(cap * 3).compactMap { depId -> UpstreamWork? in
            guard let dep = byId[depId],
                  let filed = RoadmapEngine.deliverable(for: dep, in: library) else { return nil }
            return item(filed, from: dep, unapproved: false)
        }.prefix(cap).map { $0 }
    }

    /// The first dependency that has produced nothing yet — what a chained run offers to run
    /// before the task the founder asked for.
    ///
    /// Keyed on the LIBRARY and not on `done`: a task can be `done` with no deliverable behind
    /// it, and that is exactly the case worth chaining — the downstream run has a dependency
    /// arrow pointing at nothing it can read.
    ///
    /// But only where Codepet could produce that deliverable. See the `.you` clause below.
    static func firstUnfiled(dependencyOf task: RoadmapTask,
                             in tasks: [RoadmapTask],
                             library: [Deliverable]) -> RoadmapTask? {
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return task.dependsOn.lazy.compactMap { byId[$0] }
            .first {
                // `who == .you` is the founder's own work — an interview round, a conversation,
                // something that happened off the screen. Codepet must not offer to run it:
                // `handleRunTaskId` refuses a `.you` task outright ("that one's yours to do"),
                // so an offer whose "Run both" button reached one would be promising work the
                // product declines to do everywhere else. Such a dependency simply feeds
                // nothing forward, and the downstream run proceeds without it.
                $0.who != .you && RoadmapEngine.deliverable(for: $0, in: library) == nil
            }
    }

    /// Build an item from a DRAFT rather than from the library.
    ///
    /// A chained run's upstream deliverable is deliberately not filed — chaining does not
    /// stop for approval, and filing it early would put unapproved work in the founder's
    /// library — so `assemble` cannot see it and `runChained` prepends this instead.
    /// `unapproved` defaults true because that is the only way this function is reached.
    static func fromDraft(_ draft: Deliverable, task: RoadmapTask,
                          unapproved: Bool = true) -> UpstreamWork {
        item(draft, from: task, unapproved: unapproved)
    }

    /// The one place a department and its pet are resolved for this type, so the library path
    /// and the draft path cannot credit the same department two different ways.
    private static func item(_ deliverable: Deliverable, from task: RoadmapTask,
                             unapproved: Bool) -> UpstreamWork {
        let dept = DepartmentCatalog.find(task.dept)
        let pet = DepartmentCompanions.companionId(for: task.dept ?? "")
            .flatMap { PetCharacter.all[$0] }
        return UpstreamWork(taskTitle: deliverable.title,
                            deptName: dept?.name ?? "",
                            petName: pet?.name ?? "",
                            kind: deliverable.kind.rawValue,
                            body: String(deliverable.body.prefix(bodyLimit)),
                            unapproved: unapproved)
    }
}

/// Request body for the runTask Cloud Function.
struct RunTaskRequest: Codable {
    let companyId: String?
    let language: String
    let companionId: String
    let context: String
    let taskId: String
    let taskTitle: String
    let taskDetail: String
    /// Set only on a revise re-run (chip tap or free-form redo-with-note): the
    /// instruction to apply ("Make it shorter", etc). `nil` on a blind redo/first run.
    var reviseNote: String? = nil
    /// The current draft body, sent alongside `reviseNote` so the CF revises in
    /// place instead of regenerating from scratch. `nil` on a blind redo/first run.
    var current: String? = nil
    /// The owning department of the task being run (a `DepartmentCatalog` key), so the
    /// deliverable is produced with that department's expertise rather than generic
    /// company context. nil for a legacy dept-less task, which omits the key entirely.
    ///
    /// A run has always been performed BY a department — `taskSpecialist` shows its pet on
    /// the execute log and on the draft — and until now that was the only thing the
    /// department affected. The prompt never learned which department it was writing for.
    var deptKey: String? = nil
    /// The finished work of the tasks this one `dependsOn` — see `UpstreamWork`.
    ///
    /// **Optional, not an empty array, and that is load-bearing.** The synthesized encoder
    /// omits a nil Optional and always writes an empty Array, so `[UpstreamWork] = []` would
    /// put `"upstream": []` on every request Codepet has ever sent — a wire change for the
    /// overwhelmingly common dependency-free run, which this field is supposed to leave
    /// byte-for-byte alone (the same promise `deptKey` above makes). `CompanyStore.runRequest`
    /// is the one place that collapses empty to nil.
    var upstream: [UpstreamWork]? = nil

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case language
        case companionId = "companion_id"
        case context
        case taskId = "task_id"
        case taskTitle = "task_title"
        case taskDetail = "task_detail"
        case reviseNote = "revise_note"
        case current
        case deptKey = "dept_key"
        // A stored property missing from this enum is not a compile error and not a runtime
        // error — it is simply never encoded. `UpstreamWorkTests` encodes the whole request
        // for exactly that reason: every other test here would pass with this line deleted.
        case upstream
    }
}

/// Response body from the runTask Cloud Function — a deliverable as kind + markdown.
struct RunTaskResponse: Codable {
    let kind: String
    let title: String
    let body: String
    var payload: DeliverablePayload?
}

/// Fail-open client for the (planned) runTask Cloud Function. Returns the decoded
/// response on 200, `nil` on any error / non-200 / unreachable — callers never handle
/// throws. The CF is authored + deployed separately (node-22 bundle, like companyChat);
/// until then this returns nil and the run surfaces an honest error.
enum RunTaskClient {
    static let endpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/runTask")!

    static func run(_ req: RunTaskRequest) async -> RunTaskResponse? {
        #if DEBUG
        if MockChat.enabled { return await MockChat.runResult(req) }
        #endif
        // The founder's own Claude Code first, when they granted it. Fail-open is preserved
        // (`nil` is what the caller turns into an honest error on the card), but the reason
        // is LOGGED — a run that silently produced nothing is the hardest failure here to
        // diagnose. It never falls through to the Cloud Function: that would spend the API
        // key the grant exists to stop spending.
        switch LocalTransportRouter.forOneShot() {
        case .local, .localUnavailable:
            do {
                let body = try JSONEncoder().encode(req)
                let out = try await LocalOneShotRunner.run(op: "runTask", body: body)
                return try JSONDecoder().decode(RunTaskResponse.self, from: out)
            } catch {
                LocalTransportRouter.log.error(
                    "local runTask failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        case .cloud:
            break
        }
        guard let token = try? await Auth.auth().currentUser?.getIDToken() else { return nil }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        urlRequest.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(RunTaskResponse.self, from: data)
        else { return nil }
        return decoded
    }
}
