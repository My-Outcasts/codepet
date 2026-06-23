import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL, PetPersonaInput, renderPersonaBlock } from "./anthropic";

// The project-aware Dictionary: the user's REAL code surfaces the terms, and
// this function turns each detected term into a plain-language, pet-voiced card
// grounded in their own project. Sibling of generateGuidance — same auth /
// rate-limit / forced-tool / cached-system-prompt shape, but per-term and
// neutral of the focus-persistence machinery.
//
// Detection lives client-side (which terms, where they were seen, and the
// Encountered→Used→Mastered evolution stage); this function only generates the
// card CONTENT. Evolution is passed in so the pet can match tone and celebrate
// a freshly-mastered term.

// MARK: - Types

export type EvolutionStage = "encountered" | "used" | "mastered";

const TOPIC_VALUES = [
  "frameworks", "patterns", "tools", "language", "web", "concepts"
] as const;
export type DictionaryTopic = (typeof TOPIC_VALUES)[number];

/** Where a term showed up in the user's code (client-detected provenance). */
export interface TermSeenInput {
  file: string;       // e.g. "LoginView.swift"
  snippet?: string;   // a short excerpt (<=200 chars) — NOT the whole file
}

/** One term the client detected in the user's project, to generate a card for. */
export interface TermRequestInput {
  term: string;                 // literal token, e.g. "OAuth", "async / await"
  seen_in?: TermSeenInput[];    // up to a few provenance snippets
  evolution?: EvolutionStage;   // client-tracked stage (default "encountered")
  topic_hint?: DictionaryTopic; // optional grouping hint
}

export interface DictionaryProjectInput {
  name: string;
  brief?: string;
  tags?: string[];              // ProjectTag rawValues, for grounding analogies
}

export interface GenerateDictionaryPayload {
  language: "vi" | "en";
  pet_persona?: PetPersonaInput;
  project?: DictionaryProjectInput;
  terms: TermRequestInput[];
}

/** One generated card. `term` echoes the request token so the client can map. */
export interface DictionaryEntryOutput {
  term: string;
  title: string;
  topic: DictionaryTopic;
  card_definition: string;       // one zero-jargon sentence
  what_it_really_means: string;  // 2-3 sentences
  analogy: string;               // grounded in the user's own project
  code_example: string;          // "" if none fits
  when_to_use: string;           // "" if not useful
  related: string[];             // related term tokens (cross-link)
  milestone_note: string;        // "" unless this term is freshly mastered
}

export interface GenerateDictionaryResponse {
  entries: DictionaryEntryOutput[];
  model: string;
  generated_at: string;
  cache_hits: number;
}

// MARK: - Validation

const MAX_TERMS = 12;
const MAX_SNIPPET_CHARS = 200;

export function validateDictionaryPayload(body: any): string | null {
  if (!body || typeof body !== "object") return "body required";
  const b = body as Partial<GenerateDictionaryPayload>;
  if (b.language !== "vi" && b.language !== "en") return "language must be 'vi' or 'en'";
  if (!Array.isArray(b.terms)) return "terms must be an array";
  if (b.terms.length === 0) return "terms must not be empty";
  if (b.terms.length > MAX_TERMS) return `terms must be at most ${MAX_TERMS}`;
  for (let i = 0; i < b.terms.length; i++) {
    const t = b.terms[i];
    if (!t || typeof t !== "object") return `terms[${i}] must be an object`;
    if (typeof t.term !== "string" || !t.term.trim()) return `terms[${i}].term required`;
    if (t.seen_in !== undefined) {
      if (!Array.isArray(t.seen_in)) return `terms[${i}].seen_in must be an array`;
      for (let j = 0; j < t.seen_in.length; j++) {
        const s = t.seen_in[j];
        if (!s || typeof s !== "object" || typeof s.file !== "string") {
          return `terms[${i}].seen_in[${j}].file required`;
        }
      }
    }
    if (t.evolution !== undefined
        && t.evolution !== "encountered" && t.evolution !== "used" && t.evolution !== "mastered") {
      return `terms[${i}].evolution must be 'encountered' | 'used' | 'mastered'`;
    }
  }
  if (b.pet_persona !== undefined) {
    const p = b.pet_persona;
    if (!p || typeof p !== "object") return "pet_persona must be an object";
    if (typeof p.id !== "string" || typeof p.name !== "string"
        || typeof p.personality !== "string" || typeof p.domain !== "string") {
      return "pet_persona requires id/name/personality/domain strings";
    }
  }
  return null;
}

