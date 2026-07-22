# companyChat Cloud Function Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a `companyChat` Cloud Function on `devpet-8f4b1` that turns a founder's chat message into a grounded reply voiced as their chosen companion, so the native Copilot chat is visibly alive.

**Architecture:** A non-streaming HTTPS Cloud Function that verifies a Firebase ID token, checks the per-user daily limit, builds a companion-voiced system prompt (self-contained 7-companion map) grounded on the client-sent `context` + chat history, calls Sonnet 5 (non-streaming, prompt-cached system block), and returns `{ reply, run_task_id: null }`. The Swift `CompanyChatClient` is updated to attach the ID token. Mirrors the existing `enrichBrief` CF exactly.

**Tech Stack:** TypeScript, Firebase Cloud Functions v2 (node 22), `@anthropic-ai/sdk` ^0.40, jest; Swift/SwiftUI client.

## Global Constraints

- **TWO repos, TWO branches — never mix them:**
  - **Functions repo** (CodePet-Clean): worktree `/Users/monatruong/Documents/codepet-scaffoldfn-wt`. Create branch **`feat/company-chat-fn`** off `feat/scaffold-roadmap-fn` (inherits shared infra + `enrichBrief` + `scaffoldRoadmap`). All CF work (`functions/src/**`) lives here.
  - **Native app repo** (My-Outcasts/codepet): worktree `/Users/monatruong/Documents/codepet-rebuild-wt`, branch **`feat/company-chat-cf`** (already created; holds the spec). The Swift `CompanyChatClient` change + this plan/spec live here.
- **DEPLOY IS SCOPED, ALWAYS:** `firebase deploy --only functions:companyChat`. **NEVER** run a bare `firebase deploy --only functions` from the functions repo — the `feat/scaffold-roadmap-fn` source tree does NOT export `distillReference` or `generateDictionary`, which ARE live in prod, so a bare deploy would **delete them**.
- **Model:** `claude-sonnet-5`. **max_tokens:** `1024`. **Node:** `22` (repo `engines.node: "22"`).
- **Secret:** `ANTHROPIC_API_KEY` (already configured on the project; declared on the function).
- **Response shape (fixed by the Swift client):** `{ "reply": string, "run_task_id": null }`. Request is snake_case per `CompanyChatRequest`.
- **iCloud git gotcha (both worktrees):** before any git write, `rm -f "<gitdir>/index.lock"`; run commits as **background** jobs with `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 … --no-verify`, then confirm HEAD advanced. Native gitdir: `/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt`. Functions gitdir: `/Users/monatruong/Documents/Claude/CodePet-Clean/.git/worktrees/codepet-scaffoldfn-wt`. Commit messages via `-F <file>` (zsh mangles `-m` + backticks).
- **Build authority:** `npm run build` (tsc) / `xcodebuild` output is authoritative; SourceKit/editor cross-file errors are false positives. xcodebuild runs **foreground only**.
- **Jest:** the repo runs jest via `npm test` in `functions/`. Test files live in `functions/src/__tests__/`.

---

## Task 0: Branch setup (functions repo)

**Files:** none (git only)

- [ ] **Step 1: Create the working branch off the infra-carrying branch**

```bash
cd /Users/monatruong/Documents/codepet-scaffoldfn-wt
LOCK=/Users/monatruong/Documents/Claude/CodePet-Clean/.git/worktrees/codepet-scaffoldfn-wt/index.lock
rm -f "$LOCK"
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 checkout -b feat/company-chat-fn
```

Expected: `Switched to a new branch 'feat/company-chat-fn'`

- [ ] **Step 2: Confirm the base has the shared infra**

Run: `ls src/auth.ts src/rateLimit.ts src/anthropic.ts src/enrichBrief.ts src/scaffoldRoadmap.ts`
Expected: all five listed (no "No such file").

---

## Task 1: Companion map (`companionFor`)

**Files:**
- Create: `functions/src/companyChat.ts`
- Test: `functions/src/__tests__/companyChat.test.ts`

**Interfaces:**
- Produces: `interface Companion { name: string; voice: string }`, `companionFor(id: string): Companion` (unknown id → the `byte` entry).

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyChat.test.ts`:

```ts
import { companionFor } from "../companyChat";

