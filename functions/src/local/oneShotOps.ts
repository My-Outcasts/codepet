/**
 * Every ONE-SHOT Cloud Function — a prompt in, one structured JSON body out — expressed so
 * it can run on the founder's own Claude Code instead of Codepet's API key.
 *
 * **Why a registry and not a sidecar per function.** `chatSidecar` exists because chat is
 * a streaming, tool-calling conversation; nothing else here is. `enrichBrief`,
 * `synthesizeBrief`, and the ones that follow are all the same shape: build a prompt, force
 * one tool call, read its arguments as JSON. That shape deserves ONE process and one
 * transport, not six near-identical copies of the same spawn code.
 *
 * **Prompts are not re-implemented.** Every op below imports the SAME builder the HTTP
 * handler calls, and renders the SAME `input_schema` the API's forced tool declares. That
 * is the whole anti-drift property: a prompt edited for the cloud path is edited for the
 * local path in the same keystroke, because there is only one of it.
 *
 * **What the local path cannot match.** The API can FORCE a tool call
 * (`tool_choice: {type: "tool"}`); `claude -p` has no such flag, so the schema is asked for
 * in prose and the reply is parsed. `extractJson` is therefore tolerant, and every op
 * validates what it got rather than trusting it — a model that answered with prose must
 * fail the op, not write prose into the founder's brief.
 */

import {
  CompanyBrief,
  BriefEnrichment,
  ENRICH_SYSTEM,
  ENRICH_TOOL,
  buildEnrichPrompt,
  hasEnrichableSignal,
  mergeEnrichment,
} from "../enrichBriefCore";
import {
  ROADMAP_SYSTEM,
  ROADMAP_TOOL,
  RoadmapBrief,
  buildRoadmapPrompt,
  coerceRoadmap,
} from "../generateRoadmapCore";
import {
  DECISIONS_EXTRACT_SCHEMA,
  EXTRACT_SYSTEM,
  buildExtractPrompt,
  coerceDecisions,
  parseDeliverable,
  parseExisting,
} from "../extractDecisionsCore";
import {
  DELIVERABLE_SYSTEM,
  DELIVERABLE_TOOL,
  buildRunTaskPrompt,
  coerceDeliverable,
} from "../runTaskCore";
import {
  OVERVIEW_TOOL,
  SynthesizeBriefPayload,
  buildSynthesizeUserMessage,
  synthesizeSystemPrompt,
  validateSynthesizeBriefPayload,
} from "../synthesizeBriefCore";

/** What the sidecar has to do next for one request. */
export interface OneShotPlan {
  /**
   * Set when no model call is needed at all. The HTTP handler has the same short circuits
   * (an already-summarised brief, a brief with nothing to read) and returns 200 without
   * spending anything; the local path must not spend a turn of the founder's plan where
   * the cloud path would not have spent a token.
   */
  answer?: unknown;
  system?: string;
  prompt?: string;
  /** The forced tool's `input_schema`, verbatim. Rendered into the prompt by the sidecar. */
  schema?: unknown;
}

export interface OneShotMeta {
  /** What actually answered, as Claude Code reported it. */
  model: string;
  /** Passed in rather than read here so the pure parts stay testable without a clock. */
  nowISO: string;
}

export interface OneShotOp {
  /** May throw `OneShotBadRequest` — the local equivalent of the handler's 400. */
  plan(body: any): OneShotPlan;
  /** Turn the model's parsed JSON into the EXACT body the Cloud Function returns. */
  respond(body: any, parsed: any, meta: OneShotMeta): unknown;
}

/** A payload the op refuses. Distinguished so the sidecar can report it as such. */
export class OneShotBadRequest extends Error {}

/** The model answered, but not with something this op can use. */
export class OneShotUnusableAnswer extends Error {}

/**
 * The instruction that replaces `tool_choice`.
 *
 * Two things it has to do, both learned rather than assumed:
 *
 *  1. **Name the shape from the schema itself**, not from a hand-written description of it.
 *     The API path validates against `input_schema`; a prose paraphrase would be a second
 *     source of truth that drifts the first time a field is added.
 *  2. **Cancel the tool instruction the shared prompt ends with.** `buildSynthesizeUserMessage`
 *     closes with "Now call record_overview with ..." — correct for the API, impossible
 *     here. Contradicting it explicitly beats forking the builder, which is the one thing
 *     this file exists to avoid.
 */
