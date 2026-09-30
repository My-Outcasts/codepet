// Pure logic for the runTask CF — no firebase/express/anthropic imports, so it can be
// unit-tested (and verified) without loading the heavy Cloud-Functions module tree.
// The IO handler lives in runTask.ts and imports from here.

import { evalFormula, formulaRefs, parseFormula, type FormulaNode } from "./sheetFormula";
import { companionFor } from "./companyChatCore";
import {
  departmentBrief,
  DEPARTMENT_NAMES,
  DEPARTMENT_OUTPUTS,
  departmentOutputBlock,
  coerceKindForDepartment,
} from "./departments";

// Mirrors native `DeliverableKind`. Keep in sync with codepet/Models — this is the
// contract the Swift client decodes `kind` against.
export const DELIVERABLE_KINDS = new Set([
  "doc",
  "post",
  "email",
  "legal",
  "screens",
  "sheet",
  "site",
  "dms",
  "calendar",
  "checklist",
  "plan",
  "text",
  "other",
]);

const clip = (v: unknown, n: number) => (typeof v === "string" ? v.trim().slice(0, n) : "");

/** One upstream department's finished work — the Swift `UpstreamWork` in `RunTaskClient.swift`.
 *  Field names are camelCase on both sides deliberately: the two declarations have to agree,
 *  and they are diffed against each other by name. */
export interface UpstreamWork {
  taskTitle: string;
  deptName: string;
  petName: string;
  kind: string;
  body: string;
  unapproved?: boolean;
}

/** Items past this many are dropped, and each body clipped to `UPSTREAM_BODY_LIMIT`. */
const UPSTREAM_CAP = 3;
const UPSTREAM_BODY_LIMIT = 1500;

/**
 * Narrow `upstream` off the wire — ONE function, called by `handleRunTask` and by the
 * `runTask` entry in `ONE_SHOT_OPS`, so the two transports cannot narrow it differently.
 * Two copies of these checks would drift, and the local path is the one nobody curls.
 *
 * Returns `undefined` rather than `[]` for anything unusable: `buildRunTaskPrompt` branches
 * on the array having length, and a dependency-free run must produce the prompt it always did.
 *
 * The caps are re-enforced here and not merely trusted from the client. A body arrives as a
 * string of unknown length; an unbounded one would land in a prompt already carrying 4000
 * characters of company context.
 */
export function parseUpstream(raw: unknown): UpstreamWork[] | undefined {
  if (!Array.isArray(raw)) return undefined;
  const out: UpstreamWork[] = [];
  for (const entry of raw) {
    if (out.length >= UPSTREAM_CAP) break;
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue;
    const e = entry as Record<string, unknown>;
    const body = clip(e.body, UPSTREAM_BODY_LIMIT);
    // No body, nothing to build on — an item that names a department and carries none of its
    // work would spend prompt on an instruction to credit something the model cannot read.
    if (!body) continue;
    out.push({
      taskTitle: clip(e.taskTitle, 200),
      deptName: clip(e.deptName, 80),
      petName: clip(e.petName, 80),
      kind: clip(e.kind, 40),
      body,
      unapproved: e.unapproved === true,
    });
  }
  return out.length ? out : undefined;
}

export interface RunTaskArgs {
  companionId: string;
  language: string;
  context: string;
  taskTitle: string;
  taskDetail: string;
  /** Free-text tweak for a re-run (e.g. "Shorter", "More detail", "Punchier", or custom). */
  reviseNote?: string;
  /** The current draft's body being revised. Required alongside reviseNote for a revise pass. */
  current?: string;
  /** The kind of the deliverable being revised, and its structured payload. Without them "keep
   *  the same kind" names no kind: a LIVE site revised from its body alone came back a doc. */
  currentKind?: string;
  currentPayload?: unknown;
  /** Owning department key of the task, so the deliverable comes from that function's
   *  expertise rather than generic company context. Unknown/absent → no department block. */
  deptKey?: string | null;
  /** Finished work from the departments this task depends on. The graph used to gate order
   *  and never information — see the deptKey comment below for the same bug, already fixed. */
  upstream?: UpstreamWork[];
}

/**
 * The per-kind payload guide — one entry per structured kind, in the order it renders.
 *
 * This was one flat string naming all eight kinds. It has to be addressable by kind now: a
 * department declares which kinds it may hand back, and a guide that still explains all eight
 * both wastes the prompt and re-offers the kind the contract just closed.
 */