describe("companionFor", () => {
  it("returns the named companion for a known id", () => {
    expect(companionFor("luna").name).toBe("Luna");
    expect(companionFor("luna").voice).toMatch(/gentle|warm/i);
  });
  it("falls back to byte for an unknown id", () => {
    expect(companionFor("does-not-exist").name).toBe("Byte");
  });
  it("has all seven starters", () => {
    for (const id of ["byte", "nova", "crash", "luna", "sage", "glitch", "null"]) {
      expect(companionFor(id).name.length).toBeGreaterThan(0);
    }
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/monatruong/Documents/codepet-scaffoldfn-wt/functions && npx jest companyChat -t companionFor`
Expected: FAIL — `Cannot find module '../companyChat'`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/companyChat.ts`:

```ts
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/monatruong/Documents/codepet-scaffoldfn-wt/functions && npx jest companyChat -t companionFor`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit** (background-safe git per Global Constraints)

```bash
cd /Users/monatruong/Documents/codepet-scaffoldfn-wt
LOCK=/Users/monatruong/Documents/Claude/CodePet-Clean/.git/worktrees/codepet-scaffoldfn-wt/index.lock
rm -f "$LOCK"
printf '%s\n' "feat(companyChat): companion voice map + companionFor" "" "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" > /tmp/cc1.txt
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add functions/src/companyChat.ts functions/src/__tests__/companyChat.test.ts
rm -f "$LOCK"; GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify -F /tmp/cc1.txt
```

Expected: HEAD advances (verify with `git log --oneline -1`).

---

## Task 2: System prompt builder (`buildSystemPrompt`)

**Files:**
- Modify: `functions/src/companyChat.ts`
- Test: `functions/src/__tests__/companyChat.test.ts`

**Interfaces:**
- Consumes: `companionFor` (Task 1).
- Produces: `buildSystemPrompt(args: { companionId: string; context: string; language: string }): string`.

- [ ] **Step 1: Write the failing test** (append to the test file)

```ts
import { buildSystemPrompt } from "../companyChat";

describe("buildSystemPrompt", () => {
  const base = { companionId: "luna", context: "Project: Acme. Next step: pricing page.", language: "en" };
  it("names the chosen companion and injects the context", () => {
    const s = buildSystemPrompt(base);
    expect(s).toContain("Luna");
    expect(s).toContain("Acme");
    expect(s).toContain("pricing page");
  });
  it("adds a Vietnamese instruction only for vi", () => {
    expect(buildSystemPrompt({ ...base, language: "vi" })).toMatch(/Vietnamese/i);
    expect(buildSystemPrompt(base)).not.toMatch(/Vietnamese/i);
  });
  it("falls back to byte for an unknown companion", () => {
    expect(buildSystemPrompt({ ...base, companionId: "zzz" })).toContain("Byte");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx jest companyChat -t buildSystemPrompt`
Expected: FAIL — `buildSystemPrompt is not a function`.

- [ ] **Step 3: Write minimal implementation** (append to `companyChat.ts`)

```ts
const clip = (v: unknown, n: number) => (typeof v === "string" ? v.trim().slice(0, n) : "");

// Reply-only companion system prompt. Adapted from the web BYTE_SYSTEM, trimmed to a
// pure conversational surface (no run_task / navigate / setup tools this cut) and made
// companion-agnostic. Kept static except for the companion identity + language so the
// prompt-cache prefix stays stable across turns; the per-request company context is
// appended AFTER this block by the handler (outside the cached prefix).
export function buildSystemPrompt(args: { companionId: string; context: string; language: string }): string {
  const c = companionFor(args.companionId);
  const vi = args.language === "vi"
    ? "\n\nReply in natural, fluent Vietnamese."
    : "";
  const context = clip(args.context, 4000) || "The founder hasn't filled in much of a brief yet — keep guidance general and invite them to tell you more.";
  return (
    `You are ${c.name}, the AI building companion inside Codepet — a senior operator who helps a solo founder build and understand their whole company, department by department.\n\n` +
    `Voice: ${c.voice}\n\n` +
    `You are in a chat with the founder. Be warm, plain-spoken, specific, and brief — usually 2-4 sentences, occasionally a short list when it genuinely helps. No hype, no filler, no emoji. Write plain text only — no markdown, asterisks, backticks, or arrows; the chat shows your words as-is. When they ask what to do next, ground your answer in their actual company and where they are.` +
    vi +
    `\n\nThe founder's company:\n${context}`
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx jest companyChat -t buildSystemPrompt`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Documents/codepet-scaffoldfn-wt
LOCK=/Users/monatruong/Documents/Claude/CodePet-Clean/.git/worktrees/codepet-scaffoldfn-wt/index.lock
rm -f "$LOCK"
printf '%s\n' "feat(companyChat): companion-voiced system prompt builder" "" "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" > /tmp/cc2.txt
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add functions/src/companyChat.ts functions/src/__tests__/companyChat.test.ts
rm -f "$LOCK"; GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify -F /tmp/cc2.txt
```

---

## Task 3: Message builder (`buildMessages`)

**Files:**
- Modify: `functions/src/companyChat.ts`
- Test: `functions/src/__tests__/companyChat.test.ts`

**Interfaces:**
- Produces: `interface ChatTurn { role: string; text: string }`, `interface ClaudeMessage { role: "user" | "assistant"; content: string }`, `buildMessages(history: ChatTurn[], userMessage: string): ClaudeMessage[]`.
- Behavior: maps `me`→`user`, `companion`→`assistant`; appends `userMessage` as a final `user` turn; keeps the last 20; drops any leading `assistant` turns; coalesces consecutive same-role turns (join with `\n\n`) so the result strictly alternates and starts with `user`.

- [ ] **Step 1: Write the failing test** (append)

```ts
import { buildMessages } from "../companyChat";

describe("buildMessages", () => {
  it("maps roles and appends the new user message last", () => {
    const m = buildMessages(
      [{ role: "me", text: "hi" }, { role: "companion", text: "hey" }],
      "what next?",
    );
    expect(m).toEqual([
      { role: "user", content: "hi" },
      { role: "assistant", content: "hey" },
      { role: "user", content: "what next?" },
    ]);
  });
  it("drops a leading assistant/companion turn", () => {
    const m = buildMessages([{ role: "companion", text: "welcome" }], "hello");
    expect(m).toEqual([{ role: "user", content: "hello" }]);
  });
  it("coalesces consecutive same-role turns", () => {
    const m = buildMessages(
      [{ role: "me", text: "a" }, { role: "me", text: "b" }],
      "c",
    );
    // a+b (user) coalesced, then final user c coalesced too → one user block
    expect(m).toEqual([{ role: "user", content: "a\n\nb\n\nc" }]);
  });
  it("caps to the last 20 messages", () => {
    const hist = Array.from({ length: 40 }, (_, i) => ({
      role: i % 2 === 0 ? "me" : "companion",
      text: `t${i}`,
    }));
    const m = buildMessages(hist, "final");
    expect(m.length).toBeLessThanOrEqual(20);
    expect(m[m.length - 1]).toEqual({ role: "user", content: "final" });
  });
  it("handles empty history", () => {
    expect(buildMessages([], "only")).toEqual([{ role: "user", content: "only" }]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx jest companyChat -t buildMessages`
Expected: FAIL — `buildMessages is not a function`.

- [ ] **Step 3: Write minimal implementation** (append to `companyChat.ts`)

```ts
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx jest companyChat -t buildMessages`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Documents/codepet-scaffoldfn-wt
LOCK=/Users/monatruong/Documents/Claude/CodePet-Clean/.git/worktrees/codepet-scaffoldfn-wt/index.lock
rm -f "$LOCK"
printf '%s\n' "feat(companyChat): history→Claude message builder (alternation-safe)" "" "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" > /tmp/cc3.txt
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add functions/src/companyChat.ts functions/src/__tests__/companyChat.test.ts
rm -f "$LOCK"; GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify -F /tmp/cc3.txt
```

---

## Task 4: Handler + model call + export (`handleCompanyChat`)

**Files:**
- Modify: `functions/src/companyChat.ts`
- Modify: `functions/src/index.ts`

**Interfaces:**
- Consumes: `verifyAuth` (`./auth`), `checkAndIncrement` (`./rateLimit`), `buildSystemPrompt`, `buildMessages`.
- Produces: `handleCompanyChat(req: Request, res: Response): Promise<void>`; `export const companyChat` in `index.ts`.

No unit test (network/SDK boundary — matches the repo pattern where `enrichBrief`'s handler is untested and only its pure pieces are). Deliverable = a codebase that compiles (`tsc`) with the handler wired.

- [ ] **Step 1: Add imports + client + handler** (append to `companyChat.ts`; add imports at top)

At the TOP of `companyChat.ts`:

```ts
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";

const CHAT_MODEL = "claude-sonnet-5";
```

At the BOTTOM of `companyChat.ts`:

```ts
let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _client = new Anthropic({ apiKey });
  }
  return _client;
}

interface ChatRequestBody {
  language?: string;
  companion_id?: string;
  context?: string;
  history?: ChatTurn[];
  user_message?: string;
}

export async function handleCompanyChat(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) { res.status(401).json({ error: "invalid_token" }); return; }

  const body = (req.body ?? {}) as ChatRequestBody;
  const userMessage = typeof body.user_message === "string" ? body.user_message.trim() : "";
  if (!userMessage) { res.status(400).json({ error: "invalid_payload", detail: "user_message required" }); return; }

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({ error: "daily_limit_reached", reset_at: limit.resetAt.toISOString(), limit: limit.limit });
    return;
  }

  const system = buildSystemPrompt({
    companionId: typeof body.companion_id === "string" ? body.companion_id : "byte",
    context: typeof body.context === "string" ? body.context : "",
    language: body.language === "vi" ? "vi" : "en",
  });
  const messages = buildMessages(Array.isArray(body.history) ? body.history : [], userMessage);

  try {
    const response = await client().messages.create({
      model: CHAT_MODEL,
      max_tokens: 1024,
      // Prompt-cache the static system block (the pricing spec's cheap-chat lever).
      system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }] as any,
      messages: messages as any,
    });
    const reply = response.content
      .filter((b) => b.type === "text")
      .map((b) => (b as { text: string }).text)
      .join("")
      .trim();
    res.status(200).json({ reply, run_task_id: null });
  } catch (err) {
    logger.error("companyChat failed", { uid: auth.uid, err: String(err) });
    res.status(502).json({ error: "generation_failed" });
  }
}
```

- [ ] **Step 2: Export the function** in `functions/src/index.ts`

Add the import near the other handler imports (after the `handleScaffoldRoadmap`/`handleEnrichBrief` imports):

```ts
import { handleCompanyChat } from "./companyChat";
```

Add the export next to `enrichBrief`:

```ts
export const companyChat = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleCompanyChat
);
```

- [ ] **Step 3: Build (tsc) — authoritative check**

Run: `cd /Users/monatruong/Documents/codepet-scaffoldfn-wt/functions && npm run build`
Expected: exit 0, no TypeScript errors, `lib/companyChat.js` + `lib/index.js` emitted.

- [ ] **Step 4: Run the full function test suite** (nothing regressed)

Run: `cd /Users/monatruong/Documents/codepet-scaffoldfn-wt/functions && npm test`
Expected: all suites pass, including the 3 `companyChat` describe blocks (companionFor, buildSystemPrompt, buildMessages).

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Documents/codepet-scaffoldfn-wt
LOCK=/Users/monatruong/Documents/Claude/CodePet-Clean/.git/worktrees/codepet-scaffoldfn-wt/index.lock
rm -f "$LOCK"
printf '%s\n' "feat(companyChat): handler + Sonnet 5 call + index export" "" "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" > /tmp/cc4.txt
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add functions/src/companyChat.ts functions/src/index.ts
rm -f "$LOCK"; GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify -F /tmp/cc4.txt
```

