# Codepet runs on the founder's own Claude

**Phase 1 of a two-phase change.** Phase 2 (a second provider) is named at the end and is not
designed here.

## The finding

Codepet buys inference twice. A founder who has granted Claude Code runs everything through
`claude -p` on their own plan; a founder who has not routes to Cloud Functions that spend
Codepet's Anthropic key. The second group is the default, because the grant lives in a Settings
panel rather than in onboarding.

That key has been invalid since 26 August. It is not a suspicion — `ClaudeCodeAuthorisation.swift`
records the deletion in a comment, and production says so directly:

```
runTask          6 Sep   401 authentication_error  "API key is invalid."
companyChat      7 Sep   401 authentication_error  "API key is invalid."
extractDecisions 9 Sep   401 authentication_error  "API key is invalid."
```

Fetching the deployed secret (Secret Manager v5) and calling `api.anthropic.com/v1/models` with it
returns `401` today. **So the default path through the product has been broken for roughly three
weeks**, and only granted founders — who never touch it — have been unaffected.

The decision this spec records is to stop paying for inference at all rather than to replace the
key. Codepet becomes a tool that drives the founder's own Claude subscription, and the hosted path
is removed instead of repaired.

## What was decided

| Question | Decision |
| --- | --- |
| What does Codepet charge for, with no inference cost? | **The app itself.** RevenueCat and `entitlements/{uid}` survive as a pro/not-pro check. Credits, per-run budgets and `engBudget`'s economics go. |
| What does a founder without Claude Code see? | **A hard gate in onboarding.** Nothing AI-shaped is reachable until Claude Code is detected and granted. |
| How is the subscription enforced with no server in the loop? | **Client-side**, reading `entitlements/{uid}` from Firestore. The app is already signed in. |
| How far does deletion go? | **Repo only.** The 18 hosted AI functions leave the codebase; what is deployed stays deployed and inert. |

The hard gate is what makes the rest safe. With it, the cloud branch is unreachable by
construction rather than merely unused, so deleting it cannot strand a founder mid-session.

## `CloudAIBlock` already exists, and it does half of this

**Amendment, same day.** This spec was first written without reference to
`codepet/Services/CloudAIBlock.swift`, which is the authority `CLAUDE.md` points at and which
already implements the hard part.

It is a `URLProtocol` interceptor registered at launch, sitting BELOW all six HTTP clients —
deliberately, because "there is no shared HTTP helper: six clients build their own requests, and
a guarantee that only holds for the clients someone remembered to update is not a guarantee." It
refuses any request whose last path component is in `blockedPaths`, per request, with no relaunch
needed. Today it is opt-in, persisted per company at `cp_neverUseApiKey_<companyId>`.

So Phase 1 does not invent a mechanism. It makes this one unconditional: the refusal stops being
a switch the founder may set and becomes how the app behaves. The switch and its Settings control
are removed with the choice.

**Keep it after the handlers are deleted.** Production stays deployed by decision, so the
endpoints remain reachable by URL until a later undeploy. The interceptor is the belt to the
routing change's braces, and it is the only one of the two that covers a client nobody remembered
to update.

**On 17 versus 18.** `blockedPaths` holds 17 entries; 18 exports declare `ANTHROPIC_API_KEY`. Both
are right: `engWebhook` is inbound from Anthropic's agent service, so it spends the key but is not
a path the app ever calls. The 17 are the client's concern; the 18 are the repo's.

Its doc comment also records which neighbours must NOT be blocked, and that list matches the 10
survivors above: `githubOAuthStart` / `githubOAuthCallback` spend a GitHub secret, and
`engDiff` / `engShip` / `engPreview` / `engListRepos` / `engLinkRepo` / `engCreateRepo` /
`engBalance` are GitHub and Firestore only.

## Architecture: the seam survives, its meaning changes

`LocalTransportRouter.transport()` answers *local or cloud*. It becomes *which runner, or why
not*:

```
enum Transport {
    case local                  // the founder's Claude Code
    case blocked(Reason)        // no grant, no CLI, no sidecar
}
```

`.cloud` is deleted. `.localUnavailable(String)` folds into `.blocked`, which carries a reason the
UI can render rather than a bare string.

**Keeping the seam is the point.** Collapsing the router and calling `LocalOneShotRunner` directly
is a smaller diff today and a rebuild in Phase 2, when a second provider needs exactly this
decision point. The router stops asking "whose machine" and starts asking "which runner", which is
the question Phase 2 extends.

Every caller loses its `case .cloud:` branch. `RunTaskClient.runTask` is the model: it already
routes `.local` first and already refuses to fall through, with the reason stated in a comment —
*"It never falls through to the Cloud Function: that would spend the API key the grant exists to
stop spending."* That comment describes the whole product after this change.

## Inventory

**Deleted from the repo — the 18 exports that declare `ANTHROPIC_API_KEY`:**

`summarizeTurn`, `summarizeSession`, `chatSession`, `enrichBrief`, `companyChat`, `runTask`,
`engStartRun`, `engStream`, `engWebhook`, `engSendTurn`, `generateRoadmap`, `extractDecisions`,
`generateGuidance`, `generatePlan`, `distillReference`, `synthesizeBrief`, `generateDictionary`,
`virtualCompanyRun`

Plus `anthropic.ts` (the `getClient` chokepoint), `rateLimit.ts`, `entitlements.ts`, and the
credit economics in `engineering/engBudget.ts` — `CREDIT_CENTS`, `DEFAULT_RUN_CREDITS`,
`creditsToBudget`, `listCostToCredits`.

