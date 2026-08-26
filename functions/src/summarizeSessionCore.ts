/**
 * `summarizeSession`'s payload contract and its validator — no model, no Firestore.
 *
 * Split from the handler for the reason `summarizeTurnCore` records: one set of rules for both
 * transports.
 */

import { PetPersonaInput, TurnInput } from "./anthropicCore";

export interface SummarizeSessionPayload {
  session_id: string;
  language: "vi" | "en";
  turns: TurnInput[];
  pet_persona?: PetPersonaInput;
  user_brief?: string;
  pet_memory?: string;
}

export function validateSessionPayload(body: any): string | null {
  if (!body || typeof body !== "object") return "body required";
  const b = body as Partial<SummarizeSessionPayload>;
  if (typeof b.session_id !== "string" || b.session_id.length === 0) return "session_id required";
  if (b.language !== "vi" && b.language !== "en") return "language must be 'vi' or 'en'";
  if (!Array.isArray(b.turns) || b.turns.length === 0) return "turns must be a non-empty array";
  for (const t of b.turns) {
    if (typeof t !== "object" || !t) return "each turn must be an object";
    if (typeof t.prompt !== "string") return "each turn requires prompt string";
  }
  if (b.pet_persona !== undefined) {
    const p = b.pet_persona;
    if (!p || typeof p !== "object") return "pet_persona must be an object";
    if (
      typeof p.id !== "string" ||
      typeof p.name !== "string" ||
      typeof p.personality !== "string" ||
      typeof p.domain !== "string"
    ) {
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