export function schemaInstruction(schema: unknown): string {
  return [
    "There are no tools available in this run. If anything above asks you to call a tool,",
    "do not attempt it — put exactly the arguments you would have passed to that tool in",
    "the JSON object described below instead.",
    "",
    "Reply with ONLY that JSON object. No prose before or after it, no code fence, no",
    "explanation. It must satisfy this JSON Schema:",
    "",
    JSON.stringify(schema, null, 2),
  ].join("\n");
}

/**
 * Pull the JSON object out of whatever the model actually said.
 *
 * Tolerant on purpose: the instruction above asks for a bare object, and a model that
 * wraps it in a fence or a sentence of preamble has still answered the question. What it
 * will NOT do is guess — a reply with no object in it throws, so the caller fails the op
 * instead of writing a default nobody asked for.
 *
 * The scan is brace-balanced and string-aware rather than a regex: a summary containing
 * `}` (or an escaped quote) is ordinary founder text, and a greedy or lazy regex mangles
 * one of those two cases.
 */
export function extractJson(text: string): any {
  const start = text.indexOf("{");
  if (start === -1) throw new OneShotUnusableAnswer("no JSON object in the reply");

  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) {
        const slice = text.slice(start, i + 1);
        try {
          return JSON.parse(slice);
        } catch (err) {
          throw new OneShotUnusableAnswer(`reply was not valid JSON: ${String(err)}`);
        }
      }
    }
  }
  throw new OneShotUnusableAnswer("JSON object in the reply is unterminated");
}

/**
 * Which model to report, read out of `claude -p --output-format json`.
 *
 * `modelUsage` is keyed by model id and can hold more than one — a run also bills small
 * side calls (measured: a Haiku entry alongside the answering model). The one that produced
 * the answer is the one that emitted the most output tokens, so that is what is reported.
 * Reporting a guess would be worse than the honest fallback: the `model` field reaches the
 * client and is shown.
 */
export function pickModel(envelope: any): string {
  const usage = envelope?.modelUsage;
  if (usage && typeof usage === "object") {
    let best: string | null = null;
    let bestTokens = -1;
    for (const [id, u] of Object.entries(usage as Record<string, any>)) {
      const tokens = typeof u?.outputTokens === "number" ? u.outputTokens : 0;
      if (tokens > bestTokens) {
        best = id;
        bestTokens = tokens;
      }
    }
    if (best) return best;
  }
  return "claude-code-local";
}