---

## Task 5: Scoped deploy + live verification

**Files:** none (deploy only)

- [ ] **Step 1: Confirm the active project**

Run: `cd /Users/monatruong/Documents/codepet-scaffoldfn-wt && firebase use`
Expected: `devpet-8f4b1` (Active).

- [ ] **Step 2: Deploy ONLY companyChat (scoped — never bare)**

Run:
```bash
cd /Users/monatruong/Documents/codepet-scaffoldfn-wt
firebase deploy --only functions:companyChat
```
Expected: `✔ functions[companyChat(us-central1)]` created/updated; no other function touched. If firebase prompts to DELETE any function (e.g. `distillReference`, `generateDictionary`), answer **No** and abort — that means the scope flag was dropped.

- [ ] **Step 3: Verify it is live**

Run: `firebase functions:list | grep companyChat`
Expected: `companyChat … https … us-central1 … nodejs22`.

- [ ] **Step 4: Smoke-test auth rejection (unauthenticated → 401)**

Run:
```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  https://us-central1-devpet-8f4b1.cloudfunctions.net/companyChat \
  -H "Content-Type: application/json" \
  -d '{"language":"en","companion_id":"byte","context":"x","history":[],"user_message":"hi"}'
```
Expected: `401` (no Bearer token → rejected, proving auth is enforced).

