---
name: game-implement-agent
description: "Implement phase agent for the game dev workflow. Reads DESIGN + PRD docs, follows TDD (tests first), generates GDScript code via OpenCode Serve, creates impl/ PR. NEVER merges PRs — review agent is the sole merge gate."
tags: ["workflow", "implement", "tdd", "godot", "gdscript", "opencode"]
---

# Game Implement Agent

> The **code generation phase** of the game dev pipeline. Triggered by `SPAWN: implement` from the cron poller. Reads DESIGN + PRD, generates test files FIRST, then implementation code, creates `impl/` PR. **This agent must NEVER merge its own PR.**

## ⛔ CRITICAL INVARIANT: No Self-Merge

**This agent is FORBIDDEN from calling `gh pr merge`.** Only the game-review-agent can merge implement PRs. After creating the PR and verifying CI passes, this agent's job is DONE. The review agent handles the merge gate.

If CI fails: fix the failures, push, wait for CI rerun — but still do NOT merge. The check_run event will trigger the review agent.

## Pre-Implementation: Read Everything

Before writing a single line of code, read ALL relevant context:

### Required Reading
```bash
# 1. Design specification
read_file("docs/DESIGN/<N>-*.md")

# 2. Product requirements + acceptance criteria
read_file("docs/PRD/<N>-*.md")

# 3. Existing design knowledge (don't break existing systems)
search_files("docs/GAME_DESIGN/", pattern="*.md", target="files")
# Read relevant GDD chapters

# 4. Existing codebase — understand patterns, naming, autoloads
search_files("gdscripts/", pattern="*.gd", target="files")
# Read files related to the feature area

# 5. Existing scenes — node hierarchy conventions
search_files("scenes/", pattern="*.tscn", target="files")

# 6. Project configuration
read_file("game-env/manifest.yaml")
```

## TDD: Tests FIRST

**This is non-negotiable.** The implementation follows a strict test-first workflow:

```
Step 1: Read DESIGN doc's test case descriptions (Section 6 or 7)
Step 2: Write test file(s) FIRST — they must FAIL before any code exists
Step 3: Run tests → confirm RED (no implementation yet)
Step 4: Write minimal implementation code → GREEN
Step 5: Refactor → keep GREEN
```

### Pre-Implementation: Upstream Integration Scan

After reading DESIGN + PRD, but BEFORE writing code, scan upstream Issue DESIGN docs for
resources that need to be wired into the current feature. This prevents the gap where
Issue A creates ShaderMaterial / GPUParticles2D / standalone .gd scripts, and Issue B
(the consumer) never connects them.

```bash
# 1. Read this Issue's DESIGN doc Integration Points table
read_file("docs/DESIGN/<N>-*.md")  # find §7 Integration Points

# 2. For each row with Status: ⬜ pending and a Target Issue reference:
for target_issue in <extracted target issue numbers>:
    # Read the target's DESIGN doc
    read_file("docs/DESIGN/<target>-*.md")
    # Search for upstream resources that need wiring:
    search_files("docs/DESIGN/<target>-*.md", pattern="ext_resource|ShaderMaterial|GPUParticles2D|\.gdshader|ParticleProcessMaterial")
```

**Common upstream resources to scan for:**

| Resource Pattern | What to Do |
|-----------------|------------|
| `.gdshader` + `ShaderMaterial` `.tres` | Apply as `material = ExtResource(...)` on the target node's ColorRect/Sprite2D |
| `ball_trail.gd` / standalone controller scripts | Attach as child node + wire `@onready` references (ensure `$NodeName` paths resolve correctly for siblings vs children) |
| `ParticleProcessMaterial` `.tres` | Assign as `process_material` on GPUParticles2D node |
| `GradientTexture1D` `.tres` | Referenced by ParticleProcessMaterial — ensure `.uid` file exists for headless UID resolution |

**After wiring each integration point:**
1. Update the Status column in the upstream DESIGN doc from ⬜ → ✅
2. Document the connection in your own DESIGN doc's Integration Points table
3. Verify with `godot --headless --quit` that no ext_resource / node-not-found errors appear

### Test File Structure

All test files go in `tests/` and follow the existing `run_tests.gd` pattern:

```gdscript
extends RefCounted

var failed: int = 0
var passed: int = 0

func run() -> void:
    print("=== <Feature> Tests ===")
    _test_case_a1()
    _test_case_a2()
    # ... all test cases from DESIGN doc
    print("Passed: %d, Failed: %d" % [passed, failed])

func _assert(condition: bool, msg: String) -> void:
    if condition: passed += 1
    else:
        failed += 1
        printerr("❌ %s" % msg)

func _test_case_a1() -> void:
    # Implement TC-A1 from DESIGN doc
    pass
```

