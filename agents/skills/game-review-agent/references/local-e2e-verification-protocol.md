# Local E2E Verification Protocol (review agent's evidence layer)

> Design: `docs/PLAN-e2e-verification.md` (execution) + `docs/PLAN-e2e-verification-v2.md`
> (design record) in agent-game-test. Implemented Phase 1: 2026-07-31, branch
> `impl/e2e-local-verification`, commit 52052ab (pipeline suite 69 → 93 tests).
> Purpose: prove "the game actually looks right and actually plays" with REAL
> rendered frames on the PR branch, isolated in a git worktree, evidence posted
> to the PR.

## Standard tool: scripts/run-e2e-review.sh

Review agent runs this INSTEAD of hand-typed checkout/stash commands (the
7-pitfall family). It does P0-P8:

```
P0 pre-flight   caffeinate guard / godot detect / worktree conflict / branch fetch
P1 worktree     git worktree add /tmp/wt-impl-<N> <impl-branch>  (main tree untouched)
P2 L0 compile   --headless --script tests/check_compile.gd
P3 L1 logic     --headless --script tests/run_tests.gd  (+ content: schema/Hemingway/completeness)
P4 L2 runtime   --headless tests/playthrough_test.tscn
P5 L3 visual    non-headless + in-process capture, archetype-driven, 4-fold assertions
P6 evidence     user-attachments upload → gh pr comment (screenshots + summary)
P7 summary      summary.json + exit code
P8 cleanup      trap EXIT removes worktree (merge --delete-branch must not be blocked)
```

Exit codes: 0 all pass / 1 layer failure / 2 pre-flight failure.
Flags: `--subproject NAME --skip-visual --baseline --no-comment --keep --dry-run`.

### Testability env injection (used by tests/pipeline/test_e2e_runner.py)
`RUNNER_GODOT` (fake godot in CI), `E2E_REPO_ROOT`, `E2E_WORKTREE_ROOT`,
`E2E_BRANCH`, `E2E_GH_REPO`, `E2E_DIFF_FILES`, `E2E_PLAN_PATH`.
Tests use a temp git repo + fake godot that writes gradient PNGs (with theme
patch) on `--display-driver` invocations.

### Missing test files are NOT failures
Layer exit codes: 0=pass, 1=fail, 2=unavailable (file missing). Only 1 makes
the run red; unavailable layers warn only (greenfield scaffolds, games that
haven't authored their tests yet).

## Verification archetypes (diff-driven selection)

`scripts/e2e/resolve_plan.py` selects shot-plan groups by PR diff regexes.
Default fallback: `loop`. Principle: **verification method = bounded automation
of what the producer would do for that issue type**:

| Archetype | Producer instinct | Screenshot semantics |
|-----------|-------------------|----------------------|
| loop      | play one round     | title / mid-game (with movement evidence) / terminal — 3 shots |
| journey   | play the whole game| full playthrough + transcript + state trajectory (content/narrative) |
| walkthrough | check one scene  | jump-trigger + data↔screen fidelity assertion (Label.text == JSON) |
| visual    | stare at the effect| specific effect freeze-frame |
| scaffold  | tour every scene  | boot + one frame per scene |

Shot plan (`<game>/e2e_shots.json`, game-authored at C5.5 assembly): groups +
`match` regexes + state-machine driven shots (`state`, `settle_frames`,
`require: {node, prop, min}` for "game is moving" evidence, `at_frame` fallback,
`press` for input injection). Framework owns machinery; game owns the script.

### Depth ladder for content issues (L1/L3/L4)
- 1 file / typo-level → L1 headless only (schema + Hemingway + completeness)
- single-scene dialogue → walkthrough
- multi-scene / echo / endings → journey (default for content, conservative)
- release milestone → 3-tester multi-path playtest (godot-playtest-protocol)
- **Human taste is a layer (L4)**: machine proves structure (L1) and rendering
  (L3); "does it FEEL right" is human. Content issues default to human
  confirmation — screenshots + dialogue transcript are the review material.

## 4-fold anti-fake assertions (scripts/e2e/analyze_bmp.py, pure stdlib PNG)

1. non-black (near-black ratio ≤ 0.5)
2. color count ≥ 3 (flat frame = frozen/load failure)
3. theme color present (hex, RGB tol 32)
4. frame-diff vs previous shot (Δluma ≥ 5) — catches frozen/one-frame-loop bugs
   that system screenshots can't even see.

Black image = capture failure = fail-fast. NEVER post a black image as evidence.

## Capture template pitfalls (real-render only — canary #358, 2026-08-10)

These 5 bugs were invisible to unit tests (fake godot) and only surfaced on
the FIRST real Godot run. If L3 visual fails with "shot missed" or script
errors, check these first:

1. **JSON numbers are floats** — `JSON.parse_string()` makes every number a
   float; `typeof(want) == TYPE_INT` never matches → shots never ready.
   Compare numerically: `var want: int = int(states[d["state"]])`.
2. **`Node.get()` takes ONE argument** — `node.get(prop, default)` is a
   parse error. Read the prop, default after null check.
3. **`:=` from a Variant** — `var want := dict.get(...)` triggers
   warning-as-error in 4.7.1. Use explicit `var want = ...` (or `: int =`).
4. **`Input.action_press()` emits NO InputEvent** — FSM games driven by
   `_input(event)` never see it. Use real `InputEventKey` via
   `Input.parse_input_event()` (shot plan `"press": {"key": "enter"}`).
5. **Press must fire BEFORE the readiness check** — a press DRIVES the game
   into the shot's state; checking first deadlocks (state never changes,
   press never fires).

