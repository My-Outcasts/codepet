*Codepet handoff brief* (mine + Mona's)

*Where it stands*
• Public: **build 8** (Oct 5), live at code-pet.com/download. Builds 9–13 were internal, tested by Mona. Build 13 was cut from `main` on Oct 9.
• No open PRs; everything is on `main`. Since build 13, `main` also has Mona's #251 (room card fix) and #252 (remembered facts in one line). The next build should be cut from current `main` as **build 14+** (testers already have 13; `main`'s project file still says 9).

*Shipped since build 8*
• Room/departments: ask a department, get that department (#247); each department keeps its own notebook (#248); a department can offer to convene the room (#250).
• UI (Mona): quieter Team Build / meeting / draft cards; Vega as the Sales pet; email/DM drafts survive a relaunch; lock-in shows the chosen option.

*Open*
• Your feedback on the "run a company solo" mockups: chat is the centre, dashboards are secondary. Not started.
• Known and deliberately unfixed: 5 brief fields collected but never shown; `detectConflicts` reports a false BLOCKER; Product has placeholder art.

*Where to start*
• Read `CLAUDE.md` first, especially Landmines.
• All AI runs on the founder's Claude plan (the API key was deleted). After any change in `functions/`, run `scripts/build-sidecar.sh`.
• Public release: `preflight-release.sh` → `package-macos.sh` → `release-github.sh` (the last one publishes publicly). Internal: `package-internal.sh`. The Developer ID cert is only on my Mac — ping me when you need to release.
• Run tests per suite (`-only-testing:`). Xcode 26.2 crashes the host on the full run; it's not a code bug.

Full context for Claude Code is on `main` in `docs/handoff/2026-10-15/`: pull, then tell it to read `docs/handoff/2026-10-15/HANDOFF.md`.
