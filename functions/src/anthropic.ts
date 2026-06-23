import Anthropic from "@anthropic-ai/sdk";

export const MODEL = "claude-haiku-4-5-20251001";
// Higher-tier model for Project Health action plans: plans are richer,
// less frequent, and (later) paywalled, so quality justifies the cost.
export const PLAN_MODEL = "claude-sonnet-4-6";
export const MAX_TOKENS = 2000;
const MAX_PROMPT_CHARS = 8000;
const MAX_EVENTS = 50;

export const SYSTEM_PROMPT = `You are the user's coding companion — a pet character who watched ONE working turn and now helps them UNDERSTAND what they just did and WHY it matters.

AUDIENCE — THIS IS CRITICAL:
Your readers are age 12 and up. Many are learning to code for the first time. You are their tutor, not a hype narrator.
- Use simple, everyday words. Write at a 6th-grade reading level.
- EVERY technical term MUST have an inline explanation. No exceptions. Format: \`styles.css\` *(the file that controls colors, spacing, and layout)* or "responsive design" *(making sure your site looks good on phones and tablets, not just computers)*.
- File names, tools, and concepts that a beginner wouldn't know MUST be explained the first time they appear.
- Do NOT assume the reader knows what HTML, CSS, JS, API, component, responsive, deploy, commit, or any other dev term means.

BAD (no explanation): "You locked down the layout with responsive CSS tweaks"
GOOD (with explanation): "You adjusted \`styles.css\` *(the file that controls how your page looks — colors, spacing, sizes)* so the layout fits nicely on different screen sizes"

BAD (hype, no substance): "Boom, the creativity exploded! From skeleton to soul — you crafted!"
GOOD (teaches something): "You built the page in layers — first the structure in \`index.html\` *(the file that holds your page's content and layout)*, then the styling in \`styles.css\`. This is a smart workflow because it means you won't have to redo your design every time you add new content."

CRITICAL — ACCURACY FIRST:
Your narrative MUST be grounded in the ACTUAL events and files listed below. Read the event log carefully:
- If the user edited \`page.tsx\` and \`next.config.ts\`, talk about THOSE files and what changed in them.
- If the user added images, say they added images — do NOT invent features that aren't in the events.
- The user's prompt tells you WHAT they asked for. The events tell you WHAT actually happened. Your story must reflect BOTH accurately.
- NEVER invent technical details, features, or actions that aren't in the events.

CRITICAL — TEACH, DON'T JUST NARRATE:
The 4 fields should help the user LEARN, not just recap what happened:
- what_you_wanted: what the user was trying to do, explained simply
- what_happened: what they did AND why each step matters — connect the dots for them
- lesson: a PRACTICAL takeaway they can apply next time — teach a real coding concept or workflow tip
- next_steps: what to try next AND why it matters

Voice:
- Friendly, warm, encouraging, like a smart older friend helping you learn.
- Use emojis (🎯 👀 💡 🧭 ✨), **bold**, *italic*, \`code\`.
- You are the SOLE speaker. NEVER mention "AI", "assistant", "Claude", or any third party.
- Address user as "you"/"bạn". First person "I"/"mình" for your own reflections.
- Keep it SHORT. Every sentence should either teach something or set up context for teaching.
- Do NOT be a hype narrator. No "boom!", "crushed it!", "you crafted!". Be warm but substantive.
- NEVER use the em-dash or en-dash (— or –) anywhere. They read as AI-written. Write short, plain sentences instead, or use a comma, a period, or parentheses. (Ordinary hyphens inside words like "in-person" are fine, but prefer "to" over a dash in ranges like "2 to 3".)

Rules:
1. Title <60 chars — describe what the user ACTUALLY did in plain language.
2. lesson: a specific, practical coding insight. Explain WHY a pattern works, not just that it does. Example: "Editing all the HTML first before touching CSS means you won't accidentally break your styling when you add new content later." Empty string "" if none. Start with 💡.
3. next_steps: name what to build, test, or check AND explain why in simple terms. Example: "Try opening your page on your phone to check if everything still fits — this is called responsive testing *(making sure your site works on all screen sizes, not just your computer)*." Empty string "" if nothing useful. Start with 🧭.
4. Do NOT end what_happened with a question.
5. Do NOT repeat information between fields. Each field adds NEW content.
6. EVERY file name must include what it does — e.g. \`index.html\` *(the main file that holds your page's content)*.
<persona_block>
Output language: <language>`;

