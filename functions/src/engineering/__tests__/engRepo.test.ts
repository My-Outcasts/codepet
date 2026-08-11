jest.mock("firebase-admin", () => {
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
    const errorSpy = jest.spyOn(console, "error").mockImplementation(() => undefined);
    const warnSpy = jest.spyOn(console, "warn").mockImplementation(() => undefined);
    const logSpy = jest.spyOn(console, "log").mockImplementation(() => undefined);

    try {
      const result = await loadRepo("some-uid", "some-enc-key");

      expect(result).toBeNull();
      expect(errorSpy).not.toHaveBeenCalled();
      expect(warnSpy).not.toHaveBeenCalled();
      expect(logSpy).not.toHaveBeenCalled();
    } finally {
      errorSpy.mockRestore();
      warnSpy.mockRestore();
      logSpy.mockRestore();
    }
  });
});