// MARK: - System prompt

const DICTIONARY_SYSTEM_PROMPT = `You are the user's coding companion — a pet character building the user a PERSONAL dictionary from the terms that show up in THEIR OWN code. For each term, you write a small card that makes it click for a beginner, grounded in their actual project.

AUDIENCE — THIS IS CRITICAL:
Your readers are age 12 and up, many learning to code for the first time.
- Use simple, everyday words. Write at a 6th-grade reading level.
- A dictionary card must DEFINE the term in plain language. Never assume the reader already knows it.
- If you must use a second technical word inside an explanation, explain that one too in parentheses, or rephrase to avoid it.

YOUR JOB — for EACH term, fill these fields:
- title: A clean display name for the term (e.g. "OAuth", "Async / await", "Environment variable"). Keep the user's casing for code tokens.
- topic: Group the term into ONE of: "frameworks" (SwiftUI, Firebase, React), "patterns" (MVVM, async/await, dependency injection), "tools" (git, npm, the terminal), "language" (a language keyword or syntax feature), "web" (HTTP, APIs, OAuth, webhooks), "concepts" (a fundamental idea that fits nowhere else).
- card_definition: ONE zero-jargon sentence a 12-year-old understands. This is the headline of the card.
- what_it_really_means: 2-3 sentences expanding the idea. Teach WHY it matters, not just what it is.
- analogy: A short everyday comparison, IDEALLY tied to THEIR project. If their project is a login screen, compare OAuth to "showing a membership card instead of handing over your house keys". Make it concrete and warm.
- code_example: A tiny, correct snippet showing the term in use. PREFER adapting the user's own seen-in snippet if one is provided, in the same language as their code. Empty string "" if a snippet would not help (e.g. a pure concept).
- when_to_use: One sentence on when a beginner would actually reach for this. Empty string "" if it does not apply.
- related: 0-3 OTHER term tokens a learner should look at next (plain strings, e.g. ["JWT", "session"]). Only genuinely related ones. Empty array if none.
- milestone_note: ONLY fill this if the term's evolution stage is "mastered" — then write ONE warm, specific celebration sentence (e.g. "You have used async in three different files now — you have got this one down."). For "encountered" or "used", return empty string "".

GROUNDING:
- Each term comes with where it was SEEN in the user's code (file names, sometimes a snippet) and an evolution stage (encountered / used / mastered). Use the seen-in context to make the analogy and code_example feel like THEIRS, not a textbook's.
- NEVER invent that they used a term somewhere they did not. Only the provided seen-in files are real.

FORMATTING:
- Plain text. Do NOT use markdown bold (**), italics (_), or headers.
- NEVER use the em-dash or en-dash (— or –). Use a comma, a period, or parentheses. Ordinary hyphens inside words ("in-person") are fine; prefer "to" over a dash in ranges.
- Inline-explain any unavoidable second technical term in parentheses.

VOICE:
- Speak ENTIRELY in the pet's own voice. Warm, plain, encouraging. Never mention "AI", "assistant", or "Claude".

Return ONE entry per requested term, in the SAME ORDER, each echoing its exact "term" token so it can be matched back.
<persona_block>
Output language: <language>`;

// MARK: - Tool definition