---

## Task 6: Swift client attaches the ID token

**Files:**
- Modify: `/Users/monatruong/Documents/codepet-rebuild-wt/codepet/Services/CompanyChatClient.swift`

**Interfaces:**
- `CompanyChatClient.send(_:)` unchanged signature; now attaches `Authorization: Bearer <idToken>` and returns `nil` (fail-open) when there is no signed-in user / token.

- [ ] **Step 1: Update `send` to fetch + attach the token**

Replace the body of `static func send(_ req: CompanyChatRequest) async -> CompanyChatReply?` in `CompanyChatClient.swift` with:

```swift
    static func send(_ req: CompanyChatRequest) async -> CompanyChatReply? {
        guard let token = try? await Auth.auth().currentUser?.getIDToken() else { return nil }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        urlRequest.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CompanyChatResponse.self, from: data)
        else { return nil }
        let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return nil }
        return CompanyChatReply(text: reply, runTaskId: decoded.runTaskId)
    }
```

Add the Firebase Auth import at the top of the file if not present:

```swift
import FirebaseAuth
```

Note: `getIDToken()` returns a non-optional `String` and can throw; `Auth.auth().currentUser?` makes the chained call optional, so `try? await …?.getIDToken()` yields `String??` → the `guard let token` unwraps to a non-nil `String`. No signed-in user → `nil` → fail-open (chat shows the offline line), which is the intended behavior.

