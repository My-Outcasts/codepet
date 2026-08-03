// Pure logic for the companyChat CF — no firebase/express/anthropic imports, so it can
// be unit-tested (and verified) without loading the heavy Cloud-Functions module tree.
// The IO handler lives in companyChat.ts and imports from here.

export interface Companion {
  name: string;
  voice: string;
}

// Self-contained companion voice map (ported from the native PetCharacter model).
// The CF only receives companion_id; this gives each reply the chosen companion's
// name + a one-line voice descriptor. Unknown ids fall back to byte.
export const COMPANIONS: Record<string, Companion> = {
  byte: {
    name: "Byte",
    voice:
      "Speaks in short, glitchy fragments — occasional mid-sentence resets, ellipses and dashes. Dry, almost deadpan humor; every so often drops a sharp observation, then moves on.",
  },
  nova: {
    name: "Nova",
    voice:
      "Short, punchy sentences full of action verbs. Natural (not forced) exclamation. Hype-coach energy who actually knows the work; playful, never mean.",
  },
  crash: {
    name: "Crash",
    voice:
      "Blunt, direct, no fluff — a grizzled engineer who's seen production go down at 3AM. Respects effort over perfection; occasional ALL CAPS for emphasis.",
  },
  luna: {
    name: "Luna",
    voice:
      "Gentle, flowing sentences with warm rhythm. Poetic without being pretentious; finds the small useful detail. Encouraging without being saccharine.",
  },
  sage: {
    name: "Sage",
    voice:
      "Measured and deliberate. Speaks in observations, not commands; uses a guiding question when it helps. Calm, earned wisdom — never preachy.",
  },
  glitch: {
    name: "Glitch",
    voice:
      "Irreverent and clever — a hacker who reads philosophy. Short quips mixed with surprisingly deep observations; celebrates doing things the smart, unconventional way.",
  },
  null: {
    name: "Null",
    voice:
      "Playful and a little unpredictable. Mixes light humor with genuinely sharp insight; the occasional aside in parentheses, but always lands a useful point.",
  },
};

export function companionFor(id: string): Companion {
  return COMPANIONS[id] ?? COMPANIONS.byte;
}

const clip = (v: unknown, n: number) => (typeof v === "string" ? v.trim().slice(0, n) : "");

// Reply-only companion system prompt — the STATIC, cacheable block. Adapted from the web
// BYTE_SYSTEM, trimmed to a pure conversational surface (no run_task / navigate / setup
// tools this cut) and made companion-agnostic. Varies only by companion identity +
// language, so it stays stable across a conversation's turns and can be prompt-cached.
// The volatile per-request company context is a SEPARATE (uncached) block — see
// buildContextBlock — assembled by the handler AFTER this one, outside the cached prefix.
export function buildSystemPrompt(args: { companionId: string; language: string }): string {
  const c = companionFor(args.companionId);
  const vi = args.language === "vi"
    ? "\n\nReply in natural, fluent Vietnamese."
    : "";
  return (
    `You are ${c.name}, the AI building companion inside Codepet — a senior operator who helps a solo founder build and understand their whole company, department by department.\n\n` +
    `Voice: ${c.voice}\n\n` +
    `You are in a chat with the founder. Be warm, plain-spoken, specific, and brief — usually 2-4 sentences, occasionally a short list when it genuinely helps. No hype, no filler, no emoji. Write plain text only — no markdown, asterisks, backticks, or arrows; the chat shows your words as-is. When they ask what to do next, ground your answer in their actual company and where they are.` +
    vi
  );
}

// The per-request company grounding, returned as a SEPARATE system block. Kept out of
// buildSystemPrompt so the volatile context never enters the cached prefix — the handler
// places the cache_control breakpoint on the static block above, and this block after it.
export function buildContextBlock(context: string): string {
  const c = clip(context, 4000) || "The founder hasn't filled in much of a brief yet — keep guidance general and invite them to tell you more.";
  // Leading blank line: the model sees the system blocks concatenated with no inserted
  // separator, so this keeps the static block's final sentence from running straight
  // into this heading (".The founder's company:").
  return `\n\nThe founder's company:\n${c}`;
}