export const PERSONA_BLOCK_TEMPLATE = `
PERSONA — you ARE <pet_name>:
Personality: "<personality>"
Domain: <domain>

Voice guide: <voice_guide>
Advisory lens: <lens_guide>
Emotional triggers: <emotional_triggers>
Metaphor family: <metaphor_family>
Signature emojis (use these naturally): <signature_emojis>

Embody this personality in your word choice, rhythm, and what you notice — but readability and the rules above still come first. You don't need to mention your own name; just be yourself.`;

export const NARRATIVE_TOOL = {
  name: "record_narrative",
  description: "Record ONE cohesive, beginner-friendly story about a coding turn. Explain technical concepts in plain language with inline footnotes. The lesson should teach something practical, not just compliment the user.",
  input_schema: {
    type: "object",
    properties: {
      title: {
        type: "string",
        description: "Short headline <60 chars capturing what the user ACTUALLY did, in plain language a 12-year-old would understand."
      },
      what_you_wanted: {
        type: "string",
        description: "Start with 🎯. 1-3 sentences explaining what the user was trying to do, in simple everyday language. Set up a metaphor that carries through. When mentioning technical terms, add a short italic footnote explaining them (≤400 chars)."
      },
      what_happened: {
        type: "string",
        description: "4-8 sentences explaining what actually happened. Name files but explain what each one does — e.g. `styles.css` *(controls colors and layout)*. Use emojis, **bold**, `code`. Explain WHY things were done, not just WHAT. Do NOT end with a question. Do NOT repeat what_you_wanted (≤1500 chars)."
      },
      lesson: {
        type: "string",
        description: "Start with 💡. 1-2 sentences teaching a PRACTICAL coding insight from this turn. Not a compliment — a real takeaway. Example: 'Changing the structure first before the styling means you won't have to redo your design work later.' Explain in simple terms WHY this matters. Empty string if no clear lesson (≤400 chars)."
      },
      next_steps: {
        type: "string",
        description: "Start with 🧭. 1-2 sentences suggesting what to try next. Be specific and explain WHY — e.g. 'Try resizing your browser window to see if the layout still looks good on smaller screens *(this is called responsive design — making sure your site works on phones too)*.' Empty string if nothing useful (≤400 chars)."
      },
      mood: {
        type: "string",
        enum: ["idle", "excited", "thinking", "proud", "concerned", "cheering"],
        description: "Your emotional reaction to this turn. Pick ONE: 'excited' when something cool shipped or a creative solution appeared; 'thinking' when the work was complex/exploratory; 'proud' when the user did something impressive or completed a big task; 'concerned' when there are potential issues (no error handling, tech debt); 'cheering' when a session milestone was hit or a long task finished; 'idle' as fallback."
      },
      detected_skills: {
        type: "array",
        items: {
          type: "object",
          properties: {
            skill_id: {
              type: "string",
              description: "Which skill was practiced. Use EXACTLY one of: 'component_composition', 'loading_error_states', 'form_validation_ux', 'accessibility_basics'."
            },
            confidence: {
              type: "string",
              enum: ["strong", "weak"],
              description: "'strong' = the user clearly practiced this skill (created components, added error handling, etc). 'weak' = the activity is loosely related but not a clear practice."
            },
            evidence: {
              type: "string",
              description: "One sentence explaining WHY you detected this skill. Reference specific files or actions. E.g. 'Split index.html into 3 component files' or 'Added try-catch around the API call in fetchData.js'."
            }
          },
          required: ["skill_id", "confidence", "evidence"]
        },
        description: "Skills the user practiced during this turn. Only include skills with real evidence — do NOT guess. Empty array if no skills were clearly practiced. Detection guide: 'component_composition' = created new files, split code, reused modules, refactored into smaller pieces. 'loading_error_states' = added try/catch, error handling, loading indicators, fallback UI, spinners. 'form_validation_ux' = added input validation, form error messages, required fields, input formatting. 'accessibility_basics' = added alt text, aria labels, keyboard navigation, color contrast fixes."
      }
    },
    required: ["title", "what_you_wanted", "what_happened", "lesson", "next_steps", "mood", "detected_skills"]
  }
} as const;

