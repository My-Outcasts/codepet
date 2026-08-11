// Pure logic for the companyChat CF — no firebase/express/anthropic imports, so it can
// be unit-tested (and verified) without loading the heavy Cloud-Functions module tree.
// The IO handler lives in companyChat.ts and imports from here.

// departments.ts is static curated data with no imports of its own, so it stays inside the
// "pure logic, unit-testable" boundary this file is built on.
import { departmentBrief, DEPARTMENT_NAMES } from "./departments";

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
export function buildSystemPrompt(args: { companionId: string; language: string; deptKey?: string | null }): string {
  const c = companionFor(args.companionId);
  const vi = args.language === "vi"
    ? "\n\nReply in natural, fluent Vietnamese."
    : "";
  // The department this turn belongs to, as real expertise rather than a role label.
  //
  // `DEPARTMENT_FOUNDATIONS` has existed since Jul 15 and, until now, only the ROADMAP
  // generator read it — so a founder asking Marketing a question got a marketing NAME on
  // the reply and a generalist behind it. `departmentBrief` returns '' for a null or
  // unknown key, so an ordinary chat turn is byte-identical to what it was before.
  //
  // It sits in the CACHED static block deliberately. That block previously varied only by
  // companion × language (14 shapes shared across every founder, which is what makes the
  // cache hit); adding the department takes it to at most 14 × 9. That is more shapes but
  // they are still SHARED — every founder asking Marketing hits the same prefix — and the
  // expertise text is long enough that paying for it uncached on every marketing turn
  // would cost far more than the extra shapes do. The per-founder volatile block stays
  // where it is, after the breakpoint.
  const dept = departmentBrief(args.deptKey);
  const deptName = args.deptKey ? DEPARTMENT_NAMES[args.deptKey] : undefined;
  const deptBlock = dept && deptName
    ? `\n\nYou are answering as the ${deptName} function of the founder's company. This is what that function owns:\n${dept}\n` +
      `Answer from that expertise — the specifics this function would actually know — not as a generalist who has been told the topic.\n`
    : "";
  return (
    `You are ${c.name}, the AI building companion inside Codepet — a senior operator who helps a solo founder build and understand their whole company, department by department.\n\n` +
    `Voice: ${c.voice}\n` +
    deptBlock +
    `\n` +
    `You are in a chat with the founder. Be warm, plain-spoken, specific, and brief — usually 2-4 sentences, occasionally a short list when it genuinely helps. No hype, no filler, no emoji. Write plain text only — no markdown, asterisks, backticks, or arrows; the chat shows your words as-is. When they ask what to do next, ground your answer in their actual company and where they are.\n\n` +
    // Static, so it stays inside the cacheable prefix. It repeats the draft_message tool
    // description on purpose: the failure this fixes is the model TYPING a message, and a
    // tool description is only read when the model is already reaching for a tool.
    `When you write an actual message for them to send to a person — an email, a DM, a text — put it in the draft_message tool instead of typing it into your reply. Your reply then carries only the framing and any question you have. The app renders each draft as its own card they can copy.` +
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

// The founder's tone preferences (Settings → AI), rendered as its own section of the
// VOLATILE system block — after the persona above, before the company context, so an
// explicit knob (e.g. "A single relevant emoji per reply is welcome.") is read as an
// override of the persona's "No emoji" clause rather than a contradiction of it.
//
// Deliberately NOT part of buildSystemPrompt's cached prefix: that prefix varies only
// by companion + language (14 shapes shared by every founder, which is what makes the
// cache hit), and folding a per-founder string into it would shatter that sharing for
// the sake of caching ~40 tokens.
//
// Empty when the founder changed nothing, so an untouched settings panel costs zero
// tokens on every request. The fragment itself is composed client-side by
// `AIStyle.promptFragment()`, which returns nil at defaults; clipped here because it
// arrives from the client.
export function styleBlock(fragment?: string): string {
  // Newlines are collapsed BEFORE clipping, and that is a boundary check, not tidying.
  // `style_fragment` is client-supplied and lands verbatim in a system prompt, and `clip`
  // only trims the ends and bounds the length — it leaves interior line breaks intact. A
  // fragment carrying "\n\nThe founder's company:" would therefore print a second copy of
  // `buildContextBlock`'s heading, at line start after a blank line, immediately above the
  // real one: a forged section the model has no way to tell from the genuine grounding.
  // Collapsing every whitespace run that contains a line break into a single space makes
  // this block structurally ONE line under its own heading, so no text inside it can read
  // as a heading of its own — the words survive, the forged structure does not. \u2028 and
  // \u2029 are in the class because they are line breaks too, not just \r and \n.
  const oneLine = typeof fragment === "string"
    ? fragment.replace(/\s*[\n\r\u2028\u2029]\s*/g, " ")
    : "";
  const f = clip(oneLine, 2000);
  if (!f) return "";
  return `\n\nHow the founder wants you to write:\n${f}`;
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
// ─── Skills the founder has turned ON ────────────────────────────────────────
// Distinct from `env_setup`, which carries the items that are OFF so byte can
// offer them. This is the other half of that conversation, and until now it did
// not exist: `enabledTools` never left the client, so turning a skill on changed
// nothing about the request. A toggle that alters no behaviour is a promise the
// app doesn't keep, which is exactly what this closes.
//
// THE BACKEND IS THE AUTHORITY ON WHAT IS REAL. The client may send any id from
// its catalog; only ids listed here do anything. That keeps the honest boundary
// in one place — a skill ships when it appears in this set and the code below
// acts on it, not when someone adds a row to the catalog.
export const IMPLEMENTED_SKILLS = ["web-research", "prd-writer"] as const;
export type ImplementedSkill = (typeof IMPLEMENTED_SKILLS)[number];

const IMPLEMENTED_SKILL_SET: ReadonlySet<string> = new Set(IMPLEMENTED_SKILLS);

/**
 * Anthropic's server-side web search. Hosted — declaring it is the whole
 * integration; there is no handler to write.
 *
 * `max_uses` is a COST CEILING, not a hint. Each search is billed on top of
 * tokens, and chat is priced to feel unlimited at ~0.25 credit/msg, so an
 * uncapped tool could quietly make a single turn cost more than a day of chat.
 * Three is enough to answer a real question and cheap enough to not notice.
 */
export const WEB_SEARCH_TOOL = {
  type: "web_search_20260209",
  name: "web_search",
  max_uses: 3,
} as const;

/** The subset of `enabled_skills` this backend actually implements. */
export function parseEnabledSkills(raw: unknown): Set<string> {
  if (!Array.isArray(raw)) return new Set();
  const out = new Set<string>();
  for (const v of raw) {
    if (typeof v !== "string") continue;
    const id = v.trim().toLowerCase();
    // Unknown ids are dropped rather than passed through: the founder may have
    // toggled on a catalog item we have not built, and silence is the honest
    // response to that until we have.
    if (IMPLEMENTED_SKILL_SET.has(id)) out.add(id);
  }
  return out;
}

/**
 * Per-skill instructions, appended to the VOLATILE context block (never the
 * cached static prompt — this varies per founder and per toggle).
 *
 * Empty input → '', so a founder with no skills on sees a byte-for-byte
 * unchanged prompt. Same backward-compatible shape as buildSetupBlock.
 */
export function buildSkillsBlock(skills: Set<string>): string {
  const parts: string[] = [];
  if (skills.has("web-research")) {
    parts.push(
      "- Web research: you have a `web_search` tool. Use it only when the answer " +
        "genuinely depends on current facts you cannot already know — competitor " +
        "pricing, market numbers, library or API changes. Say what you found and " +
        "where it came from. Do NOT search for anything already answered by the " +
        "company context above, and do not search to pad a reply."
    );
  }
  if (skills.has("prd-writer")) {
    parts.push(
      "- PRD writer: when the founder asks for a spec, a PRD, or what a feature " +
        "should do, answer with a STRUCTURED product spec rather than prose — the " +
        "problem and who has it, the requirements as a short numbered list, what is " +
        "explicitly out of scope, and how they would know it works. Short enough to " +
        "act on today; never pad it to look thorough. For anything that is not a " +
        "spec request, ignore this and reply normally."
    );
  }
  if (!parts.length) return "";
  return `\n\nSKILLS THE FOUNDER HAS TURNED ON (behave accordingly):\n${parts.join("\n")}`;
}

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

// ---------------------------------------------------------------------------
// Roadmap verbs — "chat is the central brain" (founder, Aug 8)
//
// Before these, the chat could only RUN a task that already existed. It could not
// create one, complete one, or reshape anything: the roadmap was written once by the
// scaffold and edited only by hand. That split is what made the roadmap feel like a
// separate app, and it is also why the companion said "you can consider this step done"
// and then handed over a navigation chip — the capability was missing, so the honest
// grounding had to forbid the sentence instead of the sentence being true.
//
// Both verbs PROPOSE. Neither mutates anything server-side: the CF validates and returns
// an intent, exactly as `run_task` does, and the native client renders a confirmation the
// founder presses. A model that can silently rewrite a roadmap is worse than one that
// cannot touch it — one wrong completion and the founder's progress is fiction.

/** A task the companion may offer to mark complete. Mirrors `RunnableTaskRef`. */
export interface CompletableTaskRef {
  id: string;
  title: string;
}

export const COMPLETE_TASK_TOOL = {
  name: "complete_task",
  description:
    "Offer to mark a roadmap task done, when the founder says they have finished it themselves — e.g. \"I did that\", \"that's done\", \"mark it complete\", \"I already talked to them\". Use the exact task_id from OPEN TASKS. This does NOT complete work for them and must never be used to claim you did something: it records that THEY finished a step they own. Do not call it for a task you drafted — that is completed by the founder approving the draft. If it is ambiguous which task they mean, ask a one-line question instead of guessing.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      task_id: {
        type: "string",
        description: "The exact id of the task the founder says they finished, copied from OPEN TASKS.",
      },
      task_title: {
        type: "string",
        description: "The task's title, copied from the same entry (optional; fallback match only).",
      },
    },
    required: ["task_id"],
  },
} as const;

