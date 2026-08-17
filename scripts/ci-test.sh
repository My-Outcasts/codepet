#!/bin/bash
# Run the Swift test suites and report an honest pass/fail.
#
# Why this exists rather than a bare `xcodebuild test` step: counting tests by grepping
# xcodebuild's log is wrong in both directions here. `^Test Case .*passed` OVERCOUNTS
# (each case prints on start and on finish), and the console's own "Executed N tests"
# line is truncated when the run is large. `xcresulttool get test-results summary` reads
# the result bundle and is the only count this project trusts.
#
# It also separates the ways a run can end badly, which xcodebuild collapses into one exit
# code:
#   TESTS FAILED          a real regression — the thing CI is for
#   TARGET DID NOT BUILD  also a regression, and NOT the same message
#   HOST DIED PART WAY    an environment problem; what ran is real, the rest is uncovered
#   NOTHING RAN           unverified, which is never a pass
# Reporting the second as the third is how a red build ships: it happened on 14 Aug, when a
# test-target compile error was announced as "the host died … not treated as a regression"
# and exited 0. Reporting the third as the first is how a team learns to ignore its own CI.
set -uo pipefail

RESULT_BUNDLE="${RESULT_BUNDLE:-build/ci.xcresult}"
SCHEME="${SCHEME:-codepet}"
PROJECT="${PROJECT:-CodePet.xcodeproj}"

# Suites excluded from CI, each with a reason and an owner-facing note. Anything listed
# here is NOT covered — that is the cost of listing it, so keep the list short and keep
# the reasons specific enough to re-test later.
#
# Both entries were measured, not assumed: a full run on `main` at dcedbce (1072 tests,
# nothing of this branch in it — the workflow files were still untracked) came back
# 1063 passed / 9 failed. Those 9 are these two suites. CI starts green so that the first
# red anyone sees is a real regression rather than inherited debt; the debt is named here
# instead of being hidden.
#
# THE LIST IS NOW EMPTY, and it should stay that way. Both former entries turned out to be
# stale TESTS rather than broken code, each asserting a product rule the founder had changed:
#   - RoadmapEngineSuggestedNextTests — the pre-Aug-5 phase window (d8e9b64). Fixed in #95.
#   - VirtualCompanyInterviewTests — convening from every message rather than from Plan only
#     (b42bc10, Aug 7, a ~$0.20-vs-~$0.005 cost gate). Its 8 failures were all one missing
#     `convenesRoom: true`. Fixed here.
# Both were reported as possible product bugs first. The pattern is worth naming: a red test
# whose subject is a RULE is stale until the rule's own file and history have been read.
#
# RoadmapEngineSuggestedNextTests was the second entry here and is NOW GUARDED AGAIN. It was
#   never a product bug: `testConfinedToTheOpenWindow` asserted the pre-Aug-5 phase-window rule,
#   which `d8e9b64` deliberately changed (a founder-owned step stopped gating; only an unapproved
#   draft does). The comment that used to sit here called it a possible leak sending founders at
#   work their roadmap had not opened — that was wrong, and the answer was already written in a
#   doc comment in RoadmapGating.swift. Test rewritten to the current rule, skip removed.
SKIP_SUITES=()

# `${arr[@]+...}` because macOS ships bash 3.2, where `"${arr[@]}"` on an EMPTY array trips
# `set -u` with "unbound variable" — so emptying the skip list would otherwise break the run
# it is meant to widen.
skip_args=()
for suite in ${SKIP_SUITES[@]+"${SKIP_SUITES[@]}"}; do
  skip_args+=("-skip-testing:${suite}")
done

rm -rf "$RESULT_BUNDLE"

# CODE_SIGNING_ALLOWED=NO: a CI runner has no Apple Development identity. The app cannot
# reach Firebase auth unsigned (see CLAUDE.md), but no test in this suite talks to a live
# Firebase — CompanyStore is driven entirely through injected closures — so unsigned is
# the right trade for CI. A signed build stays the requirement for anything a human runs.
#
# -derivedDataPath: ITS OWN, and this is not tidiness.
#
# Without it this test build writes an adhoc, entitlement-less codepet.app over the signed
# one in the shared DerivedData. Nothing announces it. The next launch looks identical and
# sign-in is simply broken, because Firebase auth needs the keychain and adhoc does not get
# it — which is exactly what happened on 14 Aug: run the suite, relaunch, spend the next
# stretch wondering why signing in stopped working.
#
# The cost is one cold build the first time and a second DerivedData on disk. The trap it
# removes is silent, hits a human rather than CI, and looks like a product bug.
DERIVED_DATA="${DERIVED_DATA:-build/dd-ci}"

set -x
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  ${skip_args[@]+"${skip_args[@]}"} \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE"
xcodebuild_status=$?
set +x

if [ ! -d "$RESULT_BUNDLE" ]; then
  echo "::error::No result bundle at $RESULT_BUNDLE — the build itself failed before any test ran."
  exit "${xcodebuild_status:-1}"
