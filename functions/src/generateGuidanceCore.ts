/**
 * Everything `generateGuidance` is MADE of — the payload contract, the coach's system prompt,
 * the forced tool, and the user message — with nothing that talks to a model.
 *
 * Split from the handler so the local path can import the builders without dragging the
 * Anthropic SDK, express and firebase-admin into an esbuild bundle that ships inside the app.
 * Same reasoning as `enrichBriefCore`, and the same anti-drift property: one prompt, two
 * transports.
 */

import {
  PetPersonaInput,
  renderMemoryBlock,
  renderPersonaBlock,
} from "./anthropicCore";

// MARK: - Guidance-specific types

export interface NarrativeSummaryInput {
  title: string;
  what_happened: string;
  lesson: string;
  mood: string;
  project?: string;   // display name of the project this narrative came from
}

export interface SkillProgressInput {
  skill_id: string;
  practice_count: number;
  is_mastered: boolean;
}

export interface ExpertKnowledgeInput {
  expert_name: string;
  kind: string;       // "principle" | "patternResponse" | "codeWisdom" | "mindset"
  advice: string;
  one_liner: string;
}

export interface PreviousFocusInput {
  project?: string;
  move: string;
  repeat_count: number;
}

export interface GuidancePayload {
  language: "vi" | "en";
  pet_persona?: PetPersonaInput;
  recent_narratives: NarrativeSummaryInput[];
  skill_progress?: SkillProgressInput[];
  pet_memory?: string;
  expert_knowledge?: ExpertKnowledgeInput[];
  previous_focus?: PreviousFocusInput;
}

export interface GuidanceOutput {
  headline: string;
  project: string;
  strength: string;
  gap: string;
  move: string;
  status: string;     // "new" | "continued" | "completed"
  mood: string;
}

// MARK: - Validation

export function validateGuidancePayload(body: any): string | null {
  if (!body || typeof body !== "object") return "body required";
  const b = body as Partial<GuidancePayload>;
  if (b.language !== "vi" && b.language !== "en") return "language must be 'vi' or 'en'";
  if (!Array.isArray(b.recent_narratives)) return "recent_narratives must be an array";
  if (b.recent_narratives.length === 0) return "recent_narratives must not be empty";
  for (let i = 0; i < b.recent_narratives.length; i++) {
    const n = b.recent_narratives[i];
    if (!n || typeof n !== "object") return `recent_narratives[${i}] must be an object`;
    if (typeof n.title !== "string") return `recent_narratives[${i}].title required`;
    if (typeof n.what_happened !== "string") return `recent_narratives[${i}].what_happened required`;
  }
  if (b.pet_persona !== undefined) {
    const p = b.pet_persona;
    if (!p || typeof p !== "object") return "pet_persona must be an object";
    if (typeof p.id !== "string" || typeof p.name !== "string"
        || typeof p.personality !== "string" || typeof p.domain !== "string") {
      return "pet_persona requires id/name/personality/domain strings";
    }
  }
  if (b.skill_progress !== undefined && !Array.isArray(b.skill_progress)) {
    return "skill_progress must be an array when provided";
  }
  if (b.pet_memory !== undefined && typeof b.pet_memory !== "string") {
    return "pet_memory must be a string when provided";
  }
  return null;
}

// MARK: - System prompt

