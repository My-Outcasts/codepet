import { parseRepoUrl, branchName, MOUNT_PATH } from "../engRepo";

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
