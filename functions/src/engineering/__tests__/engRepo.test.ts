/**
 * A PATH-AWARE Firestore double, and it has to be.
 *
 * `loadRepo` reads TWO documents now — the repo link and the connector that
 * holds the token. The previous fixture was a single shared `get` sequenced
 * with `mockResolvedValueOnce`, which cannot express "this document has a
 * token and that one does not": both reads would take the same stub, and a
 * test could not tell which document the token actually came from. That is
 * the whole behaviour being changed here, so the fixture has to be able to
 * see it.
 *
 * The store lives inside the factory because `jest.mock` is hoisted above
 * every outer binding; tests reach it through `seed`/`clearStore` below.
 */
jest.mock("firebase-admin", () => {
  const store = new Map<string, Record<string, unknown>>();
  const doc = jest.fn((path: string) => ({
    path,
    get: jest.fn(async () => ({
      exists: store.has(path),
      data: () => store.get(path)
    }))
  }));
  const firestore: unknown = jest.fn(() => ({ doc }));
  (firestore as { __store?: unknown }).__store = store;
  return { firestore };
});

jest.mock("../../oauth/githubOAuthCore", () => ({
  openToken: jest.fn(() => {
    throw new Error("bad auth tag");
  })
}));

import { parseRepoUrl, branchName, MOUNT_PATH, loadRepo } from "../engRepo";

const UID = "some-uid";
const KEY = "some-enc-key";
const REPO_PATH = `companies/${UID}/engineering/repo`;
const CONNECTOR_PATH = `companies/${UID}/connectors/github`;
const SEALED = { iv: "iv", tag: "tag", ciphertext: "ct" };

function store(): Map<string, Record<string, unknown>> {
  const admin = require("firebase-admin");
  return (admin.firestore as unknown as { __store: Map<string, Record<string, unknown>> }).__store;
}

function seed(path: string, data: Record<string, unknown>): void {
  store().set(path, data);
}

function clearStore(): void {
  store().clear();
}

/** The ordinary state: a linked repo and a connected GitHub account. */
function seedLinkedAndConnected(repo: Record<string, unknown> = {}): void {
  seed(REPO_PATH, { url: "https://github.com/owner/repo", defaultBranch: "main", ...repo });
  seed(CONNECTOR_PATH, { sealed: SEALED });
}

describe("parseRepoUrl", () => {
  it("reads owner and repo from an https URL", () => {
    expect(parseRepoUrl("https://github.com/My-Outcasts/codepet")).toEqual({
      owner: "My-Outcasts",
      repo: "codepet"
    });
  });

  it("tolerates a trailing .git and a trailing slash", () => {
    expect(parseRepoUrl("https://github.com/a/b.git")).toEqual({ owner: "a", repo: "b" });
    expect(parseRepoUrl("https://github.com/a/b/")).toEqual({ owner: "a", repo: "b" });
  });

  it("rejects anything that is not a GitHub repo URL", () => {
    expect(parseRepoUrl("https://gitlab.com/a/b")).toBeNull();
    expect(parseRepoUrl("https://github.com/a")).toBeNull();
    expect(parseRepoUrl("not a url")).toBeNull();
    expect(parseRepoUrl("")).toBeNull();
  });

  it("rejects a URL with a query string rather than baking it into the repo name", () => {
    expect(parseRepoUrl("https://github.com/owner/repo?tab=readme-ov-file")).toBeNull();
  });

  it("rejects a URL with a fragment rather than baking it into the repo name", () => {
    expect(parseRepoUrl("https://github.com/owner/repo#readme")).toBeNull();
  });
});

describe("branchName", () => {
  it("namespaces every branch under codepet/", () => {
    expect(branchName("abc123")).toBe("codepet/run-abc123");
  });

  it("is stable for a run id, so a retry reuses the branch", () => {
    expect(branchName("abc123")).toBe(branchName("abc123"));
  });
});

describe("MOUNT_PATH", () => {
  it("matches the prefix engEvents strips from tool paths", () => {
    // engEvents.MOUNT_PREFIX is MOUNT_PATH + "/". If these drift, every step
    // row shows an absolute container path instead of a repo-relative one.
    expect(MOUNT_PATH).toBe("/workspace/repo");
  });
});