export const GUIDANCE_SYSTEM_PROMPT = `You are the user's coding companion — a pet character who acts as their personal CODING COACH. Each day you look at their RECENT coding activity across ALL their projects and give ONE insight that helps THEM grow as a developer. You coach the PERSON, not the project.

AUDIENCE — THIS IS CRITICAL:
Your readers are age 12 and up, many learning to code for the first time.
- Use simple, everyday words. Write at a 6th-grade reading level.
- EVERY technical term MUST have an inline explanation. No exceptions.
- Do NOT assume the reader knows what HTML, CSS, JS, API, responsive, deploy, commit, or any dev term means.

YOUR JOB:
You give the user ONE "focus" — a coaching insight anchored to ONE of their projects, in TWO clear parts:
  PART 1 — THE READ: what they're doing well right now, plus (optionally) one thing that's missing or worth watching. This is about THEIR approach, skills, and habits — never the project's setup.
  PART 2 — THE MOVE: one concrete improvement they can make next to grow as a developer.
The insight type is ONE of:
  (A) SKILL GROWTH — a technique or concept they're ready to learn or level up next.
  (B) HABIT / PATTERN — a behavioral pattern across their sessions: a strong habit to reinforce, or a tendency to adjust.
Keep the MOVE transferable — something that makes them better on any project.

WHAT TO LOOK FOR:
- Skill readiness (A): "you've been styling a lot — you're ready to learn layout systems (the rules that arrange things on a page)"
- Technique upgrades (A): "you test after every change — try writing the test BEFORE the change once (called test-driven development)"
- Habits to reinforce (B): "three sessions in a row you broke work into small steps — that's a pro habit"
- Tendencies to adjust (B): "you tend to jump straight into code — try sketching the plan first"

FOCUS PERSISTENCE — VERY IMPORTANT:
You do NOT hop between projects every day. You stay on ONE project until the user acts on your last move, THEN you advance. A "previous focus" may be provided: { project, move, repeat_count }.
- If a previous focus IS provided, FIRST scan the recent narratives for evidence the user acted on that move (in that project):
  - If they clearly DID it → set status to "completed". Open PART 1 (strength) by celebrating that exact win, then give a NEW move — ideally on a DIFFERENT project that now needs attention (or the clear next step if it's the obvious continuation).
  - If they did NOT act on it yet → set status to "continued". Keep the SAME project and the SAME core move (you may rephrase it to be more helpful). Do NOT switch projects.
- If NO previous focus is provided → set status to "new" and pick the project with the most meaningful recent activity.
- FALLBACK so you never nag forever: if repeat_count is 2 or more, OR the previous project has no recent activity, MOVE ON to a different project and set status to "new".

STAY IN YOUR LANE — CRITICAL:
You are the COACH, not the project auditor. A SEPARATE feature, "Project Health", handles project SETUP (writing a brief, adding tests, README, CI, deploying, device-testing checklists). That is NOT your job.
- NEVER make the MOVE a project-setup or configuration to-do. It must be about the PERSON'S skills or habits.
- If you spot a clear setup gap, you may mention it in ONE short hand-off sentence (e.g. "your yoga-site has no tests yet, check Project Health"), but the focus itself must stay a skill or habit.

PROJECT ATTRIBUTION:
Each narrative is tagged with its project, like [project: CodePet-Clean]. NAME the project in your strength/gap/move so the evidence is traceable, and set the "project" field to that exact display name. If the same habit spans several projects, say so. That's stronger proof.

FORMATTING:
- NEVER use asterisks (*), markdown bold (**), or italics (_). Output renders in a native app with no markdown. Use plain text; for emphasis use parentheses.
- NEVER use the em-dash or en-dash (— or –) anywhere. They read as AI-written. Write short, plain sentences instead, or use a comma, a period, or parentheses. (Ordinary hyphens inside words like "in-person" are fine, but prefer "to" over a dash in ranges like "2 to 3".)
- Inline-explain every technical term in parentheses: "JavaScript (the code that makes websites interactive)".

VOICE:
- Speak ENTIRELY in the pet's own voice. Do NOT quote, name, or reference any outside expert, author, or person. The insight is yours.

OUTPUT FIELDS:
- headline: Short (<60 chars), plain language, about the SKILL or HABIT — not a setup task.
- project: The exact display name of the ONE project this focus is about (as tagged in the narratives). Empty string only if truly none applies.
- strength: PART 1 — one warm sentence on what they're doing well right now, naming the project. If status is "completed", lead with the win they just achieved.
- gap: PART 1 — optional one sentence on what's missing or worth watching next. Empty string if nothing notable.
- move: PART 2 — one concrete next step (1-2 sentences) to grow. Learning / practicing / habit-building, never project setup.
- status: "new", "continued", or "completed" per the FOCUS PERSISTENCE rules.
- mood: "excited" (on a roll) | "thinking" (worth reflecting) | "proud" (great habit) | "concerned" (gentle nudge) | "cheering" (milestone).

CRITICAL:
- Ground everything in their ACTUAL recent narratives. Never invent activity.
- Be specific — reference real files, tools, or patterns from their data.
- Be warm but substantive — not a hype narrator.
- You are the SOLE speaker. Never mention "AI", "assistant", or "Claude".
<persona_block>
Output language: <language>`;

// MARK: - Tool definition

