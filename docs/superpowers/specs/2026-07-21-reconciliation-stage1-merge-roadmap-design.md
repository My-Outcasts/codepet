# Reconciliation Stage 1 — Merge main + Retire the Old Roadmap — Design Spec

**Date:** 2026-07-21
**Context:** The native=web-product rebuild is complete on `feat/native-web-product` (all 8 phases, tip `1200af1`), but can't PR to `main`: the branch was cut off `main` at `46c61d9` (merge-base) before PR #3 (old SP3 reflection roadmap-core) merged, so `main` (`origin/main` = `50520f3`, the PR #4 merge) carries the old `RoadmapTask`/`RoadmapEngine` that add/add-conflict with the native ones. This is **Stage 1** of a staged reconciliation (approved): merge + retire only the old roadmap to unblock `main`. The full game/reflection deletion is Stage 2 (separate effort).
**Goal:** Merge `origin/main` into the branch, resolve so **native wins**, retire the old-roadmap files/consumers, verify the full suite green, push, and open a PR to `main` — landing the finished native product on `main`.

---

## Approved decisions (brainstorming)
1. **Staged** — Stage 1 (this) merges + reconciles only the roadmap; Stage 2 (later) deletes the whole old game/reflection stack.
2. **Merge** `origin/main` into the branch (a merge commit) — **not** rebase (the branch is pushed with shared history).
3. **Native wins** the roadmap; the broader dead game/reflection stays as-is (off the live path, compiles).

## Scope-pass findings (blast radius, verified)
- **3 add/add conflicts** (native/HEAD wins): `codepet/Models/RoadmapTask.swift`, `codepet/Models/RoadmapEngine.swift`, `codepetTests/RoadmapEngineTests.swift`.
- **4 consumers** carry SP3's roadmap additions (`roadmapTasks` field, `roadmapTasks(for:)`/`setRoadmapTasks`/`toggleRoadmapTask`, the `RoadmapSectionView(...)` block, `scaffoldRoadmap` + its DTOs). **All 4 also exist on the branch HEAD in their pre-roadmap form** (the branch never added the old roadmap; its `ReflectionAPIClient` has `enrichBrief`, which native uses, but no `scaffoldRoadmap`). So taking the **branch/HEAD version** of each cleanly drops the old roadmap while keeping what native needs.
- **5 dead files main adds** (not on the branch): `codepet/Views/Tips/RoadmapSectionView.swift` + tests `RoadmapTaskTests`, `RoadmapSectionModelTests`, `ProjectStoreRoadmapTests`, `ReflectionAPIClientScaffoldTests`.
- `CompanyData`/`CompanyChatClient` matched the grep only incidentally (a comment referencing the deferred `scaffoldRoadmap` CF); they use native `RoadmapTask` and need no change.

## Resolution procedure

### 1. Merge (no commit)
`git merge --no-commit --no-ff origin/main` — stops with the 3 add/add conflicts; the consumers + other main changes auto-merge.

### 2. Conflicts → native (HEAD/ours)
`git checkout --ours` + `git add` for the 3 conflicted files → keep the native roadmap.

### 3. Consumers → branch version (drop SP3's roadmap additions)
`git checkout HEAD -- ` + `git add` for:
- `codepet/Models/Project.swift` (drops the old `roadmapTasks` field)
- `codepet/Managers/ProjectStore.swift` (drops the roadmap-task methods)
- `codepet/Views/Tips/ProjectFolderView.swift` (drops the `RoadmapSectionView` section)
- `codepet/Services/ReflectionAPIClient.swift` (drops `scaffoldRoadmap` + DTOs; **keeps** `enrichBrief`)

(These are dead-path files except `ReflectionAPIClient.enrichBrief`; taking the branch version is safe — native never touched their roadmap and any non-roadmap main additions to dead files are irrelevant.)

### 4. Delete the dead old-roadmap files main added
`git rm`:
- `codepet/Views/Tips/RoadmapSectionView.swift`
- `codepetTests/RoadmapTaskTests.swift`, `codepetTests/RoadmapSectionModelTests.swift`, `codepetTests/ProjectStoreRoadmapTests.swift`, `codepetTests/ReflectionAPIClientScaffoldTests.swift`

### 5. Verify (the gate — before committing the merge)
Foreground `xcodebuild build` then full `xcodebuild test` → **all green**. This proves no lingering old-roadmap reference (`deptKey`/`RoadmapNextStep`/`scaffoldRoadmap`/`RoadmapSectionView`) survives and the native roadmap + all 8 phases' suites pass. If the build surfaces any other file still referencing the old API (a main-added consumer the scope grep missed), take its branch version or strip the reference, and re-verify.

### 6. Land
Commit the merge (a merge commit — both parents), push `feat/native-web-product`, open a fresh PR to `My-Outcasts/codepet` `main`.

## Data flow / architecture
No app-behavior change: the native app already routes `ContentView → AppShellView`/`CompanyStore` and uses native `RoadmapTask`/`RoadmapEngine`. This merge brings `main`'s history (Phases 1+2 + PR #2/#3) under the branch, keeps native's roadmap, and removes the old roadmap so the target compiles.

## Error handling / rollback
The whole resolution happens in the merge state before the commit. If verification fails and can't be quickly resolved, `git merge --abort` (retry; if the iCloud stat-cache blocks it, `git reset --hard HEAD` restores `1200af1`) — nothing is committed until build+test are green. iCloud: `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false`; `rm` the worktree `index.lock` on hangs.

## Testing
No new tests — this is a reconciliation. **Success = the existing full `xcodebuild test` suite stays green** after the merge (native `RoadmapTaskModelTests`/`RoadmapEngineTests`/`RoadmapBoardHelpersTests` + every phase's suite), with the old-roadmap tests removed.

## Out of scope (Stage 2)
Deleting the broader dead game/reflection stack (`MainTabView`, `ReflectionTab`, `ProjectStore`/`Project`, the ~15 old stores in `CodePetApp`, game views) + untangling `CodePetApp`/`ContentView` — its own staged effort after native is on `main`.

## Open decisions
None — resolved in brainstorming (staged; merge-not-rebase; native wins; take branch version of consumers; delete main-added dead files). Ready for implementation planning.

## Constraints
Don't touch Giang's Build Coach files (BuildCoachView/InstallView/SummaryView, tracking, `/api/track*`, `/api/build-plan`). Worktree `~/Documents/codepet-rebuild-wt` (isolated).
