# Sibling Revert Recovery — Full Recipe

> When sibling agents silently destroy your work, here's the systematic recovery path.

## Pattern Recognition

You know a sibling revert happened when:
- `write_file` returned success, but `ls <file>` shows it doesn't exist
- `git diff --stat` is empty or missing diffs you know you applied
- `git status --short` shows no unstaged changes but you just edited files
- A compile check (`--headless --quit`) fails with errors on files you already fixed

## Recovery Workflow

### 1. Diagnose what was lost

```bash
# Check if new (untracked) files still exist
ls mini-pong/gdscripts/constants.gd mini-pong/scenes/Main.tscn

# Check if modified files still have your changes
git diff HEAD -- mini-pong/gdscripts/ball.gd mini-pong/project.godot

# Check the scene file state
ls mini-pong/scenes/game.tscn mini-pong/scenes/Main.tscn
```

### 2. Attempt git-level recovery for TRACKED files

```bash
# If the changes were committed on another branch, cherry-pick them
git checkout impl/<other-branch> -- mini-pong/gdscripts/game_manager.gd mini-pong/gdscripts/paddle.gd

# Verify recovery
git diff HEAD -- mini-pong/gdscripts/game_manager.gd
```

**CRITICAL:** `git checkout <branch> -- <file>` ONLY works for files that are **tracked (committed)** on the target branch. Untracked files (new additions) return:
```
error: pathspec '<path>' did not match any file(s) known to git
```

### 3. Regenerate UNTRACKED files from DESIGN doc

For new files that never existed in any git commit, regenerate from DESIGN/PRD documentation:

```bash
# constants.gd — DESIGN §2.2 has the exact content
write_file("mini-pong/gdscripts/constants.gd", <content from DESIGN doc>)

# Main.tscn — DESIGN §2.1 has the architecture; copy from game.tscn + add nodes
write_file("mini-pong/scenes/Main.tscn", <content derived from game.tscn + DESIGN>)

# Test files — DESIGN §5 has test case descriptions
write_file("mini-pong/tests/test_constants.gd", <content>)
write_file("mini-pong/tests/test_main_scene.gd", <content>)
```

### 4. Re-apply patches to MODIFIED files

For files that were modified (not new), re-apply the DESIGN doc changes:

```bash
# Use patch with mode='replace' for each targeted change
patch(mode='replace', path='mini-pong/gdscripts/scoring_manager.gd', ...)
patch(mode='replace', path='mini-pong/gdscripts/game_manager.gd', ...)
# ... etc for all modified files
```

### 5. Verify recovery

```bash
# Compile check
cd mini-pong && godot --headless --quit 2>&1 | grep "ERROR"

# Test suite
godot --headless --path mini-pong/ --script tests/check_compile.gd
godot --headless --path mini-pong/ --script tests/run_tests.gd | grep -E "(FAIL|TOTAL)"
```

## Prevention

- **Never `git checkout <other-branch>` with unsaved work.** Commit or stash first.
- Use `git stash push --include-untracked -m "description"` to save everything.
- After stash pop, verify `git branch --show-current` before committing.
- Commit your work on your feature branch as soon as it compiles — git-committed state survives branch switches.
