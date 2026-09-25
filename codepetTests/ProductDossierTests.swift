// codepetTests/ProductDossierTests.swift
import XCTest
@testable import codepet

/// The team knows the product: a dossier read from the linked folder reaches the room, the
/// planner, every department and the build — and its images reach the project.
@MainActor
final class ProductDossierTests: XCTestCase {
    private var tmp: URL!
    private var retained: [CompanyStore] = []
    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pd-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp); super.tearDown() }

    private func dossier(_ folder: String, assets: [String] = []) -> ProductDossier {
        ProductDossier(folder: folder, summary: "## What it is\nCodepet runs your company with an AI team.",
                       assets: assets, createdAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: - Parse

    func testParseKeepsOnlyRealImagesInsideTheFolder() async {
        let reply = """
        ## What it is
        Codepet.
        ASSET: /repo/logo.png
        ASSET: `/repo/art/luna@2x.png`
        ASSET: /repo/../etc/passwd.png
        ASSET: /elsewhere/x.png
        ASSET: /repo/notes.md
        ASSET: /repo/huge.jpg
        ASSET: /repo/missing.png
        ASSET: /repo/logo.png
        """
        let sizes = ["/repo/logo.png": 10, "/repo/art/luna@2x.png": 20, "/etc/passwd.png": 5,
                     "/elsewhere/x.png": 5, "/repo/huge.jpg": ProductDossier.maxAssetBytes + 1]
        let p = ProductDossier.parse(reply, folder: "/repo", fileSize: { sizes[$0] })
        XCTAssertEqual(p.assets, ["/repo/logo.png", "/repo/art/luna@2x.png"])
        XCTAssertFalse(p.summary.contains("ASSET:"), "asset lines are not part of the summary")
        XCTAssertTrue(p.summary.contains("Codepet."))
    }

    // MARK: - Where it goes

    func testEveryContextCarriesItUnderTheBrief() async {
        let d = dossier("/repo")
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: [], product: d.contextBlock)
        XCTAssertTrue(ctx.contains("ABOUT THE PRODUCT"))
        XCTAssertTrue(ctx.contains("AI team"))
        XCTAssertEqual(ChatContext.compose(brief: CompanyBrief(), tasks: []),
                       ChatContext.compose(brief: CompanyBrief(), tasks: [], product: nil), "absent → unchanged")
        let founder = FounderContextMapper.founder(from: CompanyBrief(), product: d.contextBlock)
        XCTAssertTrue(founder.profile.contains("AI team"), "the room reads it as FOUNDER CONTEXT")
    }

    func testTheBuildPromptCarriesItAndTheImagesAndTheBar() async {
        let steps = [WorkStep(id: "build", dept: "eng", title: "Build", instruction: "", kind: "other", dependsOn: [])]
        let run = TeamRun(request: "landing page", createdAt: Date(), brief: nil,
                          plan: WorkPlan(title: "LP", slug: "lp", summary: "s", projectType: "Next.js landing page", steps: steps))
        let p = TeamBuildPrompt.prompt(for: run, docs: [], dossier: dossier("/repo"), assets: ["public/product/logo.png"])
        XCTAssertTrue(p.contains("AI team"))
        XCTAssertTrue(p.contains("public/product/logo.png"))
        XCTAssertTrue(p.contains("only because nobody knew the product"))
        XCTAssertFalse(TeamBuildPrompt.prompt(for: run, docs: []).contains("Quality bar"), "no dossier → no bar text")
    }

    func testAssetsAreCopiedIntoPublicWithDistinctNames() async throws {
        let repo = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("b"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: repo.appendingPathComponent("a/logo.png"))
        try Data([4, 5, 6]).write(to: repo.appendingPathComponent("b/logo.png"))
        let project = tmp.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let coder = NoopCoder()
        var a = ProjectAssembler(root: tmp, coder: coder)
        a.dossier = dossier(repo.path, assets: [repo.appendingPathComponent("a/logo.png").path,
                                                repo.appendingPathComponent("b/logo.png").path,
                                                "/etc/hosts"])
        let copied = a.copyProductAssets(into: project)
        XCTAssertEqual(copied, ["public/product/logo.png", "public/product/logo-2.png"])
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("public/product/logo-2.png")), Data([4, 5, 6]))
    }

    private final class NoopCoder: ProjectCodeRunning {
        func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
                 timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? { nil }
    }

    // MARK: - Store

    private func store(granted: Bool, generated: @escaping (String) -> ProductDossier?,
                       calls: @escaping () -> Void, cache: ProductDossierCache) -> CompanyStore {
        let suite = UserDefaults(suiteName: "cp.tests.\(UUID().uuidString)")!
        let map = ProjectIdentityMap(defaults: suite, key: "cp_project_ids_test")
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             identityMap: map,
                             claudeAuthorisation: ProviderAuthorisation(isAuthorised: { _, _ in granted },
                                                                        setAuthorised: { _, _, _ in }),
                             remoteURLReader: { _ in nil }, repoRootReader: { _ in nil },
                             dossierGenerator: { path in calls(); return generated(path) },
                             dossierCache: cache)
        retained.append(s)
        return s
    }

    func testLinkingAFolderReadsItOnceAndCachesIt() async throws {
        let cache = ProductDossierCache(root: tmp.appendingPathComponent("cache"))
        let folder = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var calls = 0
        let s = store(granted: true, generated: { self.dossier($0) }, calls: { calls += 1 }, cache: cache)
        await s.hydrate(companyId: "u")
        let link = s.linkProject(path: folder.path, bootstrapClaudeMd: false)
        let d = await s.ensureProductDossier()
        XCTAssertEqual(d?.folder, link.path)
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(cache.load(uid: "u", folder: link.path), "written to the cache")

        // A second store (a relaunch) finds it in the cache and spends nothing.
        var calls2 = 0
        let s2 = store(granted: true, generated: { self.dossier($0) }, calls: { calls2 += 1 }, cache: cache)
        await s2.hydrate(companyId: "u")
        s2.linkProject(path: folder.path, bootstrapClaudeMd: false)
        XCTAssertNotNil(s2.productDossier)
        XCTAssertEqual(calls2, 0)
    }

    func testWithoutTheGrantNothingIsRead() async throws {
        let folder = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var calls = 0
        let s = store(granted: false, generated: { self.dossier($0) }, calls: { calls += 1 },
                      cache: ProductDossierCache(root: tmp.appendingPathComponent("cache")))
        await s.hydrate(companyId: "u")
        s.linkProject(path: folder.path, bootstrapClaudeMd: false)
        let d = await s.ensureProductDossier()
        XCTAssertNil(d)
        XCTAssertEqual(calls, 0, "the pass spends the founder's plan, so it needs the grant")
    }
}