- [ ] **Step 2: Build the app (foreground, authoritative)**

Run (FOREGROUND — do not background xcodebuild):
```bash
cd /Users/monatruong/Documents/codepet-rebuild-wt
xcodebuild -scheme codepet -destination 'platform=macOS' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`. (SourceKit "cannot find FirebaseAuth" in-editor errors are false positives; the xcodebuild result is authoritative.)

- [ ] **Step 3: Commit (native repo — background-safe git)**

```bash
cd /Users/monatruong/Documents/codepet-rebuild-wt
LOCK=/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock
rm -f "$LOCK"
printf '%s\n' "feat(chat): attach Firebase ID token to companyChat requests" "" "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" > /tmp/cc-swift.txt
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add codepet/Services/CompanyChatClient.swift
rm -f "$LOCK"; GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify -F /tmp/cc-swift.txt
```

Expected: HEAD advances (verify with `git log --oneline -1`).

---

## Task 7: End-to-end verification (manual)

**Files:** none

The user does the visual confirm; the controller drives build/launch and reads CF logs.

- [ ] **Step 1: Signed build (required for Firebase sign-in)**

Build WITHOUT `CODE_SIGNING_ALLOWED=NO` (team `YL72VTKBR7`, "Apple Development"), foreground:
```bash
cd /Users/monatruong/Documents/codepet-rebuild-wt
xcodebuild -scheme codepet -destination 'platform=macOS' \
  DEVELOPMENT_TEAM=YL72VTKBR7 build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`. Then `open` the built `.app` (path from `-showBuildSettings` `TARGET_BUILD_DIR`/`FULL_PRODUCT_NAME`), or launch via Xcode ⌘R.

- [ ] **Step 2: Drive the chat**

Sign in (Google or email — needs the signed build for the keychain). Open Copilot chat, send a message like "what should I focus on next?". 

Expected (user confirms visually): a grounded, in-character reply appears (not "I can't reach my brain right now"). The reply should reference the founder's actual company/next step from the context.

- [ ] **Step 3: Confirm a clean 200 in the CF logs**

Run: `firebase functions:log --only companyChat -n 20`
Expected: an invocation with no error line; a `companyChat failed` entry means the model/config path threw — investigate before calling it done.

- [ ] **Step 4: Update memory + handoff**

Update `[[codepet-web-to-native-port]]` memory: companyChat CF SHIPPED + live (first cut, grounded reply only), the "3 gen CFs undeployed" gap narrowed to runTask + scaffoldRoadmap, and the corrected fact that companyChat/runTask were unauthored (not merely undeployed). Note the scoped-deploy clobber hazard (prod has distillReference + generateDictionary absent from the feat/scaffold-roadmap-fn source).

---

## Notes for the executor

- **Two repos:** CF tasks (0–5) are in `codepet-scaffoldfn-wt` (functions repo, branch `feat/company-chat-fn`); Swift tasks (6–7) are in `codepet-rebuild-wt` (native repo, branch `feat/company-chat-cf`). Don't cross the streams.
- **The single hard safety rule:** deploy is ALWAYS `--only functions:companyChat`. A bare functions deploy from this branch deletes live functions.
- **PRs:** both branches are feature branches; open PRs per each repo's flow after E2E passes ([[codepet-local-must-reach-prod]]). The functions repo has no protected-branch PR requirement noted, but confirm before merging.