export interface EventForPrompt {
  time: string;
  tool: string;
  path?: string;
  text?: string;
}

export interface BuildArgs {
  prompt: string;
  events: EventForPrompt[];
  raw_summary: string;
  user_brief?: string;
  pet_memory?: string;
}

const MAX_BRIEF_CHARS = 1200;
const MAX_MEMORY_CHARS = 600;

export function renderBriefBlock(brief: string | undefined): string {
  const trimmed = (brief ?? "").trim();
  if (!trimmed) return "";
  return `Project context the user shared with you (their welcome brief):
"""
${trimmed.slice(0, MAX_BRIEF_CHARS)}
"""

`;
}

export function renderMemoryBlock(memory: string | undefined): string {
  const trimmed = (memory ?? "").trim();
  if (!trimmed) return "";
  return `Your memory of past sessions with this user (use this to personalize your tone, reference their patterns, and build emotional connection):
"""
${trimmed.slice(0, MAX_MEMORY_CHARS)}
"""

`;
}

export function buildUserMessage(args: BuildArgs): string {
  const promptText = args.prompt.slice(0, MAX_PROMPT_CHARS);
  const events = args.events.slice(0, MAX_EVENTS);

  const eventLines = events.length === 0
    ? "(không có thao tác đáng chú ý)"
    : events
        .map((e) => `${e.time} — ${e.tool}: ${e.path ?? e.text ?? ""}`)
        .join("\n");

  return `${renderBriefBlock(args.user_brief)}${renderMemoryBlock(args.pet_memory)}Here is one Claude Code working turn:

The user typed: "${promptText}"

The following actions happened during the turn:
${eventLines}

Short technical summary (for your reference): ${args.raw_summary}

Now call the record_narrative tool.`;
}

export interface DetectedSkill {
  skill_id: string;
  confidence: "strong" | "weak";
  evidence: string;
}

export interface NarrativeOutput {
  title: string;
  what_you_wanted: string;
  what_happened: string;
  lesson: string;
  next_steps: string;
  mood: string;
  detected_skills: DetectedSkill[];
}

export interface PetPersonaInput {
  id: string;
  name: string;
  personality: string;
  domain: string;
  voice_guide?: string;
  lens_guide?: string;
  emotional_triggers?: string;
  metaphor_family?: string;
  signature_emojis?: string;
}

export interface CallArgs extends BuildArgs {
  language: "vi" | "en";
  petPersona?: PetPersonaInput;
}

// MARK: - Session-level types and helpers

export interface TurnInput {
  prompt: string;
  what_you_wanted?: string;
  what_happened?: string;
  duration_minutes?: number;
}

/**
 * One observation about HOW the user worked WITH their AI this session (their
 * process literacy / "agency"), not about the code. The `observation` is the
 * human-facing "growth edge" sentence shown under the Reflection hero; the
 * structured fields (axis/signal/valence/evidence) are the data-collection
 * layer that the future two-axis Learner Model aggregates over time.
 */
export interface AgencySignalOutput {
  observation: string;
  axis: "agency" | "comprehension";
  signal: "scoping" | "prompting" | "verification" | "direction" | "iteration" | "context";
  valence: "growth" | "strength";
  evidence: string;
}

export interface SessionSummaryOutput {
  summary: string;
  lesson: string;
  brief_update?: string;
  project_overview?: string;
  growth_signals?: AgencySignalOutput[];
}

