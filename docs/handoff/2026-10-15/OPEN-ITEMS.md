# Open items (15 Oct 2026)

## Decided, not started

1. **Chat-first after onboarding** (Astro, 15 Oct). Reports, progress and every status the
   mockups put on dashboards should arrive in chat; pages become secondary. This is the
   biggest open product direction. Mockups for reference:
   https://claude.ai/artifact/9zbiuQeahVNW6Xkd1pT1fg
2. **Cut the next build from current `main` as build 14+** so #251 and #252 reach testers
   (see HANDOFF.md §3 for why 14, not 10).

## Known and deliberately unfixed (from CLAUDE.md)

- Five brief fields (`goal`, `traction`, `problem`, `runway`, `constraints`) are collected
  by interviews and displayed nowhere.
- `detectConflicts` reports a false `BLOCKER` when two departments block the same way.
- `dept-product` has placeholder art, so Product is kept off the roster.
- `startBuild` with a folder linked and no grant still reaches the cloud coding agent, which
  401s; the Build card cannot render a `BlockReason` yet.
- `startEnrichInterviewIfNeeded` has no caller.

## Product calls left open (from the 1 Oct end-to-end test — not re-verified since)

- Starting a task from the roadmap takes 3 presses (card Start → sheet Start → "Yes, start
  it"); the sheet's Start could count as the confirmation.
- Re-planning replaces tasks that have an unapproved draft.
- Page Down does not scroll the chat transcript.

## Operational

- **`.p12` backup of the Developer ID cert** to the company vault is still owed; the key
  exists on one Mac only.