export const ADD_TASK_TOOL = {
  name: "add_task",
  description:
    "Offer to add a new task to the roadmap, when the founder describes work they want tracked that is not already on it — e.g. \"add a task to call the two bakeries\", \"we need to write a refund policy\". Write the title as an action the founder or a department can start, in their own words where possible. Do NOT call this for work already on the roadmap, for something you are about to do yourself in this chat, or to break an existing task into sub-steps.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      title: {
        type: "string",
        description: "A short, concrete action — what would be done, not a topic. Max ~80 characters.",
      },
      detail: {
        type: "string",
        description: "One sentence on what finishing it means. Optional; omit rather than padding.",
      },
      dept: {
        type: "string",
        description:
          "The department that owns it: eng, design, mkt, sales, support, fin, ops, or legal. Omit if genuinely unclear.",
      },
      owner: {
        type: "string",
        enum: ["founder", "codepet"],
        description:
          "Who does it. \"founder\" for work only they can do (conversations, decisions, anything needing their judgement or their accounts); \"codepet\" for a deliverable you could draft.",
      },
    },
    required: ["title", "owner"],
  },
} as const;

/** The validated intent to complete a task. `null` when the model named a task that isn't open. */
export function validateCompleteTaskToolUse(
  input: unknown,
  completable: CompletableTaskRef[]
): string | null {
  if (!input || typeof input !== "object") return null;
  const raw = input as { task_id?: unknown; task_title?: unknown };
  const id = typeof raw.task_id === "string" ? raw.task_id.trim() : "";
  if (id && completable.some((t) => t.id === id)) return id;
  // Same fallback as run_task: a title match rescues a turn where the model copied the
  // human-readable field correctly and the id wrongly.
  const title = typeof raw.task_title === "string" ? raw.task_title.trim().toLowerCase() : "";
  if (!title) return null;
  return completable.find((t) => t.title.trim().toLowerCase() === title)?.id ?? null;
}

