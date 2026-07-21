# Reconciliation Stage 1 — Merge main + Retire the Old Roadmap — Implementation Plan

> **For agentic workers:** This is a git merge/reconciliation, not feature TDD — execute the steps IN ORDER, inline (controller), verifying build+test green BEFORE committing the merge. Do NOT delegate individual steps to subagents (a merge is atomic). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Merge `origin/main` into `feat/native-web-product`, resolve native-wins, retire the old roadmap, verify the full suite green, commit the merge, push, and open a PR to `main`.

**Architecture:** No app-behavior change. Bring `main`'s history under the branch; keep native `RoadmapTask`/`RoadmapEngine`; drop the old SP3 roadmap so the target compiles. Spec: `docs/superpowers/specs/2026-07-21-reconciliation-stage1-merge-roadmap-design.md`.

## Global Constraints
- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product` (tip `1200af1`). `origin/main` = `50520f3`. merge-base = `46c61d9`.
- **iCloud git:** always `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false`; on any hang/lock, `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` and retry. `merge`/`commit`/`reset` can hang — long timeouts + retry.
- **Toolchain:** scheme **`codepet`** (lowercase); **FOREGROUND** `xcodebuild`. Build: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`. Test: `... xcodebuild test ... 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail -3` → `** TEST SUCCEEDED **`. SourceKit cross-file diagnostics are FALSE POSITIVES.
- **The merge must NOT be committed until build + full test are green** (Step 8). Rollback anytime before commit: `git merge --abort` (retry; if iCloud stat-cache blocks it, `git reset --hard HEAD` restores `1200af1`).
- Don't touch Giang's Build Coach files. Precondition: tree is clean at `1200af1` (verify at Step 1).

---

### Task 1: Merge + resolve + verify + commit

**Files touched:** conflict-resolve `RoadmapTask.swift`/`RoadmapEngine.swift`/`RoadmapEngineTests.swift` (native); take-branch-version `Project.swift`/`ProjectStore.swift`/`ProjectFolderView.swift`/`ReflectionAPIClient.swift`; delete `RoadmapSectionView.swift` + 4 old tests.

- [ ] **Step 1: Confirm clean precondition**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false rev-parse --short HEAD          # expect 1200af1
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false status --porcelain | head       # expect EMPTY (clean)
```
Expected: HEAD `1200af1`, clean tree. If not clean → `git reset --hard HEAD` first.

- [ ] **Step 2: Start the merge (no commit)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false merge --no-commit --no-ff origin/main 2>&1 | tail -20
```
Expected: `CONFLICT (add/add)` on `RoadmapTask.swift`, `RoadmapEngine.swift`, `RoadmapEngineTests.swift`; "Automatic merge failed; fix conflicts and then commit."

- [ ] **Step 3: Verify the conflict set is exactly the 3 expected**

```bash
cd ~/Documents/codepet-rebuild-wt
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false diff --name-only --diff-filter=U
```
Expected exactly: `codepet/Models/RoadmapEngine.swift`, `codepet/Models/RoadmapTask.swift`, `codepetTests/RoadmapEngineTests.swift`. If MORE conflicts appear, STOP and re-assess (a main-added file the scope missed) before proceeding.

- [ ] **Step 4: Resolve the 3 conflicts — native (ours/HEAD) wins**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false checkout --ours -- \
  codepet/Models/RoadmapTask.swift codepet/Models/RoadmapEngine.swift codepetTests/RoadmapEngineTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add \
  codepet/Models/RoadmapTask.swift codepet/Models/RoadmapEngine.swift codepetTests/RoadmapEngineTests.swift