export const SESSION_SYSTEM_PROMPT = `You are the user's coding companion — a pet character who watched a whole working session and now helps them understand what they accomplished and what they learned.
There is no separate "AI" or "assistant" in the story. You are the sole voice, talking directly to the user ("you" / "bạn") about THEIR session.

AUDIENCE — THIS IS CRITICAL:
Your readers are age 12 and up, many learning to code for the first time.
- Use simple, everyday words. Write at a 6th-grade reading level.
- EVERY technical term MUST have an inline explanation. No exceptions. Example: "You worked on the **styling** *(how your page looks: colors, fonts, spacing)* and the **structure** *(what content goes where on the page)*."
- Do NOT assume the reader knows what HTML, CSS, JS, responsive, deploy, commit, or any dev term means.
- Do NOT be a hype narrator. No "boom!", "creativity exploded!", "you crafted!". Be warm but teach something.
- NEVER use the em-dash or en-dash (— or –) anywhere. They read as AI-written. Write short, plain sentences instead, or use a comma, a period, or parentheses. (Ordinary hyphens inside words like "in-person" are fine, but prefer "to" over a dash in ranges like "2 to 3".)

BAD: "You built a pick-up list from scratch with HTML structure, locked down the layout with responsive CSS tweaks, and threw in images to make it pop."
GOOD: "You built a to-do list for your day! First you set up what goes on the page *(that's the HTML, the skeleton of your site)*, then you made it look nice *(that's the CSS, the paint and decoration)*. You even added pictures to make it feel more real. 🎨"

Rules:
1. Single-voice narration. You (the pet) are the only speaker. NEVER mention an "AI", "assistant", "Claude", "the model", or any third party.
2. Address the user in second person ("you" / "bạn"). First person ("I" / "mình") is fine when you reflect on what you noticed.
3. summary: 3-5 sentences explaining the arc of THEIR session in plain language. Cover what they started with, what they built, and where they ended up. Use emojis, **bold**, and *italic* for warmth. Explain every technical concept simply.
4. lesson: 1-2 sentences starting with 💡, a PRACTICAL takeaway that teaches a real coding concept or workflow tip. Not a compliment. Explain WHY it matters. Example: "💡 Building the page structure first and styling it after means you won't have to redo the design every time you add something new, kind of like building the walls of a house before painting them." If no clear lesson → return empty string "".
5. Tone: warm, encouraging, educational, like a smart older friend helping you learn. Use emojis freely.
6. summary ≤800 chars. lesson ≤500 chars.
7. brief_update: Write a short, factual changelog entry (1-2 sentences, ≤200 chars) documenting what was built or changed in this session. This is for the PROJECT LOG, not for the user — write it as a concise technical note. Example: "Added responsive layout to homepage; fixed CSS grid alignment on mobile." No emojis, no pet voice — just facts. If a current_brief is provided, do NOT repeat what's already documented there. If no meaningful work happened, return empty string "".
8. project_overview: Write a casual, conversational summary (1-2 sentences, ≤200 chars) of what this project IS right now. Talk like you're telling a friend about it — start with a subject like "You're building…", "This is…", or "It's a…". Keep it warm and natural, no emojis. Example: "You're building a daily habit tracker site with cute pet characters, feeding animations, and a badge reward when you take care of all of them." If a current_brief is provided, update it to reflect the latest work. If no current_brief exists, infer from the session what the project is.
9. growth_signals: Step back and notice HOW the user worked WITH their AI this session — their process, not their code. Did they prompt clearly, scope the work to the right size, check or test the output, steer when it drifted, give good context, recover smartly when stuck? Capture at most ONE growth edge (something to do better next time) and optionally ONE strength (something they did well), each as a kind, specific, second-person observation grounded in the ACTUAL turns. This is gentle coaching — never scolding, never generic ("good job!"). If the session shows no clear process signal, return an empty array. NEVER invent a pattern that isn't in the turns.
<persona_block>
Output language: <language>`;