export interface NewTaskIntent {
  title: string;
  detail: string;
  dept: string | null;
  owner: "founder" | "codepet";
}

const TASK_DEPTS = ["eng", "design", "mkt", "sales", "support", "fin", "ops", "legal"];
const MAX_TASK_TITLE = 120;

/** The validated intent to add a task. `null` when there is no usable title. */
export function validateAddTaskToolUse(input: unknown): NewTaskIntent | null {
  if (!input || typeof input !== "object") return null;
  const raw = input as { title?: unknown; detail?: unknown; dept?: unknown; owner?: unknown };
  const title = typeof raw.title === "string" ? raw.title.trim() : "";
  if (!title) return null;
  const detail = typeof raw.detail === "string" ? raw.detail.trim() : "";
  const dept = typeof raw.dept === "string" && TASK_DEPTS.includes(raw.dept.trim())
    ? raw.dept.trim()
    : null;
  // Anything but an explicit "codepet" is the founder's. Defaulting the OTHER way would
  // let a malformed turn queue work the founder never asked Codepet to take on.
  const owner = raw.owner === "codepet" ? "codepet" : "founder";
  return { title: title.slice(0, MAX_TASK_TITLE), detail, dept, owner };
}

const MAX_OPEN_TASKS = 60;

/** The OPEN TASKS grounding block — what `complete_task` may name. */
export function buildOpenTasksBlock(open: CompletableTaskRef[]): string {
  if (!open.length) return "";
  const lines = open
    .slice(0, MAX_OPEN_TASKS)
    .map((t) => `- ${t.id} — ${t.title}`)
    .join("\n");
  return (
    "\n\nOPEN TASKS (the founder's own steps, not yet done). To mark one complete when " +
    "they say they finished it, call complete_task with the exact id:\n" + lines
  );
}

