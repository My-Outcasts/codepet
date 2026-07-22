# companyChat Cloud Function — Design Spec (2026-07-22)

## Context

The native macOS Codepet app calls three "gen" Cloud Functions that the web product
serves as Next.js API routes: `companyChat`, `runTask`, `scaffoldRoadmap`. Ground-truth
audit (this session) found that **only `scaffoldRoadmap` is authored** (on
`feat/scaffold-roadmap-fn` in the CodePet-Clean functions repo, alongside the already-live
`enrichBrief`). **`companyChat` and `runTask` do not exist anywhere** — no source, no
branch, no git history — yet the Swift clients already POST to their endpoints and
fail-open to an honest offline message on any non-200.

This spec covers the **first cut of `companyChat`**: make the native Copilot chat
produce a real, grounded conversational reply. `runTask` and `scaffoldRoadmap` wiring are
separate, later efforts.

## Goal

A deployed `companyChat` Cloud Function on `devpet-8f4b1` that turns a founder's chat
message into a warm, grounded reply voiced as their chosen companion — so the native
Copilot chat is visibly alive instead of showing "I can't reach my brain right now."

## Scope (this cut)

**In:**
- Non-streaming HTTPS CF returning a single JSON reply.
- Firebase ID-token auth (Bearer) + per-user daily-limit guard (reused infra).
- Companion-voiced system prompt (chosen companion's name + voice).
- Grounding on the client-composed `context` string + prior chat history.
- Sonnet 5 with prompt caching on the static system block.
- Swift `CompanyChatClient` change to attach the ID token.

**Out (explicit YAGNI — follow-ups):**
- The `run_task` tool / inline deliverable-from-chat (`run_task_id` is always `null`).
  Blocked anyway: the native request only carries task *titles* in `context`, not the
  task *ids* the response would need. Requires a Swift request-shape change later.
- The `navigate` and `setup_capability` tools.
- Streaming responses (native decodes a single JSON body).
- A real credits/metering system (the daily-limit guard is the placeholder gate).

## Contract

Endpoint: `POST https://us-central1-devpet-8f4b1.cloudfunctions.net/companyChat`

Headers: `Content-Type: application/json`, `Authorization: Bearer <firebase-id-token>`.

**Request body** (snake_case — fixed by the existing Swift `CompanyChatRequest`):

```jsonc
{
  "company_id":   "string | null",  // present but not required server-side this cut
  "language":     "en" | "vi",
  "companion_id": "byte",           // one of the 7 starters; unknown → falls back to byte
  "context":      "string",         // pre-composed grounding (brief + roadmap summary)
  "history": [                       // prior turns, oldest→newest
    { "role": "me" | "companion", "text": "string" }
  ],
  "user_message": "string"          // the latest founder message
}
```

**Response body** (200):

```jsonc
{ "reply": "string", "run_task_id": null }
```

The Swift client trims `reply`; an empty reply is treated as failure (returns `nil` →
offline message). `run_task_id` is always `null` this cut.

**Error responses:** `401` (missing/invalid token), `400` (bad body / no message),
`429` (over daily limit), `5xx` (model/config failure). The Swift client fail-opens on
any non-200, so error bodies need not be structured, but standard codes are returned so
future callers degrade cleanly.

## Request flow

Mirrors the established `enrichBrief` skeleton:

1. **Auth** — `verifyAuth(req.headers.authorization)` (existing `auth.ts`) → `uid`, else
   `401`. No trust in `company_id` from the body.
2. **Rate limit** — `checkAndIncrement(uid)` (existing `rateLimit.ts`) → `429` if over
   `DAILY_LIMIT` (currently 100_000, effectively off for dev; real credit gate is later).
3. **Parse & validate body** — reject non-JSON / empty `user_message` with `400`.
4. **Build system prompt**:
   - A byte-style companion system block adapted from the web `BYTE_SYSTEM`, trimmed to
     the reply-only surface (no tool instructions this cut).
   - The **chosen companion** swapped in: name + a one-line voice descriptor from a
     self-contained `COMPANIONS` map (`id → { name, voice }`), 7 entries ported from the
     Swift `PetCharacter` (`name` + condensed `voiceGuide`). Unknown `companion_id` →
     `byte`.
   - The client-sent `context` appended as the founder's company grounding (clipped).
   - A language instruction when `language === "vi"` ("reply in natural Vietnamese").
5. **Build messages** — map `history` (`me`→`user`, `companion`→`assistant`), append
   `user_message` as the final `user` turn; cap to the last ~20 turns. Guard against a
   leading assistant turn / non-alternating history so the Claude API accepts it.
6. **Model call** — Sonnet 5 (`claude-sonnet-5`), non-streaming `messages.create`,
   `max_tokens` ≈ 1024, **prompt caching** via a `cache_control` breakpoint on the static
   system block (the pricing spec's cheap-chat lever).
7. **Respond** — `{ reply: <assistant text, trimmed>, run_task_id: null }`.

## Components (isolation)

- **`companyChat.ts`** — the handler plus pure helpers, each independently testable:
  - `COMPANIONS: Record<string, { name: string; voice: string }>` + `companionFor(id)`
    (fallback to byte).
  - `buildSystemPrompt({ companionId, context, language })` → string. Pure.
  - `buildMessages(history, userMessage)` → Claude message array. Pure; handles capping
    and role mapping and non-alternating cleanup.
  - `handleCompanyChat(req, res)` — orchestrates auth → limit → parse → prompt → model →
    respond. The only piece that touches Firebase / Anthropic / the network.
- **`index.ts`** — `export const companyChat = onRequest({ cors: false, secrets:
  ["ANTHROPIC_API_KEY"] }, handleCompanyChat);` Node 22 (repo `engines.node: "22"`).
- **Swift `CompanyChatClient`** — unchanged shape; adds the `Authorization: Bearer`
  header via `getIDToken()`, mirroring `ReflectionAPIClient`. Still fail-open (returns
  `nil` if no signed-in user / no token).

Reused unchanged: `auth.ts` (`verifyAuth`), `rateLimit.ts` (`checkAndIncrement`),
`@anthropic-ai/sdk`, the `ANTHROPIC_API_KEY` secret.

## Error handling

- Every failure path returns a proper HTTP status; the Swift client fail-opens to the
  localized offline line, so no user-facing crash is possible.
- Model/config errors are caught and logged (`firebase-functions/logger`), returned as
  `5xx`. No secret is ever echoed.
- Fail-open philosophy matches the rest of the native port: a down CF degrades the chat
  to offline, never blocks the app.

## Testing

Pure-function unit tests (`__tests__/companyChat.test.ts`, jest — the repo's existing
harness):
- `companionFor` returns the right name/voice; unknown id → byte.
- `buildSystemPrompt` includes the companion name, the context, and the Vietnamese
  instruction only when `language === "vi"`.
- `buildMessages` maps roles correctly, appends `user_message` last, caps at ~20, and
  produces an API-valid alternating sequence from messy history.

No network/integration test in CI (no emulator for Anthropic). End-to-end verification is
manual (below).

## Deploy & verify

- **Source repo:** the CodePet-Clean functions repo (carries the shared infra +
  `enrichBrief` + `scaffoldRoadmap`). Before deploying, run `firebase functions:list`
  against `devpet-8f4b1` to pin the live set and confirm the source branch is not stale.
  Add `companyChat` on a feature branch there.
- **Scoped deploy only:** `firebase deploy --only functions:companyChat`. Never a bare
  `--only functions` — that would clobber functions absent from the source (the memory's
  standing clobber guard).
- **Manual E2E:** signed native build (team `YL72VTKBR7`, WITHOUT
  `CODE_SIGNING_ALLOWED=NO` — required for Firebase keychain/sign-in), sign in, send a
  chat message in Copilot, confirm a grounded reply renders in the chosen companion's
  voice. Cross-check the CF logs for a clean 200. The user does the visual confirm; the
  controller drives build/deploy and reads logs.

## Risks / open items

- **Canonical deploy source ambiguity:** both the native app repo (`My-Outcasts/codepet`)
  and the CodePet-Clean functions repo contain a `functions/` dir with the reflection
  functions. `firebase functions:list` + checking which package matches the live deploy
  resolves which is authoritative before any push. Scoped deploy limits blast radius
  regardless.
- **Non-alternating history:** the native client sends `me`/`companion` turns that should
  already alternate, but `buildMessages` defends against a leading `companion` turn or
  doubled roles so the Claude API never 400s.
- **Prompt-cache hit rate:** caching only helps when the static system block is byte-
  identical across turns; keep all per-request variability (context, history) out of the
  cached prefix.