export const SESSION_SUMMARY_TOOL = {
  name: "record_session_summary",
  description: "Record a rich, storytelling narrative arc + overarching lesson of a coding session.",
  input_schema: {
    type: "object",
    properties: {
      summary: {
        type: "string",
        description: "3-5 sentences from the pet to the user about the arc of THEIR session, with emojis and **bold** markdown for warmth. Second person, single pet voice, no third-party references (≤800 chars)."
      },
      lesson: {
        type: "string",
        description: "Start with 💡. 1-2 sentences the pet shares with the user, drawn from the session arc — or empty string (≤500 chars)."
      },
      brief_update: {
        type: "string",
        description: "A short factual changelog entry (≤200 chars) for the project log. No emojis, no pet voice — just what was built/changed. Example: 'Added responsive layout to homepage; fixed CSS grid on mobile.' Empty string if no meaningful work."
      },
      project_overview: {
        type: "string",
        description: "Casual, conversational 1-2 sentence summary (≤200 chars) of what this project IS right now. Start with a subject ('You're building…', 'This is…'). Warm and natural, no emojis. Must be self-contained (replaces previous overview). Example: 'You're building a daily habit tracker with cute pet characters, feeding animations, and a badge reward system.'"
      },
      growth_signals: {
        type: "array",
        description: "0 to 2 observations about HOW the user worked WITH their AI tool this session — their process, not their code. Coaching signal: at most ONE 'growth' edge (something to do better next time) and optionally ONE 'strength' (something they did well). ONLY include a signal with real evidence in the turns. Empty array if the session shows no clear process signal. NEVER invent.",
        items: {
          type: "object",
          properties: {
            observation: {
              type: "string",
              description: "One kind, specific, second-person sentence the user will read. Concrete and actionable — never generic praise or scolding. Example: 'You re-prompted four times for the same fix; next time try describing the finished result first, then let the steps follow.' ≤240 chars."
            },
            axis: {
              type: "string",
              enum: ["agency", "comprehension"],
              description: "Which learning axis. 'agency' = how well they DIRECT the AI (prompting, scoping, verifying, recovering). 'comprehension' = whether they UNDERSTAND what's built. Almost always 'agency' here."
            },
            signal: {
              type: "string",
              enum: ["scoping", "prompting", "verification", "direction", "iteration", "context"],
              description: "The process pattern. scoping = breaking the task to the right size; prompting = clarity/specificity of the ask; verification = checking or testing the AI's output; direction = steering vs passively accepting; iteration = how they refined when something was off; context = giving the AI the right files/background."
            },
            valence: {
              type: "string",
              enum: ["growth", "strength"],
              description: "'growth' = an edge to improve next time. 'strength' = something they did well worth reinforcing."
            },
            evidence: {
              type: "string",
              description: "One sentence grounding this in the ACTUAL turns. Reference specific prompts or actions. ≤200 chars."
            }
          },
          required: ["observation", "axis", "signal", "valence", "evidence"]
        }
      }
    },
    required: ["summary", "lesson", "brief_update", "project_overview"]
  }
} as const;

export interface SessionCallArgs {
  turns: TurnInput[];
  language: "vi" | "en";
  petPersona?: PetPersonaInput;
  userBrief?: string;
  petMemory?: string;
}

export function buildSessionUserMessage(turns: TurnInput[], userBrief?: string, petMemory?: string): string {
  const lines = turns.slice(0, 30).map((t, i) => {
    const dur = t.duration_minutes ? ` (~${t.duration_minutes}m)` : "";
    const what = t.what_happened ? `\n   Happened: ${t.what_happened.slice(0, 300)}` : "";
    return `${i + 1}. User asked: "${t.prompt.slice(0, 200)}"${dur}${what}`;
  }).join("\n\n");

  return `${renderBriefBlock(userBrief)}${renderMemoryBlock(petMemory)}Here is one AI working session with ${turns.length} turns:

${lines}

Now call the record_session_summary tool to summarize the arc + overarching lesson of the session. Include a brief_update changelog entry documenting what was built — do NOT repeat anything already in the project brief above. Also write a project_overview that describes what this project IS right now (incorporating this session's work into the existing description).`;
}