fi

# Build errors live in the SAME bundle, under a different subcommand. Read them before
# the test summary, because a test target that failed to compile produces a bundle whose
# test summary is a perfectly well-formed zero.
build_json=$(xcrun xcresulttool get build-results --path "$RESULT_BUNDLE" 2>/dev/null)

summary=$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" 2>&1)
if [ -z "$summary" ] || ! printf '%s' "$summary" | head -c1 | grep -q '{'; then
  # Says "treating as failure" and now actually does. This used to
  # `exit "${xcodebuild_status:-1}"`, which is 0 whenever the tests themselves passed — so
  # the branch that exists to refuse to guess was reporting green while announcing it
  # could not verify anything. If the bundle is unreadable, the run is unverified, and
  # unverified is not a pass.
  echo "::error::Could not read a summary from $RESULT_BUNDLE — the run is unverified."
  printf '%s\n' "$summary" | head -5
  exit 1
fi

# The summary travels in the ENVIRONMENT, not on stdin, and that is load-bearing.
#
# This was `python3 - "$status" <<'PY' ... PY <<<"$summary"`, which has TWO stdin
# redirections. The here-string wins, so python read its PROGRAM from the JSON — and a JSON
# object is a valid Python dict literal, so it evaluated cleanly, printed nothing, and
# exited 0. Every check below was dead code, and three green CI runs said nothing beyond
# "xcodebuild exited 0". A crash would have been kinder; this failed silently in the exact
# direction that looks like success. Found by asking why the summary line never appeared in
# the logs.
SUMMARY_JSON="$summary" BUILD_JSON="$build_json" python3 - "$xcodebuild_status" <<'PY'
import json, os, sys
status = int(sys.argv[1])
d = json.loads(os.environ["SUMMARY_JSON"])
total   = d.get("totalTestCount") or 0
passed  = d.get("passedTests") or 0
failed  = d.get("failedTests") or 0
skipped = d.get("skippedTests") or 0
fails   = d.get("testFailures") or []

print(f"total {total} · passed {passed} · failed {failed} · skipped {skipped}")
for f in fails:
    name = f.get("testName") or "(unnamed)"
    text = (f.get("failureText") or "").splitlines()
    first = text[0] if text else ""
    print(f"::error::{name} — {first}")

if failed:
    print(f"\nFAILED: {failed} test(s) — a real regression.")
    sys.exit(1)

# NOTHING RAN. Never a pass, whatever the cause.
#
# This branch used to be folded into the host-death case below, which exits 0 — so on
# 14 Aug a test target that failed to COMPILE was reported as "the test host died mid-run
# … not treated as a regression", in green, having verified nothing at all. Same shape as
# the two bugs already recorded in this file: a check that announces it cannot verify
# something and then passes it anyway.
#
# Zero tests has two causes and they need different words, because they need different
# fixes: fix your code, versus re-run the flake.
if total == 0:
    errors = []
    try:
        build = json.loads(os.environ.get("BUILD_JSON") or "{}")
        for e in (build.get("errors") or []):
            # `sourceURL` is a file: URL with the position in its fragment —
            # unreadable in a CI log, so reduce it to the path:line a person
            # can paste into an editor.
            raw = e.get("sourceURL") or ""
            where = e.get("targetName") or ""
            if raw.startswith("file://"):
                path = raw.split("#", 1)[0].replace("file://", "")
                line = ""
                if "#" in raw:
                    for part in raw.split("#", 1)[1].split("&"):
                        if part.startswith("StartingLineNumber="):
                            line = ":" + part.split("=", 1)[1]
                where = os.path.relpath(path, os.getcwd()) + line
            message = e.get("message") or e.get("title") or ""
            errors.append(f"{where}: {message}".strip(": "))
    except (ValueError, TypeError):
        pass

    if errors:
        print(f"\n::error::The test target did not BUILD — {len(errors)} compile error(s), "
              f"so no test ran. This is a regression in the code, not a flaky host.")
        for line in errors[:10]:
            print(f"::error::{line}")
    else:
        print(f"\n::error::No test ran and xcodebuild exited {status}, with no compile "
              f"error in the bundle — the host died before the first test. Re-run; if it "
              f"repeats, it is not the known flake.")
    sys.exit(1)

# Some tests ran, none failed, and xcodebuild still complained: the host died PART WAY
# through. Coverage is incomplete but what did run is real, so this stays a non-blocking
# warning — with the number attached, because "incomplete" without a count is unactionable.
if status != 0:
    print(f"\n::warning::{passed} test(s) passed and none failed, but xcodebuild exited "
          f"{status} — the test host died PART WAY through rather than a test failing. "
          f"This is the known @MainActor ObservableObject dealloc crash (CLAUDE.md "
          f"landmine 3). Not a regression, but the suite did not finish: whatever runs "
          f"after the crash point was NOT covered this run.")
    sys.exit(0)

print(f"\nAll {passed} test(s) passed.")
sys.exit(0)
PY
