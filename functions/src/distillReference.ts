import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { PLAN_MODEL } from "./anthropic";

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

const DISTILL_SYSTEM_PROMPT = `You turn a recommended resource (a book, reference, or article) into a SHORT list of concrete principles that a coding agent should apply when building ONE specific project.

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

const REFERENCE_TOOL = {
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

function buildDistillUserMessage(payload: DistillPayload): string {
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

let _anthropic: Anthropic | null = null;
function anthropicClient(): Anthropic {
  if (!_anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _anthropic = new Anthropic({ apiKey });
  }
  return _anthropic;
}

// MARK: - Handler

export async function handleDistillReference(
  req: Request,
  res: Response
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const validationError = validateDistillPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as DistillPayload;

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  const system = DISTILL_SYSTEM_PROMPT
    .replace("<language>", payload.language === "vi" ? "Tiếng Viet" : "English");
  const user = buildDistillUserMessage(payload);

  let principles: string[];
  try {
    const response = await anthropicClient().messages.create({
      model: PLAN_MODEL,
      max_tokens: 800,
      system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
      tools: [REFERENCE_TOOL as any],
      tool_choice: { type: "tool", name: "record_reference" },
      messages: [{ role: "user", content: user }]
    });

    let parsed: string[] | undefined;
    for (const block of response.content) {
      if (block.type === "tool_use" && block.name === "record_reference") {
        const input = block.input as DistillOutput;
        if (Array.isArray(input.principles) && input.principles.length > 0) {
          parsed = input.principles
            .filter((s) => typeof s === "string" && s.trim().length > 0)
            .map((s) => s.trim())
            .slice(0, 5);
        }
      }
    }

    if (!parsed || parsed.length === 0) {
      throw new Error("Anthropic response missing valid record_reference tool use");
    }
    principles = parsed;
  } catch (err) {
    logger.error("anthropic distill call failed", { uid: auth.uid, err: String(err) });
    res.status(502).json({ error: "upstream_failure" });
    return;
  }

  res.status(200).json({
    principles,
    model: PLAN_MODEL,
    generated_at: new Date().toISOString()
  });
}