export const ONE_SHOT_OPS: Record<string, OneShotOp> = {
  /**
   * `enrichBrief` — the first thing onboarding asks for, and therefore the first thing a
   * founder with no API key finds broken.
   *
   * Fail-open is NOT reproduced here. The handler swallows an upstream failure and returns
   * the raw brief, because a founder mid-onboarding must not be blocked by a model outage.
   * The local path instead reports the failure and lets the CLIENT fail open — which it
   * already does (`(try? await api.enrichBrief(raw)) ?? raw`). Swallowing it in both places
   * would hide a broken local setup behind a brief that looks merely unenriched.
   */
  enrichBrief: {
    plan(body) {
      const brief = body?.brief as CompanyBrief | undefined;
      if (!brief || typeof brief !== "object") throw new OneShotBadRequest("brief required");
      // Same two short circuits as `handleEnrichBrief`, in the same order.
      if (brief.summary?.trim() || !hasEnrichableSignal(brief)) return { answer: { brief } };
      return {
        system: ENRICH_SYSTEM,
        prompt: buildEnrichPrompt(brief),
        schema: ENRICH_TOOL.input_schema,
      };
    },
    respond(body, parsed) {
      if (!parsed || typeof parsed !== "object") {
        throw new OneShotUnusableAnswer("enrichment was not an object");
      }
      // `mergeEnrichment` is what clips, drops blanks, and refuses to overwrite what the
      // founder typed. Calling it is what makes a sloppy local answer as safe as an API one.
      return { brief: mergeEnrichment(body.brief as CompanyBrief, parsed as BriefEnrichment) };
    },
  },

  /**
   * `generateRoadmap` — the board the founder sees the moment onboarding finishes.
   *
   * The cloud path pins Sonnet 5 at medium effort for cost; the local path passes whatever
   * the founder chose in Settings (nothing, by default, which leaves the decision to their
   * own Claude Code). That divergence is deliberate: pinning a model here would spend their
   * plan on a tier they did not pick, and cost is not Codepet's problem on this transport.
   *
   * `coerceRoadmap` is what makes a loose answer safe — it drops unknown phases, unknown
   * departments and dependencies that name nothing, exactly as it does for the API's forced
   * tool. An empty `tasks` array is the fail-open the client already reads as "no change".
   */
  generateRoadmap: {
    plan(body) {
      const brief = body?.brief as RoadmapBrief | undefined;
      if (!brief || typeof brief !== "object" || Array.isArray(brief)) {
        throw new OneShotBadRequest("brief required");
      }
      const language = body?.language === "vi" ? "vi" : "en";
      return {
        system: ROADMAP_SYSTEM,
        prompt: buildRoadmapPrompt({ language, brief }),
        schema: ROADMAP_TOOL.input_schema,
      };
    },
    respond(body, parsed) {
      const language = body?.language === "vi" ? "vi" : "en";
      return coerceRoadmap(parsed, { language });
    },
  },

  /**
   * `runTask` — the deliverable itself, and the most expensive thing Codepet asks for.
   *
   * Every field is narrowed exactly as `handleRunTask` narrows it, in the same order,
   * because `buildRunTaskPrompt` behaves differently for an absent field than for an empty
   * one: a revise carries `reviseNote` + `current` and edits in place, a first run carries
   * neither and writes from scratch. Passing `""` where the handler passes `undefined`
   * would silently turn every first run into a revise of nothing.
   */
  runTask: {
    plan(body) {
      const taskTitle = typeof body?.task_title === "string" ? body.task_title.trim() : "";
      if (!taskTitle) throw new OneShotBadRequest("task_title required");
      return {
        system: DELIVERABLE_SYSTEM,
        prompt: buildRunTaskPrompt({
          companionId: typeof body.companion_id === "string" ? body.companion_id : "byte",
          language: body.language === "vi" ? "vi" : "en",
          context: typeof body.context === "string" ? body.context : "",
          taskTitle,
          taskDetail: typeof body.task_detail === "string" ? body.task_detail : "",
          reviseNote: typeof body.revise_note === "string" ? body.revise_note : undefined,
          current: typeof body.current === "string" ? body.current : undefined,
          deptKey: typeof body.dept_key === "string" ? body.dept_key : undefined,
        }),
        schema: DELIVERABLE_TOOL.input_schema,
      };
    },
    respond(body, parsed) {
      const taskTitle = String(body?.task_title ?? "").trim();
      // Same coercion, and the same refusal: the handler answers 502 rather than storing a
      // deliverable it could not read, because a half-parsed one reaches the library and
      // the founder's approval flow.
      const deliverable = coerceDeliverable(parsed, taskTitle);
      if (!deliverable) throw new OneShotUnusableAnswer("no deliverable in the reply");
      return deliverable;
    },
  },

  /**
   * `extractDecisions` — what an approved deliverable locks in, for the Second Brain.
   *
   * Fire-and-forget on both transports: the founder already approved the deliverable, so a
   * failed extraction costs a Second Brain entry, not their work. `{decisions: []}` is the
   * answer for a deliverable with nothing to read — the handler returns exactly that, without
   * spending anything, and so does this.
   */
  extractDecisions: {
    plan(body) {
      const deliverable = parseDeliverable(body ?? {});
      if (!deliverable) return { answer: { decisions: [] } };
      return {
        system: EXTRACT_SYSTEM,
        prompt: buildExtractPrompt(deliverable, parseExisting(body ?? {})),
        schema: DECISIONS_EXTRACT_SCHEMA,
      };
    },
    respond(_body, parsed) {
      // `coerceDecisions` fails open to an empty list, which is why nothing here throws: a
      // junk answer must cost an entry, never the approval that already happened.
      return coerceDecisions(parsed);
    },
  },

  /**
   * `synthesizeBrief` — the reflection layer's whole-history project description.
   */
  synthesizeBrief: {
    plan(body) {
      const invalid = validateSynthesizeBriefPayload(body);
      if (invalid) throw new OneShotBadRequest(invalid);
      const payload = body as SynthesizeBriefPayload;
      return {
        system: synthesizeSystemPrompt(payload.language),
        prompt: buildSynthesizeUserMessage(payload),
        schema: OVERVIEW_TOOL.input_schema,
      };
    },
    respond(_body, parsed, meta) {
      const overview = typeof parsed?.overview === "string" ? parsed.overview.trim() : "";
      // The handler throws on an empty overview and answers 502 rather than shipping a
      // blank description into the brief box. Same rule here.
      if (!overview) throw new OneShotUnusableAnswer("reply carried no overview");
      return { overview, model: meta.model, generated_at: meta.nowISO };
    },
  },
};
