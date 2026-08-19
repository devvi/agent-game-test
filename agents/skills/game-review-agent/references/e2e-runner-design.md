# Local E2E Review Runner Design (worktree + screenshots)

> Design 2026-07-31. Full plan + rollout checklist: `docs/PLAN-e2e-modification.md`
> in the agent-game-test repo (not yet implemented as of 2026-07-31 — implement from
> this reference, following that plan's rollout order).
> Goal: script the review agent's local verification so the checkout/stash pitfall
> family (7 documented pitfalls) disappears and screenshots become auditable evidence.

## Ordering invariant (hard rule)

```
fetch → worktree add → tests (L0-L3) → screenshot → comment → worktree remove → merge
```

`gh pr merge --delete-branch` FAILS while a worktree holds that branch. Put cleanup in a
`trap EXIT` so ANY mid-run failure still removes the worktree. Never run the worktree
flow in the main working tree.

## Runner spec (`scripts/run-e2e-review.sh`)

CLI: `<PR_NUM> [--subproject NAME] [--skip-visual] [--baseline] [--no-comment] [--keep] [--dry-run]`

| Phase | Action | Fail semantics |
|-------|--------|----------------|
| P0 | pre-flight: godot present (macOS .app fallback); system-sleep guard; worktree conflict check; branch fetchable | exit 2 |
| P1 | `git worktree add /tmp/wt-impl-<N> <impl-branch>` (fetch branch first) | exit 2, cleanup |
| P2 | L0 compile: `godot --headless --script tests/check_compile.gd` (in worktree) | layer fail |
| P3 | L1 logic: `godot --headless --script tests/run_tests.gd` (incl. auto-play rounds) | layer fail |
| P4 | L2 runtime: `godot --headless tests/playthrough_test.tscn` (full engine physics) | layer fail |
| P5 | L3 visual: non-headless + in-process capture (see templates); non-black assert per frame | layer fail |
| P6 | evidence: upload PNGs + `gh pr comment --body-file` | warn, not gate |
| P7 | summary.json + exit code (0 all pass / 1 layer fail / 2 pre-flight) | — |
| P8 | trap cleanup: kill own caffeinate, `git worktree remove --force` | always |

### Testability (so the runner itself passes the pipeline test net)

- `RUNNER_GODOT` env overrides the godot binary → CI (ubuntu, no Godot) injects a fake
  godot script and tests the workflow logic (worktree lifecycle, exit aggregation, logs).
- `E2E_WORKTREE_ROOT` env (default `/tmp`) → tests inject a temp dir.
- `--no-comment` + `--dry-run` → hermetic, no network/gh.
- Pipeline tests: `tests/pipeline/test_e2e_runner.py` (temp git repo fixture: `git init -b
  main`, an `impl/N-foo` branch, fake godot recording argv); `test_analyze_bmp.py`
  (pure-stdlib BMP pixel decode — no PIL dependency on CI; struct+zlib approach verified
  on this machine).

### P0 pre-flight (data-driven, don't guess)

```bash
command -v godot || test -x /Applications/Godot.app/Contents/MacOS/Godot
# system sleep = frozen process = no screenshots possible. Display sleep is FINE.
if pmset -g assertions 2>/dev/null | grep -q PreventUserIdleSystemSleep; then
  echo "warn: system sleep already prevented by external holder"   # e.g. a remote-desktop tool
else
  caffeinate -dimsu & CAFF_PID=$!   # hold it ourselves; kill in trap
fi
git worktree list | grep -q "/tmp/wt-impl-$N" && exit 2            # conflict → refuse
git fetch origin "impl/$BRANCH" || exit 2
```

### P5 visual layer

- Copy capture template to `/tmp` — never write scripts into the repo working tree
  (unverified-file warning).
- Launch NON-headless: `godot --path <subproject>/ --display-driver macos
  --rendering-driver opengl3 --resolution 1280x720 --script /tmp/e2e-<N>/capture.gd`.
  Works with the display asleep (verified 2026-07-31: in-process capture 21/21 real
  frames while system screencapture returned 100% black).
- Per-frame anti-fake-evidence assertion: black PNG = capture failed = layer FAIL.
  Never post a black image as evidence. Pixel check via stdlib (no vision model):
  `sips -s format bmp frame.png --out frame.bmp` + analyze_bmp.py (avg RGB, near-black
  ratio, distinct colors, optional `--find` target-color hit count).
- `--baseline`: create a SECOND worktree on the default branch, run L1 there, write a
  pre-existing-vs-new comparison into summary.json — replaces the `git checkout -` /
  stash family entirely.

## Evidence upload (verified endpoints)

- **GitHub REST has NO comment attachment endpoint** (checked the official OpenAPI
  description 2026-07-31: 41 "attachments" mentions, all copilot-spaces/repo-status,
  zero comment-attachment POSTs).
- **Primary:** `POST https://github.com/upload/policies/assets` (Bearer GH_TOKEN,
  multipart `name` + `content_type`) → JSON `upload_url` → `curl -X PUT --upload-file`
  → asset URL `https://github.com/user-attachments/files/<id>/<name>.png` → reference in
  comment markdown. This is the same chain the GitHub UI uses for drag-drop images.
- **Fallback:** `gh gist create --public shot.png` → gist raw URL renders as image.
- Rollout: verify the primary once with a real PR; if it changes shape, switch to gist
  and record here.

## Files that live in the repo (when implemented)

| File | Purpose |
|------|---------|
| `scripts/run-e2e-review.sh` | the runner (P0-P8 above) |
| `scripts/e2e/analyze_bmp.py` | pixel assertions (copy from godot-headless-testing skill scripts/) |
| `framework/templates/e2e_capture.gd` | capture driver (see `templates/e2e_capture.gd` here) |
| `framework/templates/e2e_shots.json` | shot plan (see `templates/e2e_shots.json` here) |
| `tests/pipeline/test_e2e_runner.py` / `test_analyze_bmp.py` | pipeline test net |

`scripts/**` changes auto-trigger pipeline-tests CI (existing paths rule) — putting the
runner under `scripts/` gets it into the test net for free.