# sanity: no conflict markers remain in these files
grep -lE '^(<<<<<<<|=======|>>>>>>>)' codepet/Models/RoadmapTask.swift codepet/Models/RoadmapEngine.swift codepetTests/RoadmapEngineTests.swift || echo "clean (no markers)"
```
Expected: "clean (no markers)".

- [ ] **Step 5: Take the branch version of the 4 consumers (drop SP3 roadmap, keep enrichBrief)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false checkout HEAD -- \
  codepet/Models/Project.swift \
  codepet/Managers/ProjectStore.swift \
  codepet/Views/Tips/ProjectFolderView.swift \
  codepet/Services/ReflectionAPIClient.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add \
  codepet/Models/Project.swift codepet/Managers/ProjectStore.swift \
  codepet/Views/Tips/ProjectFolderView.swift codepet/Services/ReflectionAPIClient.swift
# sanity: enrichBrief kept, scaffoldRoadmap gone in ReflectionAPIClient
grep -c "func enrichBrief" codepet/Services/ReflectionAPIClient.swift    # expect >= 1
grep -c "scaffoldRoadmap" codepet/Services/ReflectionAPIClient.swift     # expect 0
```
Expected: `enrichBrief` count ≥ 1, `scaffoldRoadmap` count 0.

- [ ] **Step 6: Delete the dead old-roadmap files main added**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false rm -f \
  codepet/Views/Tips/RoadmapSectionView.swift \
  codepetTests/RoadmapTaskTests.swift \
  codepetTests/RoadmapSectionModelTests.swift \
  codepetTests/ProjectStoreRoadmapTests.swift \
  codepetTests/ReflectionAPIClientScaffoldTests.swift 2>&1 | tail
# final scope check: no remaining references to the OLD roadmap API anywhere
grep -rlE "RoadmapNextStep|\.deptKey|deptKey:|scaffoldRoadmap|RoadmapSectionView|RoadmapEngine\.nextStep\(.*stage" codepet codepetTests 2>/dev/null | grep -vE "CompanyData.swift|CompanyChatClient.swift" || echo "no old-API refs remain"
```
Expected: "no old-API refs remain" (only the incidental `CompanyData`/`CompanyChatClient` comment matches are excluded; if any OTHER file lists, it still uses the old API — take its branch version or strip, then re-run).

- [ ] **Step 7: Build to verify it compiles (merge still uncommitted)**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`. If a compile error names another old-API consumer, `git checkout HEAD -- <that file>` (if dead) or strip the reference, `git add`, and re-build.

