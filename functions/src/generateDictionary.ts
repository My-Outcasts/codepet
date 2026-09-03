import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL, cacheableSystemBlock } from "./anthropic";
import {
  DICTIONARY_TOOL,
  DictionaryEntryOutput,
  EvolutionStage,
  GenerateDictionaryPayload,
  GenerateDictionaryResponse,
  TermRequestInput,
  coerceDictionaryEntries,
  dictionaryRequest,
  validateDictionaryPayload,
} from "./generateDictionaryCore";

// Re-exported so `./generateDictionary` stays the name callers and tests already import.
export * from "./generateDictionaryCore";

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

    const { system, user } = dictionaryRequest(payload, misses.map((m) => m.term));

    let entries: DictionaryEntryOutput[];
    try {
      const response = await anthropicClient().messages.create({
        model: MODEL,
        max_tokens: 4000,
        system: [cacheableSystemBlock({ model: MODEL, text: system, tools: DICTIONARY_TOOL })],
        tools: [DICTIONARY_TOOL as any],
        tool_choice: { type: "tool", name: "record_dictionary_entries" },
        messages: [{ role: "user", content: user }]
      });

      let parsed: DictionaryEntryOutput[] | undefined;
      for (const block of response.content) {
        if (block.type === "tool_use" && block.name === "record_dictionary_entries") {
          parsed = coerceDictionaryEntries(block.input) ?? undefined;
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
