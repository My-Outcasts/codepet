/**
 * The prompt, the schema, and the merge rules for `enrichBrief` — everything that decides
 * WHAT is asked and what is safe to keep, with nothing that decides who answers.
 *
 * **Why this is its own file.** The local path (`local/oneShotSidecar`) is bundled into the
 * app with esbuild, which inlines the whole import graph. Importing these builders from the
 * handler dragged the Anthropic SDK, express and firebase-admin along with them: measured,
 * 7.5 MB of app resource for a prompt and a merge. Splitting the pure half out is what keeps
 * the bundle small AND keeps ONE copy of the prompt — the same reason `companyChatCore`
 * exists.
 */

export interface CompanyBrief {
  founderName?: string; role?: string; tech?: string; stage?: string;
  projectName?: string; oneLiner?: string; summary?: string; notes?: string;
  link?: string; categories?: string[]; audience?: string;
}
export interface BriefEnrichment { summary: string; audience: string; categories: string[]; }

const clip = (v: unknown, n: number) => (typeof v === "string" ? v.trim().slice(0, n) : "");

/** Only worth a model call when the founder gave something to read. */
export function hasEnrichableSignal(brief: CompanyBrief): boolean {
  return !!(brief.oneLiner?.trim() || brief.notes?.trim());
}

/** Ask the model to read the founder's inputs into a structured brief. */
export function buildEnrichPrompt(brief: CompanyBrief): string {
  const lines = [
    `Product name: ${clip(brief.projectName, 120) || "(unnamed)"}`,
    brief.oneLiner ? `Founder's one-liner: ${clip(brief.oneLiner, 300)}` : null,
    brief.categories?.length ? `Founder-picked categories: ${brief.categories.join(", ")}` : null,
    brief.audience ? `Founder-stated audience: ${clip(brief.audience, 200)}` : null,
    brief.link ? `Link: ${clip(brief.link, 200)}` : null,
    brief.notes ? `Founder's notes / pitch:\n${clip(brief.notes, 2000)}` : null,
  ].filter(Boolean);
  return (
    "Read what the founder told you about their product and produce a crisp structured read of it.\n\n" +
    lines.join("\n") +
    "\n\nProduce: a sharp 1-2 sentence summary of what it is and does; who it's for (audience); and 2-4 product categories. Ground EVERYTHING only in what the founder said — do not invent features, an audience, or a different product. If you genuinely can't infer a field, use an empty string / empty array rather than guessing."
  );
}

/** Fill gaps without overriding what the founder explicitly typed. */
export function mergeEnrichment(brief: CompanyBrief, e: BriefEnrichment): CompanyBrief {
  const summary = clip(e.summary, 400);
  const audience = clip(e.audience, 200);
  const cats = Array.isArray(e.categories)
    ? e.categories.map((c) => clip(c, 40)).filter(Boolean).slice(0, 4) : [];
  return {
    ...brief,
    summary: summary || brief.summary,
    audience: brief.audience?.trim() ? brief.audience : audience || brief.audience,
    categories: brief.categories?.length ? brief.categories : cats.length ? cats : brief.categories,
  };
}

export const ENRICH_TOOL = {
  name: "record_brief",
  description: "Record the structured read of the founder's product.",
  input_schema: {
    type: "object",
    properties: {
      summary: { type: "string", description: "A sharp 1-2 sentence description of what the product is and does, in plain language — grounded ONLY in what the founder said." },
      audience: { type: "string", description: "Who the product is for, inferred from the founder's input. Empty string if you genuinely cannot tell." },
      categories: { type: "array", items: { type: "string" }, description: "2-4 short product categories. Empty array if unclear." },
    },
    required: ["summary", "audience", "categories"],
  },
} as const;

export const ENRICH_SYSTEM =
  "You read a founder's raw notes about their product and distill them into a crisp, faithful structured summary. You never invent details the founder did not give you.";