// ---------------------------------------------------------------------------
// draft_message — the messages the companion writes for a person, as OBJECTS
// ---------------------------------------------------------------------------
//
// Founder report, Aug 10 2026, with a screenshot: asked for outreach copy, the companion
// replied with two complete messages typed as quoted prose inside one chat bubble. Nothing
// marked where one message ended and the next began, there was no Copy, nothing reached the
// Library, and the `[name]` / `[date]` blanks sat invisible mid-sentence. The app already
// had a message CARD — `.email`/`.dms` deliverables render one — but a message written
// conversationally never became a deliverable, so no card could fire.
//
// This verb closes that: when the companion writes a message, it emits it instead of typing
// it, and the native client renders each draft in the same card. The reply text keeps the
// lead-in and the closing question, which is what prose is actually good for.
//
// It takes an ARRAY because the reported turn contained two drafts — one for the founders
// who had already asked, one for everyone else. A single-draft shape would have forced that
// turn back into prose, which is the bug.
//
// Like remember_fact, this resolves INDEPENDENTLY of the run/nav/setup trio and of the two
// roadmap verbs: "here's the message, and I'll add a task to track replies" is one honest
// turn. It mutates nothing — it is content, not an action, so there is nothing to confirm.

export type MessageChannel = "email" | "dm" | "text";

export interface MessageDraftIntent {
  channel: MessageChannel;
  to: string;
  subject: string;
  body: string;
}

const MAX_DRAFTS = 4;
const MAX_DRAFT_BODY = 4000;
const MAX_DRAFT_SUBJECT = 200;
const MAX_DRAFT_TO = 120;