Plus: tune `ai_position_error` up (e.g. 200) so AI rallies END — a perfect
rally never reaches GAME_OVER within the deadline.

### L3 degrade gate (2026-08-10, canary #358 lesson)

L3 visual failure must NOT be silently downgraded to PASS just because the
rest of the checklist is green. Policy:

- **Degrade ONLY with evidence** — attach the P5-visual.log proving the
  failure is harness-side (capture.gd parse error, worktree flake, timeout)
  and NOT game content. If the log shows the game rendered but assertions
  failed (black shot, wrong theme, assert_text mismatch) → that is a REAL
  visual defect → REQUEST_CHANGES, never degrade.
- **Visual-scope issues (视觉相关 issue): L3 failure ALWAYS → human**.
  The screenshot is the issue's deliverable; a missing/invalid screenshot
  means the deliverable is unproven. Merge requires human confirmation.
- Use `assert_text` in shot plans to prove text deliverables (e.g. version
  number) are actually rendered — a frame existing ≠ the text showing.

### Security note: runner executes untrusted PR code

The runner runs the PR branch's GDScript locally with FULL filesystem access
(`--path` + real engine). Worktree isolation prevents main-workspace
contamination but NOT malicious code reading `~/.hermes/.env` (tokens).
Mitigations: worktree under /tmp + trap cleanup, single-owner repos.
Do NOT run the runner on PRs from untrusted contributors.

## Evidence upload (verified 2026-07-31)

GitHub REST API has NO comment-attachment endpoint (verified against
github/rest-api-description OpenAPI). Two paths:
- Primary: web endpoint `POST https://github.com/upload/policies/assets`
  (Bearer GH_TOKEN, multipart name+content_type) → `upload_url` + `asset_id`
  → PUT file → comment with `https://github.com/user-attachments/files/<id>/<name>.png`
- Fallback: `gh gist create --public` → raw URL (best-effort).

## Failure handling protocol (local e2e failure)

