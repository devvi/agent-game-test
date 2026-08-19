# Runtime Screenshot Verification (Godot real rendering + worktree isolation)

> Verified 2026-07-31 on Godot 4.7.1 / macOS M1 / mini-pong project.
> Purpose: let the review agent capture REAL game frames from a PR branch as visual
> evidence ("the game actually looks right and actually plays"), then comment the
> screenshot on the PR.

## Core finding: `--headless` CANNOT screenshot

Measured facts (do not re-derive):

| Attempt | Result |
|---------|--------|
| `godot --headless --script` + `root.get_texture().get_image()` | **Hangs** — `await process_frame` never returns (no render loop in headless) |
| `godot --headless --write-movie out.avi --script ...` | "CPU render time: 0.00 seconds" — dummy driver, **no file written** |
| `--display-driver macos --rendering-driver opengl3 --resolution WxH --script ...` | ✅ **Real GPU render, valid PNG** (134 colors, theme neon blue #4a90d9 visible) |

Root cause: headless = `dummy` rendering driver, produces zero pixels. Any future
"headless screenshot" idea is dead on arrival — always use a real display driver.

## Working screenshot recipe

```bash
# Script MUST live in /tmp (repo writes trigger unverified-file warnings)
cat > /tmp/review_shot_<PR>.gd << 'GDS'
extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var main = load("res://scenes/Main.tscn")
	if main == null:
		print("❌ main scene load failed"); quit(1); return
	root.add_child(main.instantiate())
	for i in range(15):      # let UI/particles actually render
		await process_frame
	var img = root.get_texture().get_image()
	var ok = img.save_png("/tmp/review_shot_<PR>.png")
	print("shot ok=", ok, " ", img.get_width(), "x", img.get_height())
	quit(0 if ok == 0 else 1)
GDS

# Real display driver — window flashes briefly (acceptable for low-frequency review)
godot --path <subproject>/ --display-driver macos --rendering-driver opengl3 \
      --resolution 1280x720 --script /tmp/review_shot_<PR>.gd
```

Caveats:
- Requires a WindowServer session — works on a logged-in desktop Mac; fails over
  pure SSH with no GUI session (fallback: mark screenshot unavailable, use logic tests only).
- For playthrough evidence (better than a static menu shot), drive the auto-play test
  (e.g. mini-pong #12 "100回合自动对打") and capture mid-game frames.

## Verify the PNG has real content

A flat-color PNG means the scene didn't load. Check with PIL (no vision model needed):

```bash
python3 -c "
from PIL import Image
img = Image.open('/tmp/review_shot_<PR>.png').convert('RGBA')
colors = img.getcolors(maxcolors=100000)
print('distinct colors:', len(colors) if colors else '>100000')
for cnt, col in sorted(colors, reverse=True)[:4]: print(' ', col, 'x', cnt)"
```

Expect dozens–hundreds of distinct colors including theme colors (mini-pong neon
#4a90d9 = RGB(74,143,217)). 1-color PNG = load failure. Optionally render an ASCII
luminance map to verify structure (ball/paddle/HUD visible).

## Git worktree isolation protocol (design — implement in review-agent skill)

Goal: run tests + screenshots on the PR branch WITHOUT touching the main working tree,
eliminating the checkout/stash pitfall family (7 known pitfalls in review-agent).

```bash
# 1. Create isolated worktree for the PR branch
git fetch origin <impl-branch>:<impl-branch> 2>/dev/null || true
git worktree add /tmp/wt-impl-<N> <impl-branch>

# 2. Run e2e + screenshot INSIDE the worktree
cd /tmp/wt-impl-<N>
godot --path <subproject>/ --headless --script tests/run_tests.gd    # logic
godot --path <subproject>/ --headless --script tests/smoke_test.gd   # playthrough
# ... screenshot recipe above, with --path <subproject>/ pointing into the worktree

# 3. Comment evidence on the PR
gh pr comment <N> --body "## 🖼 运行验证\n![shot](<url>)"

# 4. REMOVE the worktree BEFORE merging (shared .git)
cd ~/workspace/<repo> && git worktree remove /tmp/wt-impl-<N> --force
# ⚠️ gh pr merge --delete-branch FAILS while a worktree has that branch checked out
gh pr merge <N> --squash --delete-branch
```

Order matters: screenshot → comment → **remove worktree** → merge. Leaving the
worktree open blocks `--delete-branch` and pollutes later scans.

## Relation to the assembly loop (game-to-issues C5.5)

Logic proof = auto-play test (e.g. #12). Visual proof = this screenshot. Together
they close the "assembled game actually exists and looks right" evidence gap that
urban-night-walker failed (resources present, no playable game).
