# write_file + Git Branch Pitfalls

Captured during Issue #152 research (2026-07-23) and Issue #290 research (2026-07-29).
These are cross-tool hazards that affect the game-research-agent and any skill that
writes files + uses git in multi-agent workflows.

## 1. write_file Silent Failure

**Symptom:** `write_file` returns success (`bytes_written: N, dirs_created: true`)
but the file does not exist on disk or is 0 bytes.

**Root cause:** The tool detected the file was modified since last read and
silently discarded the write. This is a documented pitfall in the
`godot-content-implementation` skill.

**Defense:**

```bash
# IMMEDIATELY after every write_file, verify:
ls -la docs/PRD/152-*.md
# If missing or 0 bytes, recreate via terminal:
cat > docs/PRD/152-test-npc.some-file.md << 'EOF'
...full content...
EOF
```

## 2. git checkout -b silently lands on wrong branch

**Symptom:** `git checkout -b research/152-my-feature` says
"Switched to a new branch" but `git branch --show-current` later shows
a stale branch name (e.g. `research/147-old-feature`).

**Root cause:** If a stale branch with the same name exists locally OR if
there's a prior checkout-hook/stash-restore that reverts the branch, the
expected branch is not the actual current branch.

**Defense:**

1. Always check `git status --short` before branching (dirty tree can cause issues).
2. After `git checkout -b`, **immediately** run `git branch --show-current`.
3. If wrong name:
   ```bash
   git branch -D research/152-my-feature  # delete the new branch
   git checkout main
   git pull origin main
   git checkout -b research/152-my-feature
   git branch --show-current  # verify again
   ```

## 3. Commit lands on wrong branch

**Symptom:** You `git add` and `git commit` on what you think is your new
branch, but `git log --oneline` shows the commit isn't there (it was made
on a stale branch).

**Defense:**

1. Check `git branch --show-current` before any `git commit`.
2. If the commit already landed on the wrong branch:
   ```bash
   git cherry-pick <commit-hash>  # onto the correct branch
   git branch -D <wrong-branch>
   ```

## 4. Parallel Agent Branch Collision (Multi-Agent Workflow)

**Symptom:** After creating a `research/{N}-{slug}` branch and pushing, a
parallel agent (working on a different issue) force-pushes to the **same
branch name**. Your local branch still has your commit but the remote is
now at a completely different commit. Subsequent `git push --force` may
silently no-op (see §5).

**Root cause:** In multi-agent workflows with cron-driven parallel research
sessions, two agents may pick up different issues that happen to produce
the same branch slug (e.g., a research agent for #290 creates
`research/290-ai-opponent` while a plan agent for #291 force-pushes to it
by mistake, or two agents race on the same issue).

**Real example (Issue #290, 2026-07-29):** The research agent created
`research/290-ai-opponent` with commit `edea0b8`. A parallel agent
(#291 research) force-pushed commit `f97165b` to the same branch. The
`git commit` output showed `[main edea0b8]` because the local branch
tracking had been disrupted — the commit landed on `main` instead of
the intended research branch.

**Detection — always check BEFORE pushing:**

```bash
# Check if remote was already overwritten by another agent
git fetch origin research/{N}-{slug}
LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse origin/research/{N}-{slug} 2>/dev/null || echo "NONE")
echo "Local:  $LOCAL_HASH"
echo "Remote: $REMOTE_HASH"
```

**Recovery:**

```bash
# 1. Find your commit in reflog
git reflog | grep "<your commit message>" | head -3
# e.g.: edea0b8 HEAD@{5}: checkout: moving from main to main

# 2. Reset the branch to your commit
git checkout research/{N}-{slug} 2>/dev/null || git checkout -b research/{N}-{slug}
git reset --hard <your-commit-hash>

# 3. Force-push with explicit refspec (NOT simple branch push — see §5)
git push origin <your-commit-hash>:refs/heads/research/{N}-{slug} --force

# 4. Verify
git ls-remote origin refs/heads/research/{N}-{slug}
# Must match: git rev-parse HEAD
```

## 5. git push --force Silently No-Ops ("Everything up-to-date")

**Symptom:** `git push -u origin research/{N}-{slug} --force` returns
"Everything up-to-date" with exit code 0, but `git ls-remote origin
refs/heads/research/{N}-{slug}` shows the remote is at a **different**
commit. The push did nothing.

**Root cause:** When branch tracking config is broken — `git config
branch.research/{N}-{slug}.remote` is empty or the tracked remote ref
was deleted/replaced by another agent — git cannot determine what to
push and silently no-ops. The `-u` flag sets tracking but doesn't help
if the local ref's idea of the remote is corrupted.

**Real example (Issue #290):** After another agent overwrote the remote
branch, `git push -u origin research/290-ai-opponent --force` repeated
"Everything up-to-date" three times. `git ls-remote` confirmed the
remote was at `f97165b` while local was at `edea0b8`.

**Fix — always use explicit refspec when recovering:**

```bash
# WRONG — may silently no-op:
git push -u origin research/{N}-{slug} --force

# RIGHT — explicit refspec, always works:
git push origin $(git rev-parse HEAD):refs/heads/research/{N}-{slug} --force

# ALWAYS verify after push:
EXPECTED=$(git rev-parse HEAD)
ACTUAL=$(git ls-remote origin refs/heads/research/{N}-{slug} | awk '{print $1}')
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "PUSH FAILED: remote=$ACTUAL, expected=$EXPECTED"
  exit 1
fi
```

**When to use explicit refspec:** Any time you are recovering from a
branch collision, or any time a prior `git push --force` returned
"Everything up-to-date" unexpectedly. Normal first-push on a fresh
branch does not need this — use the standard `git push -u origin
research/{N}-{slug}`.