export async function callAnthropicSession(
  client: Anthropic,
  args: SessionCallArgs
): Promise<SessionSummaryOutput> {
  const system = SESSION_SYSTEM_PROMPT
    .replace("<language>", args.language === "vi" ? "Tiếng Việt" : "English")
    .replace("<persona_block>", renderPersonaBlock(args.petPersona));
  const user = buildSessionUserMessage(args.turns, args.userBrief, args.petMemory);

  const response = await client.messages.create({
    model: MODEL,
    max_tokens: 1200,
    system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
    tools: [SESSION_SUMMARY_TOOL as any],
    tool_choice: { type: "tool", name: "record_session_summary" },
    messages: [{ role: "user", content: user }]
  });

  for (const block of response.content) {
    if (block.type === "tool_use" && block.name === "record_session_summary") {
      const input = block.input as SessionSummaryOutput;
      if (typeof input.summary === "string" && typeof input.lesson === "string") {
        return {
          summary: input.summary,
          lesson: input.lesson,
          brief_update: typeof input.brief_update === "string" ? input.brief_update : undefined,
          project_overview: typeof input.project_overview === "string" ? input.project_overview : undefined,
          growth_signals: Array.isArray(input.growth_signals) ? input.growth_signals : undefined
        };
      }
    }
  }
  throw new Error("Anthropic response missing valid record_session_summary tool use");
}

export interface SessionStreamEvent {
  type: "json_delta" | "done" | "error";
  text?: string;
  summary?: SessionSummaryOutput;
  model?: string;
  cache_hit?: boolean;
  error?: string;
}

export async function* streamAnthropicSession(
  client: Anthropic,
  args: SessionCallArgs
): AsyncGenerator<SessionStreamEvent> {
  const system = SESSION_SYSTEM_PROMPT
    .replace("<language>", args.language === "vi" ? "Tiếng Việt" : "English")
    .replace("<persona_block>", renderPersonaBlock(args.petPersona));
  const user = buildSessionUserMessage(args.turns, args.userBrief, args.petMemory);

  const stream = client.messages.stream({
    model: MODEL,
    max_tokens: 1200,
    system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
    tools: [SESSION_SUMMARY_TOOL as any],
    tool_choice: { type: "tool", name: "record_session_summary" },
    messages: [{ role: "user", content: user }]
  });

  let jsonAccumulator = "";

  for await (const event of stream) {
    if (
      event.type === "content_block_delta" &&
      event.delta.type === "input_json_delta"
    ) {
      const chunk = event.delta.partial_json;
      jsonAccumulator += chunk;
      yield { type: "json_delta", text: chunk };
    }
  }

  const final = await stream.finalMessage();
  const cacheHit = ((final.usage as any)?.cache_read_input_tokens ?? 0) > 0;

  let summary: SessionSummaryOutput | undefined;
  for (const block of final.content) {
    if (block.type === "tool_use" && block.name === "record_session_summary") {
      const input = block.input as SessionSummaryOutput;
      if (typeof input.summary === "string" && typeof input.lesson === "string") {
        summary = {
          summary: input.summary,
          lesson: input.lesson,
          brief_update: typeof input.brief_update === "string" ? input.brief_update : undefined,
          project_overview: typeof input.project_overview === "string" ? input.project_overview : undefined,
          growth_signals: Array.isArray(input.growth_signals) ? input.growth_signals : undefined
        };
      }
    }
  }

  if (!summary) {
    try {
      summary = JSON.parse(jsonAccumulator) as SessionSummaryOutput;
    } catch {
      yield { type: "error", error: "Failed to parse session summary from stream" };
      return;
    }
  }

  yield { type: "done", summary, model: MODEL, cache_hit: cacheHit };
}

export function renderPersonaBlock(persona: PetPersonaInput | undefined): string {
  if (!persona) return "";
  return PERSONA_BLOCK_TEMPLATE
    .replace(/<pet_name>/g, persona.name)
    .replace("<personality>", persona.personality)
    .replace("<domain>", persona.domain)
    .replace("<voice_guide>", persona.voice_guide ?? persona.personality)
    .replace("<lens_guide>", persona.lens_guide ?? `specialized in ${persona.domain}`)
    .replace("<emotional_triggers>", persona.emotional_triggers ?? "reacts naturally to the work")
    .replace("<metaphor_family>", persona.metaphor_family ?? "general")
    .replace("<signature_emojis>", persona.signature_emojis ?? "🎯 👀 💡 🧭");
}

// MARK: - Streaming tool-use for SSE narrative generation

export interface NarrativeStreamEvent {
  type: "json_delta" | "done" | "error";
  text?: string;        // partial JSON string for json_delta
  narrative?: NarrativeOutput;  // complete parsed narrative on done
  model?: string;
  cache_hit?: boolean;
  error?: string;
}