const PAYLOAD_GUIDE: ReadonlyArray<readonly [string, string]> = [
  ["checklist", "Build a concrete setup/launch checklist — every actionable step it really takes, in order (`items[].t`), each with `done` true only for obvious already-satisfied prerequisites. Give a step an `owner` (a role, a department, or \"you\" for the founder) and a `due` (\"today\", \"before launch\", \"day 3\") where the company context makes them clear; leave either empty rather than invent one."],
  ["doc", "`call` = the decision/recommendation in 1-2 sentences up front; `sections[]` = 2-5 labeled {h,p} reasoning blocks (why it's right, tradeoffs, what's out); `next[]` = 1-3 next actions; `rules_out[]` = 0-3 options this decision forecloses, so it can be revisited; a section may carry `source` = what it rests on (a fact from the company context or an upstream deliverable), empty if nothing specific."],
  ["legal", "`sections[]` = the document's clauses in order, as many as it needs, each {h,p}: `h` a short clause heading WITHOUT a number (the app numbers them), `p` the clause text. The `body` carries the same document in full."],
  ["plan", "an HONEST code-change plan — `goal` (one line), `steps[]` (3-5 ordered), `changes[]` = {area, edit} in plain terms (no fabricated file paths), `verify[]` (future-tense checks), `risks` (one line). Never claim it shipped."],
  ["dms", "2-4 outreach message TEMPLATES, `messages[]` = {audience, note, msg}. `audience` is a TYPE of person or a place (\"lapsed journaler\", \"r/CasualConversation\"), never an invented name: the founder may send these, and a made-up recipient reads exactly like a real one. `note` = why this audience is worth writing to; `msg` = the warm, specific message, with `[name]` where the founder will put a real recipient."],
  ["post", "`platform` = where it will be published (\"X\", \"LinkedIn\", \"Threads\"…). The `body` is the post itself and must fit that platform's length limit; `limit` = that limit in characters if you know it."],
  ["email", "`subject` = the subject line (never repeated as a heading in the body); `to` = who it is for, in the founder's own words or as a type of person (\"the two who asked to pay\", \"beta testers who went quiet\"), never an invented name and never an address — empty if unknown. The `body` is the email itself."],
  ["calendar", "a plan in phases — a content calendar, a launch runway, a rollout — `phases[]` = 1-8 {label, from, to, items[]}: `label` names the phase (\"Week 1\", \"Five days out\", \"Ship day\"), `from`/`to` its span as relative labels (\"T-5\", \"Day 8\"), never a calendar date; each phase's `items[]` = 1-8 {when, format, channel, owner, body}: `when` a relative day (\"Mon\", \"T-5\"), `format` what it is (thread, email, review), `channel` where it goes (\"X\", \"App Store\") and `owner` who does it (a department or \"you\") where known, else empty; `body` the item itself, specific to this company."],
  ["sheet", "a live model of whatever the task is about (pricing, costs, a runway, a funnel) — `inputs[]` = 2-8 assumptions the founder can move, each {key, name, unit, val, min, max, step}: `key` a short snake_case id, `unit` \"$\", \"%\" (8 means 8%), \"users\", \"mo\" or a short word, `val` a realistic default inside a sensible `min`-`max` range; `outputs[]` = 1-8 results, the most important FIRST, each {key, name, unit, formula}. A `formula` uses input keys, other output keys, numbers, + - * / ^ ( ) and min, max, round, ceil, floor — e.g. `round(waitlist * conversion / 100)`. Never write an output's value; the app computes it from the formula. `summary` = one paragraph on what the model shows at the defaults."],
  ["site", "copy for a one-page landing site — `title`, `brand`, `headline`, `sub`, `ctaPrimary`, `howEyebrow`, `howTitle`, exactly 3 `steps[]` = {h,p}, `featEyebrow`, `featTitle`, exactly 3 `features[]` = {h,p}, `finalTitle`, `finalCta`, `accent` (6-digit hex). Use empty strings for unused optional fields (kicker, headlineHi, ctaSecondary, quote, quoteBy, finalSub). Never write HTML."],
  ["screens", "exactly 3 onboarding `screens[]` = {name, time, kick, title, sub, art, cta, note}, with `art` set to \"connect\", \"session\", \"recap\" in that order."],
];

/** "a", "a or b", "a, b, or c" — the prose the guide preamble used to spell out by hand. */
const orList = (xs: readonly string[]): string =>
  xs.length < 2
    ? xs[0] ?? ""
    : xs.length === 2
      ? `${xs[0]} or ${xs[1]}`
      : `${xs.slice(0, -1).join(", ")}, or ${xs[xs.length - 1]}`;

/**
 * The kind a revise pass must keep, or undefined. Only a REAL revise (note and current body both
 * present — the same guard the prompt uses), only a kind the vocabulary knows, and only one the
 * task's department may still produce: pinning a kind the contract closed would put back exactly
 * what `coerceKindForDepartment` exists to take out.
 */
export function revisePin(args: {
  reviseNote?: string; current?: string; currentKind?: string; deptKey?: string | null;
}): string | undefined {
  const k = typeof args.currentKind === "string" ? args.currentKind.trim() : "";
  if (!args.reviseNote?.trim() || !args.current?.trim() || !DELIVERABLE_KINDS.has(k)) return undefined;
  return coerceKindForDepartment(args.deptKey, k) === k ? k : undefined;
}

