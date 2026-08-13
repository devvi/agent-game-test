---
name: game-research-agent
id: game-research-agent
title: Game Design Research Agent
description: >
  Research agent for Godot 4.7 GDScript projects. Reads GitHub Issues (label:
  workflow/research), explores existing source code, produces a structured PRD
  at docs/PRD/{N}-{slug}.md and opens a research/ PR.
category: autonomous-ai-agents
tags:
  - gamedev
  - research
  - godot
  - gdscript
  - game-design
  - prd
---

# Game Design Research Agent

## 🛠️ WORKTREE 工作流（强制, 2026-08-13 起 — 多 agent 隔离红线）

> **必须在独立 worktree 中开发, 禁止在主工作区操作。** 根因: 多 agent 并发共用
> 主工作区导致 PR 互相污染 (#440 混入 #387 文件等)。方案见 docs/PLAN-worktree-isolation.md。

```bash
# 1. 创建 worktree (基于最新 origin/main, 幂等)
WT=$(./scripts/worktree-setup.sh research <N> <slug>)

# 2. 所有文件操作在 worktree 内 (绝对路径)
#    写 PRD:  $WT/docs/PRD/<N>-<slug>.md

# 3. 完成 → 提交 (脚本自动: 提交前 merge main + 冲突分级 + 白名单 add)
./scripts/worktree-commit.sh <N> "docs(research): PRD for #<N> — <title>" "$WT/docs/PRD/<N>-<slug>.md"

# 4. PR 创建 (worktree 内)
cd "$WT" && gh pr create --base main --head research/<N>-<slug> --title "research: PRD for #<N>" --body "parent #<N>"

# 5. 清理
git worktree remove "$WT" --force
```

> ⚠️ `WT=$(...)` 捕获了脚本的 log 行（log 打到 stdout）— 直接用确定性路径
> `/tmp/wt-<phase>-<N>`（如 `/tmp/wt-research-465`）或 `WT=$(... | tail -1)`（Patch 4）。

**红线:**
- ❌ 绝不 `git add .` — worktree-commit.sh 强制白名单
- ❌ 绝不 `git stash` — worktree 隔离后不需要 (stash 是污染时代的遗产)
- ✅ merge 冲突: 脚本自动尝试合并, 失败则 abort + 报告, 不硬解

> ⚠️ **Profile-level shadow of global skill.** This skill was created because
> `skill_manage` cannot edit the global skill at
> `~/.hermes/skills/software-development/game-research-agent/SKILL.md` from
> within the default profile. It contains patches documented during Issue #46's
> and Issue #58's research phases that the global skill cannot be modified to
> include.
> If the global skill is ever updated, this profile-level shadow should be
> deleted.
> See `skill_view('software-development:game-research-agent')` for the base
> skill, which has a **broken REST API command** (the `-f labels='[...]'`
> syntax returns 422 — use `echo '{"labels":[...]}' | gh api ... --input -`
> instead). The patches below include the fix.

### Patch 7: NPC Architecture Patterns reference

Research sessions about NPC systems (like Issue #54) should consult `references/npc-architecture-patterns.md` for the three evaluated approaches (component vs SceneBase extension vs manager autoload), the decision flow chart, and dialogue engine integration patterns. Covers Godot 4.x composition patterns with personality layer evaluation, state machines, and exported property design.

### Patch 8: Bug investigation reference

Research sessions on `bug`-labeled issues (compile/runtime errors) should consult `references/bug-investigation-techniques.md` for trace-back techniques — parent class inheritance verification, API signature checking, null reference tracing, tscn format verification via hexdump, and Godot import cache management. The standard feature-research workflow (searching for code patterns, reading design docs) does not cover these techniques.

### Patch 9: Architectural intent analysis for interaction/controller features

When the issue title mentions input, controls, WASD, or player movement, the
research must determine whether the codebase was ARCHITECTED for a player body
that was never built before choosing an approach. Follow the interaction
research pattern documented in the `game-prd-research` skill at
section §9 and `references/interaction-controller-research-patterns.md`.

Key checks before writing the PRD's Solution Comparison:

```bash
# 1. Check for proximity infrastructure (strongest intent signal)
rg 'is_in_group\("player"\)' gdscripts/*.gd      # Does NPCNode check for player?
rg 'body_entered\|body_exited' gdscripts/*.gd     # Are proximity hooks wired?

# 2. Check if Space conflicts with dialogue_select
awk '/^\[input\]/,0' project.godot | grep 'space\|32\|4194306'

# 3. Measure scene sizes for WASD viability
grep -A5 'Floor\|Ground\|StreetSurface' scenes/*/*.tscn | grep size
```

If NPCNode already has `body_entered` + `is_in_group("player")` checks (like
of the agent-game-test project), the architecture was designed for a moving player
body, and WASD free-movement is the correct approach. The NPC proximity labels,
prompts, and `_player_nearby` state are all ready — only the player body needs
creation.

### Patch 10: Bug pre-investigation workflow reference

Research sessions on `bug`-labeled issues should run **pre-investigation** (`references/bug-pre-investigation-workflow.md`) BEFORE applying technical debugging techniques. This workflow detects cases where the described bug has been partially or fully addressed by prior PRs, prevents re-fixing already-fixed code, and surfaces the actual remaining behavioral issues.

Key steps:
1. **Check current source** — Read the exact file+line the issue mentions. If the fix already exists, it was addressed by a prior commit.
2. **Find the fixing commit** — `git log --oneline --all | grep <issue-N>` to find the batch PR that addressed it. Read the diff to understand the scope of the prior fix.
3. **Cross-reference prior docs** — Search existing PRDs, DESIGN docs, and TASKS docs for mentions of the same system. Prior planning may have anticipated remaining issues.
4. **Map the non-obvious surface area** — Do a scene-by-scene inventory (which scenes use the affected system, which have pre-existing nodes vs programmatic creation). Check cross-file call chains.
5. **Identify the real remaining bug** — Often the issue title describes a pre-fix symptom that no longer exists. The actual remaining problem is a secondary effect of the fix.

Document findings as a table in the PRD's Problem Definition section:
- **Already fixed** — what was done and in which commit/PR
- **Still broken** — what remains, with evidence
- **Stale claims** — issue claims that don't match current code

## Patches vs Global Skill

This profile-level skill extends the global `game-research-agent` with the
following improvements discovered during real research sessions.

### Patch Index (reading order)

| # | Topic | Location |
|---|-------|----------|
| 1 | Stage-gate integration before merge | ↓ §Patch 1 |
| 2 | Auto-merge with `--squash` | ↓ §Patch 2 |
| 3 | Auto-advance via workflow-chain.yml (+ squash-merge gap) | ↓ §Patch 3 |
| 4 | Pitfalls discovered (12+ real traces) | ↓ §Patch 4 |
| 5 | REST API label advancement (422 fix) | ↓ §Patch 5 |
| 6 | Feishu webhook notification | ↓ §Patch 6 |
| 7 | NPC architecture patterns reference | ↑ §Patch 7 (top) |
| 8 | Bug investigation reference | ↑ §Patch 8 (top) |
| 9 | Interaction/controller architectural intent | ↑ §Patch 9 (top) |
| 10 | Bug pre-investigation workflow | ↑ §Patch 10 (top) |
| 11 | Default branch detection (manifest → gh → main) | ↓ §Patch 11 |
| 12 | Manual-PR fallback for GitHub API 500 | ↓ §Patch 12 |
| 13 | godot_dialogue_manager integration | ↓ §Patch 13 |
| 14 | PRD scope deconfliction | ↓ §Patch 14 |
| 15 | Addon classification + depth/light PRD sections | ↓ §Patch 15 |
| 16 | Implementation-PRD codebase audit | ↓ §Patch 16 |
| 18 | Minimum PRD quality gate (reject "Auto-generated") | ↓ §Patch 18 |
| 19 | Issue constraint inheritance (engine/dir/platform) | ↓ §Patch 19 |
| 20 | Assembly/Integration PRD scene gap analysis | ↓ §Patch 20 |
| 21 | GPUParticles2D display diagnostics (visibility_rect culling + ClassDB verify) | ↓ §Patch 21 |

> Patches 7-10 (research-type-specific flows) are at the top of this file —
> they apply to NPC/bug/interaction research sessions. Patches 1-6 & 11-20
> below apply to the general research workflow. (No Patch 17 — number was
> skipped during accumulation.)

### Patch 1: Stage-gate integration

After opening the PR (step 7), run stage-gate validation **before** merging:

```bash
source ~/.hermes/.env
python3 scripts/stage-gate.py --issue <N> --stage research --pr <PR_NUM>
```

This catches and auto-fixes missing workflow labels (common when `gh pr create`
uses the REST API fallback, which doesn't set labels).

### Patch 2: Auto-merge with --squash

Research PRs are docs-only with no CI gate. Merge with:

```bash
gh pr merge <PR_NUM> --squash --delete-branch
```

### Patch 3: Auto-advance via workflow-chain.yml

When `.github/workflows/workflow-chain.yml` exists, the GitHub Action
automatically advances the parent issue's label on PR merge:
`workflow/research` → `workflow/plan`. The manual `gh issue edit` step in the
global skill is only a fallback.

**⚠️ Known gap: squash-merge may not trigger auto-advance.** During Issue #58
research, the label did not advance after a squash-merge (PR #99). Always check
after merging — if the issue still has `workflow/research`, use the REST API
fallback (Patch 5) to manually advance before declaring done.

**Auto-merge vs direct merge:** Research PRs (docs-only, no CI) can use
either `gh pr merge <N> --squash --delete-branch` (direct merge, blocks until
done) or `gh pr merge <N> --auto --squash` (auto-merge, queues and returns
immediately). For docs-only PRs with no CI gate, auto-merge fires instantly.
Auto-merge is preferred when you want to do other work (notification, label
check) while GitHub processes the merge, but always verify the merge happened
before proceeding: `gh pr view <N> --json state,mergedAt`.

### Patch 4: Pitfalls discovered

| Pitfall | Resolution |
|---------|-----------|
| PR missing workflow label after creation | Stage-gate auto-fixes it. Or: `gh issue edit PR_NUM --add-label workflow/research` |
| Forgetting to source env before gh | `source ~/.hermes/.env` before any `gh` call |
| Merging without stage-gate | Stage-gate catches missing labels, wrong branches, and missing body refs. Without it, workflow-chain.yml silently skips |
| Research PR not merged with --squash | Research PRs are docs-only. Always `--squash --delete-branch` |
| REST API label add fails with 422 (`-f labels='["x"]'`) | The `-f` flag doesn't serialize arrays correctly. Use `echo '{"labels":["x"]}' \| gh api ... --input -` |
| Label DELETE returns 404 after adding plan label | Harmless — GitHub may auto-remove `workflow/research` when `workflow/plan` is added. Wrap in `2>/dev/null \|\| true` |
| workflow-chain.yml silent skip after squash-merge | Auto-advance may not fire. Always verify issue labels post-merge. Fall back to manual REST API advance |
| Name collision — `skill_view('game-research-agent')` fails | Both this skill and the global skill share `game-research-agent`. Always use full path: `skill_view(name='autonomous-ai-agents/game-research-agent')` or `skill_view(name='software-development/game-research-agent')` |
| Issue was CLOSED from prior aborted attempt | Before running stage-gate, check issue state with `gh issue view <N> --json state`. If CLOSED, reopen with `gh issue reopen <N>` |
| Dirty working tree — `git checkout -b` silently lands on wrong branch | Check `git status --short` before branching. Stash dirty changes first: `git stash push -m "research-{N}-pre-branch"`. If commit landed on wrong branch, delete and cherry-pick: `git branch -D research/{N}-{slug}` → checkout main → create branch → `git cherry-pick <hash>` |
| `docs/PRD/` directory does not exist yet | Run `mkdir -p docs/PRD` before writing the PRD file. While `write_file` auto-creates dirs, failing at this step wastes a round-trip |
| `git stash pop` fails after PR merge updates main | After the PR merges, `git checkout main && git pull origin main` can leave stash entries with files that conflict with the updated main. Resolution: `git stash drop` (discard temp changes) or `git stash branch temp-branch` to apply stash on a new branch |
| PR body `"parent #N"` vs `"Parent #N"` capitalization | Default convention is **lowercase `p`**, but if the task message explicitly specifies capitalization (e.g. `body 用 Parent #465`), follow it **verbatim** — the `workflow-chain.yml` parser is case-insensitive so either advances. `parent: #N` (with colon) does NOT match. |
| `WT=$(./scripts/worktree-setup.sh ...)` captures log lines, not a clean path | The script's `log()` echoes to **stdout**, so the captured var is polluted and `cd "$WT"` fails. Use the deterministic path directly: `/tmp/wt-<phase>-<N>` (e.g. `/tmp/wt-research-465`), or strip logs: `WT=$(./scripts/worktree-setup.sh ... | tail -1)`. The worktree itself is created correctly either way (2026-08-13 #465 trace). |
| godot headless `--script` output mixed with project autoload warnings | Project autoloads (e.g. audio_engine headless warnings) print to stdout BEFORE your script's output. Pipe through grep for your print markers: `godot --path mini-pong/ --headless --script /tmp/x.gd 2>&1 | grep 'default\|^==='` — don't read the raw tail. |
| Issue file domain names a file that doesn't exist under that name | Map issue-named file → actual repo file in the PRD (2026-08-13 #465: issue says `test_rain_curtain.gd`, registered suite is `test_rain.gd`). Recommend extending the existing file (no duplicate suites), state the decision explicitly for the review gate; rename only if the gate requires the literal name. |
| Feishu webhook URL unknown or not configured | The webhook URL is stored in the pipeline configuration, not in env vars. If you don't have it, skip the notification step — it's not blocking. |
| PRD section structure differs from template | This project's PRDs use a specific 8-section format (see `references/prd-section-structure.md`) that diverges from `templates/PRD_TEMPLATE.md`. Always follow the established PRD patterns in `docs/PRD/` rather than the generic template. |
| GitHub API returns HTTP 500 on PR creation | Both `gh pr create` (GraphQL) and `gh api repos/.../pulls -X POST` (REST) return 500/\"Something went wrong\". This is a **server-side GitHub failure**, not rate limit or auth — rate limit shows thousands remaining and auth is fine. Resolution: verify the branch has commits differing from base (`git log --oneline main..research/N-slug`), then generate a manual compare URL: `echo \"https://github.com/$OWNER/$REPO/compare/$BASE...research/N-slug?expand=1\"`. The user can open this in a browser to create the PR. |
| `gh pr merge` errors about untracked files but merge succeeded remotely | In multi-agent workflows, parallel agents create untracked files (e.g. `docs/PRD/289-*.md`). When `gh pr merge --squash --delete-branch` runs, the local fast-forward fails: `error: The following untracked working tree files would be overwritten by merge: ... Aborting`. **The remote merge often already succeeded.** The squash-merge commit landed on origin/main despite the local error. Always verify: `git log --oneline origin/main | head -3` or `gh pr view <N> --json state,mergedAt`. If merged: `git checkout main && git reset --hard origin/main`. If NOT merged: `git stash push -m "temp" -- <untracked-files>` then retry. Never give up on the merge before checking remote state — the error is a local working-tree artifact, not a merge rejection. |
| Parallel agent branch collision — remote branch overwritten by another agent | In multi-agent workflows, another agent may force-push to the same `research/{N}-{slug}` branch. Symptoms: your commit lands on a different branch (`git commit` output says `[main <hash>]` instead of `[research/{N}-{slug}]`); `git push --force` later says "Everything up-to-date" but `git ls-remote origin refs/heads/research/{N}-{slug}` shows a foreign commit. **Recovery:** (1) Find your commit in reflog: `git reflog | grep "<your commit message>"`. (2) Reset your branch to it: `git reset --hard <hash>`. (3) Force-push with explicit refspec (see next pitfall). (4) Verify: `git ls-remote origin refs/heads/research/{N}-{slug}`. |
| `git push --force` silently no-ops ("Everything up-to-date") when tracking is broken | When another agent overwrites the remote branch, `git push -u origin <branch> --force` can silently return "Everything up-to-date" even though `git ls-remote` shows mismatched commits. Root cause: `git config branch.<name>.remote` is empty or stale after the overwrite. **Fix:** use explicit refspec: `git push origin <commit-hash>:refs/heads/research/{N}-{slug} --force`. Always verify with `git ls-remote origin refs/heads/research/{N}-{slug}` — the hash must match `git rev-parse HEAD`. |
| Stage-gate fails on issue label after another agent advanced it | In multi-agent workflows, the issue may already have `workflow/plan` (advanced by another agent's pipeline). Stage-gate fails the issue-label check but the PR gate passes (branch/PR labels are correct). **Resolution:** merge anyway. The label is already correct — skip manual advancement. Only block on stage-gate if the PR gate itself failed. |

### Patch 5: REST API fallback for label advancement (corrected)

The global skill's REST API label command `-f labels='["workflow/plan"]'` **does
not work** (returns HTTP 422). The correct syntax pipes JSON via stdin:

```bash
REMOTE_URL=$(git remote get-url origin)
OWNER_REPO=$(echo "$REMOTE_URL" | sed -E 's|.*github\\.com[:/]||; s|\\.git$||')

# Add workflow/plan label — use --input -, NOT -f labels=...
echo '{"labels":["workflow/plan"]}' \
  | gh api repos/$OWNER_REPO/issues/<N>/labels -X POST --input -

# Remove old label (may 404 — harmless, GitHub often auto-cleans)
gh api repos/$OWNER_REPO/issues/<N>/labels/workflow/research \
  -X DELETE 2>/dev/null || true
```

Also verify the label state after, not just trust the API exit code:

```bash
gh issue view <N> --json labels \
  | python3 -c "import json,sys; print([l['name'] for l in json.load(sys.stdin)['labels']])"
```

### Patch 11: Default branch detection from game-env/manifest.yaml

The global skill hardcodes `main` as the default branch in all branching,
checkout, and PR creation commands. However, some projects use `master`
or another branch name. Always check `game-env/manifest.yaml` before
running git/gh commands:

```bash
# Read default branch: manifest → gh repo view (dynamic) → main (NOT master)
# ⚠️ Do NOT use python3 -c "import yaml" — PyYAML may not be installed
# on most systems. Use grep+sed for portability:
DEFAULT_BRANCH=$(grep -E '^\s*default_branch\s*:' game-env/manifest.yaml 2>/dev/null \
  | head -1 \
  | sed -E 's/.*default_branch\s*:\s*"?([^"#\r]+)"?.*/\1/' \
  | tr -d '[:space:]')
# Fallback 1: dynamic detection (authoritative when manifest missing)
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "")
fi
# Fallback 2: main — GitHub's default. NOT master (2026-07-31 convention).
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
# Verify with git branch (source of truth):
ACTUAL_BRANCH=$(git branch | grep '^\*' | sed 's/^..//')
if [ -n "$ACTUAL_BRANCH" ] && [ "$DEFAULT_BRANCH" != "$ACTUAL_BRANCH" ]; then
  DEFAULT_BRANCH="$ACTUAL_BRANCH"
fi
echo "Using default branch: $DEFAULT_BRANCH"
```

Then use `$DEFAULT_BRANCH` in all commands instead of the hardcoded `main`:
```bash
git checkout "$DEFAULT_BRANCH"
git pull origin "$DEFAULT_BRANCH"
gh pr create --base "$DEFAULT_BRANCH" --head research/{N}-{slug} ...
```

**Fallback order:** Manifest → `gh repo view` dynamic detection → `main`
(2026-07-31: fallback is `main`, NOT `master` — GitHub's default; the repo
convention is main and the manifest is tracked with `default_branch: main`).

**⚠️ Pitfall: Ignoring manifest causes PRs to target wrong base branch.**
2026-07-23 trace: Research agents for Issues #147, #148, #150, #152 all
created PRs targeting `main` (following the global skill's hardcoded command)
even though the cron context explicitly said "Default branch: master (NOT main)."
The agents read the skill first and followed its hardcoded `main` commands
instead of the context override. All four PRs target `main` instead of `master`.

**Verification after each PR creation:**
```bash
gh pr view <N> --json baseRefName
# Must match $DEFAULT_BRANCH
```

### Patch 12: Manual-PR fallback for GitHub API server errors

When `gh pr create` or the REST API fallback (`gh api repos/.../pulls -X POST`) returns HTTP 500 or "Something went wrong", even with a valid branch that has commits, the cause is **GitHub server-side failure** — not rate limiting, not auth, and not content validation.

**Diagnosis steps before falling back:**

```bash
# 1. Confirm it's not rate limiting
gh api rate_limit | python3 -c "import json,sys; r=json.load(sys.stdin)['resources']['core']; print(f'Remaining: {r["remaining"]}/{r["limit"]}')"

# 2. Confirm branch actually differs from base
git log --oneline "$DEFAULT_BRANCH..research/{N}-{slug}"

# 3. Confirm auth is fine
gh auth status
```

If all above check out but PR creation still fails, **do not retry indefinitely** — the issue is on GitHub's side.

**Alternative API call patterns to try before giving up:**

Sometimes JSON and form-encoded submission hit different code paths on GitHub's backend:

```bash
# Pattern A — JSON via --input (may return HTTP 500 on server bug):
echo '{"title":"...","head":"research/{N}-{slug}","base":"main","body":"parent #N"}' \
  | gh api repos/$OWNER_REPO/pulls -X POST --input -

# Pattern B — Form-encoded (may return 422 instead of 500):
gh api repos/$OWNER_REPO/pulls -X POST \
  -f title="..." \
  -f head="research/{N}-{slug}" \
  -f base="main" \
  -f body="parent #N"

# Pattern C — If form-encoded returns 422 "field:head, code:invalid",
# try prefixing the head ref with the owner:
gh api repos/$OWNER_REPO/pulls -X POST \
  -f title="..." \
  -f head="$OWNER:research/{N}-{slug}" \
  -f base="main" \
  -f body="parent #N"

# Pattern D — Draft PR also fails the same way (doesn't bypass 500):
gh pr create --draft ...
```

If **all patterns** fail (both JSON and form-encoded return errors), the head ref format is unlikely to be the issue — the failure is GitHub server-side and cannot be worked around by changing request format.

**Generate a manual compare URL:**

```bash
REMOTE_URL=$(git remote get-url origin)
OWNER_REPO=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[:/]||; s|\.git$||')
COMPARE_URL="https://github.com/$OWNER_REPO/compare/$DEFAULT_BRANCH...research/{N}-{slug}?expand=1"
echo "Create PR manually: $COMPARE_URL"
```

The `?expand=1` query parameter pre-fills the PR form with title and branch info.

**Consequences of manual fallback:**
- The PR labels will not be set automatically. The stage-gate script must fix this post-merge.
- The PR body must be `parent #N` (lowercase p). If typed wrong, fix with: `gh pr edit <N> --body "parent #N"`

**Post-creation verification (same as normal):**
```bash
gh pr view <N> --json baseRefName,body,labels
```

### Patch 13: godot_dialogue_manager integration reference

Research sessions about dialogue engine features (like Issue #215) should consult `references/godot-dialogue-manager-integration.md` for the v3.10.5 API reference, `.dialogue` language syntax, StateSystem integration patterns, DialogueBalloon code template, JSON→.dialogue migration table, and known pitfalls. This covers the API of the 3727-star dialogue addon for Godot 4.7.

### Patch 14: PRD scope deconfliction — detect overlapping existing PRDs

When an issue's topic overlaps with a prior research PRD, the new PRD must scope
itself to a DIFFERENT angle to avoid redundancy and scoping conflicts. Add this
step after codebase exploration and before producing the PRD:

```bash
# Scan existing PRDs for overlap with current issue topic
ls -t docs/PRD/*.md | head -10
ISSUE_TITLE=$(gh issue view <N> --json title --jq '.title')
for prd in docs/PRD/*.md; do
  base=$(basename "$prd" .md)
  if echo "$base" | grep -q "^${N}-"; then
    continue  # Skip our own PRD (not yet written, but no-op)
  fi
  # Score keyword overlap between issue title and first 10 lines of PRD
  echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | grep -oE '\w+' | \
    while read -r word; do
      head -10 "$prd" | tr '[:upper:]' '[:lower:]' | grep -q "\b$word\b" && echo "match:$word"
    done | sort | uniq -c | sort -rn | head -5
  echo "---"
done
```

**Scope deconfliction rules — real cases from agent-game-test:**

| Current Issue (PRD #) | Existing PRD Topic | Overlap Detected | Correct Scope for New PRD |
|----------------------|-------------------|-----------------|--------------------------|
| Scene navigation UX (#221) | #156 — Scene Transition System (ExitZone) | Both about moving between scenes | Route design, guidance UX, fallbacks — NOT re-covering transition mechanics |
| NPC interaction | #54 — NPC Framework (dialogue)<br>#156 — ExitZone (proximity) | Proximity detection pattern overlap | Movement-based interaction, prompt UI, physics-ray detection — NOT re-covering dialogue or exit zones |
| Player movement | #142 — PlayerController (WASD) | Both about player motion | Input remapping, accessibility options, controller support — NOT re-covering CharacterBody3D physics |

**When overlap is found:**
1. **Read the overlapping PRD's Problem Definition** — understand what's already been researched and its scope boundaries.
2. **In the new PRD's Problem Definition**, explicitly state the boundary: "PRD #{M} covered [technical layer]. This PRD covers [different layer — design/UX/route/failover]."
3. **In the Solution Comparison**, reference the existing PRD's approach as a foundation rather than re-listing technical details: "Using the ExitZone from PRD #156's Approach A, this PRD designs the guidance layer on top."
4. **Do NOT re-analyze approaches the existing PRD already covered.** If PRD #156 already compared 3 approaches for scene transition mechanics, the new PRD should compare approaches for the NEW scope (guidance UX → 3 approaches) instead.

**Common patterns for PRD scope overlap:**

| Existing PRD Covers | Remaining Overlap for New PRD |
|--------------------|------------------------------|
| Runtime mechanics (HOW it works) | Design/UX (WHAT the player experiences) |
| A specific component class | The system that orchestrates it across scenes |
| The data model | The runtime behavior and edge cases |
| A single scene's implementation | Cross-scene patterns and state management |

**Reference file:** `references/prd-scope-deconfliction-examples.md` (created when a specific overlap case is worth preserving).

### Patch 6: Feishu webhook notification

After the research PR is merged (or auto-merge is enabled), notify the project's
Feishu bot channel. This is a pipeline convention that lets downstream agents
and humans track progress without polling GitHub.

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"msg_type":"text","content":{"text":"📋 #<N> → research (light|standard|deep)"}}' \
  <WEBHOOK_URL>
```

**Depth label in message:** Append `(light)`, `(standard)`, or `(deep)` matching the issue's
`depth/` label so the channel can tell research scope at a glance.

**When to run this:** After enabling auto-merge (`gh pr merge <N> --auto --squash`)
or after a direct merge — but before proceeding to label advancement. The
notification is non-blocking; if the webhook URL is unavailable or unknown, skip
it.

**Where to find the webhook URL:** The `feature-plan-documentation` skill stores
the URL in its Pipeline Follow-up (Post-PR) section. For the agent-game-test
project: `https://open.feishu.cn/open-apis/bot/v2/hook/76101281-b359-49ab-ae2f-fc486bf65958`.
Alternatively check `.github/workflows/` files. If you don't have it, the step
is optional.

### Patch 15: Addon classification research + depth/light PRD clarification

**Addon classification research:**

When an issue references a third-party GitHub addon (theme, plugin, library),
run the investigation protocol in `references/addon-classification-research.md`
before writing the PRD. This prevents the common pitfall of assuming a
highly-starred addon can be used directly at runtime when it's actually an
editor-only tool.

**Key investigation steps (see reference for full protocol):**

1. Check README for editor-only keywords: `EditorSettings`, `EditorInterface`, "editor theme"
2. Download and inspect the `.tres`/resource file content — don't trust README alone
3. Look for `@tool` scripts or `EditorInterface` imports in the resource's GDScript source
4. Check if Godot's built-in theme already covers the addon's purpose (since Godot 4.6)

**Example:** Issue #216 asked to "integrate godot-minimal-theme" (3781⭐). Inspection
revealed the `.tres` file uses `EditorInterface.get_editor_settings()` making it
**editor-only**. The project needed a custom runtime Theme resource instead.
Since Godot 4.6, this theme is already the built-in default editor theme.

**depth/light PRD section requirements clarification:**

The PRD section structure reference at `references/prd-section-structure.md` specifies:

| Depth | Sections Required |
|-------|------------------|
| `depth/deep` | All 8 sections — Section 7 (Spike/Experiment) mandatory with ≥3 experiments |
| `depth/standard` | Sections 1–6 + 8 — Section 7 optional |
| `depth/light` | Sections 1–5 + 8 — Section 6 (Dependencies) and Section 7 optional |

**⚠️ Important:** Section 8 (Continuation Context) is **required for ALL depths**,
including `depth/light`. It is the handoff to the plan agent. Skipping it means the
plan agent must re-scan all source files. Always include it.

The PRD MUST follow the project-specific 8-section format from
`references/prd-section-structure.md` rather than the generic `templates/PRD_TEMPLATE.md`.
The project's PRD format (Problem Definition → Design Intent → Impact Analysis →
Solution Comparison → Boundary Conditions → Dependencies → Spike → Continuation Context)
diverges significantly from the template's structure (Overview → Motivation →
Requirements → etc.).

### Patch 18: Minimum PRD quality requirement — reject "Auto-generated" PRD

> **Issue #286 session trace (2026-07-27):** The research agent for `[Scaffold] 项目骨架 — 目录结构与 CI` produced a PRD with a single line: `# [Scaffold] 项目骨架 — 目录结构与 CI\n\n## Overview\nAuto-generated PRD.` This 1-line, content-free PRD was merged, then the plan agent produced a 10-line DESIGN describing a 3D scene (completely wrong for a 2D scaffold), and the implement agent built a Vite web project + Snake game instead of a Godot 4.7 Mini Pong project.

**Root cause:** The research agent had no minimum quality gate for PRD output. A 1-line "Auto-generated PRD." was accepted and merged.

**Fix — PRD quality gate:**

Before opening the research PR, ALWAYS verify the PRD meets minimum quality standards:

```bash
# Count meaningful content lines (exclude title, blank, and auto-generated markers).
# ⚠️ Do NOT use '^[A-Za-z]' — it misses lines starting with CJK characters,
# markdown formatting (# | - [x] >), and table rows. Use a broad character-count
# regex that covers ASCII, CJK Unicode (U+4E00–U+9FFF), and digits.
PRD_FILE="docs/PRD/${N}-${slug}.md"
MEANINGFUL_LINES=$(grep -cE '[A-Za-z0-9\u4e00-\u9fff]{3,}' "$PRD_FILE" 2>/dev/null || echo 0)
NONBLANK_LINES=$(grep -c '.' "$PRD_FILE" 2>/dev/null || echo 0)
AUTO_GEN_LINES=$(grep -ci "auto-generated\|auto generated" "$PRD_FILE" 2>/dev/null || echo 0)

if [ "$MEANINGFUL_LINES" -lt 5 ]; then
  echo "❌ PRD quality FAIL: only $MEANINGFUL_LINES meaningful lines ($NONBLANK_LINES non-blank)"
  echo "Must have at least 5 substantive lines (Problem Definition, Design Intent, etc.)"
  echo "Expand the PRD before creating the PR."
  exit 1
fi

if [ "$AUTO_GEN_LINES" -gt 0 ]; then
  echo "❌ PRD quality FAIL: contains 'Auto-generated' marker"
  echo "Replace placeholder content with actual research findings."
  exit 1
fi

echo "✅ PRD quality PASS: $MEANINGFUL_LINES substantive lines, $NONBLANK_LINES non-blank"
```

**Minimum PRD structure (all depths):**

| Section | Required | Min Lines |
|---------|----------|-----------|
| Problem Definition | ✅ | 3+ lines explaining what the issue requires |
| Design Intent | ✅ | 2+ lines connecting to the game's overall architecture |
| Continuation Context | ✅ | 2+ lines of handoff to the next phase agent |

**The following indicate the research agent is broken / not doing real work:**
- PRD is a single line or contains only "Auto-generated PRD."
- PRD is copy-pasted from the issue title with no additional context
- PRD does not mention engine, platform, or directory constraints from the issue
- PRD has no Problem Definition section — just a list of TODO items

**⚠️ The stage-gate or workflow must also catch empty PRDs.** The research agent's self-check is the first line of defense, but `stage-gate.py` should also flag PRDs that are too short or contain placeholder text.

### Patch 19: Issue constraint inheritance — PRD must inherit engine/dir/platform from the issue

The PRD must explicitly carry forward the issue's technical constraints. A scaffold Issue that says "Godot 4.7.1, directory mini-pong/, CI workflow" must produce a PRD that references these exact constraints.

**Before creating the PRD, read the issue body:**

```bash
gh issue view <N> --json body --jq '.body'
```

Then ensure the PRD's Problem Definition restates these constraints in its own words. The implement agent reads the DESIGN doc, not the original issue — so if the PRD doesn't transmit the constraints, the entire pipeline loses them.

When a single issue covers **multiple independent subsystems** (e.g. rain particles, neon decals, ground fog, light cones as 4 separate visual systems), the PRD must deviate from the standard single-Solution-Comparison structure:

**Multi-sub-system PRD rules:**

1. **Subdivide Section 4 (Solution Comparison)** — Create 4.1, 4.2, 4.3, 4.n, one per subsystem. Each subsection follows the standard 2-3 Approach A/B/C format with Pros/Cons/Risk/Effort for that subsystem alone.

2. **Add a recommendation table** at the end of Section 4 summarizing the chosen combination:

   ```markdown
   | Subsystem | Recommended | Core File |
   |-----------|-------------|-----------|
   | Raindrops | A: GPUParticles3D + shader | `rain_particles.gd` |
   | Neon halos | A: Independent Decal + dynamic color | `neon_decal_controller.gd` |
   | Ground fog | A: GPUParticles3D + semi-transparent | `ground_fog.gd` |
   ```

3. **Each subsystem needs its own experiment** in Section 7 (Spike). A single experiment covering all subsystems at once is too coarse. For a 4-subsystem PRD, ≥4 experiments are expected (one per subsystem + possibly an integration one).

4. **Impact Analysis must list every subsystem's files** — don't lump them under "visual system". Each subsystem has its own script, scene placement, and materials.

5. **Deconfliction per subsystem, not per issue** — Check overlap between each subsystem and existing PRDs independently. One subsystem may overlap while another doesn't.

**Parameter-contract-to-execution-layer pattern:**

When the research scan reveals that a **prior issue defined abstract parameters** (a "contract" of what values exist and what they mean) but no runtime infrastructure consumes those parameters, the current issue is about building the **execution layer** that makes the contract actionable.

**Detection signals:**
- A prior PRD/issue mentions parameters like `rain_density`, `light_flicker`, `vignette` as "mapped" or "defined" — but no code instantiates GPUParticles3D, modifies Decal opacity, or animates light intensity
- `grep -r 'get_hallucination_params\|rain_density\|light_flicker' gdscripts/` returns results in a `worldview_controller.gd` or similar "mapping" file, but no `GPUParticles3D.amount` or `Decal.modulate` is set from those values
- The issue title contains words like "基础/基础设施/baseline" alongside "视觉/visual/atmosphere" — suggesting it's the foundational layer, not the dynamic one
- The issue body explicitly says "本Issue只做基础视觉效果，幻觉等级驱动的动态变化在#N中扩展" (static baseline, dynamics deferred)

**When the pattern is detected, the PRD must:**
1. **Explicitly name the parameter contract** in Problem Definition — show the prior issue defined values X, Y, Z that need an execution layer
2. **Design components with @export parameters** matching the contract keys — so #19 can simply write `rain_particles.amount = base + hallucination_params.rain_density * max_bonus`
3. **Add a "Scope Boundaries" table** in Problem Definition showing what the parameter contract covers (from prior issue) vs what the execution layer builds (current issue)
4. **Add an explicit deferred-dynamics note** in Design Intent: "This issue builds static baseline infrastructure. Dynamic conditioning by hallucination level is deferred to #N."
5. **In the Boundary Conditions**, add: "All @export parameters must be readable/writable from external scripts" — this is the API contract for the deferred dynamic layer
6. **In Continuation Context**, list the parameter keys the execution layer exposes and which future issue (#N) is expected to drive them

**Real example (Issue #217):**
- #214's `WorldviewController.get_hallucination_params()` defined a parameter contract with keys `{vignette, rain_density, light_flicker, text_drift, view_instability}` for hallucination levels 0-10
- #217 built the execution layer: `rain_particles.gd` (GPUParticles3D), `neon_decal_controller.gd` (Decal nodes), `ground_fog.gd` (GPUParticles3D), `light_cone_controller.gd` (SpotLight3D+Decal)
- Each component exposed `@export var density`, `@export var flicker_intensity`, etc. matching the contract keys
- #217 was explicitly static: "错觉等级驱动的动态变化在#19中扩展"
- Without this pattern recognition, a researcher might propose hallucination-driven parameters in #217 itself, violating the issue's explicit scope boundary. See `references/multi-subsystem-prd-pattern.md` for the full #217 session trace.

### Patch 16: Implementation-PRD codebase audit — verify DESIGN was actually built

When the research PRD covers an **implementation** issue (the issue DEPENDS ON a
prior issue with a DESIGN doc, or the issue title contains "实现"/"Implementation"),
the PRD must include a **source-code audit** step BEFORE writing the Problem
Definition. This detects cases where prior PRs partially or fully implemented the
DESIGN doc's recommendations, so the new PRD scopes to the actual remaining work.

**When to trigger this:**
- The issue's `Depends On` references a prior issue with a DESIGN doc
- The issue body says "按#N的设计" (per the design of #N)
- The issue title ends with "实现" (implementation)
- The issue is labeled `workflow/implement` or the research scan reveals
  that another PR merged code related to the same topic

**Audit procedure — read source files, not just docs:**

```bash
# 1. Identify every component the PRIOR DESIGN doc says should exist.
#    Read the DESIGN doc's "New Files" and "Modified Files" sections.
#    For each claimed file, check if it actually exists:
ls gdscripts/exit_zone.gd 2>/dev/null && echo "EXISTS" || echo "MISSING"
ls gdscripts/scene_title_overlay.gd 2>/dev/null && echo "EXISTS" || echo "MISSING"

# 2. For existing files, read the source to verify the DESIGN-specified
#    exports, signals, and methods are present.
#    Example: DESIGN #221 specified exit_label and route_hint exports
#    on ExitZone. The source must match:
grep '^@export var' gdscripts/exit_zone.gd

# 3. Check GameManager / Constants for DESIGN-specified properties
grep 'navigation_context\|fallback_count' gdscripts/game_manager.gd
grep 'NAV_' gdscripts/constants.gd

# 4. Cross-reference the DEPENDENCY PRD — what approach did it recommend
#    vs what was DESIGN'd vs what was actually coded?
```

**Produce a three-column gap analysis table in the PRD's Problem Definition:**

| Component | DESIGN #N Status | Actual Code Status | Gap |
|-----------|:---------------:|:-----------------:|:---:|
| `gdscripts/exit_zone.gd` | ✅ Specified | ✅ Built (146 lines) | None |
| `gdscripts/navigation_controller.gd` | ✅ Specified | ❌ Not built | Needs creation |
| `GameManager.navigation_context` | ✅ Specified | ✅ Built (line 35) | None |

**Scope deconfliction for implementation PRDs:**

An implementation PRD differs from a design PRD in these ways:

| Dimension | Design PRD | Implementation PRD |
|-----------|-----------|-------------------|
| **Goal** | Choose an approach | Plan the build of the chosen approach |
| **Solution Comparison** | 2-3 competing approaches | Often single approach (already chosen), focus on implementation variants |
| **Dependencies** | May reference speculative deps | Lists concrete files and their build status |
| **Continuation Context** | Design handoff | Build handoff with file-by-file audit |
| **Edge Cases** | Theoretical | Concrete (verified against source) |

**When the audit reveals a gap (component exists but differs from DESIGN):**
- Document what the DESIGN said vs what was actually built
- In the Solution Comparison, evaluate whether to retro-fit the DESIGN spec or
  adjust the implementation plan to match current reality
- Add an explicit "已实现 ≠ 设计" table entry

**When the audit reveals a component was fully built already:**
- Mark it as "✅ BUILT" in the gap analysis
- Do NOT re-specify it in the implementation plan
- Note it in Continuation Context as existing infrastructure the
  implement agent should NOT re-create

**Real example (Issue #226):** The PRD for #226 audited DESIGN #221's file
manifest (7 new/modified files). 4 of 7 were fully built (ExitZone,
SceneTitleOverlay, GameManager properties, Constants) and 3 were not
(NavigationController, NavFallback, per-scene guidance config). The PRD
scoped itself entirely around the 3 missing components, saving ~200 lines
of redundant analysis.

### Patch 20: Assembly/Integration PRD — scene-file gap analysis

When the issue title contains "组装"/"Assembly" or "Integration" or the
issue body says "胶水代码"/"glue code", the research task is **not** about
designing new components — all components already exist from prior issues.
The research is a gap analysis: what does the existing scene file contain
vs what the issue requires.

This is a distinct PRD class from feature PRDs, implementation PRDs,
greenfield PRDs, and bug-investigation PRDs.

**Trigger conditions (any of these):**
- Issue title: "组装", "Assembly", "Integration", "胶水"
- Issue body: "胶水代码", "glue code", "不包含新功能", "no new features"
- The issue depends on 5+ prior issues (all closed)
- A scene file already exists with most component instances

**Research procedure (3 phases):**

**Phase 1: Node inventory — parse the existing scene file:**

```bash
# Read the existing scene file (game.tscn, Main.tscn, etc.)
# Extract all node names and their types
grep '\[node name=' mini-pong/scenes/game.tscn | head -30
# Check which ext_resource refs are already wired
grep 'ext_resource.*path=' mini-pong/scenes/game.tscn
```

**Phase 2: Gap analysis — compare scene file against issue requirements:**

Produce a 3-column table in the PRD's Problem Definition:

```markdown
| 组件 | Issue # | 当前状态 | 缺失 |
|------|---------|:-------:|------|
| Ball (Area2D) | #287 | ✅ 已实例化 | — |
| WorldEnvironment | #289 | ❌ 未实例化 | .tscn 存在但未在场景中实例化 |
| ScoreZones (左/右) | — | ❌ 不存在 | 得分通过 _process() 硬编码 X 检测 |
```

**Phase 3: Signal chain audit — trace every signal from producer to consumer:**

Create an ASCII diagram using ✅ (connected and working), ⚠️ (declared but
missing consumer), and ❌ (not connected):

```
Ball.score(side: int)
    │
    ▼
ScoringManager._on_ball_score(side)
    ├── scored(winner) ──► GameStateMachine._on_scored()  ← ✅
    ├── scored(winner) ──► ScoreFlash._on_score_changed() ← ✅ connected but ⚠️ node missing
    └── GameManager.add_score(winner)
            ├── score_changed(p,a) ──► GameHUD._on_score_changed()  ← ✅
            ├── game_won(winner)  ──► ⚠️ 无人监听 (expected for MVP)
            └── match_over(winner) ──► GameOverScreen._on_match_over()  ← ✅
```

**Bonus audit: Constants duplication detection:**

```bash
# Find duplicate const definitions across gdscripts/
grep -rh '^const [A-Z_]' mini-pong/gdscripts/*.gd | sort | uniq -c | sort -rn | head -20
# Any count > 1 is a candidate for extraction to constants.gd
```

This catches the common pattern where `POINTS_TO_WIN_GAME=5` is defined
in both `scoring_manager.gd` and `game_manager.gd`.

**How the assembly PRD differs from other PRD classes:**

| Dimension | Feature PRD | Assembly PRD |
|-----------|-----------|--------------|
| **Goal** | Design a new system | Assemble existing components |
| **Solution Comparison** | 2-3 competing architectures | Compare assembly strategies (incremental fix vs rebuild vs patch) |
| **Problem Definition** | "What should exist that doesn't" | "What's in the scene vs what should be" |
| **Impact Analysis** | New files to create | Existing files to modify (add nodes, update paths) |
| **Continuation Context** | Design handoff | Phase-ordered implementation plan (constants → scene → paths → test) |
| **Key deliverables** | Approach comparison, spike experiments | Gap analysis table, signal chain audit diagram, constants dedup |

**Scope deconfliction for assembly PRDs:**

Every predecessor issue is a component that the assembly PRD explicitly
does NOT re-design. Create a scope boundaries table showing:

```markdown
| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|-----------------|
| #287 (Ball Physics) | 球物理逻辑 | ❌ 不修改 ball.gd — 只编排其在场景中的位置和信号连接 |
```

Each row names the predecessor PRD, what it covers, and explicitly what
this PRD does NOT touch. The assembly PRD's unique scope is: the scene
file node tree structure, NodePath configuration, ext_resource references,
and signal wiring completeness.

**Reference PRD:** `docs/PRD/295-main-scene-assembly.md` (524 lines,
Issue #295 — assembled 12 components from 8 predecessor issues into Main.tscn).

### Patch 21: GPUParticles2D display diagnostics — "few/no particles" root causes

Graphics/particle bug issues (like #465 — rain curtain "single leak point"): before
writing the PRD's diagnosis, check the GPUParticles2D config against the three-candidate
decision tree. **The #1 root cause for "particles only visible near one spot" is the
default `visibility_rect = Rect2(-100,-100,200,200)`** (node-local coords) culling every
particle outside a 200×200 window — verified live via a headless ClassDB dump
(2026-08-13, Godot 4.7.1).

Full detail + copy-paste verification script: `references/godot-particle-diagnostics.md`.

Key facts to embed in the PRD:
- `visibility_rect` is Rect2 in **local coords**; default culls particles far from the
  node. Full-screen fix: node at screen center + `visibility_rect = Rect2(-w/2, -h/2, w, h)`.
- `emission_rect_extents` is **half-extents** (Vector2(360,8) = 720×16, not 720×8).
  World emission rect = node.position ± extents.
- Verify ANY Godot property name/type/default without docs:
  `ClassDB.class_get_property_list("Class")` / `class_get_property_default_value(...)`
  in a `--headless --script` SceneTree script; grep stdout for your lines (autoload
  warnings mix in).
- Platform-backend bugs (macOS Metal GPU particles) are the LAST resort — fix
  culling/geometry first (D1 → D2 → D3 order). Note: **CPUParticles2D has no
  `process_material`** (ParticleProcessMaterial is GPU-only), so swapping breaks
  `_material.*` modulation code and its tests.
- Issue spec bands (e.g. "velocity 800–1200 px/s") map to the runtime-modulated BASE
  constants; document the modulated band at default vs max intensity in the PRD.
- Issue file-domain names can differ from actual repo files — map and note the decision
  (see Patch 4 pitfalls table).