export const DRAFT_MESSAGE_TOOL = {
  name: "draft_message",
  description:
    "Use whenever you write an actual message for the founder to send to a person — a cold email, a reply, a DM, a text. Put the message text ONLY in this tool: do not also write it out in your reply, or the founder sees it twice. Your reply should carry just the framing (what the versions are, why) and any closing question. Call it once with every version you wrote — if you drafted one message for people who already asked and another for everyone else, that is one call with two entries, not two calls. Keep placeholders in square brackets, like [name] or [date], so the founder can see what they must fill in. If the founder is asking for a message that is already a task on their roadmap, prefer run_task so the draft is saved to their Library.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      messages: {
        type: "array",
        maxItems: MAX_DRAFTS,
        description: "Every version you wrote this turn, in the order you would present them.",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            channel: {
              type: "string",
              enum: ["email", "dm", "text"],
              description: "How it would be sent. Use \"dm\" for a direct message and \"text\" for SMS/WhatsApp.",
            },
            to: {
              type: "string",
              description:
                "Who it is for, in the founder's own words — \"the two who asked to pay\", \"Maria at Bluebird\". Not an address.",
            },
            subject: {
              type: "string",
              description: "Subject line. Email only — omit for a dm or a text.",
            },
            body: {
              type: "string",
              description: "The message itself, ready to paste. No surrounding quotation marks, no commentary.",
            },
          },
          required: ["channel", "body"],
        },
      },
    },
    required: ["messages"],
  },
} as const;

/**
 * The validated drafts. `null` when nothing usable came through — the caller then leaves the
 * turn as plain prose rather than rendering an empty card.
 *
 * A draft with no body is dropped rather than rescued: unlike a task id, there is no
 * second field that could stand in for the message itself.
 */
export function validateDraftMessageToolUse(input: unknown): MessageDraftIntent[] | null {
  if (!input || typeof input !== "object") return null;
  const raw = (input as { messages?: unknown }).messages;
  if (!Array.isArray(raw)) return null;

  const out: MessageDraftIntent[] = [];
  for (const entry of raw.slice(0, MAX_DRAFTS)) {
    if (!entry || typeof entry !== "object") continue;
    const e = entry as { channel?: unknown; to?: unknown; subject?: unknown; body?: unknown };

    // Models like to wrap a quoted message in the quotes they saw in the conversation.
    // Those belong to the presentation, not to the message the founder pastes.
    const body = typeof e.body === "string" ? stripWrappingQuotes(e.body.trim()) : "";
    if (!body) continue;

    const channel: MessageChannel =
      e.channel === "email" || e.channel === "text" ? e.channel : "dm";
    const to = typeof e.to === "string" ? e.to.trim().slice(0, MAX_DRAFT_TO) : "";
    // A subject on a dm or a text is a mistake in the call, and rendering it would put an
    // email header on something that has none.
    const subject =
      channel === "email" && typeof e.subject === "string"
        ? e.subject.trim().slice(0, MAX_DRAFT_SUBJECT)
        : "";

    out.push({ channel, to, subject, body: body.slice(0, MAX_DRAFT_BODY) });
  }
  return out.length ? out : null;
}

/** Removes one matched pair of wrapping quotes — and only a pair that wraps the WHOLE body. */
function stripWrappingQuotes(s: string): string {
  const pairs: Array<[string, string]> = [['"', '"'], ["“", "”"], ["'", "'"]];
  for (const [open, close] of pairs) {
    if (s.length >= 2 && s.startsWith(open) && s.endsWith(close)) {
      const inner = s.slice(1, -1);
      // Only if the quotes were decoration. If the body contains its own closing quote
      // earlier, these are real punctuation and stripping them would corrupt the text.
      if (!inner.includes(close)) return inner.trim();
    }
  }
  return s;
}
