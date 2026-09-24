# Smoke test and Slack report: proving a build works before anyone clicks it

**Date:** 24 September 2026
**Status:** approved, not implemented
**Scope:** an automated post-install smoke test of the *shipped* macOS app, reporting to
Slack, plus a watch mode that re-runs it against local builds. The existing unit suite, CI,
and any dashboard over historical test results are explicitly NOT in this spec; see
*Out of scope*.

## Why this exists

On 24 September the founder uninstalled Codepet to install a fresh build from
`https://code-pet.com/download` — "to test if it work". That sentence is the whole problem.
There is no definition of *work*, and no way to answer it except by clicking around.

What the repo has today:

- **268 test files, ~1,072 XCTest tests**, run on every PR by `tests.yml` through
  `scripts/ci-test.sh`. They are unit tests. `CompanyStore` is driven entirely through
  injected closures, and CI builds with `CODE_SIGNING_ALLOWED=NO`.
- **Zero `XCUIApplication`.** Nothing has ever driven the real app.
- `pages.yml` publishes a live work stream — commits, PRs, releases, workflow runs. It
  reports on *activity*, never on whether a build launches.

So every check that matters for a release happens in the gap the suite cannot reach:
the signature, the quarantine flag, the keychain, the deployed functions, the founder's
real account. Those are exactly the failures this project keeps rediscovering by hand:

- **14 Aug** — a test build wrote an adhoc, entitlement-less `codepet.app` over the signed
  one in shared DerivedData. Sign-in simply stopped working. Nothing announced it.
  (`scripts/ci-test.sh` now carries its own `-derivedDataPath` because of it.)
- **Chat dead? check BILLING, not the key** — deployed functions read their key from Secret
  Manager, so a chat turn can die in production while every local test is green.
- **"Still looks the same" = STALE BUILD** — the recurring conclusion that a change did not
  work, when the binary under test was never rebuilt.

None of those are catchable by a unit test, and all of them are catchable by launching the
thing and watching what it does.

## Decisions

| Decision | Value | Why |
|---|---|---|
| What is under test | The **installed app bundle** | The artefact a user actually receives — signature, quarantine, entitlements and all. CI's unsigned build cannot answer this. |
| How behaviour is observed | **LevelDB ground truth, logs as evidence** | The app's 103 log call sites are overwhelmingly error-path; the happy path has almost no signposts. A missing log line cannot prove success, but a persisted reply can. |
| How the app is driven | **Minimal System Events** — launch, focus, type, Enter | `count windows` has reported 0 while the app was visibly on screen, and assistive access drops mid-session. Every additional UI assertion is a future false red. |
| Where it lives | `smoke/` in this repo | Checks assert on app behaviour and must move in lockstep with the app. A separate repo drifts. |
| Language | **Python 3, no third-party deps** | Matches `scripts/ci-test.sh`. `fswatch` is not installed and `plyvel` is not available; neither becomes a prerequisite. |
| Task-run check | **Opt-in (`--with-task`)** | It spends real credits on every run. |
| Watch-mode Slack policy | **Transitions only** | Watch mode runs dozens of times a day. A per-run post makes the channel unreadable and trains the team to mute it. |
| Verdict vocabulary | `pass` / `fail` / `error` / `skip` | Lifted from `ci-test.sh`: a harness that broke is not a product regression, and neither one is a pass. |

## Architecture

```
smoke/
  smoke                 # CLI entry point
  lib/
    drive.py            # System Events: launch, focus, type, Enter. The ONLY UI code.
    logstream.py        # wraps `log stream --predicate 'subsystem == "app.murror.codepet"'`
    store.py            # reads the Firestore LevelDB after quit — ground truth
    build.py            # identifies the target: version, codesign, quarantine xattr, mtime
    report.py           # Result[] -> report.json + report.html
    slack.py            # posts the summary via incoming webhook
  checks/
    launch.py  auth.py  chat.py  task.py
  runs/                 # gitignored: runs/<timestamp>/{report.json,report.html,log.txt,*.png}
```

