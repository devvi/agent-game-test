# Trace: Missing implement-agent and plan-agent Skills (2026-07-29)

## Summary

`game-implement-agent` and `game-plan-agent` skills were created via `write_file` 
but **never committed to git**. They existed as untracked files on disk with symlinks
from `~/.hermes/skills/software-development/` pointing to them. When the files 
disappeared from disk, the symlinks broke silently. For ~10 days, implement agents 
ran without skill guidance — no TDD constraints, no test-file requirements, and no 
merge prohibition.

## Symptom Pattern

User reports: "workflow used to work normally, now features don't work."

Actual state:
- `skill_view("game-implement-agent")` → "not found"
- Symlinks broken: `~/.hermes/skills/software-development/game-implement-agent → agents/skills/game-implement-agent` (target doesn't exist)
- `git log --all --oneline --follow -- "agents/skills/game-implement-agent/SKILL.md"` → empty (never committed)

## Investigation Methodology

When user says "used to work but doesn't anymore":

1. **Check symlink integrity:**
   ```bash
   ls -la ~/.hermes/skills/software-development/game-implement-agent/SKILL.md
   find ~/.hermes/skills -type l ! -exec test -e {} \; -print
   ```

2. **Check git history for file existence:**
   ```bash
   git log --all --oneline --follow -- "agents/skills/game-implement-agent/SKILL.md"
   # Empty output = file was NEVER committed = untracked = lost on disk operations
   ```

3. **Check alternative skill paths:**
   ```bash
   find ~/.hermes/skills -type d -name "game-implement-agent"
   # Some skills survive at alternate locations (e.g., godot/game-plan-agent/)
   ```

4. **Search session history for creation evidence:**
   ```
   session_search(query="game-implement-agent create skill write_file SKILL.md")
   ```

## Root Cause

Sub-agents (delegate_task) were told to create SKILL.md files using `write_file` 
to `agents/skills/game-X-agent/SKILL.md`. `write_file` writes to disk but does NOT 
`git add` + `git commit` + `git push`. The files were untracked — invisible to git, 
vulnerable to any working-tree operation (checkout, clean, stash, branch switch).

## Consequences

For ~10 days (Jul 20-29), implement agents spawned without skill guidance:
- No TDD (test-driven development) constraints
- No requirement to write test files
- No prohibition on `gh pr merge` — agents self-merged PRs bypassing review
- DESIGN doc test case descriptions were ignored (not translated to runnable tests)
- PRs #309, #310 created with zero test files, zero code review

## Prevention

1. **Use `skill_manage(action='create')`** for new agent skills — it writes to `~/.hermes/skills/` directly, bypassing the repo/symlink fragility
2. **If `write_file` to repo is required**, always follow with `git add` + `git commit` + `git push`
3. **Verify after creation:** `git log --all --oneline -1 -- agents/skills/<new-skill>/`
4. **Periodic health check:** `find ~/.hermes/skills -type l ! -exec test -e {} \; -print`

## Related

- `workflow-cron-handler/references/direct-plan-handling-missing-skill.md` — related pattern of missing skill causing degraded behavior
- `dev-workflow-dispatcher` skill — contains the "Agent Skills Lost as Untracked Files" pitfall