### Integrate into run_tests.gd

After creating the test file, add its runner to `tests/run_tests.gd`:

```gdscript
# In _init():
var feature_tests = load("res://tests/test_feature.gd").new()
feature_tests.run()
if feature_tests.failed > 0:
    _failed += 1
```

### Godot 4 Headless Test Pitfalls

See `godot-headless-test-patterns` skill for the full reference. Key gotchas:

| Pitfall | Pattern |
|---------|---------|
| `class_name` invisible in `--script` | Use `preload("res://path.gd")` instead |
| Node `.new()` returns null | Use `Node.new()` + `set_script(load(...))` |
| Lambda capture is by-value | Use member vars + handler methods |
| `var x := load().method()` compile fail | Use explicit type: `var x: Dict = ...` |
| `@export var` not writable after `set_script()` | Assign private member vars directly |

## Implementation: OpenCode Workflow

Use OpenCode Serve (`http://127.0.0.1:18765`) for GDScript code generation. Before using, verify it's reachable:

```bash
curl -s --max-time 5 -o /dev/null -w "%{http_code}" http://127.0.0.1:18765/health
# HTTP 200 = reachable (body may be HTML — that's normal)
```

### OpenCode Run (Recommended)

```bash
opencode run '<prompt>' --model deepseek/deepseek-v4-flash --thinking
```

The prompt should include:
- Full DESIGN doc's implementation spec
- File paths and conventions
- Test files already written (OpenCode should make them pass)
- Specific Godot 4.7 / GDScript 2.0 syntax requirements

### Fallback: Direct File Writing

If OpenCode is unreachable or returns HTML instead of code, write files directly via `write_file`. The DESIGN doc contains enough implementation detail to proceed manually.

### Layer Order

1. **Tests** (already written in TDD step)
2. **Scaffold** — `.tscn` files with correct node hierarchy, CollisionShape2D with non-null shapes
3. **Core logic** — `.gd` files implementing the DESIGN spec
4. **Assets** — `.tres`, `.gdshader`, etc.
5. **Integration** — add to existing `run_tests.gd`, verify with CI-compatible paths
6. **Refactor** — clean up, apply GDScript best practices

## After Implementation: Create PR

### 1. Verify Locally

```bash
# Compile check (use --path to scope to the sub-project)
/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path mini-pong/ 2>&1 | grep -E "ERROR|SCRIPT ERROR"

# Run tests (--path is REQUIRED — without it, res:// resolves from CWD)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path mini-pong/ --script tests/run_tests.gd 2>&1 | tail -20
```

**Note:** The `--path` flag is mandatory — without it, Godot resolves `res://` from the working directory, so `res://tests/test_*.gd` looks in `<CWD>/tests/` instead of `<project>/tests/`, causing "file not found" on all tests.

Expected: all tests pass, exit code 0.

Leak warnings about RIDs and ObjectDB instances at exit are normal in headless mode — ignore them.

### 2. Branch and Commit

```bash
# Determine default branch
DEFAULT_BRANCH=$(gh repo view devvi/agent-game-test --json defaultBranchRef --jq '.defaultBranchRef.name')

# Check for uncommitted changes
git stash  # if needed

git checkout $DEFAULT_BRANCH
git pull origin $DEFAULT_BRANCH
git checkout -b impl/<N>-<slug>

# Stage ONLY your files — never `git add .` in multi-agent workspace
# Run `git status --short` first to inspect sibling agent changes
git add mini-pong/gdscripts/<your-file>.gd mini-pong/tests/<your-test>.gd ...
git commit -m "feat(<N>): <feature description>"
git push origin impl/<N>-<slug>
```

### 3. Create PR

```bash
gh pr create \
  --base $DEFAULT_BRANCH \
  --head impl/<N>-<slug> \
  --title "feat(<N>): <feature description>" \
  --body "Closes #<N>

Parent #<N>"
```

**PR body format:** "Closes #N" on first line, "Parent #N" on third line. This is the canonical format that event-processor.py parses.

### 4. Run Stage-Gate

```bash
cd /Users/devvi/workspace/agent-game-test
python3 ~/.hermes/scripts/stage-gate.py --pr <PR_NUMBER>
```

Stage-gate validates labels, branch naming, and **disables auto-merge** on `impl/*` PRs. This is the enforcement mechanism that prevents self-merge.

### 5. Wait for CI

CI runs automatically via `opencode-review.yml`. Monitor:

```bash
gh pr checks <PR_NUMBER> --watch
```

**If CI fails:** fix the issues on the branch, `git push`, wait for CI rerun. Do NOT close the PR and create a new one.

**If CI passes:** Your job is done. The `check_run.completed` event will trigger the review agent, which handles merge + GDD update.

