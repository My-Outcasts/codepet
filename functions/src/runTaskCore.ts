// Pure logic for the runTask CF — no firebase/express/anthropic imports, so it can be
// unit-tested (and verified) without loading the heavy Cloud-Functions module tree.
// The IO handler lives in runTask.ts and imports from here.

import { companionFor } from "./companyChatCore";
import { departmentBrief, DEPARTMENT_NAMES } from "./departments";

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
  /** Owning department key of the task, so the deliverable comes from that function's
   *  expertise rather than generic company context. Unknown/absent → no department block. */
  deptKey?: string | null;
}

/** Build the companion-voiced generation prompt for a single roadmap task. */
export function buildRunTaskPrompt(args: RunTaskArgs): string {
  const c = companionFor(args.companionId);
  const context = clip(args.context, 4000);
  const taskTitle = clip(args.taskTitle, 200);
  const taskDetail = clip(args.taskDetail, 1000);
  const kindsList = Array.from(DELIVERABLE_KINDS).join(", ");
  const vi = args.language === "vi" ? "\n\nWrite the title and body in natural, fluent Vietnamese." : "";
  const reviseNote = clip(args.reviseNote, 500);
  const current = clip(args.current, 6000);
  // Only a real revise pass when we have BOTH the note and the draft it applies to — mirrors
  // web's guard (lib/ai/runTaskPrompt.ts). Without both, behavior is identical to today.
  const revise =
    reviseNote && current
      ? `\n\nYou are REVISING an existing deliverable. Current version:\n${current}\n\nApply this change: ${reviseNote}. Keep the same kind and intent; return the full revised deliverable (not a diff).`
      : "";

  // The department this task belongs to, as expertise. A run has always been performed BY a
  // department — its pet is credited on the execute log and on the draft card — but the
  // prompt was never told which one, so a marketing deliverable was written with no
  // marketing knowledge behind it. Empty for a dept-less (legacy) task.
  const deptBrief = departmentBrief(args.deptKey);
  const deptName = args.deptKey ? DEPARTMENT_NAMES[args.deptKey] : undefined;
  const deptBlock = deptBrief && deptName
    ? `You are doing this work as the ${deptName} function of the founder's company:\n${deptBrief}\n` +
      `Produce what that function would actually produce, at the level of specificity it would use.\n\n`
    : "";

  return (
    `You are ${c.name}, the AI building companion inside Codepet — a senior operator who does real work for a solo founder, department by department.\n\n` +
    `Voice: ${c.voice}\n\n` +
    deptBlock +
    `The founder's company:\n${context || "The founder hasn't filled in much of a brief yet — keep the deliverable general but still genuinely useful."}\n\n` +
    `Task to complete: ${taskTitle || "(untitled task)"}\n` +
    (taskDetail ? `Task detail: ${taskDetail}\n` : "") +
    `\nProduce the REAL deliverable for this task — not a plan to do it, not a description of what you would do, the actual finished artifact (the document, the copy, the checklist, the email, whatever the task calls for), written as markdown in the body. Pick whichever "kind" best fits what you produced from this exact list: ${kindsList}. Give it a short, clear title. Ground everything in the founder's actual company context above — do not invent facts about them.` +
    "\n\nALWAYS write the markdown `body`. If (and only if) the kind you chose is checklist, doc, plan, dms, calendar, sheet, site, or screens, ALSO fill `payload` with that kind's structured fields (leave `payload` empty for any other kind):\n" +
    "- checklist: Build a concrete setup/launch checklist — exactly 5-7 actionable steps in order (`items[].t`), each with `done` true only for obvious already-satisfied prerequisites.\n" +
    "- doc: `call` = the decision/recommendation in 1-2 sentences up front; `sections[]` = 2-5 labeled {h,p} reasoning blocks (why it's right, tradeoffs, what's out); `next[]` = 1-3 next actions.\n" +
    "- plan: an HONEST code-change plan — `goal` (one line), `steps[]` (3-5 ordered), `changes[]` = {area, edit} in plain terms (no fabricated file paths), `verify[]` (future-tense checks), `risks` (one line). Never claim it shipped.\n" +
    "- dms: exactly 4 personalized 1:1 outreach `messages[]` = {name (persona placeholder), note (why a strong target), msg (warm specific DM)}.\n" +
    "- calendar: a 2-week build-in-public content calendar — `weeks[]` = exactly 2 {label, items[]}, each week's `items[]` = 2-3 {day, kind, body} posts specific to this company.\n" +
    "- sheet: a pricing model — the 4 fixed inputs `price`, `waitlist`, `conversion`, `churn`, each {val, min, max, step} with a realistic default and sensible range, plus `summary` (one paragraph on what the model shows at those defaults). Never add a 5th input.\n" +
    "- site: copy for a one-page landing site — `title`, `brand`, `headline`, `sub`, `ctaPrimary`, `howEyebrow`, `howTitle`, exactly 3 `steps[]` = {h,p}, `featEyebrow`, `featTitle`, exactly 3 `features[]` = {h,p}, `finalTitle`, `finalCta`, `accent` (6-digit hex). Use empty strings for unused optional fields (kicker, headlineHi, ctaSecondary, quote, quoteBy, finalSub). Never write HTML.\n" +
    "- screens: exactly 3 onboarding `screens[]` = {name, time, kick, title, sub, art, cta, note}, with `art` set to \"connect\", \"session\", \"recap\" in that order." +
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

export interface ChecklistItem { t: string; done: boolean; }
export interface ChecklistPayload { items: ChecklistItem[]; }
export interface DocSection { h: string; p: string; }
export interface DocPayload { call: string; sections: DocSection[]; next: string[]; }
export interface PlanChange { area: string; edit: string; }
export interface PlanPayload { goal: string; steps: string[]; changes: PlanChange[]; verify: string[]; risks: string; }
export interface DmMessage { name: string; note: string; msg: string; }
export interface DmsPayload { messages: DmMessage[]; }
export interface CalendarItem { day: string; kind: string; body: string; }
export interface CalendarWeek { label: string; items: CalendarItem[]; }
export interface CalendarPayload { weeks: CalendarWeek[]; }
export interface SheetInputField { val: number; min: number; max: number; step: number; }
export interface SheetPayload {
  price: SheetInputField;
  waitlist: SheetInputField;
  conversion: SheetInputField;
  churn: SheetInputField;
  summary: string;
}
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
  | PlanPayload
  | DmsPayload
  | CalendarPayload
  | SheetPayload
  | SitePayload
  | ScreensPayload;

const STRUCTURED_KINDS = new Set(["checklist", "doc", "plan", "dms", "calendar", "sheet", "site", "screens"]);
/** Illustrations the native screens viewer can render. Keep in sync with web's SCREEN_ARTS. */
const SCREEN_ARTS = new Set(["connect", "session", "recap"]);
const s = (v: unknown, n = 600) => (typeof v === "string" ? v.trim().slice(0, n) : "");
const strArr = (v: unknown, n = 12, len = 400): string[] =>
  Array.isArray(v) ? v.map((x) => s(x, len)).filter(Boolean).slice(0, n) : [];
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/** Sanitize the raw payload for a kind; null if it lacks the kind's required content. */
export function coercePayload(kind: string, raw: unknown): DeliverablePayload | null {
  const r = (raw ?? {}) as Record<string, unknown>;
  if (kind === "checklist") {
    const items = (Array.isArray(r.items) ? r.items : [])
      .map((it) => { const o = (it ?? {}) as Record<string, unknown>; return { t: s(o.t, 300), done: o.done === true }; })
      .filter((it) => it.t).slice(0, 7);
    return items.length ? { items } : null;
  }
  if (kind === "doc") {
    const call = s(r.call, 600);
    const sections = (Array.isArray(r.sections) ? r.sections : [])
      .map((it) => { const o = (it ?? {}) as Record<string, unknown>; return { h: s(o.h, 120), p: s(o.p, 1200) }; })
      .filter((x) => x.h && x.p).slice(0, 6);
    const next = strArr(r.next, 3, 200);
    return call && sections.length ? { call, sections, next } : null;
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
      .map((it) => { const o = (it ?? {}) as Record<string, unknown>; return { name: s(o.name, 80), note: s(o.note, 200), msg: s(o.msg, 1200) }; })
      .filter((x) => x.name && x.msg).slice(0, 4);
    return messages.length ? { messages } : null;
  }
  if (kind === "calendar") {
    const weeks = (Array.isArray(r.weeks) ? r.weeks : [])
      .map((w) => {
        const o = (w ?? {}) as Record<string, unknown>;
        const label = s(o.label, 40);
        const items = (Array.isArray(o.items) ? o.items : [])
          .map((it) => { const io = (it ?? {}) as Record<string, unknown>; return { day: s(io.day, 20), kind: s(io.kind, 40), body: s(io.body, 300) }; })
          .filter((x) => x.day && x.body)
          .slice(0, 4);
        return { label, items };
      })
      .filter((w) => w.label && w.items.length)
      .slice(0, 2);
    return weeks.length ? { weeks } : null;
  }
  if (kind === "sheet") {
    const input = (v: unknown): SheetInputField | null => {
      const o = (v ?? {}) as Record<string, unknown>;
      const val = num(o.val); const min = num(o.min); const max = num(o.max); const step = num(o.step);
      return val !== null && min !== null && max !== null && step !== null ? { val, min, max, step } : null;
    };
    const price = input(r.price);
    const waitlist = input(r.waitlist);
    const conversion = input(r.conversion);
    const churn = input(r.churn);
    const summary = s(r.summary, 800);
    return price && waitlist && conversion && churn && summary
      ? { price, waitlist, conversion, churn, summary }
      : null;
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

/** Validate + coerce the model's raw tool input into a safe deliverable, or null if unusable. */
export function coerceDeliverable(raw: unknown, taskTitle: string): Deliverable | null {
  const r = (raw ?? {}) as Record<string, unknown>;
  const body = typeof r.body === "string" ? r.body.trim() : "";
  if (!body) return null;

  const rawKind = typeof r.kind === "string" ? r.kind.trim() : "";
  const kind = DELIVERABLE_KINDS.has(rawKind) ? rawKind : "doc";

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
          items: { type: "array", description: "checklist: 5-7 ordered steps.",
            items: { type: "object", additionalProperties: false, properties: { t: { type: "string" }, done: { type: "boolean" } }, required: ["t", "done"] } },
          call: { type: "string", description: "doc: the decision up front (1-2 sentences)." },
          sections: { type: "array", description: "doc/legal: labeled {h,p} blocks.",
            items: { type: "object", additionalProperties: false, properties: { h: { type: "string" }, p: { type: "string" } }, required: ["h", "p"] } },
          next: { type: "array", description: "doc: 1-3 next actions.", items: { type: "string" } },
          goal: { type: "string", description: "plan: one-line goal." },
          changes: { type: "array", description: "plan: areas touched.",
            items: { type: "object", additionalProperties: false, properties: { area: { type: "string" }, edit: { type: "string" } }, required: ["area", "edit"] } },
          verify: { type: "array", description: "plan: future-tense verification checks.", items: { type: "string" } },
          risks: { type: "string", description: "plan: one-line main risk." },
          messages: { type: "array", description: "dms: exactly 4 persona DMs.",
            items: { type: "object", additionalProperties: false, properties: { name: { type: "string" }, note: { type: "string" }, msg: { type: "string" } }, required: ["name", "note", "msg"] } },
          weeks: { type: "array", description: "calendar: exactly 2 weeks, each with a label and 2-3 posts.",
            items: { type: "object", additionalProperties: false, properties: {
              label: { type: "string" },
              items: { type: "array", items: { type: "object", additionalProperties: false, properties: { day: { type: "string" }, kind: { type: "string" }, body: { type: "string" } }, required: ["day", "kind", "body"] } },
            }, required: ["label", "items"] } },
          price: { type: "object", description: "sheet: monthly Pro price input {val,min,max,step}.",
            additionalProperties: false, properties: { val: { type: "number" }, min: { type: "number" }, max: { type: "number" }, step: { type: "number" } }, required: ["val", "min", "max", "step"] },
          waitlist: { type: "object", description: "sheet: waitlist size input {val,min,max,step}.",
            additionalProperties: false, properties: { val: { type: "number" }, min: { type: "number" }, max: { type: "number" }, step: { type: "number" } }, required: ["val", "min", "max", "step"] },
          conversion: { type: "object", description: "sheet: conversion % input {val,min,max,step}.",
            additionalProperties: false, properties: { val: { type: "number" }, min: { type: "number" }, max: { type: "number" }, step: { type: "number" } }, required: ["val", "min", "max", "step"] },
          churn: { type: "object", description: "sheet: monthly churn % input {val,min,max,step}.",
            additionalProperties: false, properties: { val: { type: "number" }, min: { type: "number" }, max: { type: "number" }, step: { type: "number" } }, required: ["val", "min", "max", "step"] },
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