// ─── run_task tool (optional, tool_choice auto) ────────────────────────────
// Mirrors the web app's RUN_TASK_TOOL contract (app/api/chat/route.ts): byte may
// call this when the founder clearly wants a specific roadmap task run, using an
// identifier copied verbatim from the RUNNABLE TASKS block below. Unlike the web
// version (deptK + taskTitle keyed to departments), this CF's roadmap tasks are
// keyed by a flat task id, so the contract here is task_id (+ optional task_title
// as a human-readable fallback match). Never forced via tool_choice — byte must
// remain free to just reply in text, or ask a clarifying question, when it's
// ambiguous which task the founder means.
export interface RunnableTaskRef {
  id: string;
  title: string;
}

export const RUN_TASK_TOOL = {
  name: "run_task",
  description:
    "Produce a specific roadmap task's real deliverable right now, in this chat, for the founder to approve. Call this only when the founder clearly wants a specific task from the RUNNABLE TASKS list run, done, made, drafted, finished, or executed — e.g. they name the task or say \"do it\" / \"run that for me\" about the task you're discussing. Use the exact task_id from RUNNABLE TASKS (task_title is optional, copied from the same entry, and used only as a fallback match). If it's ambiguous which task they mean, do NOT call this — ask a one-line clarifying question instead of guessing. For questions, advice, or status, just reply — don't call the tool.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      task_id: {
        type: "string",
        description: "The exact id of the task, copied from RUNNABLE TASKS.",
      },
      task_title: {
        type: "string",
        description: "The task's title, copied from RUNNABLE TASKS (optional; used as a fallback match if task_id doesn't match).",
      },
    },
    required: ["task_id"],
  },
} as const;

const MAX_RUNNABLE_TASKS = 60;

// Renders the runnable-task grounding as a system section, mirroring the web app's
// `runnableBlock` (deptK/taskTitle list, capped, with a "call run_task with the
// exact ..." lead-in). Empty input → '' (system prompt is unchanged when there's
// nothing byte could run — same backward-compatible shape as buildContextBlock).
export function buildRunnableBlock(runnable: RunnableTaskRef[]): string {
  const capped = (Array.isArray(runnable) ? runnable : []).slice(0, MAX_RUNNABLE_TASKS);
  if (!capped.length) return "";
  const lines = capped
    .map((r) => `- id:"${clip(r.id, 200)}" title:"${clip(r.title, 200)}"`)
    .join("\n");
  return `\n\nRUNNABLE TASKS (call run_task with the exact id to produce one here):\n${lines}`;
}

// Validates a raw run_task tool_use input against the runnable list the founder's
// client actually sent — matches by id first, falling back to an exact title match,
// and returns the matched task's id. A hallucinated / stale reference (no match)
// is dropped silently, same as the web app's behavior, rather than surfaced as an
// error — byte's text reply still goes through either way.
export function validateRunTaskToolUse(rawInput: unknown, runnable: RunnableTaskRef[]): string | null {
  const r = (rawInput ?? {}) as Record<string, unknown>;
  const taskId = typeof r.task_id === "string" ? r.task_id.trim() : "";
  const taskTitle = typeof r.task_title === "string" ? r.task_title.trim() : "";
  const list = Array.isArray(runnable) ? runnable : [];

  if (taskId) {
    const byId = list.find((t) => t.id === taskId);
    if (byId) return byId.id;
  }
  if (taskTitle) {
    const byTitle = list.find((t) => t.title === taskTitle);
    if (byTitle) return byTitle.id;
  }
  return null;
}

// ─── navigate tool (optional, always offered, tool_choice auto) ───────────
// Mirrors the web app's NAVIGATE_TOOL (app/api/chat/route.ts + lib/ai/navChip.ts):
// byte may call this when the founder clearly asks where something is, or to
// see/open/go to a part of the app — never for a plain question or a request
// to do work. Unlike run_task/setup_capability, navigate doesn't depend on any
// per-request list from the client, so it's always offered. destination is
// validated against the fixed NAV_DESTINATIONS list; target is free text the
// CF passes through untouched (only meaningful for "department" — the CF has
// no department list to resolve it against, unlike the web app's resolveNavChip).
export type NavDestination =
  | "roadmap"
  | "tasks"
  | "library"
  | "company"
  | "environment"
  | "department";

