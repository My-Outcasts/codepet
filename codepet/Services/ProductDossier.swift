// codepet/Services/ProductDossier.swift
import Foundation
import CryptoKit
import os

/// What the team knows about the founder's product, read from their linked folder.
///
/// Why it exists (2026-09-25): a Team Build of "a landing page for Codepet" produced one headline
/// and an email box. The room's own decision said why — "Nothing is on record about what codepet
/// is" — because the departments, the room and the planner never see the linked folder; only chat
/// and the build step do. With nothing known, the room correctly chose the smallest possible page.
///
/// A dossier is written ONCE per folder by a read-only `claude -p` (Read/Glob/Grep under
/// `--restricted`, confined to that folder) rather than scraped: this very repo's README still
/// describes the retired learning game, so excerpting files would have taught the team the wrong
/// product. The text then rides every context the team reads (`ChatContext.compose`, the room's
/// founder profile, the planner's company facts, the build prompt), and `assets` are copied into
/// a web project's `public/product/` so the page can show the real product.
struct ProductDossier: Codable, Equatable {
    let folder: String
    let summary: String
    /// Absolute paths inside `folder`, validated: images only, under `maxAssetBytes`.
    let assets: [String]
    let createdAt: Date

    static let maxSummaryChars = 6000
    static let maxAssets = 12
    static let maxAssetBytes = 3_000_000
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "svg"]

    /// The block every context gets. Capped so it cannot crowd out the rest of a prompt.
    var contextBlock: String {
        "ABOUT THE PRODUCT (read from the founder's own project folder — treat as fact):\n"
            + String(summary.prefix(Self.maxSummaryChars))
    }

    // MARK: - Generation

    /// The prompt for the read-only pass. Ends with one `ASSET:` line per image worth showing,
    /// which is how the model hands back paths without a schema.
    static func prompt(folder: String) -> String {
        """
        You are reading a founder's project folder so their team (marketing, design, engineering, sales)
        can describe the product accurately. The folder is: \(folder)

        Read enough to be sure — CLAUDE.md, AGENTS.md, docs/, README (it may be OUT OF DATE; prefer the code
        and the most recent docs when they disagree), package.json / project files, and the main source folders.
        Then write, in plain English, under these headings:

        ## What it is
        One paragraph: the product, who it is for, the problem it solves.
        ## Who it is for
        ## What it does today
        6–10 bullets of REAL, shipped capabilities, with the product's own names for them.
        ## How it works
        The user's flow in 3–6 steps.
        ## What makes it different
        ## Platform, pricing, status
        Only what the folder states. Write "unknown" rather than guess.
        ## Brand
        Colours, type, tone and any design system the folder defines.

        Do not invent customers, numbers, quotes or pricing. Do not describe retired features as current.

        Finally list up to \(maxAssets) image files that would look good on a marketing page (logos, app icon,
        screenshots, characters/illustrations), one per line, as absolute paths inside the folder:
        ASSET: /absolute/path/to/file.png
        """
    }

    /// Splits the model's reply into the summary and validated asset paths. An `ASSET:` line
    /// pointing outside `folder`, at a non-image, a missing file or an oversized one is dropped —
    /// the model's word is not trusted for what gets copied into the founder's project.
    static func parse(_ reply: String, folder: String,
                      fileSize: (String) -> Int? = { (try? FileManager.default.attributesOfItem(atPath: $0))?[.size] as? Int })
        -> (summary: String, assets: [String]) {
        let root = URL(fileURLWithPath: folder).standardizedFileURL.path
        var assets: [String] = []
        var kept: [String] = []
        for line in reply.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("ASSET:") else { kept.append(line); continue }
            let raw = t.dropFirst("ASSET:".count).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
            let path = URL(fileURLWithPath: raw).standardizedFileURL.path
            guard path.hasPrefix(root + "/"),
                  imageExtensions.contains((path as NSString).pathExtension.lowercased()),
                  let size = fileSize(path), size > 0, size <= maxAssetBytes,
                  !assets.contains(path), assets.count < maxAssets else { continue }
            assets.append(path)
        }
        let summary = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (String(summary.prefix(maxSummaryChars)), assets)
    }

    /// Runs the read-only pass. nil on failure or an empty reply.
    ///
    /// `--restricted` confines Read/Glob/Grep to the temp cwd plus `--add-dir folder` and ignores
    /// the founder's settings files; no Write, Edit or Bash is offered (measured on 2.1.282: a Read
    /// outside both directories is refused).
    nonisolated static func generate(folder: String, timeout: TimeInterval = 240) async -> ProductDossier? {
        guard CLIRunner.isShellSafePath(folder) else { return nil }
        let fm = FileManager.default
        let run = fm.temporaryDirectory.appendingPathComponent("codepet-dossier-\(UUID().uuidString)")
        guard (try? fm.createDirectory(at: run, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? fm.removeItem(at: run) }
        let promptFile = run.appendingPathComponent("prompt.txt")
        guard (try? prompt(folder: folder).write(to: promptFile, atomically: true, encoding: .utf8)) != nil else { return nil }
        let cmd = "claude -p --output-format text --restricted --setting-sources '' "
            + "--add-dir \"\(folder)\" --tools Read,Glob,Grep --allowedTools Read Glob Grep --max-turns 30 "
            + "< prompt.txt"
        let result = await ProjectAssembler.runShell(cmd, run, timeout: timeout, tailChars: 40_000)
        guard result.ok else {
            log.error("dossier pass failed: \(String(result.tail.suffix(300)), privacy: .public)")
            return nil
        }
        let parsed = parse(result.tail, folder: folder)
        guard parsed.summary.count > 200 else { return nil }
        return ProductDossier(folder: folder, summary: parsed.summary, assets: parsed.assets, createdAt: Date())
    }

    private static let log = Logger(subsystem: "app.murror.codepet", category: "ProductDossier")
}

/// One file per (account, folder) under `~/.codepet/accounts/<uid>/dossiers/`. Local only, like
/// the chat archive: it describes a folder on this Mac.
struct ProductDossierCache {
    var root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codepet/accounts")

    func url(uid: String, folder: String) -> URL {
        let safe = uid.filter { $0.isLetter || $0.isNumber }
        let key = SHA256.hash(data: Data(folder.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(safe.isEmpty ? "unknown" : safe)
            .appendingPathComponent("dossiers").appendingPathComponent("\(key).json")
    }

    func load(uid: String, folder: String) -> ProductDossier? {
        guard let data = try? Data(contentsOf: url(uid: uid, folder: folder)),
              let d = try? JSONDecoder().decode(ProductDossier.self, from: data), d.folder == folder else { return nil }
        return d
    }

    func save(_ d: ProductDossier, uid: String) {
        let u = url(uid: uid, folder: d.folder)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(d).write(to: u, options: .atomic)
    }
}