These four fall cleanly. `anthropic.ts` and `rateLimit.ts` are imported only by handlers on the
deletion list — `enrichBrief`, `summarizeTurn`, `generateRoadmap`, `companyChat`,
`synthesizeBrief` — and by nothing that survives. `entitlements.ts` exports `resolvePlanTier`,
whose only consumer is `generatePlan`; `revenueCatWebhook` writes the `entitlements/{uid}`
document but never reads through that module, so the webhook is unaffected by its removal.

**The `*Core.ts` prompt builders stay.** They are not hosted code that happens to live in
`functions/` — they are what `scripts/build-sidecar.sh` bundles into the app, and they carry the
department output contract merged in #138. Deleting a handler must not take its builder with it.
This is the single most likely way to get this change wrong.

**The 10 exports with no key survive unchanged:** `capabilities`, `githubOAuthStart`,
`githubOAuthCallback`, `engListRepos`, `engLinkRepo`, `engCreateRepo`, `engShip`, `engPreview`,
`engDiff`, `revenueCatWebhook`. None of them buy inference; they move repos, complete OAuth, and
mirror subscription state.

## Onboarding: the gate

Claude Code detection and the grant move from `ClaudeCodePanel` into the onboarding flow as a
required step. The panel already has the parts — a `.notInstalled` blocker with an install path, a
probe, and the grant switch — so this is a promotion, not a new screen.

The step passes when the CLI is present, the sidecar bundles are available
(`LocalOneShotRunner.isAvailable()`), and the founder has granted the company. It fails with the
reason named, never with a generic error: "not installed", "installed but not granted", and
"granted but the local runner is missing" are three different problems with three different fixes.

**UI design for this step is not settled here.** Per the project's working agreement, the screen
gets proposed and approved before it is built.

## Entitlements, client-side

`resolvePlanTier` is reimplemented in the app, reading `entitlements/{uid}` from Firestore
directly; the server copy in `entitlements.ts` is deleted with its only caller. The RevenueCat
webhook continues to write that document, and nothing about the purchase flow changes.

This is spoofable by a founder willing to edit their own Firestore document, and that is accepted:
it is true of any local-first app, and the thing being protected is a feature tier rather than
someone else's compute. The previous arrangement was not meaningfully stronger — on the local path
`generatePlan` already answered `tier: "full"` because there was no entitlement to read.

## `startSessionBuild` belongs in this phase

A grant is not a folder. `startBuild` sends a granted founder with a **linked folder** to
`ClaudeCodeRunner`; without a folder it goes to the cloud agent, because the local run would land
in `.noProject`. `CLAUDE.md` names it as the only call that can still reach the cloud agent by
design.

Left alone, it would be the one surviving route to a deleted function — the exact "silently reaches
a thing that no longer exists" failure the hard gate exists to prevent. It gets its own gate: a
build with no folder linked asks the founder to link one, in the same shape as the Claude Code
gate. That is a blocker with a reason, not a rebuild of the coding agent.

## What is knowingly given up

These are listed in `CLAUDE.md` as what the local path does not reproduce. They stop being a
fallback's limitations and become how the product behaves:

- **No kill switch.** A runaway hosted run could be stopped server-side. There is no such lever on
  the founder's machine. This is the one with no mitigation in this phase, and it is called out as
  an open question rather than solved quietly.
- **No server-side caches** — narrative, dictionary terms, prompt caching. Work the hosted path
  served free is regenerated on the founder's own quota on every run.
- **No rate limit** and **no blackboard write** for a virtual-company meeting.

None of these block Phase 1. All of them are permanent until something replaces them.

## Testing

The suites already cover both transports, so most of the work is subtraction: the cloud-branch
tests go with the branches. What gets added:

1. `transport()` can never answer with a hosted runner — a total check over its cases, so a future
   case cannot quietly reintroduce one.
2. The onboarding gate blocks every AI entry point until it passes, and names which of the three
   reasons it failed for.
3. The client-side tier resolves from `entitlements/{uid}`, including the absent-document case
   (not pro).
4. `startSessionBuild` with no folder blocks rather than dispatching.
5. A guard that the `*Core.ts` builders still export what the sidecar bundles import — the
   regression that deleting handlers could cause, caught by the build rather than by a founder.

The existing gates stand: the Swift suite (2,539 tests) and the functions suite, both on CI, which
is the only place the whole Swift suite runs.

## Out of scope

- **Phase 2 — a second provider** (ChatGPT via Codex CLI, or others). There is no non-Claude
  support anywhere today; `ClaudeCodeModel` is Claude-only. A second provider is a second CLI with
  its own flags, output shape and schema coercion, built behind the seam this phase preserves.
- **Undeploying the 18 functions from production.** A separate, deliberate step. It must not be a
  full `firebase deploy --only functions`: `extractKnowledge` and `scaffoldRoadmap` are live in
  production and absent from `main`, so a full deploy deletes them silently. That drift is resolved
  first, or the undeploy is done function by function.
- **Replacing the caches or the kill switch.**

## Open question

**The kill switch.** With every run on the founder's machine there is no remote stop. Worth an
answer before this reaches founders who are not the author — a local cancel exists
(`codingRun.cancel()`), but that is the founder stopping their own run, not Codepet stopping a
runaway one.
