/**
 * `summarizeTurn`'s payload contract and its validator — no model, no Firestore.
 *
 * Split from the handler so the local path validates a turn with the SAME rules the endpoint
 * does: a payload the cloud would refuse must not quietly produce a narrative locally.
 */

import { EventForPrompt, PetPersonaInput } from "./anthropicCore";

export interface SummarizePayload {
  turn_id: string;
  session_id: string;
  language: "vi" | "en";
  prompt: string;
  events: EventForPrompt[];
  raw_summary: string;
  pet_persona?: PetPersonaInput;
  user_brief?: string;
  pet_memory?: string;
}

export function validatePayload(body: any): string | null {
  if (!body || typeof body !== "object") return "body required";
  const b = body as Partial<SummarizePayload>;
  if (typeof b.turn_id !== "string" || b.turn_id.length === 0) return "turn_id required";
  if (typeof b.session_id !== "string" || b.session_id.length === 0) return "session_id required";
  if (b.language !== "vi" && b.language !== "en") return "language must be 'vi' or 'en'";
  if (typeof b.prompt !== "string" || b.prompt.length === 0) return "prompt required";
  if (!Array.isArray(b.events)) return "events must be an array";
  if (typeof b.raw_summary !== "string") return "raw_summary required";
  if (b.pet_persona !== undefined) {
    const p = b.pet_persona;
    if (!p || typeof p !== "object") return "pet_persona must be an object";
    if (typeof p.id !== "string" || typeof p.name !== "string"
        || typeof p.personality !== "string" || typeof p.domain !== "string") {
      return "pet_persona requires id/name/personality/domain strings";
    }
  }
  if (b.user_brief !== undefined && typeof b.user_brief !== "string") {
    return "user_brief must be a string when provided";
  }
  if (b.pet_memory !== undefined && typeof b.pet_memory !== "string") {
    return "pet_memory must be a string when provided";
  }
  return null;
}
