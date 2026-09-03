import { buildRunTaskPrompt, parseUpstream } from "../runTaskCore";
import { ONE_SHOT_OPS } from "../local/oneShotOps";

/**
 * Outputs feeding forward, on the prompt side.
 *
 * Mirrors the `deptKey` bug this file already records at `runTaskCore.ts:60-63`: a run has
 * always been performed BY a department, and the prompt was never told which one, so a
 * marketing deliverable was written with no marketing knowledge behind it. Same shape here —
 * `mur-site` depends on `mur-brand`, the dependency arrows were on screen, and the model
 * never heard about them.
 */

const base = {
  companionId: "nova", language: "en", context: "Murror",
  taskTitle: "Build the Murror landing page", taskDetail: "", deptKey: "mkt",
};

describe("upstream work in the run prompt", () => {
  it("names the pet, the department and the body, and asks the model to credit it", () => {
    const p = buildRunTaskPrompt({
      ...base,
      upstream: [{ taskTitle: "Shape the Murror visual direction", deptName: "Design",
                   petName: "Luna", kind: "doc", body: "Night sky, warm light." }],
    });
    expect(p).toContain("Luna (Design)");
    expect(p).toContain("Shape the Murror visual direction");
    expect(p).toContain("Night sky, warm light.");
    expect(p).toMatch(/build on this/i);
    expect(p).toMatch(/say so in one short phrase/i);
  });

  it("omits the block entirely when there is no upstream", () => {
    expect(buildRunTaskPrompt(base)).not.toMatch(/already produced work/i);
    expect(buildRunTaskPrompt({ ...base, upstream: [] })).not.toMatch(/already produced work/i);
  });

  it("marks an unapproved draft as one", () => {
    const p = buildRunTaskPrompt({
      ...base,
      upstream: [{ taskTitle: "T", deptName: "Design", petName: "Luna",
                   kind: "doc", body: "B", unapproved: true }],
    });
    expect(p).toMatch(/not yet approved/i);
  });

  /**
   * A dependency-free run is nearly every run, so the block's absence has to leave the
   * prompt byte-for-byte what it was before this field existed — the same promise `deptKey`
   * made when it landed. An "omits the block" assertion on one phrase would still pass if
   * the field had appended a stray blank line to every prompt Codepet sends.
   */
  it("leaves a run with no upstream byte-for-byte unchanged", () => {
    expect(buildRunTaskPrompt({ ...base, upstream: [] })).toBe(buildRunTaskPrompt(base));
    expect(buildRunTaskPrompt({ ...base, upstream: undefined })).toBe(buildRunTaskPrompt(base));
  });
});

/**
 * `parseUpstream` exists so the two transports cannot narrow this field differently. It is
 * one function called by `handleRunTask` and by the `runTask` entry in `ONE_SHOT_OPS`,
 * rather than two copies of the same `typeof` checks that drift apart.
 *
 * What arrives here is off the wire and its shape is not ours to trust.
 */
describe("parseUpstream", () => {
  const item = { taskTitle: "Brand", deptName: "Design", petName: "Luna",
                 kind: "doc", body: "B" };

  it("reads a well-formed array", () => {
    expect(parseUpstream([item])).toEqual([{ ...item, unapproved: false }]);
  });

  /** Absent, not empty — `buildRunTaskPrompt` branches on the array having length. */
  it("answers undefined for anything that is not a non-empty array", () => {
    expect(parseUpstream(undefined)).toBeUndefined();
    expect(parseUpstream(null)).toBeUndefined();
    expect(parseUpstream([])).toBeUndefined();
    expect(parseUpstream("upstream")).toBeUndefined();
    expect(parseUpstream({ 0: item })).toBeUndefined();
  });

  it("drops an item with no body and one that is not an object", () => {
    expect(parseUpstream([{ ...item, body: "   " }])).toBeUndefined();
    expect(parseUpstream(["nope", null, item])).toEqual([{ ...item, unapproved: false }]);
  });

  /**
   * The caps are enforced HERE and not only in the Swift that sends it. A body arrives as a
   * string of unknown length; trusting the client's cap would put an unbounded deliverable
   * into a prompt already carrying 4000 characters of company context.
   */
  it("caps at three items and clips each body", () => {
    const many = [1, 2, 3, 4, 5].map((n) => ({ ...item, taskTitle: `T${n}`,
                                               body: "x".repeat(4000) }));
    const out = parseUpstream(many)!;
    expect(out).toHaveLength(3);
    expect(out.map((u) => u.taskTitle)).toEqual(["T1", "T2", "T3"]);
    for (const u of out) expect(u.body.length).toBeLessThanOrEqual(1500);
  });

  it("keeps a missing name as an empty string rather than the word undefined", () => {
    const out = parseUpstream([{ taskTitle: "Brand", body: "B" }])!;
    expect(out[0].petName).toBe("");
    expect(out[0].deptName).toBe("");
  });

  it("reads unapproved as a boolean", () => {
    expect(parseUpstream([{ ...item, unapproved: true }])![0].unapproved).toBe(true);
    expect(parseUpstream([{ ...item, unapproved: "yes" }])![0].unapproved).toBe(false);
  });
});

/**
 * The third place. `RunTaskArgs` and the HTTP handler are the two obvious ones; miss the
 * `ONE_SHOT_OPS` entry and the local path — which is now the DEFAULT for a founder running
 * on their own Claude plan — silently drops the field, on the transport nobody curls.
 */
describe("the local runTask op forwards upstream", () => {
  const op = ONE_SHOT_OPS.runTask;
  const body = {
    language: "en", companion_id: "nova", context: "Murror",
    task_title: "Build the Murror landing page", task_detail: "", dept_key: "mkt",
    upstream: [{ taskTitle: "Shape the Murror visual direction", deptName: "Design",
                 petName: "Luna", kind: "doc", body: "Night sky, warm light." }],
  };

  it("asks with the same prompt the Cloud Function would build", () => {
    expect(op.plan(body).prompt).toBe(buildRunTaskPrompt({
      companionId: "nova", language: "en", context: "Murror",
      taskTitle: "Build the Murror landing page", taskDetail: "",
      reviseNote: undefined, current: undefined, deptKey: "mkt",
      upstream: parseUpstream(body.upstream),
    }));
  });

  /** The behavioural version of the same guard: the pet is IN the prompt, not merely equal. */
  it("puts the upstream department's work in the prompt it sends", () => {
    expect(op.plan(body).prompt).toContain("Luna (Design)");
    expect(op.plan(body).prompt).toContain("Night sky, warm light.");
  });

  it("leaves a body with no upstream identical to before the field existed", () => {
    const { upstream, ...withoutUpstream } = body;
    expect(op.plan(withoutUpstream).prompt).toBe(buildRunTaskPrompt({
      companionId: "nova", language: "en", context: "Murror",
      taskTitle: "Build the Murror landing page", taskDetail: "", deptKey: "mkt",
    }));
  });
});
