// Pure logic for the extractDecisions CF — no firebase/express/anthropic imports, so it
// unit-tests without the Cloud-Functions module tree. Ported from the web app's
// lib/ai/decisions.ts (schema + prompt) and app/api/remember/route.ts (system prompt).
// Stateless: the native client sends existing decisions and does the merge/persist.

export interface ExtractedDecision {
  topic: string;
  statement: string;
  source?: string;
}

/** What the client sends as "already on record" (no timestamp needed for the prompt). */
export interface DecisionOnRecord {
  topic: string;
  statement: string;
}

/** The approved deliverable's high-signal fields, passed to extraction. */
export interface ApprovedDeliverable {
  title: string;
  dept: string;
  type: string;
  out: string;
}

export const EXTRACT_SYSTEM = `You extract durable company decisions from a deliverable a founder just approved. A decision is an explicit, lasting choice — about pricing, positioning, naming, target audience, tech, brand voice, or scope — that should constrain the company's future work.

Only extract decisions that are EXPLICIT and durable. Ignore transient details, task lists, examples, and anything speculative or clearly a draft. Reuse an existing topic when the deliverable CHANGES a decision already on record; never re-emit an unchanged one. If the deliverable locks in no clear new decision, return an empty list. Prefer few, high-confidence decisions over many shaky ones.`;

export const DECISIONS_EXTRACT_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  properties: {
    decisions: {
      type: "array",
      description:
        "New or changed durable decisions this deliverable locks in. Empty array if none.",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          topic: {
            type: "string",
            description:
              "A short lowercase key for the decision area, e.g. pricing, positioning, naming, audience, tech, brand-voice, scope. Reuse an existing topic when the deliverable changes it.",
          },
          statement: {
            type: "string",
            description: 'One concrete sentence stating the decision (e.g. "Plus tier is $4/mo").',
          },
          source: {
            type: "string",
            description: "Where it came from — usually the deliverable title and department.",
          },
        },
        required: ["topic", "statement"],
      },
    },
  },
  required: ["decisions"],
};

const OUT_CAP = 2000;

export function buildExtractPrompt(deliverable: ApprovedDeliverable, existing: DecisionOnRecord[]): string {
  const onRecord = existing.length
    ? existing.map((d) => `- ${d.topic}: ${d.statement}`).join("\n")
    : "(none yet)";
  const out = deliverable.out.trim().replace(/\s+/g, " ").slice(0, OUT_CAP);
  return [
    "Decisions already on record (reuse a topic only if this deliverable CHANGES it; do not repeat unchanged ones):",
    onRecord,
    "",
    "The founder just approved this deliverable:",
    `Title: ${deliverable.title}`,
    `Department: ${deliverable.dept}`,
    `Type: ${deliverable.type}`,
    "---",
    out,
    "---",
    "Extract only NEW or CHANGED durable decisions it locks in. If there are none, return an empty list.",
  ].join("\n");
}

const clip = (v: unknown, n: number) => (typeof v === "string" ? v.trim().slice(0, n) : "");

/** Sanitize the model's tool output to a clean ExtractedDecision[]. Never throws. No cap
 *  or merge — the native client's mergeDecisions handles supersede + the 30 cap. */
export function coerceDecisions(raw: unknown): { decisions: ExtractedDecision[] } {
  const inArr =
    raw && Array.isArray((raw as { decisions?: unknown }).decisions)
      ? ((raw as { decisions: unknown[] }).decisions as unknown[])
      : [];
  const decisions: ExtractedDecision[] = [];
  for (const d of inArr) {
    if (!d || typeof d !== "object") continue;
    const rec = d as { topic?: unknown; statement?: unknown; source?: unknown };
    const topic = clip(rec.topic, 60);
    const statement = clip(rec.statement, 300);
    if (!topic || !statement) continue;
    const source = clip(rec.source, 200);
    decisions.push(source ? { topic, statement, source } : { topic, statement });
  }
  return { decisions };
}

// The request narrowing, moved here from the handler when the local path started needing it.
// Shared rather than copied because these two functions decide what counts as extractable at
// all: a second copy that read `out` slightly differently would make one transport extract
// decisions from a deliverable the other one skipped.
export interface ExtractRequestBody {
  deliverable?: { title?: unknown; dept?: unknown; type?: unknown; out?: unknown };
  existing_decisions?: unknown;
}

const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");

export function parseDeliverable(body: ExtractRequestBody): ApprovedDeliverable | null {
  const d = body.deliverable;
  if (!d || typeof d !== "object") return null;
  const title = str(d.title);
  const out = str(d.out);
  if (!title || !out) return null; // need a title + content to extract anything
  return { title, dept: str(d.dept), type: str(d.type), out };
}

export function parseExisting(body: ExtractRequestBody): DecisionOnRecord[] {
  const arr = Array.isArray(body.existing_decisions) ? body.existing_decisions : [];
  const out: DecisionOnRecord[] = [];
  for (const e of arr) {
    if (!e || typeof e !== "object") continue;
    const rec = e as { topic?: unknown; statement?: unknown };
    const topic = str(rec.topic);
    const statement = str(rec.statement);
    if (topic && statement) out.push({ topic, statement });
  }
  return out;
}
