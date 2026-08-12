import { parseCompare } from "../engDiff";

const compare = {
  files: [
    { filename: "api/billing.ts", additions: 62, deletions: 0, status: "added", patch: "@@ -0,0 +1,62 @@\n+import Stripe" },
    { filename: "web/Checkout.tsx", additions: 21, deletions: 14, status: "modified", patch: "@@ -1,4 +1,5 @@\n-old\n+new" },
    { filename: "assets/logo.png", additions: 0, deletions: 0, status: "added" }
  ]
};

describe("parseCompare", () => {
  it("extracts one entry per changed file", () => {
    expect(parseCompare(compare).files).toHaveLength(3);
  });

  it("totals additions and deletions across files", () => {
    const summary = parseCompare(compare);
    expect(summary.additions).toBe(83);
    expect(summary.deletions).toBe(14);
  });

  it("keeps a binary file with a null patch rather than dropping it", () => {
    const binary = parseCompare(compare).files.find((f) => f.path === "assets/logo.png");
    expect(binary).toEqual({ file: "assets/logo.png", path: "assets/logo.png", additions: 0, deletions: 0, status: "added", patch: null });
  });

  it("flags a truncated compare so the UI can say so", () => {
    // GitHub caps the compare response at 300 files.
    const many = { files: Array.from({ length: 300 }, (_, i) => ({ filename: `f${i}.ts`, additions: 1, deletions: 0, status: "added", patch: "@@" })) };
    expect(parseCompare(many).truncated).toBe(true);
    expect(parseCompare(compare).truncated).toBe(false);
  });

  it("reads the new name for a rename, and keeps the old one visible", () => {
    const renamed = { files: [{ filename: "b.ts", previous_filename: "a.ts", additions: 0, deletions: 0, status: "renamed" }] };
    expect(parseCompare(renamed).files[0].path).toBe("a.ts → b.ts");
  });

  it("returns an empty summary for a compare with no changes", () => {
    expect(parseCompare({ files: [] })).toEqual({ files: [], additions: 0, deletions: 0, truncated: false });
  });

  it("returns an empty summary rather than throwing on a malformed payload", () => {
    expect(parseCompare(null)).toEqual({ files: [], additions: 0, deletions: 0, truncated: false });
    expect(parseCompare({ files: "nope" })).toEqual({ files: [], additions: 0, deletions: 0, truncated: false });
  });

  it("does not leak a shared mutable array between calls", () => {
    // A caller that pushes onto the result would corrupt a module constant.
    const firstResult = parseCompare({ files: [{}] });
    const secondResult = parseCompare({ files: [{}] });

    // Mutate the first result's files array.
    firstResult.files.push({ file: "mutated.ts", path: "mutated.ts", additions: 0, deletions: 0, status: "added", patch: null });

    // The second call's files must still be empty — not corrupted by the first call.
    expect(secondResult.files).toHaveLength(0);

    // They must also be different array objects, not aliases.
    expect(firstResult.files).not.toBe(secondResult.files);
  });

  it("reports truncated=true even when a malformed entry is filtered out", () => {
    // GitHub caps at 300 files. If we filter out one malformed entry, we have 299
    // valid files, but the input WAS capped, so we must report truncated: true.
    const entries: unknown[] = Array.from({ length: 299 }, (_, i) => ({ filename: `f${i}.ts`, additions: 1, deletions: 0, status: "added", patch: "@@" }));
    // Add one malformed entry (missing filename) to reach 300 total.
    entries.push({ additions: 1, deletions: 0, status: "added", patch: "@@" });

    const result = parseCompare({ files: entries });

    expect(result.files).toHaveLength(299);
    expect(result.truncated).toBe(true);
  });

  it("yields file: current name for a renamed file, while path shows the arrow form", () => {
    const renamed = { files: [{ filename: "b.ts", previous_filename: "a.ts", additions: 0, deletions: 0, status: "renamed" }] };
    const file = parseCompare(renamed).files[0];
    expect(file.path).toBe("a.ts → b.ts");
    expect(file.file).toBe("b.ts");
  });

  it("yields file equal to path for a non-renamed file", () => {
    const result = parseCompare(compare);
    for (const file of result.files) {
      expect(file.file).toBe(file.path);
    }
  });

  it("yields a correct file for a binary with no patch", () => {
    const binary = parseCompare(compare).files.find((f) => f.path === "assets/logo.png");
    expect(binary?.file).toBe("assets/logo.png");
    expect(binary?.patch).toBe(null);
  });
});
