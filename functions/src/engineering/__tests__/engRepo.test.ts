jest.mock("firebase-admin", () => {
  // Base template only: every test below overrides this per-call with
  // mockResolvedValueOnce, so this default value itself is never read.
  // Kept as a non-throwing shape so an accidental extra `.get()` call
  // (one not stubbed by a test) fails on an assertion rather than on a
  // missing mock implementation.
  const get = jest.fn().mockResolvedValue({
    exists: true,
    data: () => ({
      url: "https://github.com/owner/repo",
      sealed: { iv: "iv", tag: "tag", ciphertext: "ct" }
    })
  });
  const doc = jest.fn().mockReturnValue({ get });
  const firestore = jest.fn().mockReturnValue({ doc });
  return { firestore };
});

jest.mock("../../oauth/githubOAuthCore", () => ({
  openToken: jest.fn(() => {
    throw new Error("bad auth tag");
  })
}));

import { parseRepoUrl, branchName, MOUNT_PATH, loadRepo } from "../engRepo";

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
  it("returns null and logs nothing when the sealed token fails to open", async () => {
    // Per-test override, not a change to the shared module-level default
    // mock: this must clear EVERY earlier guard (url, sealed, AND
    // defaultBranch) so execution actually reaches `openToken` and throws
    // into the catch.
    const admin = require("firebase-admin");
    admin.firestore().doc().get.mockResolvedValueOnce({
      exists: true,
      data: () => ({
        url: "https://github.com/owner/repo",
        sealed: { iv: "iv", tag: "tag", ciphertext: "ct" },
        defaultBranch: "main"
      })
    });

    const { openToken } = require("../../oauth/githubOAuthCore");

    const errorSpy = jest.spyOn(console, "error").mockImplementation(() => undefined);
    const warnSpy = jest.spyOn(console, "warn").mockImplementation(() => undefined);
    const logSpy = jest.spyOn(console, "log").mockImplementation(() => undefined);

    try {
      const result = await loadRepo("some-uid", "some-enc-key");

      expect(result).toBeNull();
      // The assertion this test exists for: proof that execution actually
      // reached the try block and called openToken, rather than returning
      // null from an earlier guard. Every guard also returns null and logs
      // nothing, so without this the rest of the assertions here cannot
      // tell "reached the catch" apart from "exited early" — a future
      // guard added above the decrypt call would keep this test green
      // while testing nothing.
      expect(openToken).toHaveBeenCalled();
      expect(errorSpy).not.toHaveBeenCalled();
      expect(warnSpy).not.toHaveBeenCalled();
      expect(logSpy).not.toHaveBeenCalled();
    } finally {
      errorSpy.mockRestore();
      warnSpy.mockRestore();
      logSpy.mockRestore();
    }
  });

  // This is the tripwire against a reinstated `data.defaultBranch ?? "main"`
  // fallback: a missing field only produces "main" under the old,
  // guessing behaviour, so this test fails against it. The "exact value
  // when present" test below cannot serve that role — nullish coalescing
  // only substitutes on null/undefined, so a defined "master" passes
  // through unchanged under the old code too, and that test would pass
  // identically either way.
  it("returns null when defaultBranch is missing from the repo doc", async () => {
    const admin = require("firebase-admin");
    admin.firestore().doc().get.mockResolvedValueOnce({
      exists: true,
      data: () => ({
        url: "https://github.com/owner/repo",
        sealed: { iv: "iv", tag: "tag", ciphertext: "ct" }
        // NO defaultBranch
      })
    });

    const result = await loadRepo("some-uid", "some-enc-key");

    expect(result).toBeNull();
  });

  it("returns null when defaultBranch is an empty string", async () => {
    const admin = require("firebase-admin");
    admin.firestore().doc().get.mockResolvedValueOnce({
      exists: true,
      data: () => ({
        url: "https://github.com/owner/repo",
        sealed: { iv: "iv", tag: "tag", ciphertext: "ct" },
        defaultBranch: ""
      })
    });

    const result = await loadRepo("some-uid", "some-enc-key");

    expect(result).toBeNull();
  });

  it("returns null when defaultBranch is whitespace-only", async () => {
    const admin = require("firebase-admin");
    admin.firestore().doc().get.mockResolvedValueOnce({
      exists: true,
      data: () => ({
        url: "https://github.com/owner/repo",
        sealed: { iv: "iv", tag: "tag", ciphertext: "ct" },
        defaultBranch: "   "
      })
    });

    const result = await loadRepo("some-uid", "some-enc-key");

    expect(result).toBeNull();
  });

  it("returns null rather than throwing when url is not a string", async () => {
    const admin = require("firebase-admin");
    admin.firestore().doc().get.mockResolvedValueOnce({
      exists: true,
      data: () => ({
        url: 12345,
        sealed: { iv: "iv", tag: "tag", ciphertext: "ct" },
        defaultBranch: "main"
      })
    });

    await expect(loadRepo("some-uid", "some-enc-key")).resolves.toBeNull();
  });

  it("trims padding from defaultBranch before returning it", async () => {
    const admin = require("firebase-admin");
    admin.firestore().doc().get.mockResolvedValueOnce({
      exists: true,
      data: () => ({
        url: "https://github.com/owner/repo",
        sealed: { iv: "iv", tag: "tag", ciphertext: "ct" },
        defaultBranch: " master "
      })
    });

    const { openToken } = require("../../oauth/githubOAuthCore");
    openToken.mockReturnValueOnce("test-token");

    const result = await loadRepo("some-uid", "some-enc-key");

    expect(result).toEqual({
      url: "https://github.com/owner/repo",
      owner: "owner",
      repo: "repo",
      defaultBranch: "master",
      token: "test-token"
    });
  });

  it("returns a RepoLink with the exact defaultBranch value when present", async () => {
    const admin = require("firebase-admin");
    admin.firestore().doc().get.mockResolvedValueOnce({
      exists: true,
      data: () => ({
        url: "https://github.com/owner/repo",
        sealed: { iv: "iv", tag: "tag", ciphertext: "ct" },
        defaultBranch: "master"
      })
    });

    const { openToken } = require("../../oauth/githubOAuthCore");
    openToken.mockReturnValueOnce("test-token");

    const result = await loadRepo("some-uid", "some-enc-key");

    expect(result).toEqual({
      url: "https://github.com/owner/repo",
      owner: "owner",
      repo: "repo",
      defaultBranch: "master",
      token: "test-token"
    });
  });
});