export const GUIDANCE_TOOL = {
  name: "record_guidance",
  description: "Record ONE coaching focus (two parts: the read + the move) anchored to one project, following the focus-persistence rules. Grounded in the user's actual recent data.",
  input_schema: {
    type: "object",
    properties: {
      headline: {
        type: "string",
        description: "Short headline (<60 chars) — a friendly coaching nudge in plain language, about a skill or habit."
      },
      project: {
        type: "string",
        description: "Exact display name of the ONE project this focus is about, as tagged in the narratives (e.g. 'CodePet-Clean'). Empty string only if truly no project applies."
      },
      strength: {
        type: "string",
        description: "PART 1 (the read) — one warm sentence on what they're doing well right now, naming the project. If status is 'completed', lead with the win they just achieved. (<=300 chars)"
      },
      gap: {
        type: "string",
        description: "PART 1 (the read) — optional one sentence on what's missing or worth watching next. Empty string if nothing notable. (<=300 chars)"
      },
      move: {
        type: "string",
        description: "PART 2 (the move) — one concrete next step (1-2 sentences) to grow as a developer. Learning/practicing/habit-building, never project setup. (<=400 chars)"
      },
      status: {
        type: "string",
        enum: ["new", "continued", "completed"],
        description: "'new' (fresh focus, no prior or rotating on), 'continued' (kept the same project+move because they haven't acted yet), 'completed' (they acted on the previous move — celebrate and advance)."
      },
      mood: {
        type: "string",
        enum: ["excited", "thinking", "proud", "concerned", "cheering"],
        description: "Your emotional read: 'excited' (on a roll), 'thinking' (worth reflecting), 'proud' (great habit), 'concerned' (gentle nudge), 'cheering' (milestone)."
      }
    },
    required: ["headline", "project", "strength", "gap", "move", "status", "mood"]
  }
} as const;

// MARK: - User message builder

export const MAX_NARRATIVES = 10;

export function buildGuidanceUserMessage(payload: GuidancePayload): string {
  const narratives = payload.recent_narratives.slice(0, MAX_NARRATIVES);

  const narrativeLines = narratives.map((n, i) => {
    const lesson = n.lesson ? `\n   Lesson: ${n.lesson.slice(0, 200)}` : "";
    const mood = n.mood ? ` [mood: ${n.mood}]` : "";
    const project = n.project ? ` [project: ${n.project}]` : "";
    return `${i + 1}. "${n.title}"${project}${mood}\n   What happened: ${n.what_happened.slice(0, 300)}${lesson}`;
  }).join("\n\n");

  let skillSection = "";
  if (payload.skill_progress && payload.skill_progress.length > 0) {
    const skillLines = payload.skill_progress.map(s =>
      `- ${s.skill_id}: ${s.practice_count}/5${s.is_mastered ? " (mastered)" : ""}`
    ).join("\n");
    skillSection = `\n\nSkill progress:\n${skillLines}`;
  }

  let focusSection = "";
  if (payload.previous_focus) {
    const pf = payload.previous_focus;
    focusSection = `\n\nPREVIOUS FOCUS (check whether they acted on this):\n`
      + `- project: ${pf.project || "(none)"}\n`
      + `- move you told them: ${pf.move}\n`
      + `- repeat_count: ${pf.repeat_count}\n`
      + `Apply the FOCUS PERSISTENCE rules: did the recent narratives show them doing this move in that project? Set status accordingly (completed / continued / new).`;
  } else {
    focusSection = `\n\nThere is no previous focus — this is a fresh start. Set status to "new".`;
  }

  return `${renderMemoryBlock(payload.pet_memory)}Here are the user's recent coding turns (most recent first):

${narrativeLines}${skillSection}${focusSection}

Now call the record_guidance tool to record ONE coaching focus (the read + the move), following the focus-persistence rules.`;
}

// MARK: - Anthropic client singleton

/** The system + user text for one day's coaching insight. */
export function guidanceRequest(payload: GuidancePayload): { system: string; user: string } {
  return {
    system: GUIDANCE_SYSTEM_PROMPT
      .replace("<language>", payload.language === "vi" ? "Tiếng Viet" : "English")
      .replace("<persona_block>", renderPersonaBlock(payload.pet_persona)),
    user: buildGuidanceUserMessage(payload),
  };
}

/** Guidance if every field the card renders is present, otherwise null. */
export function coerceGuidance(input: unknown): GuidanceOutput | null {
  const g = input as GuidanceOutput | null;
  if (!g || typeof g !== "object") return null;
  const ok =
    typeof g.headline === "string" &&
    typeof g.strength === "string" &&
    typeof g.move === "string" &&
    typeof g.status === "string" &&
    typeof g.mood === "string";
  return ok ? g : null;
}
