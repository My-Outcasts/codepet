import {
  SHARED_PREAMBLE,
  POSITION_SCHEMA_DOC,
  buildSharedPrefix,
  estimateTokens
} from "../company/preamble";
import { MODEL_PRICING, AGENT_MODEL } from "../anthropic";
import { FounderContext } from "../company/types";

const founder: FounderContext = {
  profile:
    "Solo founder, technical, previously a backend engineer at a mid-size fintech. " +
    "Has shipped one product before that reached 200 paying users then plateaued. " +
    "Comfortable with Swift and TypeScript, no design or sales background.",
  stage:
    "Pre-revenue, 4 months of runway left, product in closed beta with 30 users, " +
    "no pricing page yet.",
  constraints: [
    "Cannot hire — no budget for headcount this quarter.",
    "Must ship to the App Store before the end of next month.",
    "Refuses to take outside investment at this stage."
  ],
  language: "vi"
};

const rawRequest =
  "Should I build a team-collaboration feature so companies can buy seats, " +
  "or should I first put a price on the single-player product I already have?";

describe("estimateTokens", () => {
  test("scales with length and never returns zero for non-empty input", () => {
    expect(estimateTokens("")).toBe(0);
    expect(estimateTokens("a")).toBeGreaterThan(0);
    expect(estimateTokens("a".repeat(3500))).toBeGreaterThan(estimateTokens("a".repeat(350)));
  });

  test("approximates 3.5 chars per token", () => {
    expect(estimateTokens("a".repeat(3500))).toBe(1000);
  });
});

describe("buildSharedPrefix", () => {
  test("contains the shared preamble verbatim", () => {
    expect(buildSharedPrefix({ founder, rawRequest })).toContain(SHARED_PREAMBLE.trim());
  });

  test("embeds founder context, stage, and every constraint", () => {
    const prefix = buildSharedPrefix({ founder, rawRequest });
    expect(prefix).toContain(founder.profile);
    expect(prefix).toContain(founder.stage);
    for (const c of founder.constraints) {
      expect(prefix).toContain(c);
    }
  });

  test("embeds the founder's request verbatim", () => {
    expect(buildSharedPrefix({ founder, rawRequest })).toContain(rawRequest);
  });

  test("resolves the output language to a human name", () => {
    expect(buildSharedPrefix({ founder, rawRequest })).toContain("Tiếng Việt");
    expect(
      buildSharedPrefix({ founder: { ...founder, language: "en" }, rawRequest })
    ).toContain("English");
  });

  test("handles an empty constraints list without emitting a dangling header", () => {
    const prefix = buildSharedPrefix({
      founder: { ...founder, constraints: [] },
      rawRequest
    });
    expect(prefix).toContain("None stated.");
  });

  test("contains no agent role text — roles live after the cache breakpoint", () => {
    const prefix = buildSharedPrefix({ founder, rawRequest });
    expect(prefix).not.toContain("Head of Product");
    expect(prefix).not.toContain("Head of Finance");
    expect(prefix).not.toContain("Devil's Advocate");
  });

  test("is deterministic — identical inputs give byte-identical output", () => {
    expect(buildSharedPrefix({ founder, rawRequest })).toBe(
      buildSharedPrefix({ founder, rawRequest })
    );
  });

  test("clears the cache minimum for the department-agent model", () => {
    // Below claude-sonnet-5's 1024-token floor, cache_control silently no-ops:
    // no error, no warning, just full price on every agent call.
    const floor = MODEL_PRICING[AGENT_MODEL].cacheMinTokens;
    expect(estimateTokens(buildSharedPrefix({ founder, rawRequest }))).toBeGreaterThan(floor);
  });

  test("clears the cache floor even with a minimal founder context", () => {
    // Caching must not depend on how verbose the founder was. A terse profile
    // is the worst case, so it is the one worth asserting.
    const floor = MODEL_PRICING[AGENT_MODEL].cacheMinTokens;
    const minimal = buildSharedPrefix({
      founder: { profile: "Solo founder.", stage: "Pre-revenue.", constraints: [], language: "en" },
      rawRequest: "Should I raise prices?"
    });
    expect(estimateTokens(minimal)).toBeGreaterThan(floor);
  });

  test("the constant portion alone clears the cache floor", () => {
    // The structural guarantee behind the test above: preamble + schema doc are
    // present in every prefix regardless of input, so if they clear the floor on
    // their own, caching can never silently switch off. Shortening either
    // constant is what would break it — hence this assertion rather than a
    // comment asking future editors to be careful.
    const floor = MODEL_PRICING[AGENT_MODEL].cacheMinTokens;
    const constantOnly = estimateTokens(SHARED_PREAMBLE) + estimateTokens(POSITION_SCHEMA_DOC);
    expect(constantOnly).toBeGreaterThan(floor);
  });
});