/** Build the companion-voiced generation prompt for a single roadmap task. */
export function buildRunTaskPrompt(args: RunTaskArgs): string {
  const c = companionFor(args.companionId);
  const context = clip(args.context, 4000);
  const taskTitle = clip(args.taskTitle, 200);
  const taskDetail = clip(args.taskDetail, 1000);
  // Which kinds this run is allowed to produce. A department declares its own contract
  // (`DEPARTMENT_OUTPUTS`); a dept-less legacy task keeps the whole list, because inventing a
  // contract for a task that never had one would change what it produces.
  const contract = args.deptKey ? DEPARTMENT_OUTPUTS[args.deptKey] : undefined;
  const kinds = contract
    ? [...contract.primary, ...contract.allowed]
    : Array.from(DELIVERABLE_KINDS);
  const kindsList = kinds.join(", ");
  // The payload guide, narrowed the same way. Constraining only `kindsList` would leave every
  // kind named a second time down here — both the wrong instruction (Finance does not need to
  // know how to fill a `screens` payload) and a re-offer of the kind the contract just closed.
  const guide = PAYLOAD_GUIDE.filter(([k]) => kinds.includes(k));
  const payloadBlock = guide.length
    ? "\n\nALWAYS write the markdown `body`. If (and only if) the kind you chose is " +
      orList(guide.map(([k]) => k)) +
      ", ALSO fill `payload` with that kind's structured fields (leave `payload` empty for any other kind):\n" +
      guide.map(([k, g]) => `- ${k}: ${g}`).join("\n")
    : "\n\nALWAYS write the markdown `body`. Leave `payload` empty.";
  const vi = args.language === "vi" ? "\n\nWrite the title and body in natural, fluent Vietnamese." : "";
  const reviseNote = clip(args.reviseNote, 500);
  const current = clip(args.current, 6000);
  // Only a real revise pass when we have BOTH the note and the draft it applies to — mirrors
  // web's guard (lib/ai/runTaskPrompt.ts). Without both, behavior is identical to today.
  // A revise that knows the kind it is revising names it, and hands over the payload the kind
  // renders from — a site IS its payload; the body is only its copy. An unknown kind keeps the
  // original wording rather than naming something the contract does not have.
  const pinned = revisePin(args);
  // The app nests each rich kind's fields under the kind's own key (`{"site": {...}}`); the
  // schema the model answers in is flat, so the nested form is unwrapped before it is shown.
  const raw = args.currentPayload && typeof args.currentPayload === "object"
    ? args.currentPayload as Record<string, unknown> : undefined;
  const nested = pinned && raw && raw[pinned] && typeof raw[pinned] === "object" ? raw[pinned] : raw;
  const payloadJson = pinned && nested ? clip(JSON.stringify(nested), 4000) : "";
  const revise =
    reviseNote && current
      ? pinned
        ? `\n\nYou are REVISING an existing deliverable of kind "${pinned}". Current version:\n${current}` +
          (payloadJson ? `\n\nIts current structured payload:\n${payloadJson}` : "") +
          `\n\nApply this change: ${reviseNote}. Keep kind "${pinned}" and the same intent` +
          (STRUCTURED_KINDS.has(pinned) ? `, and return the full revised \`payload\` for it too` : "") +
          `; return the full revised deliverable (not a diff).`
        : `\n\nYou are REVISING an existing deliverable. Current version:\n${current}\n\nApply this change: ${reviseNote}. Keep the same kind and intent; return the full revised deliverable (not a diff).`
      : "";

  // The department this task belongs to, as expertise. A run has always been performed BY a
  // department — its pet is credited on the execute log and on the draft card — but the
  // prompt was never told which one, so a marketing deliverable was written with no
  // marketing knowledge behind it. Empty for a dept-less (legacy) task.
  const deptBrief = departmentBrief(args.deptKey);
  const deptName = args.deptKey ? DEPARTMENT_NAMES[args.deptKey] : undefined;
  // The output contract rides with the department identity, not with the kind list further
  // down: "This function produces …" only has a referent once "the Finance function" has been
  // named. Empty for a dept-less task, so its paragraph is unchanged.
  const deptOutputs = departmentOutputBlock(args.deptKey);
  const deptBlock = deptBrief && deptName
    ? `You are doing this work as the ${deptName} function of the founder's company:\n${deptBrief}\n` +
      `Produce what that function would actually produce, at the level of specificity it would use.\n` +
      (deptOutputs ? `${deptOutputs}\n` : "") +
      `\n`
    : "";

  // What the departments this task depends on have already produced. Same shape as the
  // deptBlock bug above: the dependency arrows were drawn on the roadmap and the model was
  // never told about them, so Marketing wrote a landing page having never read Design's
  // brand direction. Asking the model to NAME what it relied on is what makes the credit on
  // the card honest rather than decorative.
  const upstream = args.upstream ?? [];
  const upstreamBlock = upstream.length
    ? `Other departments have already produced work this task must build on:\n\n` +
      upstream
        .map(
          (u) =>
            `— ${u.petName} (${u.deptName}) produced "${clip(u.taskTitle, 200)}"` +
            `${u.unapproved ? " (a draft, not yet approved)" : ""}:\n${clip(u.body, UPSTREAM_BODY_LIMIT)}`
        )
        .join("\n\n") +
      `\n\nBuild on this. Do not contradict it, and do not re-derive what it already decided. ` +
      `Where you rely on it, say so in one short phrase.\n\n`
    : "";

  return (
    `You are ${c.name}, the AI building companion inside Codepet — a senior operator who does real work for a solo founder, department by department.\n\n` +
    `Voice: ${c.voice}\n\n` +
    deptBlock +
    upstreamBlock +
    `The founder's company:\n${context || "The founder hasn't filled in much of a brief yet — keep the deliverable general but still genuinely useful."}\n\n` +
    `Task to complete: ${taskTitle || "(untitled task)"}\n` +
    (taskDetail ? `Task detail: ${taskDetail}\n` : "") +
    `\nProduce the REAL deliverable for this task — not a plan to do it, not a description of what you would do, the actual finished artifact (the document, the copy, the checklist, the email, whatever the task calls for), written as markdown in the body. Pick whichever "kind" best fits what you produced from this exact list: ${kindsList}. Give it a short, clear title. Ground everything in the founder's actual company context above — do not invent facts about them.` +
    payloadBlock +
    // Length discipline. Every field above says what to produce and none said how
    // long, so `body` — the part the founder actually reads — was unbounded.
    // Framed as what a finished artifact looks like rather than as a word cap:
    // a hard count starves the longer kinds (site copy, a 2-week calendar) while
    // still leaving a short email padded.
    "\n\nLENGTH: this is a finished artifact, not a report about one. Write only what the founder needs to use it. No preamble, no restating the task, no \"here is\", no summary of what you just wrote, no closing offer of further help. Do not add sections the kind above does not ask for. Prefer the shortest version that is still complete and specific: an email is an email, not an email plus notes on the email. If a sentence does not change what the founder would do next, cut it." +
    vi +
    revise
  );
}

export interface Deliverable {
  kind: string;
  title: string;
  body: string;
  payload?: DeliverablePayload;
}