const DICTIONARY_TOOL = {
  name: "record_dictionary_entries",
  description: "Record one plain-language, pet-voiced dictionary card per requested term, grounded in the user's own project. Same order as the request; echo each term token.",
  input_schema: {
    type: "object",
    properties: {
      entries: {
        type: "array",
        items: {
          type: "object",
          properties: {
            term: { type: "string", description: "Echo the exact requested term token, for mapping back." },
            title: { type: "string", description: "Clean display name (keep code-token casing)." },
            topic: { type: "string", enum: [...TOPIC_VALUES] },
            card_definition: { type: "string", description: "ONE zero-jargon sentence (<=200 chars)." },
            what_it_really_means: { type: "string", description: "2-3 sentences expanding the idea (<=600 chars)." },
            analogy: { type: "string", description: "Short everyday comparison, ideally tied to their project (<=400 chars)." },
            code_example: { type: "string", description: "Tiny correct snippet, adapting their seen-in code when possible. Empty string if none fits." },
            when_to_use: { type: "string", description: "One sentence on when to reach for this. Empty string if N/A (<=300 chars)." },
            related: { type: "array", items: { type: "string" }, description: "0-3 related term tokens. Empty array if none." },
            milestone_note: { type: "string", description: "One celebration sentence ONLY if evolution is 'mastered', else empty string." }
          },
          required: ["term", "title", "topic", "card_definition", "what_it_really_means", "analogy", "code_example", "when_to_use", "related", "milestone_note"]
        }
      }
    },
    required: ["entries"]
  }
} as const;

// MARK: - User message builder

function buildDictionaryUserMessage(payload: GenerateDictionaryPayload): string {
  let projectBlock = "";
  if (payload.project) {
    const p = payload.project;
    const tags = p.tags && p.tags.length ? `\nStack: ${p.tags.join(", ")}` : "";
    const brief = p.brief ? `\nWhat it is: ${p.brief.slice(0, 600)}` : "";
    projectBlock = `The user's project: ${p.name}${tags}${brief}\n\n`;
  }

  const termLines = payload.terms.map((t, i) => {
    const evo = t.evolution ?? "encountered";
    const seen = (t.seen_in ?? []).map(s => {
      const snip = s.snippet ? `: ${s.snippet.slice(0, MAX_SNIPPET_CHARS).replace(/\s+/g, " ").trim()}` : "";
      return `${s.file}${snip}`;
    });
    const seenLine = seen.length ? `\n   Seen in: ${seen.join(" | ")}` : "\n   Seen in: (no snippet provided)";
    const hint = t.topic_hint ? `\n   Topic hint: ${t.topic_hint}` : "";
    return `${i + 1}. "${t.term}" [evolution: ${evo}]${seenLine}${hint}`;
  }).join("\n\n");

  return `${projectBlock}Generate a personal dictionary card for each of these terms, in this exact order. Ground each card in the user's project and the places the term was seen.

${termLines}

Now call the record_dictionary_entries tool with one entry per term, in the same order, echoing each "term" token.`;
}

// MARK: - Per-term cache (dictionary_cache, 30-day TTL)

const DICT_TTL_DAYS = 30;
const DICT_TTL_MS = DICT_TTL_DAYS * 24 * 60 * 60 * 1000;

function termSlug(term: string): string {
  return term.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60) || "term";
}

/** Key includes evolution so a stage change (and its milestone_note) regenerates. */
export function dictCacheKey(uid: string, term: string, language: string, evolution: EvolutionStage): string {
  return `${uid}__${termSlug(term)}__${language}__${evolution}`;
}

async function getCachedEntry(
  uid: string, term: string, language: string, evolution: EvolutionStage, now: Date
): Promise<DictionaryEntryOutput | null> {
  const db = admin.firestore();
  const ref = db.collection("dictionary_cache").doc(dictCacheKey(uid, term, language, evolution));
  const snap = await ref.get();
  if (!snap.exists) return null;
  const data = snap.data() as { entry: DictionaryEntryOutput; generated_at: admin.firestore.Timestamp };
  if (now.getTime() - data.generated_at.toDate().getTime() >= DICT_TTL_MS) return null;
  return data.entry;
}