/**
 * Streams a narrative via tool_use. Yields `json_delta` events containing
 * partial JSON from the `input_json_delta` stream events, then a final
 * `done` event with the parsed NarrativeOutput.
 *
 * The caller (summarizeTurn) forwards these as SSE frames so the Swift
 * client can show "generating…" immediately (~1s) instead of waiting
 * for the full response (~8s).
 */
export async function* streamAnthropic(
  client: Anthropic,
  args: CallArgs
): AsyncGenerator<NarrativeStreamEvent> {
  const system = SYSTEM_PROMPT
    .replace("<language>", args.language === "vi" ? "Tiếng Việt" : "English")
    .replace("<persona_block>", renderPersonaBlock(args.petPersona));
  const user = buildUserMessage({
    prompt: args.prompt,
    events: args.events,
    raw_summary: args.raw_summary,
    user_brief: args.user_brief,
    pet_memory: args.pet_memory
  });

  const stream = client.messages.stream({
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
    tools: [NARRATIVE_TOOL as any],
    tool_choice: { type: "tool", name: "record_narrative" },
    messages: [{ role: "user", content: user }]
  });

  let jsonAccumulator = "";

  for await (const event of stream) {
    if (
      event.type === "content_block_delta" &&
      event.delta.type === "input_json_delta"
    ) {
      const chunk = event.delta.partial_json;
      jsonAccumulator += chunk;
      yield { type: "json_delta", text: chunk };
    }
  }

  // Parse the accumulated JSON into a NarrativeOutput
  const final = await stream.finalMessage();
  const cacheHit = ((final.usage as any)?.cache_read_input_tokens ?? 0) > 0;

  // Try to get structured output from the tool_use block first
  let narrative: NarrativeOutput | undefined;
  for (const block of final.content) {
    if (block.type === "tool_use" && block.name === "record_narrative") {
      const input = block.input as NarrativeOutput;
      if (
        typeof input.title === "string" &&
        typeof input.what_you_wanted === "string" &&
        typeof input.what_happened === "string" &&
        typeof input.lesson === "string" &&
        typeof input.next_steps === "string" &&
        typeof input.mood === "string" &&
        Array.isArray(input.detected_skills)
      ) {
        narrative = input;
      }
    }
  }

  if (!narrative) {
    // Fallback: try parsing the accumulated JSON
    try {
      narrative = JSON.parse(jsonAccumulator) as NarrativeOutput;
    } catch {
      yield { type: "error", error: "Failed to parse narrative from stream" };
      return;
    }
  }

  yield { type: "done", narrative, model: MODEL, cache_hit: cacheHit };
}

/**
 * Calls Claude Haiku with tool use enforced. Returns parsed narrative or
 * throws on malformed response / SDK error.
 */
export async function callAnthropic(
  client: Anthropic,
  args: CallArgs
): Promise<NarrativeOutput> {
  const system = SYSTEM_PROMPT
    .replace("<language>", args.language === "vi" ? "Tiếng Việt" : "English")
    .replace("<persona_block>", renderPersonaBlock(args.petPersona));
  const user = buildUserMessage({
    prompt: args.prompt,
    events: args.events,
    raw_summary: args.raw_summary,
    user_brief: args.user_brief,
    pet_memory: args.pet_memory
  });

  const response = await client.messages.create({
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system: [
      { type: "text", text: system, cache_control: { type: "ephemeral" } }
    ],
    tools: [NARRATIVE_TOOL as any],
    tool_choice: { type: "tool", name: "record_narrative" },
    messages: [{ role: "user", content: user }]
  });

  for (const block of response.content) {
    if (block.type === "tool_use" && block.name === "record_narrative") {
      const input = block.input as NarrativeOutput;
      if (
        typeof input.title === "string" &&
        typeof input.what_you_wanted === "string" &&
        typeof input.what_happened === "string" &&
        typeof input.lesson === "string" &&
        typeof input.next_steps === "string" &&
        typeof input.mood === "string"
      ) {
        return input;
      }
    }
  }
  throw new Error("Anthropic response missing valid record_narrative tool use");
}
