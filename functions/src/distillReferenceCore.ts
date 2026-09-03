/**
 * Everything `distillReference` is MADE of — the payload contract, the system prompt, the forced tool,
 * and the user message — with nothing that talks to a model.
 *
 * Split from the handler so the local path can import the builders without dragging the
 * Anthropic SDK, express and firebase-admin into an esbuild bundle that ships inside the app.
 * Same reasoning as `enrichBriefCore`, and the same anti-drift property: one prompt, two
 * transports.
 */

// MARK: - Types
//
// Distills a recommended reading resource into a few CONCRETE, project-specific
// principles the coding agent can apply while building. Mirrors generatePlan's
// shape (auth + rate limit + tool-use), but the output is reference guidance
// that gets written into the project's CLAUDE.md, not an on-screen plan.

export interface DistillProjectInput {
  name: string;
  stage: "idea" | "building" | "launch" | "growth";
  brief: string;
  tags: string[];      // ProjectTag rawValues, e.g. ["swiftUI", "firebase"]
  domains: string[];   // ProjectDomain rawValues, e.g. ["finance"]
}

export interface DistillResourceInput {
  title: string;
  author: string;
  kind: string;        // e.g. "Book", "Reference"
  why: string;         // the matcher's blurb for why it fits this project
}

export interface DistillPayload {
  language: "vi" | "en";
  project: DistillProjectInput;
  resource: DistillResourceInput;
}

export interface DistillOutput {
  principles: string[];   // 3-5 concrete, project-specific directives
}

// MARK: - Validation

export function validateDistillPayload(body: any): string | null {
  if (!body || typeof body !== "object") return "body required";
  const b = body as Partial<DistillPayload>;
  if (b.language !== "vi" && b.language !== "en") return "language must be 'vi' or 'en'";

  const p = b.project;
  if (!p || typeof p !== "object") return "project required";
  if (typeof p.name !== "string") return "project.name required";
  if (!["idea", "building", "launch", "growth"].includes(p.stage as string)) {
    return "project.stage must be idea|building|launch|growth";
  }
  if (typeof p.brief !== "string") return "project.brief required (may be empty)";
  if (!Array.isArray(p.tags)) return "project.tags must be an array";
  if (!Array.isArray(p.domains)) return "project.domains must be an array";

  const r = b.resource;
  if (!r || typeof r !== "object") return "resource required";
  if (typeof r.title !== "string") return "resource.title required";
  if (typeof r.author !== "string") return "resource.author required";
  if (typeof r.kind !== "string") return "resource.kind required";
  if (typeof r.why !== "string") return "resource.why required (may be empty)";
  return null;
}

// MARK: - System prompt
//
// Neutral, instructional voice (like generatePlan). Output is consumed by a
// coding agent reading CLAUDE.md, so each principle must be concrete and
// directly applicable to THIS project — never a generic book summary.

export const DISTILL_SYSTEM_PROMPT = `You turn a recommended resource (a book, reference, or article) into a SHORT list of concrete principles that a coding agent should apply when building ONE specific project.

YOUR JOB:
Given a project (its stage, brief, tech, and what it is about) and ONE resource, extract 3 to 5 principles FROM THAT RESOURCE, each rewritten as a direct, actionable directive for THIS project.

CRITICAL RULES:
- SPECIFIC to THIS project. Reference its tech, domain, or stage. Never generic advice that could apply to any app.
- ACTIONABLE. Each principle is a directive the builder or coding agent can act on (e.g. "Validate form inputs inline as the user types"), not a vague theme ("good UX matters").
- GROUNDED in the resource. Use the resource's actual ideas. If the brief is empty, work from the name, tech, and domain.
- CONCISE. Each principle is one sentence, ideally under 140 characters.
- A coding agent reads these. Write them as instructions to that agent, in plain imperative voice.

VOICE:
- Neutral and instructional. Do NOT speak as a pet, mascot, or named persona. Do NOT use "I".
- NEVER use markdown bold (**), asterisks, or bullet characters inside a principle. Each principle is plain text; the app adds the bullets.
- NEVER use the em-dash or en-dash (— or –) anywhere. Use a comma, a period, or parentheses instead. (Ordinary hyphens inside words like "in-person" are fine; prefer "to" over a dash in ranges like "2 to 3".)
- Never mention "AI", "assistant", "Claude", or any model.

Output 3 to 5 principles via the record_reference tool.
Output language: <language>`;

// MARK: - Tool definition

export const REFERENCE_TOOL = {
  name: "record_reference",
  description: "Record 3 to 5 concrete, project-specific principles distilled from a resource, written as directives for the coding agent building this project.",
  input_schema: {
    type: "object",
    properties: {
      principles: {
        type: "array",
        description: "3 to 5 concrete, actionable principles from the resource, each rewritten as a one-sentence directive specific to THIS project.",
        items: { type: "string" }
      }
    },
    required: ["principles"]
  }
} as const;

// MARK: - User message builder

export function buildDistillUserMessage(payload: DistillPayload): string {
  const p = payload.project;
  const r = payload.resource;

  const tags = p.tags.length ? p.tags.join(", ") : "(none detected)";
  const domains = p.domains.length ? p.domains.join(", ") : "(none detected)";
  const brief = p.brief.trim() ? p.brief.trim().slice(0, 600) : "(no brief written yet)";

  return `PROJECT
- name: ${p.name}
- stage: ${p.stage}
- tech: ${tags}
- about (domain): ${domains}
- brief: ${brief}

RESOURCE TO DISTILL
- title: ${r.title}
- author: ${r.author}
- kind: ${r.kind}
- why it fits this project: ${r.why.trim() ? r.why.trim().slice(0, 300) : "(not specified)"}

Now call the record_reference tool with 3 to 5 concrete principles from this resource, each rewritten as a directive for building THIS project at its current stage.`;
}

// MARK: - Anthropic client singleton

/** The system + user text for one reference distillation. */
export function distillRequest(payload: DistillPayload): { system: string; user: string } {
  return {
    system: DISTILL_SYSTEM_PROMPT
      .replace("<language>", payload.language === "vi" ? "Tiếng Viet" : "English"),
    user: buildDistillUserMessage(payload),
  };
}

/**
 * At most five non-empty principles, trimmed — or null when there are none.
 *
 * The cap and the trim are the handler's, kept here so both transports apply them: a local
 * answer with eight principles must not reach a client sized for five.
 */
export function coercePrinciples(input: unknown): string[] | null {
  const raw = (input as { principles?: unknown } | null)?.principles;
  if (!Array.isArray(raw)) return null;
  const principles = raw
    .filter((s): s is string => typeof s === "string" && s.trim().length > 0)
    .map((s) => s.trim())
    .slice(0, 5);
  return principles.length > 0 ? principles : null;
}