Every unit has one job and a stated dependency. `drive.py` is the only file that knows about
System Events, so the blast radius of accessibility flakiness is one file. `checks/*` are
pure functions over captured evidence — they never touch the app, which is what makes them
unit-testable against fixtures.

### The check contract

Each check returns one record: `{name, status, duration, evidence[], detail}`.

| Status | Meaning | Consequence |
|---|---|---|
| `pass` | The behaviour was observed. | — |
| `fail` | The app is broken. A real regression. | Run is red. |
| `error` | **The harness** broke: accessibility denied, app not installed, our own timeout. | Run is red, and says so differently. |
| `skip` | A dependency failed, or the check was opt-in and not requested. | Neutral. |

The `error` / `fail` split is the point. `ci-test.sh` was shipped reporting a non-building
test target as a dead host, in green, having verified nothing — and the same shape of bug is
available here in a dozen places. A check that could not run must never read as a check that
passed. When launch fails, auth/chat/task report `skip`, so the Slack post names **one**
broken thing rather than four.

### Reading the store without a LevelDB client

`plyvel` is not installed and does not become a prerequisite, so `store.py` does not speak
the LevelDB protocol. It scans the `.ldb` and `.log` files under the database directory for
byte patterns: the run token for check 3, and the account's known key prefixes for check 2.

This is deliberately weaker than parsing, and the limit must be stated rather than
discovered. A byte scan can prove a value **is present**; it cannot prove structure, cannot
read a value it was not told to look for, and will see a key that a later compaction has
tombstoned but not yet removed. That is sufficient here because each check asks a presence
question about a token this run just minted — a token that cannot pre-exist a run.

It is not sufficient for anything richer. If a future check needs to read *state* rather
than confirm presence, this is the seam to replace, and `plyvel` becomes the honest answer
at that point.

### Modes

| Command | Target | Slack |
|---|---|---|
| `smoke run` | `/Applications/codepet.app`, or `--dmg <url>` to download and mount first | every run |
| `smoke run --dev` | the local Xcode build | terminal only, unless `--slack` |
| `smoke watch` | the local build, re-run when it changes | transitions only |

## The four checks

1. **Launch.** `codesign -v` and the `com.apple.quarantine` xattr are read *before* the app
   is opened — Gatekeeper is the likeliest failure for a downloaded build, and it deserves
   its own sentence rather than a generic timeout. Then `open`, then wait for the process
   and a rendered window.
2. **Auth.** After quit, the LevelDB at
   `~/Library/Application Support/firestore/__FIRAPP_DEFAULT/devpet-8f4b1/main` carries a
   user/session document. No screen-scraping and no keychain poking.
3. **Chat round-trip.** `drive.py` types a probe message carrying a unique run token. The
   verdict is that a **reply** persisted against that token — proving app → deployed
   functions → model → back. The log stream is captured alongside as evidence, so a failure
   arrives with `ChatTransport`'s own words attached.
4. **Task run.** Opt-in. Verdict is a terminal state with a deliverable.

## Data flow

A release run:

1. `build.py` identifies the target and records version, `CFBundleVersion`, signature,
   quarantine state, mtime. Every report states which binary it judged.
2. `logstream.py` starts, teeing to `runs/<ts>/log.txt`.
3. Checks run in order, short-circuiting to `skip` on a failed dependency.
4. Teardown — in a `finally` — quits the app and stops the stream.
5. `store.py` reads the LevelDB *now that the lock is released*.
6. `report.py` writes `report.json` and `report.html`.
7. `slack.py` posts the summary.

The Slack message is one compact post, never a thread:

```
🔴 Codepet smoke — 1.0 (2)  ·  installed build  ·  2m14s
✅ Launch      signed, not quarantined, window in 3.1s
✅ Auth        session restored for nguyen@murror.app
❌ Chat        no reply persisted for probe f3a91c after 90s
⏭️ Task        skipped (chat failed)
   ChatTransport: non-streaming retry refused: billing
```