export interface ChecklistItem { t: string; done: boolean; owner?: string; due?: string; }
export interface ChecklistPayload { items: ChecklistItem[]; }
export interface DocSection { h: string; p: string; source?: string; }
export interface DocPayload { call: string; sections: DocSection[]; next: string[]; rules_out?: string[]; }
export interface PostPayload { platform: string; limit?: number; }
/** `to` describes a recipient; it is never an address and never an invented person. */
export interface EmailPayload { subject: string; to?: string; }
export interface LegalPayload { sections: DocSection[]; }
export interface PlanChange { area: string; edit: string; }
export interface PlanPayload { goal: string; steps: string[]; changes: PlanChange[]; verify: string[]; risks: string; }
/** `audience`, not `name`: a template addressed to a type, never an invented recipient. */
export interface DmMessage { audience: string; note: string; msg: string; }
export interface DmsPayload { messages: DmMessage[]; }
/** `when`/`format` were `day`/`kind` before CP-002 E1, and a legacy `weeks[]` is lifted into them. */
export interface CalendarItem { when: string; format: string; channel?: string; owner?: string; body: string; }
export interface CalendarPhase { label: string; from: string; to: string; items: CalendarItem[]; }
export interface CalendarPayload { phases: CalendarPhase[]; }
export interface SheetInputField { val: number; min: number; max: number; step: number; }
/** One assumption the founder can move. */
export interface SheetVariable { key: string; name: string; unit: string; val: number; min: number; max: number; step: number; }
/** One result, written as a formula; `value` is computed HERE at the defaults, never taken from the model. */
export interface SheetOutput { key: string; name: string; unit: string; formula: string; value: number; }
/** `legacy`: lifted from the old fixed four, so the client can localise the names it knows. */
export interface SheetPayload { inputs: SheetVariable[]; outputs: SheetOutput[]; summary: string; legacy?: true; }
export interface SiteCard { h: string; p: string; }
export interface SitePayload {
  title: string;
  brand: string;
  kicker: string;
  headline: string;
  headlineHi: string;
  sub: string;
  ctaPrimary: string;
  ctaSecondary: string;
  howEyebrow: string;
  howTitle: string;
  steps: SiteCard[];
  featEyebrow: string;
  featTitle: string;
  features: SiteCard[];
  quote: string;
  quoteBy: string;
  finalTitle: string;
  finalSub: string;
  finalCta: string;
  accent: string;
  footNote: string;
}
export interface Screen { name: string; time: string; kick: string; title: string; sub: string; art: string; cta: string; note: string; }
export interface ScreensPayload { screens: Screen[]; }
export type DeliverablePayload =
  | ChecklistPayload
  | DocPayload
  | LegalPayload
  | PostPayload
  | EmailPayload
  | PlanPayload
  | DmsPayload
  | CalendarPayload
  | SheetPayload
  | SitePayload
  | ScreensPayload;

const STRUCTURED_KINDS = new Set(["checklist", "doc", "legal", "post", "email", "plan", "dms", "calendar", "sheet", "site", "screens"]);
/** Illustrations the native screens viewer can render. Keep in sync with web's SCREEN_ARTS. */
const SCREEN_ARTS = new Set(["connect", "session", "recap"]);
const s = (v: unknown, n = 600) => (typeof v === "string" ? v.trim().slice(0, n) : "");
const strArr = (v: unknown, n = 12, len = 400): string[] =>
  Array.isArray(v) ? v.map((x) => s(x, len)).filter(Boolean).slice(0, n) : [];
/** A clause heading's own numbering — "1.", "§2", "Section 3:", "4)", "Clause 5 —". The legal
 *  viewer numbers clauses itself, so a heading that kept it would read "1. 1. Definitions". A
 *  number only counts when a separator follows it: "2FA requirements" is a heading, not clause 2. */
const CLAUSE_NUMBER = /^(?:(?:section|clause|article)\s+|§\s*)?\d+(?:\.\d+)*(?:[.):]|\s+[—–-])?\s+/i;
/** Character limits for the platforms a post names most often, as of 2026. */
const POST_PLATFORMS: ReadonlyArray<{ label: string; names: readonly string[]; limit: number }> = [
  { label: "X", names: ["x", "twitter", "x (twitter)", "x/twitter"], limit: 280 },
  { label: "LinkedIn", names: ["linkedin"], limit: 3000 },
  { label: "Threads", names: ["threads"], limit: 500 },
  { label: "Bluesky", names: ["bluesky", "bsky"], limit: 300 },
  { label: "Mastodon", names: ["mastodon"], limit: 500 },
  { label: "Instagram", names: ["instagram"], limit: 2200 },
];
const CALENDAR_MAX = 8;
const SHEET_KEY = /^[a-z][a-z0-9_]{0,23}$/;
const SHEET_MAX = 8;

/**
 * The old fixed model, as a model. Every sheet filed before CP-002 D has these four inputs, and
 * the six outputs are exactly what `SheetModel.compute` (Swift) did — same floors (price at 1,
 * churn at 1%), same rounding — so a lifted sheet shows the same numbers it always did. The one
 * addition is `costs`: break-even always divided by a hard-coded $2,500 no founder could see or
 * move, and it is now the fifth input (founder decision, 30 Sep). The Swift decode lifts with the
 * same table (`SheetPayload.lift`), for sheets already stored.
 */
const LEGACY_SHEET_INPUTS: ReadonlyArray<readonly [string, string, string]> = [
  ["price", "Pro price / mo", "$"], ["waitlist", "Waitlist size", "users"],
  ["conversion", "Waitlist → paid", "%"], ["churn", "Monthly churn", "%"],
];
const LEGACY_SHEET_COSTS = { key: "costs", name: "Monthly costs", unit: "$", val: 2500, min: 0, max: 20000, step: 100 };
const LEGACY_SHEET_OUTPUTS: ReadonlyArray<readonly [string, string, string, string]> = [
  ["mrr", "Seed MRR", "$", "paid * max(price, 1)"],
  ["paid", "Paid users", "users", "round(waitlist * conversion / 100)"],
  ["arr", "Run-rate ARR", "$", "mrr * 12"],
  ["ltv", "LTV / user", "$", "round(max(price, 1) / (max(churn, 1) / 100))"],
  ["life", "Churn-adj. life", "mo", "round(100 / max(churn, 1))"],
  ["breakeven", "Break-even users", "users", "ceil(costs / max(price, 1))"],
];

function coerceSheetVariable(v: unknown): SheetVariable | null {
  const o = (v ?? {}) as Record<string, unknown>;
  const key = s(o.key, 24).toLowerCase();
  const min = num(o.min), max = num(o.max), step = num(o.step), val = num(o.val);
  if (!SHEET_KEY.test(key) || min === null || max === null || step === null || val === null) return null;
  if (!(min < max) || !(step > 0)) return null;
  return { key, name: s(o.name, 40) || key, unit: s(o.unit, 12), val: Math.min(max, Math.max(min, val)), min, max, step };
}

