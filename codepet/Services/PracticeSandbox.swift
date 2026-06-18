import Foundation

/// A self-contained practice project Codepet ships and materializes on disk so
/// users can practice skills WITHOUT touching their real code.
///
/// One shared mini "yoga-site" covers all four skills (a Hero block to extract,
/// an unguarded data load, an unvalidated form, images missing alt text). On
/// each exercise we hand `claude` this throwaway copy — never the user's project.
/// `reset()` restores the pristine version so retries always start clean.
enum PracticeSandbox {

    /// Where the working copy lives. Uses the real home (not the sandbox
    /// container) for consistency with the rest of the app.
    static var rootURL: URL {
        RealHome.url.appendingPathComponent("Library/Application Support/Codepet/PracticeSandbox/yoga-site")
    }

    static var path: String { rootURL.path }

    /// Ensure the sandbox exists on disk; returns its absolute path.
    /// - Parameter reset: when true, wipes any existing copy first.
    @discardableResult
    static func prepare(reset: Bool = false) throws -> String {
        let fm = FileManager.default
        if reset, fm.fileExists(atPath: rootURL.path) {
            try fm.removeItem(at: rootURL)
        }
        // Write any file that's missing. On a fresh sandbox this lays down the
        // whole project; on an existing one it backfills newly-added files (e.g.
        // a new skill's target) without clobbering the user's in-progress edits.
        for (relativePath, contents) in files {
            let fileURL = rootURL.appendingPathComponent(relativePath)
            guard !fm.fileExists(atPath: fileURL.path) else { continue }
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return rootURL.path
    }

    /// Restore the pristine project (used by the "Reset" button).
    @discardableResult
    static func reset() throws -> String {
        try prepare(reset: true)
    }

    /// Read a file's current contents from the working copy (for previews/diffs).
    static func currentContents(of relativePath: String) -> String? {
        try? String(contentsOf: rootURL.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The most relevant file to show for a given skill, so the user knows what
    /// they're working with before writing a prompt. Each skill points at the
    /// file that actually contains its issue.
    static func primaryFile(forSkill skillId: String) -> String {
        switch skillId {
        case "responsive_layout":
            // Fixed, desktop-only styles with no breakpoints.
            return "app/globals.css"
        case "performance":
            // A component that recomputes/derives on every render.
            return "app/components/ClassList.tsx"
        case "component_composition",   // Hero block to extract
             "loading_error_states",     // unguarded data load
             "form_validation_ux",       // unvalidated contact form
             "accessibility_basics":     // images missing alt text
            return "app/page.tsx"
        default:
            return "app/page.tsx"
        }
    }

    // MARK: - Bundled project (materialized on disk at runtime)

    private static let files: [String: String] = [
        "app/page.tsx": pageTSX,
        "app/components/ClassList.tsx": classListTSX,
        "app/globals.css": globalsCSS,
        "app/lib/site-data.ts": siteDataTS,
        "package.json": packageJSON,
        "README.md": readme
    ]

    private static let pageTSX = """
    import Image from "next/image";
    import Link from "next/link";
    import { classes, loadClasses } from "@/app/lib/site-data";

    export default async function HomePage() {
      // Data is loaded with no error handling and no loading state.
      const schedule = await loadClasses();

      return (
        <main className="home">
          {/* ---- Hero (a large inline block — a good candidate to extract) ---- */}
          <section className="hero">
            <div className="hero-text">
              <h1>Breathe. Move. Belong.</h1>
              <p>
                A neighborhood yoga studio for every body. Drop in for a class
                or join the community — no experience required.
              </p>
              <Link href="/schedule" className="cta">View the schedule</Link>
            </div>
            <div className="hero-art">
              <Image src="/hero.jpg" width={520} height={360} />
            </div>
          </section>

          {/* ---- Class list (rendered from loaded data) ---- */}
          <section className="classes">
            <h2>This week</h2>
            <ul>
              {schedule.map((c) => (
                <li key={c.id}>
                  <img src={c.photo} width={80} height={80} />
                  <div>
                    <strong>{c.name}</strong>
                    <span>{c.time} · {c.teacher}</span>
                  </div>
                </li>
              ))}
            </ul>
          </section>

          {/* ---- Contact form (no validation yet) ---- */}
          <section className="contact">
            <h2>Ask us anything</h2>
            <form action="/api/contact" method="post">
              <input name="name" placeholder="Your name" />
              <input name="email" placeholder="Email" />
              <textarea name="message" placeholder="Message" />
              <button type="submit">Send</button>
            </form>
          </section>
        </main>
      );
    }
    """

    // Performance practice target: a client component that recomputes its
    // derived list on every render (including each keystroke) with no memoization.
    private static let classListTSX = """
    "use client";
    import { useState } from "react";
    import type { YogaClass } from "@/app/lib/site-data";

    // Renders the weekly class list with a teacher filter.
    // PERF: `visible` is rebuilt from scratch on EVERY render — filtered, sorted,
    // and re-formatted — even when only unrelated state changes. Nothing here is
    // memoized (no useMemo / no memoized component), so typing in the filter box
    // re-does all of this work each keystroke.
    export function ClassList({ classes }: { classes: YogaClass[] }) {
      const [query, setQuery] = useState("");

      const visible = classes
        .filter((c) => c.teacher.toLowerCase().includes(query.toLowerCase()))
        .sort((a, b) => a.name.localeCompare(b.name))
        .map((c) => ({ ...c, label: `${c.name} — ${c.time} · ${c.teacher}` }));

      return (
        <div className="classes">
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Filter by teacher"
          />
          <ul>
            {visible.map((c) => (
              <li key={c.id}>
                <img src={c.photo} alt={`${c.name} class`} width={80} height={80} />
                <div>
                  <strong>{c.name}</strong>
                  <span>{c.time} · {c.teacher}</span>
                </div>
              </li>
            ))}
          </ul>
        </div>
      );
    }
    """

    // Responsive practice target: every size is a fixed desktop pixel width and
    // there are no media queries, so the page overflows on a phone.
    private static let globalsCSS = """
    /* Global styles for the yoga site.
       NOTE: everything is sized for a wide desktop window. There are no
       responsive breakpoints, so on a narrow screen the layout overflows
       horizontally and the columns never stack. */

    .home {
      width: 1100px;        /* fixed — does not shrink on small screens */
      margin: 0 auto;
      padding: 48px;
    }

    .hero {
      display: flex;        /* always side-by-side, even when too narrow */
      gap: 48px;
    }

    .hero-text { width: 520px; }
    .hero-art img { width: 520px; height: 360px; }

    .classes ul {
      display: flex;        /* a single non-wrapping row of cards */
      gap: 24px;
      list-style: none;
      padding: 0;
    }

    .classes li { width: 320px; }

    .contact form {
      display: grid;
      grid-template-columns: 1fr 1fr;   /* two columns, cramped on mobile */
      gap: 16px;
      width: 640px;
    }
    """

    private static let siteDataTS = """
    export type YogaClass = {
      id: string;
      name: string;
      time: string;
      teacher: string;
      photo: string;
    };

    const SCHEDULE: YogaClass[] = [
      { id: "vin-mon", name: "Vinyasa Flow", time: "Mon 6:00pm", teacher: "Mara",  photo: "/c1.jpg" },
      { id: "yin-tue", name: "Yin & Restore", time: "Tue 7:30am", teacher: "Devin", photo: "/c2.jpg" },
      { id: "pow-wed", name: "Power Hour",    time: "Wed 12:00pm", teacher: "Sam",   photo: "/c3.jpg" },
    ];

    // Simulates a network fetch — sometimes the network is slow, sometimes it fails.
    export async function loadClasses(): Promise<YogaClass[]> {
      await new Promise((r) => setTimeout(r, 400));
      return SCHEDULE;
    }

    export const classes = SCHEDULE;
    """

    private static let packageJSON = """
    {
      "name": "yoga-site",
      "version": "0.1.0",
      "private": true,
      "description": "A tiny practice project for Codepet exercises. Safe to change — it is a throwaway copy.",
      "dependencies": {
        "next": "14.0.0",
        "react": "18.2.0",
        "react-dom": "18.2.0"
      }
    }
    """

    private static let readme = """
    # yoga-site (practice sandbox)

    This is a **throwaway copy** Codepet created so you can practice safely.
    Nothing you do here touches your real projects. Reset it anytime from the app.
    """
}