- [ ] **Step 8: Run the FULL test suite (the gate)**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|-\[.*\] failed" | tail -6`
Expected: `** TEST SUCCEEDED **` (native `RoadmapTaskModelTests`/`RoadmapEngineTests`/`RoadmapBoardHelpersTests` + every phase's suite; old-roadmap tests removed). **Do NOT proceed to commit until this is green.**

- [ ] **Step 9: Commit the merge**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
printf '%s\n' 'merge: origin/main → feat/native-web-product; retire the old SP3 roadmap' '' \
  'Merge main (Phases 1+2 via PR #4 + PR #2/#3) under the branch. Resolve the 3 add/add' \
  'conflicts native-wins (RoadmapTask/RoadmapEngine + RoadmapEngineTests). Take the branch' \
  'version of the 4 consumers (Project/ProjectStore/ProjectFolderView/ReflectionAPIClient) —' \
  'drops SP3 roadmapTasks/scaffoldRoadmap, keeps enrichBrief. Delete RoadmapSectionView + the' \
  '4 old roadmap tests. Native RoadmapTask/RoadmapEngine are the go-forward. Build + full suite GREEN.' '' \
  'Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>' \
  > /private/tmp/claude-501/-Users-monatruong/91dd5ce8-f87d-4104-8427-1676fe5f3070/scratchpad/mergemsg.txt
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F /private/tmp/claude-501/-Users-monatruong/91dd5ce8-f87d-4104-8427-1676fe5f3070/scratchpad/mergemsg.txt 2>&1 | tail -3
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false log --oneline -1                 # the merge commit
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false rev-parse --short HEAD^2 2>/dev/null && echo "has 2 parents (merge commit)"
```
Expected: a merge commit with two parents (`HEAD^2` resolves). If the commit hangs, `rm` the lock and retry (it usually lands on retry).

---

### Task 2: Push + PR

- [ ] **Step 1: Push the branch**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false push origin feat/native-web-product 2>&1 | tail -5
```
Expected: push succeeds (branch now contains the merge + all native phases).

- [ ] **Step 2: Confirm the branch is no longer behind main + open the PR**

```bash
cd ~/Documents/codepet-rebuild-wt
# branch should now contain origin/main (0 behind)
gh api "repos/My-Outcasts/codepet/compare/main...feat/native-web-product" --jq '{ahead:.ahead_by, behind:.behind_by, status:.status}'
```
Expected: `behind: 0` (main is now an ancestor). Then open the PR:
```bash
gh pr create --repo My-Outcasts/codepet --base main --head feat/native-web-product \
  --title "Native = web product: full rebuild (Phases 1–8) + retire old roadmap" \
  --body "$(printf '%s\n' \
    'Lands the completed native=web-product rebuild on main.' '' \
    '## What' \
    '- All 8 phases: shell + CompanyStore, onboarding/brief, Overview roadmap board (3A/3B), Copilot chat (5), deliverables + Library (6A/6B/6C), Environment/toolkit (7), Settings (8).' \
    '- ContentView routes to AppShellView (native); CompanyStore/companies-{uid} replaces the reflection ProjectStore path.' '' \
    '## Reconciliation (Stage 1)' \
    '- Merges origin/main and retires the old SP3 roadmap: native RoadmapTask/RoadmapEngine win the add/add conflict; SP3 roadmapTasks/scaffoldRoadmap/RoadmapSectionView + 4 old roadmap tests removed. enrichBrief kept.' '' \
    '## Not in this PR (Stage 2)' \
    '- Full deletion of the dead game/reflection stack (MainTabView/ReflectionTab/ProjectStore + ~15 old stores) — a separate staged effort.' '' \
    '## Gen backend' \
    '- scaffoldRoadmap / companyChat / runTask CFs are fail-open + UNDEPLOYED (node-22) — roadmap-gen/chat/deliverable-gen are wired+tested but inert until deploy.' '' \
    'Full build + test suite green.' '' \
    '🤖 Generated with [Claude Code](https://claude.com/claude-code)')"
```
Expected: PR created; print its URL. (If `gh pr create` reports a PR already exists for the branch, it prints that URL instead — report it.)

---

## Final verification
The branch's merge commit is pushed; `gh api compare main...feat/native-web-product` shows `behind: 0`; a PR to `main` is open. `main` is now mergeable to land the full native product (Stage 1 scope). Report the PR URL.

---

## Self-Review
**Spec coverage:** merge no-commit (T1 S2 ✓); native-wins the 3 conflicts (T1 S4 ✓); branch-version the 4 consumers keeping enrichBrief (T1 S5 ✓); delete the 5 dead files (T1 S6 ✓); build + full-test gate before commit (T1 S7-8 ✓); commit merge (T1 S9 ✓); push + PR (T2 ✓). Rollback documented (Global Constraints). Stage 2 out of scope (spec).

**Placeholder scan:** none — every step is an exact command with expected output.

**Consistency:** the resolution verbs match the spec (`checkout --ours` for conflicts, `checkout HEAD --` for consumers, `git rm` for dead files); the verification gate precedes the commit; iCloud lock-handling on every git write.

**Known notes for the executor:** (a) execute INLINE (controller) — a merge can't be split across subagents; (b) if Step 3's conflict set is larger than the 3 expected, or Step 7 surfaces another old-API consumer, resolve it the same way (branch version if dead / strip if native) and re-verify — do not force past a red build/test; (c) the commit is a real merge commit (2 parents) — confirm via `HEAD^2`; (d) nothing is committed until Step 8 is green, so any failure is a clean `merge --abort`/`reset --hard` back to `1200af1`.