/** Inputs + raw outputs → the sheet, with every output that cannot be computed dropped. */
function buildSheet(inputs: SheetVariable[], rawOutputs: unknown[], summary: string, legacy: boolean): SheetPayload | null {
  if (!inputs.length) return null;
  const inputKeys = inputs.map((i) => i.key);
  const seen = new Set(inputKeys);
  let outs = rawOutputs
    .map((v) => {
      const o = (v ?? {}) as Record<string, unknown>;
      const key = s(o.key, 24).toLowerCase();
      const formula = s(o.formula, 200);
      const node = parseFormula(formula);
      if (!SHEET_KEY.test(key) || seen.has(key) || !node) return null;
      seen.add(key);
      return { key, name: s(o.name, 40) || key, unit: s(o.unit, 12), formula, node };
    })
    .filter(<T,>(x: T | null): x is T => x !== null)
    .slice(0, SHEET_MAX);
  // Kahn's algorithm: place an output once everything it reads is an input or already placed.
  // Whatever never becomes placeable reads an unknown name, itself, or a cycle — or is built on
  // one of those — and is dropped. Outputs may refer to one another in any listed order.
  const inputSet = new Set(inputKeys);
  const placed: string[] = [];
  const placedSet = new Set<string>();
  for (let progress = true; progress;) {
    progress = false;
    for (const o of outs) {
      if (placedSet.has(o.key)) continue;
      if ([...formulaRefs(o.node)].every((r) => inputSet.has(r) || placedSet.has(r))) {
        placed.push(o.key); placedSet.add(o.key); progress = true;
      }
    }
  }
  outs = outs.filter((o) => placedSet.has(o.key));
  const order = placed;
  const env: Record<string, number> = Object.fromEntries(inputs.map((i) => [i.key, i.val]));
  for (const k of order) env[k] = evalFormula((outs.find((o) => o.key === k) as { node: FormulaNode }).node, env);
  const outputs = outs
    .filter((o) => Number.isFinite(env[o.key]))
    .map(({ key, name, unit, formula }) => ({ key, name, unit, formula, value: env[key] as number }));
  if (!outputs.length) return null;
  return { inputs, outputs, summary, ...(legacy && { legacy: true as const }) };
}

