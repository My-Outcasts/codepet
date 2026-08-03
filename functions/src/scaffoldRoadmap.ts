import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL } from "./anthropic";

export interface DeptInput { key: string; name: string; expertise: string; }
export interface ScaffoldTask { title: string; detail: string; who: string; kind: string; }
export interface ScaffoldDept { key: string; tasks: ScaffoldTask[]; }
export interface ScaffoldResult { departments: ScaffoldDept[]; }

const clip = (v: unknown, n: number) => (typeof v === "string" ? v.trim().slice(0, n) : "");
const WHO = new Set(["draft", "does", "needsYou"]);

export function buildScaffoldPrompt(brief: any, stage: string, depts: DeptInput[]): string {
  const lines = [
    `Product: ${clip(brief?.projectName, 120) || "(unnamed)"}${brief?.oneLiner ? " — " + clip(brief.oneLiner, 300) : ""}`,
    brief?.summary ? `Summary: ${clip(brief.summary, 400)}` : null,
    brief?.audience ? `Audience: ${clip(brief.audience, 200)}` : null,
    `Stage: ${clip(stage, 40) || "building"}`,
    "",
    "Departments (generate 2-4 concrete, stage-appropriate build tasks for EACH):",
    ...depts.map((d) => `- ${d.name} (${d.key}): ${clip(d.expertise, 300)}`),
  ].filter(Boolean);
  return (
    "You are planning a founder's next concrete build tasks, department by department, grounded ONLY in what the founder told you.\n\n" +
    lines.join("\n") +
    "\n\nFor each department produce 2-4 tasks: a short imperative title, a 1-2 sentence detail, a `who` of exactly 'draft' | 'does' | 'needsYou', and kind 'build'. Ground everything in this product and stage — do not invent a different product, and do not invent facts the founder did not give you."
  );
}

/** Keep only known departments; trim/validate task fields. Never throws — returns empty on junk. */
export function coerceScaffold(raw: any, depts: DeptInput[]): ScaffoldResult {
  const known = new Set(depts.map((d) => d.key));
  const inDepts = raw && Array.isArray(raw.departments) ? raw.departments : [];
  const departments: ScaffoldDept[] = [];
  for (const d of inDepts) {
    if (!d || !known.has(d.key) || !Array.isArray(d.tasks)) continue;
    const tasks: ScaffoldTask[] = [];
    for (const t of d.tasks.slice(0, 4)) {
      const title = clip(t?.title, 120);
      if (!title) continue;
      tasks.push({
        title,
        detail: clip(t?.detail, 400),
        who: WHO.has(t?.who) ? t.who : "draft",
        kind: clip(t?.kind, 40) || "build",
      });
    }
    if (tasks.length) departments.push({ key: d.key, tasks });
  }
  return { departments };
}

const SCAFFOLD_TOOL = {
  name: "record_roadmap",
  description: "Record the generated build tasks per department.",
  input_schema: {
    type: "object",
    properties: {
      departments: {
        type: "array",
        items: {
          type: "object",
          properties: {
            key: { type: "string", description: "The department key exactly as given." },
            tasks: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  title: { type: "string" }, detail: { type: "string" },
                  who: { type: "string", description: "'draft' | 'does' | 'needsYou'" },
                  kind: { type: "string" },
                },
                required: ["title", "detail", "who", "kind"],
              },
            },
          },
          required: ["key", "tasks"],
        },
      },
    },
    required: ["departments"],
  },
} as const;

const SYSTEM = "You plan a founder's concrete next build tasks per department. You never invent details the founder did not give you.";

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) {
    const k = process.env.ANTHROPIC_API_KEY;
    if (!k) throw new Error("ANTHROPIC_API_KEY not set");
    _client = new Anthropic({ apiKey: k });
  }
  return _client;
}

export async function handleScaffoldRoadmap(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) { res.status(401).json({ error: "invalid_token" }); return; }
  const body = req.body ?? {};
  const depts: DeptInput[] = Array.isArray(body.departments) ? body.departments : [];
  if (!depts.length) { res.status(400).json({ error: "invalid_payload", detail: "departments required" }); return; }
  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) { res.status(429).json({ error: "daily_limit_reached", reset_at: limit.resetAt.toISOString(), limit: limit.limit }); return; }
  try {
    const response = await client().messages.create({
      model: MODEL, max_tokens: 2048, system: SYSTEM,
      tools: [SCAFFOLD_TOOL as any], tool_choice: { type: "tool", name: "record_roadmap" },
      messages: [{ role: "user", content: buildScaffoldPrompt(body.brief, body.stage, depts) }],
    });
    const block = response.content.find((b) => b.type === "tool_use") as any;
    res.status(200).json(coerceScaffold(block?.input, depts));
  } catch (err) {
    logger.error("scaffoldRoadmap failed", { uid: auth.uid, err: String(err) });
    res.status(200).json({ departments: [] }); // fail-open
  }
}
