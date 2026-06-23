import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { MODEL } from "./anthropic";

// MARK: - Types

export interface ExtractedEntry {
  label: string;
  kind: "principle" | "patternResponse" | "codeWisdom" | "mindset";
  advice: string;
  one_liner: string;
  tech_tags: string[];
  triggers: TriggerDef[];
}

export interface TriggerDef {
  type: "usesTech" | "healthGapExists" | "recentActivity" | "inactiveArea" | "projectStage" | "always";
  value?: string;
}

export interface ExtractionPayload {
  expert_name: string;
  source_text: string;
  source_type: "case_study" | "blog_post" | "slack_message" | "notion_page" | "voice_transcript" | "raw_note";
}

export interface ExtractionResponse {
  entries: ExtractedEntry[];
  source_summary: string;
  model: string;
}

// MARK: - Validation

export function validateExtractionPayload(body: any): string | null {
  if (!body || typeof body !== "object") return "body required";
  if (typeof body.expert_name !== "string" || !body.expert_name) return "expert_name required";
  if (typeof body.source_text !== "string" || !body.source_text) return "source_text required";
  if (body.source_text.length < 50) return "source_text must be at least 50 characters";
  if (body.source_text.length > 20000) return "source_text must be under 20000 characters";
  const validTypes = ["case_study", "blog_post", "slack_message", "notion_page", "voice_transcript", "raw_note"];
  if (!validTypes.includes(body.source_type)) return `source_type must be one of: ${validTypes.join(", ")}`;
  return null;
}

// MARK: - System prompt

const EXTRACTION_SYSTEM_PROMPT = `You are a knowledge extraction engine. Your job is to read text written by or about a product expert and extract discrete, actionable pieces of practical knowledge.

Each piece of knowledge becomes a structured entry with:
- label: Internal short name (3-5 words)
- kind: One of "principle" (universal truth), "patternResponse" (triggered by specific user situation), "codeWisdom" (tech-specific insight), "mindset" (motivation/mental model)
- advice: 2-4 sentences written in the expert's voice (first person). This is what the AI pet will use when giving advice grounded in the expert's experience. Be specific — mention real products, real tools, real numbers.
- one_liner: One punchy sentence capturing the core insight. Like something you'd put on a sticky note.
- tech_tags: Array of technologies this applies to (empty for universal). Use standard names: "SwiftUI", "Firebase", "HTML", "CSS", "JavaScript", "React", "Node", "Python", etc.
- triggers: Array of conditions that make this entry relevant:
  - {"type": "always"} — universal advice
  - {"type": "usesTech", "value": "SwiftUI"} — user's project uses this tech
  - {"type": "healthGapExists", "value": "tests"} — user is missing tests
  - {"type": "recentActivity", "value": "ui-building"} — user has been doing this
  - {"type": "inactiveArea", "value": "styling"} — user hasn't done this in a while
  - {"type": "projectStage", "value": "building"} — project is at this stage
  Common activities: "ui-building", "styling", "auth-setup", "debugging", "testing", "refactoring", "adding-features", "prototyping", "shipping", "design"
  Common gaps: "tests", "ci", "readme", "backend", "error-handling", "accessibility"
  Common stages: "building", "pre-launch", "launched", "maintaining"

RULES:
- Extract 3-8 entries per source text. Don't force it — if the text only has 2 real insights, return 2.
- Each entry must be grounded in something SPECIFIC from the text. Don't generalize.
- The advice field must sound like the expert talking, not a textbook.
- Prefer "patternResponse" kind when the insight is about a specific situation (most useful for the matching engine).
- Don't extract the same insight twice with different wording.
- For short inputs (Slack messages, voice notes), extract 1-2 entries max.`;

// MARK: - Tool definition

const EXTRACTION_TOOL = {
  name: "record_knowledge_entries",
  description: "Extract structured knowledge entries from expert source text.",
  input_schema: {
    type: "object",
    properties: {
      entries: {
        type: "array",
        items: {
          type: "object",
          properties: {
            label: { type: "string", description: "Short internal name (3-5 words)" },
            kind: { type: "string", enum: ["principle", "patternResponse", "codeWisdom", "mindset"] },
            advice: { type: "string", description: "2-4 sentences in the expert's voice" },
            one_liner: { type: "string", description: "One punchy sentence" },
            tech_tags: { type: "array", items: { type: "string" } },
            triggers: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  type: { type: "string", enum: ["usesTech", "healthGapExists", "recentActivity", "inactiveArea", "projectStage", "always"] },
                  value: { type: "string" }
                },
                required: ["type"]
              }
            }
          },
          required: ["label", "kind", "advice", "one_liner", "tech_tags", "triggers"]
        }
      },
      source_summary: {
        type: "string",
        description: "One sentence summarizing what this source text was about."
      }
    },
    required: ["entries", "source_summary"]
  }
} as const;

// MARK: - Anthropic client

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

export async function handleExtractKnowledge(
  req: Request,
  res: Response
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  // Auth
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  // Validate
  const validationError = validateExtractionPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as ExtractionPayload;

  // Build prompt
  const userMessage = `Expert: ${payload.expert_name}
Source type: ${payload.source_type}

--- SOURCE TEXT ---
${payload.source_text}
--- END SOURCE TEXT ---

Extract practical knowledge entries from this text. Remember: each entry must be grounded in something specific from the text, written in ${payload.expert_name}'s voice.`;

  // Call Claude
  let result: { entries: ExtractedEntry[]; source_summary: string };
  try {
    const response = await anthropicClient().messages.create({
      model: MODEL,
      max_tokens: 4000,
      system: [{ type: "text", text: EXTRACTION_SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
      tools: [EXTRACTION_TOOL as any],
      tool_choice: { type: "tool", name: "record_knowledge_entries" },
      messages: [{ role: "user", content: userMessage }]
    });

    let parsed: { entries: ExtractedEntry[]; source_summary: string } | undefined;
    for (const block of response.content) {
      if (block.type === "tool_use" && block.name === "record_knowledge_entries") {
        const input = block.input as any;
        if (Array.isArray(input.entries) && typeof input.source_summary === "string") {
          parsed = { entries: input.entries, source_summary: input.source_summary };
        }
      }
    }

    if (!parsed) {
      throw new Error("Anthropic response missing valid tool use");
    }
    result = parsed;
  } catch (err) {
    logger.error("knowledge extraction failed", { uid: auth.uid, err: String(err) });
    res.status(502).json({ error: "upstream_failure" });
    return;
  }

  // Respond
  res.status(200).json({
    entries: result.entries,
    source_summary: result.source_summary,
    model: MODEL,
    expert_name: payload.expert_name,
    extracted_at: new Date().toISOString()
  } as ExtractionResponse & { expert_name: string; extracted_at: string });
}