const EMAIL_ADDRESS = /[^\s@]+@[^\s@]+\.[^\s@]+/;
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/** Sanitize the raw payload for a kind; null if it lacks the kind's required content. */
export function coercePayload(kind: string, raw: unknown): DeliverablePayload | null {
  const r = (raw ?? {}) as Record<string, unknown>;
  if (kind === "checklist") {
    const items = (Array.isArray(r.items) ? r.items : [])
      .map((it) => {
        const o = (it ?? {}) as Record<string, unknown>;
        const owner = s(o.owner, 60); const due = s(o.due, 60);
        // Omitted rather than "", so a checklist without them coerces exactly as it always did.
        return { t: s(o.t, 300), done: o.done === true, ...(owner && { owner }), ...(due && { due }) };
      })
      .filter((it) => it.t).slice(0, 30);
    return items.length ? { items } : null;
  }
  if (kind === "doc") {
    const call = s(r.call, 600);
    const sections = (Array.isArray(r.sections) ? r.sections : [])
      .map((it) => {
        const o = (it ?? {}) as Record<string, unknown>;
        const source = s(o.source, 200);
        return { h: s(o.h, 120), p: s(o.p, 1200), ...(source && { source }) };
      })
      .filter((x) => x.h && x.p).slice(0, 6);
    const next = strArr(r.next, 3, 200);
    const rules_out = strArr(r.rules_out, 3, 200);
    return call && sections.length ? { call, sections, next, ...(rules_out.length && { rules_out }) } : null;
  }
  if (kind === "post") {
    const platform = s(r.platform, 40);
    if (!platform) return null;
    // A known platform's limit is ours, not the model's: a wrong limit would pass a post that
    // fails on publish, which is the one thing the field exists to catch.
    const known = POST_PLATFORMS.find((p) => p.names.includes(platform.toLowerCase()));
    if (known) return { platform: known.label, limit: known.limit };
    const limit = num(r.limit);
    return limit !== null && Number.isInteger(limit) && limit >= 20 && limit <= 100000 ? { platform, limit } : { platform };
  }
  if (kind === "email") {
    const subject = s(r.subject, 200);
    if (!subject) return null;
    const to = s(r.to, 120);
    // An address is not "who it is for", and a model that writes one has most likely made it up.
    return to && !EMAIL_ADDRESS.test(to) ? { subject, to } : { subject };
  }
  if (kind === "legal") {
    // No `call`: a clause document has no decision up front, and a doc's cap of six blocks
    // would cut a real policy off halfway through.
    const sections = (Array.isArray(r.sections) ? r.sections : [])
      .map((it) => { const o = (it ?? {}) as Record<string, unknown>; return { h: s(o.h, 120).replace(CLAUSE_NUMBER, ""), p: s(o.p, 2400) }; })
      .filter((x) => x.h && x.p).slice(0, 30);
    return sections.length ? { sections } : null;
  }
  if (kind === "plan") {
    const goal = s(r.goal, 300);
    const steps = strArr(r.steps, 6, 300);
    const changes = (Array.isArray(r.changes) ? r.changes : [])
      .map((it) => { const o = (it ?? {}) as Record<string, unknown>; return { area: s(o.area, 120), edit: s(o.edit, 400) }; })
      .filter((x) => x.area && x.edit).slice(0, 8);
    const verify = strArr(r.verify, 6, 300);
    const risks = s(r.risks, 300);
    return goal && steps.length && changes.length ? { goal, steps, changes, verify, risks } : null;
  }
  if (kind === "dms") {
    const messages = (Array.isArray(r.messages) ? r.messages : [])
      // A legacy payload (and a model still answering the old prompt) says `name`; it is lifted
      // into `audience` so nothing downstream ever sees the old key.
      .map((it) => { const o = (it ?? {}) as Record<string, unknown>; return { audience: s(o.audience, 80) || s(o.name, 80), note: s(o.note, 200), msg: s(o.msg, 1200) }; })
      .filter((x) => x.audience && x.msg).slice(0, 4);
    return messages.length ? { messages } : null;
  }
  if (kind === "calendar") {
    // A legacy `weeks[]` (the fixed two-week calendar) is one phase per week with no span, its
    // `day` read as `when` and its `kind` as `format` — so nothing a founder saw is lost.
    const legacy = !Array.isArray(r.phases) && Array.isArray(r.weeks);
    const raw = (legacy ? r.weeks : r.phases) as unknown[] | undefined;
    const phases = (Array.isArray(raw) ? raw : [])
      .map((ph) => {
        const o = (ph ?? {}) as Record<string, unknown>;
        const items = (Array.isArray(o.items) ? o.items : [])
          .map((it) => {
            const io = (it ?? {}) as Record<string, unknown>;
            const channel = s(io.channel, 40), owner = s(io.owner, 40);
            return {
              when: s(legacy ? io.day : io.when, 20),
              format: s(legacy ? io.kind : io.format, 40),
              ...(channel && { channel }), ...(owner && { owner }),
              body: s(io.body, 300),
            };
          })
          .filter((x) => x.body)
          .slice(0, CALENDAR_MAX);
        return { label: s(o.label, 40), from: legacy ? "" : s(o.from, 20), to: legacy ? "" : s(o.to, 20), items };
      })
      .filter((p) => p.label && p.items.length)
      .slice(0, CALENDAR_MAX);
    return phases.length ? { phases } : null;
  }
  if (kind === "sheet") {
    const summary = s(r.summary, 800);
    if (Array.isArray(r.inputs)) {
      const seen = new Set<string>();
      const inputs = r.inputs.map(coerceSheetVariable)
        .filter((i): i is SheetVariable => i !== null && !seen.has(i.key) && !!seen.add(i.key))
        .slice(0, SHEET_MAX);
      return buildSheet(inputs, Array.isArray(r.outputs) ? r.outputs : [], summary, false);
    }
    // The old fixed four — a sheet filed before CP-002 D, or a model still answering the old
    // prompt. All four must be there, as they always had to be.
    const legacy = LEGACY_SHEET_INPUTS.map(([key, name, unit]) => {
      const o = (r[key] ?? {}) as Record<string, unknown>;
      return coerceSheetVariable({ key, name, unit, val: o.val, min: o.min, max: o.max, step: o.step });
    });
    if (legacy.some((i) => i === null)) return null;
    return buildSheet(
      [...(legacy as SheetVariable[]), { ...LEGACY_SHEET_COSTS }],
      LEGACY_SHEET_OUTPUTS.map(([key, name, unit, formula]) => ({ key, name, unit, formula })),
      summary, true
    );
  }
  if (kind === "site") {
    const card = (v: unknown): SiteCard | null => {
      const o = (v ?? {}) as Record<string, unknown>;
      const h = s(o.h, 80); const p = s(o.p, 300);
      return h && p ? { h, p } : null;
    };
    const steps = (Array.isArray(r.steps) ? r.steps : [])
      .map(card).filter((x): x is SiteCard => x !== null).slice(0, 3);
    const features = (Array.isArray(r.features) ? r.features : [])
      .map(card).filter((x): x is SiteCard => x !== null).slice(0, 3);
    const title = s(r.title, 120);
    const brand = s(r.brand, 80);
    const kicker = s(r.kicker, 80);
    const headline = s(r.headline, 200);
    const headlineHi = s(r.headlineHi, 100);
    const sub = s(r.sub, 300);
    const ctaPrimary = s(r.ctaPrimary, 40);
    const ctaSecondary = s(r.ctaSecondary, 40);
    const howEyebrow = s(r.howEyebrow, 60);
    const howTitle = s(r.howTitle, 120);
    const featEyebrow = s(r.featEyebrow, 60);
    const featTitle = s(r.featTitle, 120);
    const quote = s(r.quote, 300);
    const quoteBy = s(r.quoteBy, 80);
    const finalTitle = s(r.finalTitle, 120);
    const finalSub = s(r.finalSub, 200);
    const finalCta = s(r.finalCta, 40);
    const accent = s(r.accent, 20);
    const footNote = s(r.footNote, 120);
    const ok = !!(
      title && brand && headline && sub && ctaPrimary && howEyebrow && howTitle && steps.length &&
      featEyebrow && featTitle && features.length && finalTitle && finalCta && accent
    );
    return ok
      ? {
          title, brand, kicker, headline, headlineHi, sub, ctaPrimary, ctaSecondary,
          howEyebrow, howTitle, steps, featEyebrow, featTitle, features,
          quote, quoteBy, finalTitle, finalSub, finalCta, accent, footNote,
        }
      : null;
  }
  if (kind === "screens") {
    const screens = (Array.isArray(r.screens) ? r.screens : [])
      .map((it) => {
        const o = (it ?? {}) as Record<string, unknown>;
        const art = typeof o.art === "string" && SCREEN_ARTS.has(o.art) ? o.art : "connect";
        return {
          name: s(o.name, 40),
          time: s(o.time, 12),
          kick: s(o.kick, 40),
          title: s(o.title, 200),
          sub: s(o.sub, 300),
          art,
          cta: s(o.cta, 60),
          note: s(o.note, 200),
        };
      })
      .filter((x) => x.name && x.title)
      .slice(0, 3);
    return screens.length ? { screens } : null;
  }
  return null;
}

/**
 * Validate + coerce the model's raw tool input into a safe deliverable, or null if unusable.
 *
 * `deptKey` is the owning department of the task, and it closes the contract the prompt only
 * asked for: neither transport can force a particular `kind` (the API forces the tool but not
 * its fields, and `claude -p` cannot be forced to a tool call at all), so an out-of-contract
 * kind can still arrive. Absent → no contract to judge against, and the kind is left alone.
 */