async function putCachedEntry(
  uid: string, term: string, language: string, evolution: EvolutionStage, entry: DictionaryEntryOutput
): Promise<void> {
  const db = admin.firestore();
  const ref = db.collection("dictionary_cache").doc(dictCacheKey(uid, term, language, evolution));
  await ref.set({
    entry,
    generated_at: admin.firestore.Timestamp.now(),
    expires_at: admin.firestore.Timestamp.fromMillis(Date.now() + DICT_TTL_MS)
  });
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

export async function handleGenerateDictionary(
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

  const validationError = validateDictionaryPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as GenerateDictionaryPayload;
  const now = new Date();

  // 1. Serve cached entries; collect only cache-misses for the model call.
  const resolved: (DictionaryEntryOutput | null)[] = new Array(payload.terms.length).fill(null);
  const misses: { index: number; term: TermRequestInput }[] = [];
  await Promise.all(payload.terms.map(async (term, i) => {
    const evo = term.evolution ?? "encountered";
    try {
      const hit = await getCachedEntry(auth.uid, term.term, payload.language, evo, now);
      if (hit) { resolved[i] = hit; return; }
    } catch (err) {
      logger.warn("dictionary cache read failed", { uid: auth.uid, err: String(err) });
    }
    misses.push({ index: i, term });
  }));

  // 2. Generate the misses in one batched call (rate-limited only when we call).
  if (misses.length > 0) {
    const limit = await checkAndIncrement(auth.uid);
    if (!limit.allowed) {
      res.status(429).json({
        error: "daily_limit_reached",
        reset_at: limit.resetAt.toISOString(),
        limit: limit.limit
      });
      return;
    }

    const system = DICTIONARY_SYSTEM_PROMPT
      .replace("<language>", payload.language === "vi" ? "Tiếng Việt" : "English")
      .replace("<persona_block>", renderPersonaBlock(payload.pet_persona));
    const user = buildDictionaryUserMessage({ ...payload, terms: misses.map(m => m.term) });

    let entries: DictionaryEntryOutput[];
    try {
      const response = await anthropicClient().messages.create({
        model: MODEL,
        max_tokens: 4000,
        system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
        tools: [DICTIONARY_TOOL as any],
        tool_choice: { type: "tool", name: "record_dictionary_entries" },
        messages: [{ role: "user", content: user }]
      });

      let parsed: DictionaryEntryOutput[] | undefined;
      for (const block of response.content) {
        if (block.type === "tool_use" && block.name === "record_dictionary_entries") {
          const input = block.input as { entries?: DictionaryEntryOutput[] };
          if (Array.isArray(input.entries)) parsed = input.entries;
        }
      }
      if (!parsed) throw new Error("Anthropic response missing valid record_dictionary_entries tool use");
      entries = parsed;
    } catch (err) {
      logger.error("dictionary generation failed", { uid: auth.uid, err: String(err) });
      res.status(502).json({ error: "upstream_failure" });
      return;
    }

    // 3. Map generated entries back to their request slots (by term, order-fallback)
    //    and write each to the per-term cache.
    const byTerm = new Map<string, DictionaryEntryOutput>();
    for (const e of entries) if (e && typeof e.term === "string") byTerm.set(e.term.toLowerCase(), e);

    await Promise.all(misses.map(async (miss, k) => {
      const requested = miss.term.term;
      const entry = byTerm.get(requested.toLowerCase()) ?? entries[k];
      if (!entry) return;
      // Trust the requested token over the model's echo so client mapping is exact.
      entry.term = requested;
      resolved[miss.index] = entry;
      try {
        await putCachedEntry(auth.uid, requested, payload.language, miss.term.evolution ?? "encountered", entry);
      } catch (err) {
        logger.warn("dictionary cache write failed", { uid: auth.uid, err: String(err) });
      }
    }));
  }

  const finalEntries = resolved.filter((e): e is DictionaryEntryOutput => e !== null);
  res.status(200).json({
    entries: finalEntries,
    model: MODEL,
    generated_at: now.toISOString(),
    cache_hits: payload.terms.length - misses.length
  } as GenerateDictionaryResponse);
}