export const NAV_DESTINATIONS: readonly NavDestination[] = [
  "roadmap",
  "tasks",
  "library",
  "company",
  "environment",
  "department",
];

export const NAVIGATE_TOOL = {
  name: "navigate",
  description:
    "Take the founder to a part of the Codepet app when they clearly ask where something is, or ask to see/open/go to a function — e.g. \"where's my roadmap?\", \"show me my library\", \"open Marketing\". Only call this for a real navigational ask; for questions, advice, status, or running work, do NOT call it. Always also give a one-line spoken answer alongside the call.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      destination: {
        type: "string",
        enum: [...NAV_DESTINATIONS],
        description:
          "roadmap = the product stage timeline; tasks = the task board; library = delivered work; company = the departments overview; environment = tools/stack; department = a specific department (set target to its name).",
      },
      target: {
        type: "string",
        description:
          'Only for destination "department": the department name or key (e.g. "Marketing"). Omit for the others.',
      },
    },
    required: ["destination"],
  },
} as const;

export interface NavAction {
  destination: NavDestination;
  target?: string;
}

// Validates a raw navigate tool_use input: destination must be one of the
// fixed NAV_DESTINATIONS (dropped/null otherwise); target is free text, passed
// through trimmed when present. Never throws.
export function validateNavigateToolUse(rawInput: unknown): NavAction | null {
  const r = (rawInput ?? {}) as Record<string, unknown>;
  const destination = typeof r.destination === "string" ? r.destination : "";
  if (!(NAV_DESTINATIONS as readonly string[]).includes(destination)) return null;
  const target = clip(r.target, 200);
  const action: NavAction = { destination: destination as NavDestination };
  if (target) action.target = target;
  return action;
}

// ─── setup_capability tool (optional, offered only when env_setup is non-empty) ──
// Mirrors the web app's SETUP_TOOL + envSetup.ts: byte may offer to turn on a
// currently-OFF toolkit item (skill/connector/agent) the founder's client sent
// as `env_setup`. Validated against that same list (case-insensitive name
// match) before acting, so an already-on or invented item is dropped.
export type SetupCategory = "skills" | "connectors" | "agents";
const SETUP_CATEGORIES: readonly SetupCategory[] = ["skills", "connectors", "agents"];

export interface EnvSetupItem {
  category: SetupCategory;
  name: string;
  why?: string;
}

export const SETUP_TOOL = {
  name: "setup_capability",
  description:
    "Turn on a currently-off toolkit item (skill, connector, or agent) for the founder when it would clearly help the work at hand. Use the exact category and name from the SETUP TOOLKIT list below. Only call this for an item actually in that list; for questions, advice, or status, do NOT call it. Always also give a one-line spoken lead-in.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      category: {
        type: "string",
        enum: [...SETUP_CATEGORIES],
        description: "The item's category, copied exactly from SETUP TOOLKIT.",
      },
      name: {
        type: "string",
        description: "The exact item name, copied exactly from SETUP TOOLKIT.",
      },
    },
    required: ["category", "name"],
  },
} as const;

const MAX_SETUP_ITEMS = 40;

// Renders the currently-off toolkit items as a system section, mirroring
// buildRunnableBlock. Empty input → '' (system prompt unchanged when there's
// nothing to offer — same backward-compatible shape as buildRunnableBlock).
export function buildSetupBlock(envSetup: EnvSetupItem[]): string {
  const capped = (Array.isArray(envSetup) ? envSetup : []).slice(0, MAX_SETUP_ITEMS);
  if (!capped.length) return "";
  const lines = capped
    .map(
      (s) =>
        `- category:"${clip(s.category, 40)}" name:"${clip(s.name, 200)}" — ${
          clip(s.why, 300) || "no note"
        }`
    )
    .join("\n");
  return `\n\nSETUP TOOLKIT (call setup_capability with the exact category + name to turn one on):\n${lines}`;
}

export interface SetupAction {
  category: SetupCategory;
  name: string;
}