export function coerceDeliverable(
  raw: unknown,
  taskTitle: string,
  deptKey?: string | null,
  /** A revise pass's kind (`revisePin`): the answer keeps it whatever kind the model named. */
  pinKind?: string
): Deliverable | null {
  const r = (raw ?? {}) as Record<string, unknown>;
  const body = typeof r.body === "string" ? r.body.trim() : "";
  if (!body) return null;

  const rawKind = pinKind ?? (typeof r.kind === "string" ? r.kind.trim() : "");
  // The contract judges the kind first, then the kind vocabulary catches what is left. An
  // out-of-contract kind becomes `doc` — see `coerceKindForDepartment`, which explains why the
  // department's speciality is the wrong answer once the payload has been dropped. `doc` is also
  // the floor for a dept-less task, which has no contract to judge against.
  const contractKind = coerceKindForDepartment(deptKey, rawKind);
  const kind = DELIVERABLE_KINDS.has(contractKind) ? contractKind : "doc";

  const rawTitle = typeof r.title === "string" ? r.title.trim() : "";
  const title = rawTitle || clip(taskTitle, 200) || "Untitled deliverable";

  if (STRUCTURED_KINDS.has(kind)) {
    const payload = coercePayload(kind, (raw as Record<string, unknown>)?.payload);
    if (payload) return { kind, title, body, payload };
  }
  return { kind, title, body };
}

// The forced tool's schema and the system prompt, moved here from the handler when the
// local path started needing them: `local/oneShotSidecar` is esbuild-bundled into the app,
// so anything it imports from a handler drags the Anthropic SDK in with it. One schema for
// both transports — the API forces this tool, the local path renders the same
// `input_schema` into its prompt, which is the only way a payload this large stays in step.
export const DELIVERABLE_SYSTEM =
  "You produce real, finished work product for a solo founder's company — never a plan to do the work, the work itself.";

/**
 * Which payload fields belong to which kinds.
 *
 * The schema's own field descriptions already carry this ("checklist: 5-7 ordered steps."), but
 * parsing prose to decide what to put in front of a model would be a second source of truth that
 * drifts the first time a description is reworded. Declared here instead, with a test asserting
 * it covers every field the schema declares, so adding a field without classifying it goes red.
 */
export const PAYLOAD_FIELD_KINDS: Record<string, readonly string[]> = {
  items: ["checklist"],
  call: ["doc"],
  rules_out: ["doc"],
  platform: ["post"],
  limit: ["post"],
  subject: ["email"],
  to: ["email"],
  sections: ["doc", "legal"],
  next: ["doc"],
  goal: ["plan"],
  changes: ["plan"],
  verify: ["plan"],
  risks: ["plan"],
  steps: ["plan", "site"],
  messages: ["dms"],
  phases: ["calendar"],
  inputs: ["sheet"],
  outputs: ["sheet"],
  summary: ["sheet"],
  title: ["site"],
  brand: ["site"],
  kicker: ["site"],
  headline: ["site"],
  headlineHi: ["site"],
  sub: ["site"],
  ctaPrimary: ["site"],
  ctaSecondary: ["site"],
  howEyebrow: ["site"],
  howTitle: ["site"],
  featEyebrow: ["site"],
  featTitle: ["site"],
  features: ["site"],
  quote: ["site"],
  quoteBy: ["site"],
  finalTitle: ["site"],
  finalSub: ["site"],
  finalCta: ["site"],
  accent: ["site"],
  footNote: ["site"],
  screens: ["screens"],
};