describe("loadRepo", () => {
  beforeEach(() => {
    clearStore();
    const { openToken } = require("../../oauth/githubOAuthCore");
    (openToken as jest.Mock).mockReset();
    (openToken as jest.Mock).mockImplementation(() => {
      throw new Error("bad auth tag");
    });
  });

  // ---- where the token comes from ---------------------------------------

  it("takes the token from the connector, not from the repo document", async () => {
    // One credential, one home. The OAuth callback writes connectors/github;
    // nothing else should hold a copy.
    seed(REPO_PATH, { url: "https://github.com/owner/repo", defaultBranch: "main" });
    seed(CONNECTOR_PATH, { sealed: SEALED });
    const { openToken } = require("../../oauth/githubOAuthCore");
    (openToken as jest.Mock).mockReturnValueOnce("tok_from_connector");

    const result = await loadRepo(UID, KEY);

    expect(result?.token).toBe("tok_from_connector");
    expect(openToken).toHaveBeenCalledWith(SEALED, KEY);
  });

  it("returns null when the repo is linked but GitHub is not connected", async () => {
    // Disconnecting GitHub must STOP runs, not run them from a stale copy.
    seed(REPO_PATH, { url: "https://github.com/owner/repo", defaultBranch: "main" });

    await expect(loadRepo(UID, KEY)).resolves.toBeNull();
  });

  it("ignores a sealed token left on the repo document by the old shape", async () => {
    // Migration safety. Before this change the token lived on the repo doc;
    // preferring that copy would mean a founder who reconnected GitHub kept
    // running against the revoked token, with nothing to indicate why.
    const stale = { iv: "stale", tag: "stale", ciphertext: "stale" };
    seed(REPO_PATH, { url: "https://github.com/owner/repo", defaultBranch: "main", sealed: stale });
    seed(CONNECTOR_PATH, { sealed: SEALED });
    const { openToken } = require("../../oauth/githubOAuthCore");
    (openToken as jest.Mock).mockReturnValueOnce("current");

    const result = await loadRepo(UID, KEY);

    expect(result?.token).toBe("current");
    expect(openToken).toHaveBeenCalledWith(SEALED, KEY);
    expect(openToken).not.toHaveBeenCalledWith(stale, KEY);
  });

  // ---- the guards, all of which fail closed ------------------------------

  it("returns null and logs nothing when the sealed token fails to open", async () => {
    // Every guard must be cleared so execution actually REACHES openToken and
    // throws into the catch — otherwise this test passes from an early return
    // and protects nothing.
    seedLinkedAndConnected();
    const { openToken } = require("../../oauth/githubOAuthCore");
    (openToken as jest.Mock).mockClear();

    const errorSpy = jest.spyOn(console, "error").mockImplementation(() => undefined);
    const warnSpy = jest.spyOn(console, "warn").mockImplementation(() => undefined);
    const logSpy = jest.spyOn(console, "log").mockImplementation(() => undefined);

    try {
      const result = await loadRepo(UID, KEY);

      expect(result).toBeNull();
      // Proof the catch was reached rather than an earlier guard returning
      // null: every guard also returns null and logs nothing, so without this
      // the assertions below cannot tell the two apart.
      expect(openToken).toHaveBeenCalledTimes(1);
      expect(errorSpy).not.toHaveBeenCalled();
      expect(warnSpy).not.toHaveBeenCalled();
      expect(logSpy).not.toHaveBeenCalled();
    } finally {
      errorSpy.mockRestore();
      warnSpy.mockRestore();
      logSpy.mockRestore();
    }
  });

  it("returns null when the repo document does not exist at all", async () => {
    seed(CONNECTOR_PATH, { sealed: SEALED });
    await expect(loadRepo(UID, KEY)).resolves.toBeNull();
  });

  it("returns null when defaultBranch is missing from the repo doc", async () => {
    seed(REPO_PATH, { url: "https://github.com/owner/repo" });
    seed(CONNECTOR_PATH, { sealed: SEALED });
    await expect(loadRepo(UID, KEY)).resolves.toBeNull();
  });

  it("returns null when defaultBranch is an empty string", async () => {
    seedLinkedAndConnected({ defaultBranch: "" });
    await expect(loadRepo(UID, KEY)).resolves.toBeNull();
  });

  it("returns null when defaultBranch is whitespace-only", async () => {
    seedLinkedAndConnected({ defaultBranch: "   " });
    await expect(loadRepo(UID, KEY)).resolves.toBeNull();
  });

  it("returns null rather than throwing when url is not a string", async () => {
    seedLinkedAndConnected({ url: 42 });
    await expect(loadRepo(UID, KEY)).resolves.toBeNull();
  });

  // ---- the success path --------------------------------------------------

  it("trims padding from defaultBranch before returning it", async () => {
    seedLinkedAndConnected({ defaultBranch: " master " });
    const { openToken } = require("../../oauth/githubOAuthCore");
    (openToken as jest.Mock).mockReturnValueOnce("test-token");

    await expect(loadRepo(UID, KEY)).resolves.toEqual({
      url: "https://github.com/owner/repo",
      owner: "owner",
      repo: "repo",
      defaultBranch: "master",
      token: "test-token"
    });
  });

  it("returns a RepoLink with the exact defaultBranch value when present", async () => {
    seedLinkedAndConnected({ defaultBranch: "master" });
    const { openToken } = require("../../oauth/githubOAuthCore");
    (openToken as jest.Mock).mockReturnValueOnce("test-token");

    await expect(loadRepo(UID, KEY)).resolves.toEqual({
      url: "https://github.com/owner/repo",
      owner: "owner",
      repo: "repo",
      defaultBranch: "master",
      token: "test-token"
    });
  });
});