Verdict first, build identity always, and a failure carries the first line of real evidence —
so the channel answers *what broke* without anyone opening an artefact.

### Watch mode

Polls the built bundle's `Info.plist` mtime and debounces until 3s of quiet, because a build
writes many files. Then, in order:

- **Freshness gate.** Compare `CFBundleVersion` and mtime against the last run and refuse to
  report on a bundle that did not change. The stale-build trap is caught by the tool instead
  of by a person concluding their change did not work.
- **Never hijack the app.** If `codepet.app` is already running, the tool determines whether
  *it* launched it. If the founder did, it prints `deferred: your app is running` and waits.
  It does not `pkill`. A running app is also what kills an `xcodebuild test` host, so the
  same guard protects the unit suite.
- **Lockfile** at `smoke/runs/.lock`, so two runs — or two parallel Claude sessions — cannot
  drive the app at once.

## Error handling

- **Every check is bounded by its own timeout**, and a timeout is `error`, not `fail`.
  We did not observe a regression; we failed to observe anything.
- **Teardown always runs.** A crashed check must not leave the app holding the LevelDB lock
  and blocking the next `xcodebuild test`.
- **Launch flags go through `--args`, never `defaults write`.** A leftover sandbox container
  silently redirects the `app.murror.codepet` domain, and `defaults read` then confirms the
  lie. Anything the harness needs to set, it sets at launch.
- **The LevelDB is read only after the app quits.** LevelDB holds a single-process lock;
  reading underneath a live app is how this codebase has produced phantom results before.
- **Slack never rewrites the verdict.** The local report is the record; Slack is a
  notification about it. A failed post leaves the run's verdict exactly as the checks found
  it, and is surfaced as its own line — a green run whose post did not deliver is still a
  green run, and must not be re-reported as a failure.

## Cost and blast radius

- `--with-task` is opt-in and watch mode never runs it.
- Chat probes cost credits too, so watch mode runs at most once per changed build.
- Probes carry a run token and go to a dedicated project, so smoke traffic is identifiable
  and never mixes into real founder work.

## Testing

The checks are pure functions over captured evidence, so they are unit-tested against
recorded fixtures: real `log stream` output and real LevelDB dumps, captured once from a
genuine run.

Per this project's own rule, every fixture is hand-traced before it is trusted, and each
guard is broken deliberately and watched to go red. Five tests in one earlier plan could not
fail — a floor test scoring 0, a substring test whose words contained no search term — and a
green test that cannot fail is worse than no test, because it is believed.

`drive.py` is the one unit that cannot be fixture-tested. It is therefore kept as small as
the four checks allow.

## Out of scope

- **XCUITest.** Considered and rejected: macOS runners bill at 10x and UI tests are the
  flakiest thing available to put in CI. This tool runs on the founder's Mac, against a
  signed build, with a real login — none of which a runner has.
- **A dashboard over the ~1,072 unit tests** — pass-rate history, flake ranking. A real gap
  (xcresult bundles are uploaded only on failure, retained 7 days), but a different project.
- **Reporting to Notion.** Slack was chosen. `/eng-log` already owns the Notion surfaces.
- **Running in GitHub Actions.** The app cannot reach Firebase auth unsigned, so a runner
  cannot execute these checks at all.

## Open questions

1. **The Slack channel is unreachable.** `C0C3Y0QP6Q5` returns `channel_not_found` — it is
   not among the 33 channels this account belongs to, so it is either private with the Claude
   app uninvited, or in another workspace. Resolved by `/invite @Claude` in that channel.
2. **The webhook does not exist yet.** Standalone posting needs an incoming webhook URL
   created once in Slack and stored locally — keychain, or a gitignored file. Until then,
   only the in-session path can post.
3. **The dedicated probe project** for check 3 has not been created.

None of the three block implementation; all three block the first green run.