export const DELIVERABLE_TOOL = {
  name: "record_deliverable",
  description: "Record the finished deliverable produced for this task.",
  input_schema: {
    type: "object",
    properties: {
      kind: { type: "string", description: "The deliverable kind that best fits what was produced." },
      title: { type: "string", description: "A short, clear title for the deliverable." },
      body: { type: "string", description: "The full deliverable content, written as markdown." },
      payload: {
        type: "object",
        additionalProperties: true,
        description: "Structured fields for the chosen kind. Fill ONLY the fields for that kind (see the per-kind guide in the prompt); omit for kinds without a structured form.",
        properties: {
          items: { type: "array", description: "checklist: every step in order, each with an optional owner and due.",
            items: { type: "object", additionalProperties: false, properties: { t: { type: "string" }, done: { type: "boolean" }, owner: { type: "string" }, due: { type: "string" } }, required: ["t", "done"] } },
          call: { type: "string", description: "doc: the decision up front (1-2 sentences)." },
          sections: { type: "array", description: "doc/legal: labeled {h,p} blocks (a legal heading carries no number).",
            items: { type: "object", additionalProperties: false, properties: { h: { type: "string" }, p: { type: "string" }, source: { type: "string" } }, required: ["h", "p"] } },
          rules_out: { type: "array", description: "doc: 0-3 options this decision forecloses.", items: { type: "string" } },
          platform: { type: "string", description: "post: where it will be published." },
          limit: { type: "number", description: "post: that platform's length limit in characters." },
          subject: { type: "string", description: "email: the subject line." },
          to: { type: "string", description: "email: who it is for, described, never an invented name or an address." },
          next: { type: "array", description: "doc: 1-3 next actions.", items: { type: "string" } },
          goal: { type: "string", description: "plan: one-line goal." },
          changes: { type: "array", description: "plan: areas touched.",
            items: { type: "object", additionalProperties: false, properties: { area: { type: "string" }, edit: { type: "string" } }, required: ["area", "edit"] } },
          verify: { type: "array", description: "plan: future-tense verification checks.", items: { type: "string" } },
          risks: { type: "string", description: "plan: one-line main risk." },
          messages: { type: "array", description: "dms: 2-4 message templates, each addressed to an audience (a type of person), never an invented name.",
            items: { type: "object", additionalProperties: false, properties: { audience: { type: "string" }, note: { type: "string" }, msg: { type: "string" } }, required: ["audience", "note", "msg"] } },
          phases: { type: "array", description: "calendar: 1-8 phases of a plan, each with a relative span and its items.",
            items: { type: "object", additionalProperties: false, properties: {
              label: { type: "string" }, from: { type: "string" }, to: { type: "string" },
              items: { type: "array", items: { type: "object", additionalProperties: false, properties: {
                when: { type: "string" }, format: { type: "string" }, channel: { type: "string" }, owner: { type: "string" }, body: { type: "string" },
              }, required: ["when", "format", "body"] } },
            }, required: ["label", "from", "to", "items"] } },
          inputs: { type: "array", description: "sheet: 2-8 assumptions the founder can move.",
            items: { type: "object", additionalProperties: false, properties: {
              key: { type: "string" }, name: { type: "string" }, unit: { type: "string" },
              val: { type: "number" }, min: { type: "number" }, max: { type: "number" }, step: { type: "number" },
            }, required: ["key", "name", "unit", "val", "min", "max", "step"] } },
          outputs: { type: "array", description: "sheet: 1-8 results, most important first, each a formula over the inputs and other outputs.",
            items: { type: "object", additionalProperties: false, properties: {
              key: { type: "string" }, name: { type: "string" }, unit: { type: "string" }, formula: { type: "string" },
            }, required: ["key", "name", "unit", "formula"] } },
          summary: { type: "string", description: "sheet: one paragraph on what the model shows at the defaults." },
          title: { type: "string", description: "site: browser tab / SEO title." },
          brand: { type: "string", description: "site: company or product name." },
          kicker: { type: "string", description: "site: tiny label above the headline; empty string if none." },
          headline: { type: "string", description: "site: the hero H1." },
          headlineHi: { type: "string", description: "site: accent-colored tail of the headline; empty string if none." },
          sub: { type: "string", description: "site: one supporting sentence under the headline." },
          ctaPrimary: { type: "string", description: "site: primary button label." },
          ctaSecondary: { type: "string", description: "site: secondary button label; empty string if only one CTA." },
          howEyebrow: { type: "string", description: "site: eyebrow over the how-it-works section." },
          howTitle: { type: "string", description: "site: how-it-works section heading." },
          steps: { type: "array", description: "plan: 3-5 ordered approach steps (strings). site: exactly 3 how-it-works steps, each {h,p}.", items: {} },
          featEyebrow: { type: "string", description: "site: eyebrow over the features section." },
          featTitle: { type: "string", description: "site: features section heading." },
          features: { type: "array", description: "site: exactly 3 feature cards, each {h,p}.",
            items: { type: "object", additionalProperties: false, properties: { h: { type: "string" }, p: { type: "string" } }, required: ["h", "p"] } },
          quote: { type: "string", description: "site: one pull-quote/testimonial line; empty string if none." },
          quoteBy: { type: "string", description: "site: attribution for the quote; empty string if none." },
          finalTitle: { type: "string", description: "site: closing call-to-action heading." },
          finalSub: { type: "string", description: "site: line under the closing CTA; empty string if none." },
          finalCta: { type: "string", description: "site: closing CTA button label." },
          accent: { type: "string", description: "site: brand accent colour as a 6-digit hex." },
          footNote: { type: "string", description: "site: footer line." },
          screens: { type: "array", description: "screens: exactly 3 onboarding steps, each {name,time,kick,title,sub,art,cta,note}; art is connect/session/recap in order.",
            items: { type: "object", additionalProperties: false, properties: {
              name: { type: "string" }, time: { type: "string" }, kick: { type: "string" }, title: { type: "string" }, sub: { type: "string" },
              art: { type: "string", enum: ["connect", "session", "recap"] }, cta: { type: "string" }, note: { type: "string" },
            }, required: ["name", "time", "kick", "title", "sub", "art", "cta", "note"] } },
        },
      },
    },
    required: ["kind", "title", "body"],
  },
} as const;

/** The tool as a transport hands it over: same shape, optionally narrowed to one department. */
export interface DeliverableToolShape {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
}

/**
 * The forced tool, narrowed to one department's contract.
 *
 * The prompt tells the model which kinds it may use; this stops the schema from contradicting it
 * two paragraphs later. On the local transport that is not a nicety: `renderPrompt` emits
 * `prompt + schemaInstruction(schema)`, so an unnarrowed schema spells out the `screens` and
 * `site` fields immediately AFTER the prompt has said "Do not use any other kind" — measured for
 * Finance at 2,810 prompt characters, 14,765 with the unnarrowed schema appended, 7,291 with the
 * narrowed one. On the API path the enum
 * goes further than steering: an out-of-contract kind becomes impossible rather than coerced.
 *
 * Returns the shared `DELIVERABLE_TOOL` itself — the same object, not a copy — for a dept-less or
 * unknown department, so a legacy task is handed the exact schema it has always been handed.
 */
export function deliverableTool(deptKey?: string | null): DeliverableToolShape {
  const o = deptKey ? DEPARTMENT_OUTPUTS[deptKey] : undefined;
  if (!o) return DELIVERABLE_TOOL as unknown as DeliverableToolShape;

  const kinds = [...o.primary, ...o.allowed];
  const schema = DELIVERABLE_TOOL.input_schema as unknown as {
    properties: Record<string, Record<string, unknown>>;
  } & Record<string, unknown>;
  const payload = schema.properties.payload as {
    properties: Record<string, unknown>;
  } & Record<string, unknown>;

  const fields = Object.fromEntries(
    Object.entries(payload.properties).filter(([f]) =>
      (PAYLOAD_FIELD_KINDS[f] ?? []).some((k) => kinds.includes(k))
    )
  );

  return {
    name: DELIVERABLE_TOOL.name,
    description: DELIVERABLE_TOOL.description,
    input_schema: {
      ...schema,
      properties: {
        ...schema.properties,
        // No `enum: []` for a department that declares nothing: an empty enum matches no value,
        // so the forced tool call could never be satisfied. Such a department has no contract to
        // apply, which is the same thing `coerceKindForDepartment` concludes.
        kind: { ...schema.properties.kind, ...(kinds.length ? { enum: kinds } : {}) },
        payload: { ...payload, properties: fields },
      },
    },
  };
}