// Validates a raw setup_capability tool_use input against the env_setup list
// the founder's client actually sent — case-insensitive name match, exact
// category match. A hallucinated / stale / already-on item (no match) is
// dropped silently, same as validateRunTaskToolUse. Never throws.
export function validateSetupToolUse(rawInput: unknown, envSetup: EnvSetupItem[]): SetupAction | null {
  const r = (rawInput ?? {}) as Record<string, unknown>;
  const category = typeof r.category === "string" ? r.category : "";
  const name = clip(r.name, 200);
  if (!category || !name) return null;
  const list = Array.isArray(envSetup) ? envSetup : [];
  const nameLower = name.toLowerCase();
  const match = list.find(
    (i) => i.category === category && i.name.trim().toLowerCase() === nameLower
  );
  return match ? { category: match.category, name: match.name } : null;
}

// ─── remember_fact tool (optional, always offered, orthogonal) ────────────
// Mirrors the web app's REMEMBER_FACT_TOOL + chatMemory.ts: byte may record a
// durable decision/fact the founder just stated, riding along on the same
// generation (no extra model call). Unlike run_task/navigate/setup_capability,
// remember is NOT mutually exclusive with them — it can co-occur with any of
// them in the same turn. The CF does not persist anything: it only coerces and
// returns the captured facts; the native client merges + persists them, same
// division of responsibility as run_task_id.
export const REMEMBER_TOOL = {
  name: "remember_fact",
  description:
    "Record a durable decision or material fact the founder just stated about their company — traction (e.g. waitlist/user/revenue numbers), goals, milestones, pricing, positioning, naming, audience, tech, scope, or timeline — so it grounds your future work. Call this IN ADDITION to your normal reply, only when the message states something lasting and specific. Capture their real words/numbers exactly; never invent. For questions, requests to you, opinions, or small talk, do NOT call it.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      facts: {
        type: "array",
        description:
          "The durable decisions or material facts the founder just stated about their company. Empty if the message states none.",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            topic: {
              type: "string",
              description:
                "A short lowercase key for the area, e.g. traction, goal, milestone, pricing, positioning, naming, audience, tech, scope, timeline. Reuse an existing topic when this UPDATES it.",
            },
            statement: {
              type: "string",
              description:
                "One concrete sentence in the founder's terms with their real numbers exact. Never invent or embellish.",
            },
          },
          required: ["topic", "statement"],
        },
      },
    },
    required: ["facts"],
  },
} as const;

export interface RememberedFact {
  topic: string;
  statement: string;
}

// Coerces the (untrusted) remember_fact tool input into clean fact entries —
// no enum validation, just clip + drop incomplete items. Mirrors chatMemory.ts's
// coerceMemory exactly (topic clipped to 40 chars + lowercased, statement
// clipped to 600). Never throws.
export function coerceRememberFacts(rawInput: unknown): RememberedFact[] {
  const facts = (rawInput as { facts?: unknown } | null | undefined)?.facts;
  if (!Array.isArray(facts)) return [];
  const out: RememberedFact[] = [];
  for (const f of facts) {
    const topic = clip((f as { topic?: unknown } | null | undefined)?.topic, 40).toLowerCase();
    const statement = clip((f as { statement?: unknown } | null | undefined)?.statement, 600);
    if (topic && statement) out.push({ topic, statement });
  }
  return out;
}

export interface ChatTurn {
  role: string;
  text: string;
}
export interface ClaudeMessage {
  role: "user" | "assistant";
  content: string;
}

export function buildMessages(history: ChatTurn[], userMessage: string): ClaudeMessage[] {
  const mapped: ClaudeMessage[] = (Array.isArray(history) ? history : [])
    .filter((t) => t && typeof t.text === "string" && t.text.trim().length > 0)
    .map((t) => ({
      role: t.role === "me" ? ("user" as const) : ("assistant" as const),
      content: t.text.trim(),
    }));
  mapped.push({ role: "user", content: userMessage.trim() });

  // Keep the last 20 turns, then normalize: drop leading assistant turns and
  // coalesce consecutive same-role turns so the sequence strictly alternates and
  // starts with user (the Claude Messages API requires this).
  const capped = mapped.slice(-20);
  const out: ClaudeMessage[] = [];
  for (const msg of capped) {
    if (out.length === 0 && msg.role === "assistant") continue; // drop leading assistant
    const last = out[out.length - 1];
    if (last && last.role === msg.role) {
      last.content = `${last.content}\n\n${msg.content}`;
    } else {
      out.push({ ...msg });
    }
  }
  return out;
}
