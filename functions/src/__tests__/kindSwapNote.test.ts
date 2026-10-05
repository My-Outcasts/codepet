import { coerceDeliverable } from "../runTaskCore";

/**
 * CP-062. A screens task filed under Engineering came back as a plain doc: only Design may make
 * screens, so `coerceKindForDepartment` turns the model's `screens` into `doc` — by design. The
 * founder was never told, so it read as the app ignoring the request (5 Oct, build 7). The
 * founder's call: keep the doc, and say why on the card. The server reports the swap.
 */
describe("a kind swapped by the department contract is reported (CP-062)", () => {
  const screens = {
    kind: "screens",
    title: "Onboarding screens",
    body: "# Onboarding\nSix screens.",
    payload: { screens: [{ title: "Welcome", body: "Hi", art: "a pet" }] },
  };

  it("says what was asked for and which department makes it", () => {
    const d = coerceDeliverable(screens, "Design the onboarding screens", "eng") as any;
    expect(d.kind).toBe("doc");
    expect(d.coerced).toEqual({ from: "screens", dept: "design" });
  });

  it("names the owner for each structured kind", () => {
    const owner = (kind: string, dept: string) =>
      (coerceDeliverable({ kind, title: "t", body: "b" }, "t", dept) as any).coerced?.dept;
    expect(owner("sheet", "eng")).toBe("fin");
    expect(owner("site", "eng")).toBe("design");
    expect(owner("calendar", "eng")).toBe("mkt");
  });

  it("is absent when the kind was allowed", () => {
    const d = coerceDeliverable(screens, "Design the onboarding screens", "design") as any;
    expect(d.kind).toBe("screens");
    expect(d.coerced).toBeUndefined();
  });

  it("is absent for a swap that loses nothing the founder could see (doc-to-doc kinds)", () => {
    const d = coerceDeliverable({ kind: "checklist", title: "t", body: "b" }, "t", "design") as any;
    expect(d.kind).toBe("doc");
    expect(d.coerced).toBeUndefined();
  });

  it("is absent with no kind, an unknown kind, no department, or a pinned revise", () => {
    expect((coerceDeliverable({ title: "t", body: "b" }, "t", "eng") as any).coerced).toBeUndefined();
    expect((coerceDeliverable({ kind: "poster", title: "t", body: "b" }, "t", "eng") as any).coerced).toBeUndefined();
    expect((coerceDeliverable(screens, "t", null) as any).coerced).toBeUndefined();
    expect((coerceDeliverable(screens, "t", "eng", "doc") as any).coerced).toBeUndefined();
  });
});

/**
 * The swap above almost never happens on its own: the prompt offers a department only its own
 * kinds, so as Engineering the model writes a doc and never names `screens` (live run, 5 Oct:
 * kind doc, nothing to report). So the answer format lets the model say what the TASK asked for.
 */
describe("asked_for: the task asked for a kind this department does not make (CP-062)", () => {
  const { deliverableTool } = require("../runTaskCore");
  const askedFor = (dept: string) =>
    (deliverableTool(dept).input_schema.properties as any).asked_for;

  it("is offered with exactly the structured kinds the department cannot make", () => {
    expect(askedFor("eng").enum.sort()).toEqual(["calendar", "screens", "sheet", "site"]);
    expect(askedFor("design").enum.sort()).toEqual(["calendar", "sheet"]);
    expect(askedFor("mkt").enum.sort()).toEqual(["screens", "sheet"]);
  });

  it("is not required, so a normal answer is unchanged", () => {
    expect(deliverableTool("eng").input_schema.required ?? []).not.toContain("asked_for");
  });

  it("turns into the swap report on the deliverable", () => {
    const d = coerceDeliverable({ kind: "doc", asked_for: "screens", title: "t", body: "b" }, "t", "eng") as any;
    expect(d.kind).toBe("doc");
    expect(d.coerced).toEqual({ from: "screens", dept: "design" });
  });

  it("is ignored for a kind the department can make, or one it does not know", () => {
    expect((coerceDeliverable({ kind: "doc", asked_for: "screens", title: "t", body: "b" }, "t", "design") as any).coerced).toBeUndefined();
    expect((coerceDeliverable({ kind: "doc", asked_for: "poster", title: "t", body: "b" }, "t", "eng") as any).coerced).toBeUndefined();
  });
});
