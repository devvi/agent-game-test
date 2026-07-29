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
# Compile check
/Applications/Godot.app/Contents/MacOS/Godot --headless --quit 2>&1 | grep -E "ERROR|SCRIPT ERROR"

# Run tests
/Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/run_tests.gd 2>&1 | tail -20
```

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

git add .
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
| Merge called by implement agent | Stage-gate disables auto-merge; review agent is sole merge gate |
| Tests not written | TDD-first is enforced — tests fail before any code exists |
| No context reading | Pre-implementation checklist requires DESIGN, PRD, GDD, existing code |
| OpenCode unavailable | Fall back to direct file writing from DESIGN doc |
| Wrong default branch | Always query `gh repo view --json defaultBranchRef` |
| CI exit code captured from pipe | Use `${PIPESTATUS[0]}` not `$?` after pipes |
| SubResource ordering | All `[sub_resource]` blocks BEFORE `[node]` |

## Verification Checklist

Before considering the task done:

- [ ] All DESIGN doc test cases have corresponding `_test_*()` functions
- [ ] Tests run and pass: `godot --headless --script tests/run_tests.gd`
- [ ] New test file integrated into `tests/run_tests.gd`
- [ ] CollisionShape2D/3D shapes are non-null
- [ ] `.tscn` files: format=3, uid:// present, sub_resources before nodes
- [ ] PR created with body "Closes #N\n\nParent #N"
- [ ] Stage-gate ran successfully on the PR
- [ ] CI passing (or in progress)
- [ ] gh pr merge was NEVER called