**Do NOT route local e2e failures into the CI-driven self-correct loop.**
`SPAWN: self-correct` fires only on `check_run.completed(failure)`; a local
failure means CI is GREEN (that's why review spawned) — no event exists, and
CI can never re-verify a local-only bug (ubuntu headless can't render).
Routing it through CI creates a NON-CONVERGING loop: fix → push → CI green →
review re-spawns → local red again, burning a full diagnose→fix→CI→review cost
per round. **The loop that detects a bug must be the loop that verifies it.**

Classification (evidence-first, then act):
- **A. infra/harness** (black shots, worktree flake, timeout) → fix harness or
  degrade L3=unavailable; NOT a cycle; file separate infra issue.
- **B. pre-existing** (main fails too) → existing status/blocked + fix-issue path.
- **C. spec/aesthetic deviation** (runs but wrong) → REQUEST_CHANGES + evidence;
  human decides taste (machine never auto-fixes aesthetics).
- **D. code defect** → local convergence loop:
  1. review labels `workflow/self-correct` + evidence comment (shots/logs/
     suspected root cause — observation, NOT the fix; don't bias the fixer)
  2. event-processor rule (implemented 2026-07-31, commit 9c91e60, suite 99):
     label without pending check_run(failure) →
     `SPAWN: self-correct,issue=N,pr=N,branch=impl/...,source=local-e2e`
     — impl PR auto-looked-up via `gh pr list --search head:impl/<issue>`;
     a pending check_run(failure) for the same issue outranks the label in the
     per-issue group (P1 check_run > P2 labeled), so the label path NEVER
     double-spawns (guarded by test_label_self_correct_loses_to_pending_ci_failure)
  3. self-correct agent fixes IN THE WORKTREE, self-verifies with
     run-e2e-review.sh (same evidence domain as detection)
  4. push → CI green is REGRESSION PROTECTION only
  5. review re-spawns → re-runs local e2e ← convergence criterion
  6. cap: 2 local-failure rounds → stop, escalate to human with evidence
     bundle (classification, screenshots, logs, what was tried)

Cost governance: local cycles reuse the 🔄 marker counting +
SELF_CORRECT_THRESHOLD=3 (→ depth=light). Infra failures (A) never count.

## Pitfalls (discovered implementing Phase 1)

- **py3.9 vs py3.11 dual compat**: local `python3` on devvi's Mac is
  `/usr/bin/python3` = 3.9.6; CI (pipeline-tests.yml) uses 3.11. Any `X | None`
  annotation crashes at def time on 3.9 → always add
  `from __future__ import annotations` to scripts/ + tests/pipeline/ files.
- **`git worktree add` refuses a branch already checked out** in the main tree
  (`fatal: 'impl/1-test' is already checked out at ...`). Test fixtures must
  `git checkout main` after creating the impl branch. For baseline worktrees on
  the default branch use `git worktree add --detach <path> main`.
- **zsh glob kills command chains** when a dir is empty (`rm dir/*.png` →
  `no matches found` aborts the `&&` chain). Guard with `[ -f "$f" ] || continue`
  or separate statements.
- System sleep ≠ display sleep: `pmset -g` reports them independently.
  Display asleep → frames still render (in-process capture works); system
  asleep → process frozen, capture dead. Guard with caffeinate or verify a
  PreventUserIdleSystemSleep holder exists.
- Diff files via `gh pr diff --name-only` fail when offline → runner tolerates
  local-branch existence (falls back to default archetype, warns).
- **`gh ... --jq ".[0]"` prints the OBJECT (or literal `null`), not an array** —
  `json.loads` on the real output yields a dict, and `"null"` is a TRUTHY
  string: guard `if pr_json and pr_json != "null"` and defensively accept
  dict/list/None. When mocking `subprocess.run` for event-processor tests the
  mock MUST set `returncode=0` — the `gh()` helper gates data on
  `result.returncode == 0`, so a missing returncode silently returns `""`,
  the SPAWN enrichment never fires, and you chase a ghost.
- **patch-tool block-replacement hazard on large files**: when a file was read
  with pagination, an old_string spanning a whole block + a new_string with
  only the insertion silently REPLACES the block (this session accidentally
  deleted the implement cost-governance block while inserting the self-correct
  block). After patching large pipeline files, verify the net change is
  additive-only: `git diff scripts/... | grep -E '^[-+]' | grep -v '^[-+][-+]'`.
- **Single-source-of-truth configs must be git-tracked AND test-guarded**:
  game-env/manifest.yaml was untracked (fresh clones/worktrees lack it, and
  worktrees never contain untracked files). `test_manifest.py` now asserts
  `git ls-files` contains it — a P0 regression guard (2026-07-31).