### 6. Notify

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"msg_type":"text","content":{"text":"💻 #<N> → implement complete, CI passed, awaiting review"}}' \
  https://open.feishu.cn/open-apis/bot/v2/hook/76101281-b359-49ab-ae2f-fc486bf65958
```

## Godot-Specific Conventions

### TSCN Format
- `format=3` with `uid://` identifiers
- All `[sub_resource]` blocks before first `[node]` tag
- Omit `load_steps` (Godot auto-calculates when absent)
- CollisionShape2D/3D shapes must be non-null
- ColorRect offsets relative to parent origin

### GDScript 2.0 (Godot 4.x)
- `@export var` for inspector-visible properties
- `@onready var` for node references (only in Node subclasses, not autoloads)
- `signal` declarations at top of script
- `extends CharacterBody2D` / `extends Area2D` / `extends Node`
- `_ready()` for initialization, `_process(delta)` / `_physics_process(delta)` for per-frame

### Testing
- `extends RefCounted` for test helpers (no SceneTree dependency)
- `extends SceneTree` only for the main `run_tests.gd`
- `_init()` runs in `--script` mode; `_ready()` does NOT
- Use `quit(code)` for clean exit (not `OS.call_deferred("exit")`)

## Pitfalls

| Pitfall | Mitigation |
|---------|-----------|
| **Upstream resources created but not wired** | See "Pre-Implementation: Upstream Integration Scan" above. When an upstream Issue (e.g., neon visual system #289) created ShaderMaterial / GPUParticles2D / standalone .gd scripts but the DESIGN doc says "后续 Issue 建立连接", this Issue MUST wire them. Scan upstream DESIGN docs' Integration Points tables for ⬜ rows targeting your Issue number. The most common pattern: a .gdshader + ShaderMaterial .tres was created, but no scene applies `material = ExtResource(...)` on the target node. |
| Merge called by implement agent | Stage-gate disables auto-merge; review agent is sole merge gate |
| Tests not written | TDD-first is enforced — tests fail before any code exists |
| No context reading | Pre-implementation checklist requires DESIGN, PRD, GDD, existing code |
| OpenCode unavailable | Fall back to direct file writing from DESIGN doc |
| Wrong default branch | Always query `gh repo view --json defaultBranchRef` |
| Stash/pop lands on wrong branch (sibling agent modified workspace) | Before `git stash`, inspect `git status --short` for uncommitted changes from sibling subagents. Stash captures ALL dirty files — popping on a different branch may amend the wrong commit with mixed-author changes. Prefer `git checkout impl/<other-issue> -- <files>` to cherry-pick specific files from another branch, or `git add` only your own files explicitly rather than `git add .`. After `git stash pop`, always verify `git branch --show-current` before committing. |
| CI exit code captured from pipe | Use `${PIPESTATUS[0]}` not `$?` after pipes |
| SubResource ordering | All `[sub_resource]` blocks BEFORE `[node]` |
| TSCN format drift (adding `layout_mode` to derivative scenes) | When creating a derivative `.tscn` (e.g. `Main.tscn` from `game.tscn`), match the original scene's formatting exactly — **do not add properties** like `layout_mode = 0` that weren't in the source. Godot 4.2+ auto-adds `layout_mode` on save in the editor, but scenes created by earlier issues or handwritten TSCN files won't have it. Adding it changes CanvasItem layout behavior and may cause UI nodes to render differently. Copy the original first, then insert new nodes/blocks without reformatting existing ones. |
| `:=` type inference fails in Godot 4.7.1 headless | **Godot 4.7.1 treats all `:=` type-inference warnings as hard errors in `--script` mode.** `load()` returns `Variant`, `Engine.get_singleton()` returns `Variant`, `get_parent()` returns `Node` — `:=` fails on all of these. Always use plain `=` instead: `var gm = Engine.get_singleton("GameManager")`, `var parent = get_parent()`, `var hud = _get_sibling("GameHUD")`. Never use `:=` on function returns unless the return type is explicitly annotated with a concrete type. |
| Autoload class_name reference fails in `--script` | Production scripts referencing autoload singletons by name (`GameManager.reset_match()`) fail at parse time because the script class cache is empty. Use `Engine.get_singleton("GameManager")` at runtime with `has_method()`/`has_signal()` guards. **HOWEVER:** `Engine.get_singleton()` returns `null` when the autoload uses the `*` lazy-load prefix in `project.godot`. Access via `root.get_node_or_null("GameManager")` for SceneTree scripts, or `get_node_or_null("/root/GameManager")` for in-tree nodes. See `godot-headless-testing` skill → `references/lazy-autoload-singleton-pitfall.md`. |
| Files silently not created | After creating `.gd` / `.tscn` files in sub-project directories, verify with `ls` that they actually exist on disk. `write_file` may report success but the files may not be present — fall back to `terminal` with `cat` heredocs if files are missing after creation. Always verify file existence before running Godot tests. |
| Sibling subagents revert or corrupt changes silently | In multi-agent workflows, sibling subagents sharing the same workspace may revert, delete, **introduce compile errors**, or **commit** files you've written. Observed behaviors: `write_file` reports success but the file is gone moments later; `patch` diffs are applied, then overwritten; **compile-breaking edits** (dangling variable references, removed guards) are introduced; a sibling **commits your files** as part of their own PR, so `git diff HEAD` shows nothing even though the files are modified — your changes were absorbed into their commit. After every write/edit pass: (1) verify with `ls` + `git diff --stat` that files still exist and diffs are intact, (2) run a `--headless --quit` compile check on modified files — file presence ≠ compile safety, (3) if `git diff` shows nothing but the file should be modified, check `git show HEAD:<path>` to see if your changes were committed by a sibling. If changes were corrupted, re-apply them immediately from the DESIGN doc. Do not assume persistence across turns. |
| Branch switch silently discards unstaged changes + untracked files | `git checkout <other-branch>` may succeed **without warning** even when you have unstaged modifications and untracked files on the current branch. Git allows the switch when there are no conflicts — but the unstaged changes are left stranded on the old branch and effectively lost. **Never switch branches with unsaved work.** Always commit or `git stash` first. After switching back, unstaged changes from the prior branch are NOT recoverable — they were never committed and don't travel with the branch. Use `git stash` with `--include-untracked` (`-u`) to capture new files too. |
| `git checkout <branch> -- <file>` fails for untracked files | `git checkout <other-branch> -- <path>` can only recover files that are **tracked** in the target branch. For new files that exist only as untracked additions (e.g. `constants.gd`, `Main.tscn`), this command returns `error: pathspec '...' did not match any file(s) known to git`. The only recovery path is **regeneration from DESIGN docs and memory**. See `references/sibling-revert-recovery.md` for the full step-by-step recipe including prevention, diagnosis, and verification. |
| `git stash push <pathspec>` fails for deleted files | `git stash push -- <pathspec>` operates only on tracked files. If a pathspec includes a deleted file (e.g. `game.tscn` that was `rm`'d), the command fails with `error: pathspec '...' did not match any file(s) known to git`. Remove deleted-file pathspecs from the stash command or use `git stash push --include-untracked` without pathspecs to capture everything. |
| Cross-branch ext_resource dependencies in TSCN files | A `.tscn` file may reference an ext_resource (`.gd` script, sub-scene) that exists on one branch but not another. When copying or creating TSCN files, verify that ALL `[ext_resource]` paths resolve on the **current branch** — not just the branch where the TSCN originated. Run `--headless --quit` immediately after creating/modifying TSCN files; any `"Parse Error: [ext_resource] referenced non-existent resource"` means a dependency is missing on the current branch. This is a pre-existing issue if the same error occurs with the original (unmodified) scene file. |

### Audio Synthesis: AudioStreamGenerator Pitfalls

| Pitfall | Pattern |
|---------|---------|
| `stream_paused` on `AudioStreamGenerator` | `stream_paused` is an `AudioStreamPlayer` property, NOT on `AudioStreamGenerator`. Store the player reference (`_stream_player = player`) and set `_stream_player.stream_paused = true` — never `generator.stream_paused`. Godot 4.7 rejects this at compile time. |
| `generator.get_playback()` | Use `player.get_stream_playback()` instead. On `AudioStreamPlayer`, the correct method is `get_stream_playback()`. |
| Dangling references after sibling edits | Sibling subagents often strip `stream_paused` guards from `_play_tone()` leaving undefined variable references (`gen_node`). After detecting sibling interference, run `--headless --quit` compile check — don't trust file existence alone. |

## Verification Checklist

Before considering the task done:

- [ ] All DESIGN doc test cases have corresponding `_test_*()` functions
- [ ] Tests run and pass: `godot --headless --script tests/run_tests.gd`
- [ ] New test file integrated into `tests/run_tests.gd`
- [ ] **Upstream integration points wired** — scanned upstream DESIGN docs, applied ShaderMaterial/GPUParticles2D/scripts to scene nodes, updated Status ⬜→✅
- [ ] CollisionShape2D/3D shapes are non-null
- [ ] `.tscn` files: format=3, uid:// present, sub_resources before nodes
- [ ] PR created with body "Closes #N\n\nParent #N"
- [ ] Stage-gate ran successfully on the PR
- [ ] CI passing (or in progress)
- [ ] gh pr merge was NEVER called
