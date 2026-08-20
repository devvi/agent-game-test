#!/usr/bin/env bash
# run-e2e-review.sh — local E2E verification for impl PRs (plan v2, 2026-07-31).
#
# Runs L0-L3 verification inside an isolated git worktree so the main working
# tree is never touched (kills the checkout/stash pitfall family), captures
# REAL rendered frames (in-process capture, display-sleep immune), asserts they
# are not fake (4-fold anti-fake check), and posts evidence to the PR.
#
# Usage:
#   scripts/run-e2e-review.sh <PR_NUM> [--subproject NAME] [--skip-visual]
#       [--baseline] [--no-comment] [--keep] [--dry-run]
#
# Headless semantics (#586 gap 6, 2026-08-20): `--headless` = dummy
# DisplayServer with NO rendering (screenshots come out black), so the capture
# layer MUST pick a real display driver explicitly — never fall back silently.
# Three tiers:
#   Tier 1  local unattended   --display-driver <os> --rendering-driver opengl3
#                              --resolution WxH (this script; WxH read from
#                              project.godot, see P5)
#   Tier 2  CI xvfb            xvfb-run godot ... (Linux; optional pipeline job)
#   Tier 3  Movie Maker        --write-movie out.png (supplementary evidence,
#                              NOT the main path — AC1 auto-script contract)
#
# Testability env overrides (used by tests/pipeline/test_e2e_runner.py):
#   RUNNER_GODOT      godot binary (fake godot in CI tests)
#   E2E_WORKTREE_ROOT worktree/output root (default /tmp)
#   E2E_BRANCH        impl branch name (default: gh pr view)
#   E2E_GH_REPO       owner/repo (default: from git remote)
#   E2E_DIFF_FILES    newline-separated PR file list (default: gh pr diff)
#   E2E_PLAN_PATH     shot plan path (default: <subproject>/e2e_shots.json)
#
# Exit codes: 0 = all layers pass  1 = layer failure  2 = pre-flight failure

set -u

PR_NUM=""
SUBPROJECT=""
SKIP_VISUAL=0
BASELINE=0
NO_COMMENT=0
KEEP=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --subproject) SUBPROJECT="$2"; shift 2 ;;
    --skip-visual) SKIP_VISUAL=1; shift ;;
    --baseline) BASELINE=1; shift ;;
    --no-comment) NO_COMMENT=1; shift ;;
    --keep) KEEP=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) PR_NUM="$1"; shift ;;
  esac
done

[ -n "$PR_NUM" ] || { echo "usage: run-e2e-review.sh <PR_NUM> [options]" >&2; exit 2; }

# ── Environment / paths ────────────────────────────────────────────────────
REPO_ROOT="${E2E_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH_REPO="${E2E_GH_REPO:-$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?/?$#\1#' | sed 's/\.git$//')}"
BRANCH="${E2E_BRANCH:-$(gh pr view "$PR_NUM" --repo "$GH_REPO" --json headRefName --jq '.headRefName' 2>/dev/null || echo "impl/$PR_NUM")}"
WORKTREE_ROOT="${E2E_WORKTREE_ROOT:-/tmp}"
WT="$WORKTREE_ROOT/wt-impl-$PR_NUM"
OUT="$WORKTREE_ROOT/e2e-$PR_NUM"
GODOT="${RUNNER_GODOT:-$(command -v godot 2>/dev/null || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"

mkdir -p "$OUT/shots"
SUMMARY="$OUT/summary.json"
LOG_LINES=()

log()  { echo "[e2e] $*"; LOG_LINES+=("$*"); }
die()  { log "❌ $1"; exit "${2:-2}"; }

# ── Dry-run wrapper ────────────────────────────────────────────────────────
maybe() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

# ── Cleanup trap: worktree MUST be gone before merge --delete-branch ───────
CAFF_PID=""
WT_OWNED=0  # 2026-08-15: 1=runner 自建(可删), 0=复用的 implement worktree(不删)
cleanup() {
  [ -n "$CAFF_PID" ] && kill "$CAFF_PID" 2>/dev/null
  if [ "$KEEP" != "1" ] && [ "$WT_OWNED" = "1" ] && [ -d "$WT" ]; then
    git -C "$REPO_ROOT" worktree remove "$WT" --force 2>/dev/null && log "worktree removed: $WT"
  fi
}
trap cleanup EXIT

# ── Manifest helpers ───────────────────────────────────────────────────────
default_subproject() {
  # 2026-08-18: 读 game.active（一次一个游戏的切换开关），而非列表第一个。
  python3 - "$REPO_ROOT/game-env/manifest.yaml" <<'PY' 2>/dev/null || true
import re, sys
try:
    txt = open(sys.argv[1], encoding="utf-8").read()
    m = re.search(r"^game:\s*$", txt, re.M)
    if m:
        block = txt[m.end():]
        am = re.search(r"active:\s*(\S+)", block[:200])
        if am:
            print(am.group(1))
            raise SystemExit
    # 回退: 旧格式 source.subprojects 第一个
    m2 = re.search(r"^  subprojects:\s*$", txt, re.M)
    if m2:
        for line in txt[m2.end():].splitlines():
            s = line.strip()
            if s.startswith("- "):
                print(s[2:].strip())
                break
except Exception:
    pass
PY
}
DEFAULT_BRANCH="main"
if [ -f "$REPO_ROOT/game-env/manifest.yaml" ]; then
  DEFAULT_BRANCH="$(python3 - "$REPO_ROOT/game-env/manifest.yaml" <<'PY' || echo main
import re, sys
try:
    txt = open(sys.argv[1], encoding="utf-8").read()
    m = re.search(r"default_branch:\s*(\S+)", txt)
    print(m.group(1) if m else "main")
except Exception:
    print("main")
PY
)"
fi

# ═══════════════════════════ P0 PRE-FLIGHT ════════════════════════════════
log "P0 pre-flight (PR #$PR_NUM, branch $BRANCH, repo $GH_REPO)"

if [ ! -x "$GODOT" ] && ! command -v "$GODOT" >/dev/null 2>&1; then
  die "godot not found: $GODOT (set RUNNER_GODOT)"
fi

# System sleep = frozen process = capture guaranteed dead. Display sleep is fine.
if [ "$(uname)" = "Darwin" ] && [ "$DRY_RUN" = "0" ]; then
  if pmset -g assertions 2>/dev/null | grep -q PreventUserIdleSystemSleep; then
    log "system sleep already prevented (external holder)"
  else
    caffeinate -dimsu & CAFF_PID=$!
    log "caffeinate held (pid $CAFF_PID)"
  fi
fi

if [ -d "$WT" ]; then
  die "worktree already exists: $WT (clean up or pick another PR)" 2
fi

if ! maybe git -C "$REPO_ROOT" fetch origin "$BRANCH" 2>/dev/null; then
  if git -C "$REPO_ROOT" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    log "no origin/offline — branch exists locally, continuing"
  else
    die "branch fetch failed: $BRANCH"
  fi
fi
log "P0 ok"

# ═══════════════════════════ P1 WORKTREE ══════════════════════════════════
# 2026-08-15 设计变更: 优先复用 implement agent 留下的 worktree。
# implement 完成后保留 worktree(不再删除),E2E 在这里验证 L0-L2 —
# 避免新建 worktree 与同一分支冲突 (fatal: already checked out at ...)。
# 找不到该分支的 worktree 才新建(implement 没留的兜底)。
WT=""
# 2026-08-17 修复 (方案 X 复盘 #1): `git worktree list --porcelain` 的
# branch 行前一行是 HEAD, 不是 worktree — grep -B1 恒抓 HEAD → 复用检测
# 从未成功 → 总走新建 → 与 implement 保留的 worktree 冲突 (fatal: already
# checked out) → E2E infra-error 无限重试 (#513 实证)。必须 -B2。
WT=$(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null \
  | grep -B2 "^branch refs/heads/$BRANCH$" | grep "^worktree" | head -1 \
  | awk '{print $2}')
if [ -n "$WT" ] && [ -d "$WT" ]; then
  log "P1 reuse existing worktree: $WT (branch $BRANCH)"
  WT_OWNED=0  # 复用的 implement worktree — 不删
else
  # 2026-08-17 命名统一 (#3): implement 用 /tmp/wt-implement-<N>
  # (worktree-setup.sh: WT=/tmp/wt-$PHASE-$ISSUE) — 兜底新建也用同名,
  # 避免 wt-impl-<pr> 与 wt-implement-<N> 双名并存造成混乱。
  WT="${WORKTREE_ROOT}/wt-implement-$PR_NUM"
  log "P1 worktree add $WT"
  maybe git -C "$REPO_ROOT" worktree add "$WT" "$BRANCH" || die "worktree add failed" 2
  log "P1 worktree created: $WT"
  WT_OWNED=1  # 自建 — cleanup 时删
fi
log "P1 ok — main working tree untouched"

# ═══════════════════════════ P2-P4 LOGIC LAYERS ═══════════════════════════
[ -n "$SUBPROJECT" ] || SUBPROJECT="$(default_subproject)"
[ -n "$SUBPROJECT" ] || die "no subproject (pass --subproject)"
log "subproject: $SUBPROJECT"

run_script_layer() {
  local layer="$1" script="$2"
  if [ ! -f "$WT/$SUBPROJECT/$script" ]; then
    log "$layer: unavailable ($script missing)"
    return 2
  fi
  log "$layer: $script"
  ( cd "$WT" && maybe "$GODOT" --path "$SUBPROJECT/" --headless --script "$script" > "$OUT/$layer.log" 2>&1 )
  local code=$?
  log "$layer: exit=$code"
  return $code
}

COMPILE=2; LOGIC=2; RUNTIME=2
run_script_layer "L0-compile" "tests/check_compile.gd"; COMPILE=$?
run_script_layer "L1-logic"   "tests/run_tests.gd";    LOGIC=$?

if [ -f "$WT/$SUBPROJECT/tests/playthrough_test.tscn" ]; then
  log "L2-runtime: tests/playthrough_test.tscn"
  ( cd "$WT" && maybe "$GODOT" --path "$SUBPROJECT/" --headless "tests/playthrough_test.tscn" > "$OUT/L2-runtime.log" 2>&1 )
  RUNTIME=$?
  log "L2-runtime: exit=$RUNTIME"
else
  log "L2-runtime: unavailable (tests/playthrough_test.tscn missing)"
fi

# ═══════════════════════════ P5 VISUAL LAYER ══════════════════════════════
# 2026-08-15 决策: 视觉层默认跳过(deepseek 无多模态, 视觉断言价值低
# 且复杂度高 — 截图通道/防伪断言/orchestrator)。L0-L2(编译/逻辑/运行
# 时)是核心验证。用 --with-visual 显式开启。
VISUAL="skip"
if [ "$SKIP_VISUAL" = "1" ]; then
  log "P5 visual: skipped (--skip-visual)"
else
  log "P5 visual: resolving shot plan from diff"
  PLAN_SRC="${E2E_PLAN_PATH:-$WT/$SUBPROJECT/e2e_shots.json}"
  [ -f "$PLAN_SRC" ] || PLAN_SRC="$REPO_ROOT/framework/templates/e2e_shots.json"
  log "  plan source: $PLAN_SRC"

  if [ -n "${E2E_DIFF_FILES:-}" ]; then
    printf '%s\n' "$E2E_DIFF_FILES" > "$OUT/diff.txt"
  else
    maybe gh pr diff "$PR_NUM" --repo "$GH_REPO" --name-only > "$OUT/diff.txt" 2>/dev/null || true
  fi
  log "  diff files: $(wc -l < "$OUT/diff.txt")"

  maybe python3 "$SCRIPT_DIR/e2e/resolve_plan.py" "$PLAN_SRC" "$OUT/diff.txt" "$OUT/plan.json" \
    || { log "P5 visual: plan resolution failed"; VISUAL="fail"; }

  # Inject out_dir into the resolved plan (capture driver writes shots here)
  if [ "$VISUAL" != "fail" ] && [ "$DRY_RUN" = "0" ]; then
    python3 - "$OUT/plan.json" "$OUT/shots" <<'PY' >/dev/null 2>&1 || true
import json, sys
p = json.load(open(sys.argv[1]))
p["out_dir"] = sys.argv[2]
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
  fi

  # #661 multi-scene: count distinct main_scenes in the resolved plan.
  # 0/1 scene → byte-identical single capture of plan.json (old behavior).
  SCENE_COUNT=$(python3 - "$OUT/plan.json" <<'PY' 2>/dev/null || echo 1
import json, sys
p = json.load(open(sys.argv[1]))
print(len(p.get("scene_groups", {})))
PY
  )
  log "  scene_groups: $SCENE_COUNT"

  if [ "$VISUAL" != "fail" ] && [ "$DRY_RUN" = "0" ]; then
    # 2026-08-20 (#586 gap 3): P5 分辨率从 project.godot 读取——不再硬编码
    # 720x1280（#383 mini-pong 竖屏遗留）。shandong-wolf=1280x720,
    # mini-pong=720x1280；无 viewport 键时回退 1280x720（照 default_subproject
    # 同款 inline python）。L3 用同值 --size 校验 PNG 尺寸（AC2）。
    VIEWPORT="$(python3 - "$WT/$SUBPROJECT/project.godot" <<'PY' || echo 1280x720
import re, sys
txt = open(sys.argv[1], encoding="utf-8").read()
w = re.search(r"window/size/viewport_width=(\d+)", txt)
h = re.search(r"window/size/viewport_height=(\d+)", txt)
print(f"{w.group(1)}x{h.group(1)}" if w and h else "1280x720")
PY
)"
    log "  viewport: $VIEWPORT (from project.godot)"
    maybe cp "$CAPTURE_SRC" "$OUT/capture.gd"

    # #661 multi-scene: one godot process per distinct main_scene (sub-plan).
    run_capture() {
      local plan_path="$1"
      local log_name="$2"
      log "  running capture (real rendering, display-sleep immune)"
      ( cd "$WT" && maybe "$GODOT" --path "$SUBPROJECT/" --display-driver macos --rendering-driver opengl3 \
          --resolution "$VIEWPORT" --script "$OUT/capture.gd" -- "$plan_path" > "$OUT/$log_name" 2>&1 )
      local_capture=$?
      log "  capture exit=$local_capture"
      return $local_capture
    }

    if [ "$SCENE_COUNT" -le 1 ]; then
      run_capture "$OUT/plan.json" "P5-visual.log"
    else
      log "  multi-scene capture ($SCENE_COUNT scenes): splitting by main_scene"
      python3 - "$OUT/plan.json" "$OUT" <<'PY'
import json, sys
plan, out = json.load(open(sys.argv[1])), sys.argv[2]
groups = plan["scene_groups"]
for i, (scene, shots) in enumerate(groups.items()):
    sub = dict(plan)
    sub["main_scene"] = scene
    sub["shots"] = shots
    sub["out_dir"] = f"{out}/shots/{i}"
    json.dump(sub, open(f"{out}/sub-plan-{i}.json", "w"), indent=2)
PY
      i=0
      CAPTURE_FAILS=0
      for sub in "$OUT"/sub-plan-*.json; do
        run_capture "$sub" "P5-visual-$i.log" || { CAPTURE_FAILS=1; true; }
        i=$((i+1))
      done
      mkdir -p "$OUT/shots"
      for d in "$OUT"/shots/*/; do cp "$d"*.png "$OUT/shots/" 2>/dev/null || true; done
      local_capture=$CAPTURE_FAILS
    fi

    # 4-fold anti-fake assertions on every shot
    VISUAL_FAIL=0
    if [ -z "$(ls "$OUT/shots/"*.png 2>/dev/null)" ]; then
      log "❌ zero screenshots produced — capture failed"
      VISUAL_FAIL=1
    else
      prev=""
      for png in "$OUT/shots/"*.png; do
        args=(--min-colors 3 --name "$(basename "$png")")
        args+=(--size "$VIEWPORT")
        shot_theme_args="$(python3 - "$OUT/plan.json" "$(basename "$png" .png)" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
name = sys.argv[2]
shot = next((s for s in plan.get("shots", []) if s.get("name") == name), {})
top = plan.get("theme_color", "")
for k in shot:
    if k.startswith("theme") and k not in ("theme_color", "theme_absent"):
        print(f"WARN: shot {name} unknown theme key '{k}'", file=sys.stderr)
ta = shot.get("theme_absent")
tc = shot.get("theme_color")
if ta and tc is not None:
    print(f"ERROR: shot {name} declares both theme_color and theme_absent", file=sys.stderr)
    sys.exit(3)
out = []
if ta:
    out += ["--theme-absent", str(ta).lstrip("#")]
elif "theme_color" in shot and tc is None:
    pass  # explicit null -> skip theme assertion
elif tc:
    out += ["--theme", str(tc).lstrip("#")]
elif top:
    out += ["--theme", str(top).lstrip("#")]
print(" ".join(out))
PY
)"
        rc=$?
        if [ "$rc" -eq 3 ]; then
          log "  ❌ shot '$(basename "$png")' theme config error (mutually exclusive)"
          VISUAL_FAIL=1
          continue
        fi
        [ -n "$shot_theme_args" ] && args+=( $shot_theme_args )
        if [ -n "$prev" ]; then
          args+=(--diff-with "$prev" --min-delta 5.0 --diff-ratio 0.005)
        fi
        if python3 "$SCRIPT_DIR/e2e/analyze_bmp.py" "$png" "${args[@]}" >> "$OUT/P5-assert.log" 2>&1; then
          log "  ✅ $(basename "$png") assertions pass"
        else
          log "  ❌ $(basename "$png") failed assertions"
          VISUAL_FAIL=1
        fi
        prev="$png"
      done
    fi
    VISUAL="pass"
    [ "$VISUAL_FAIL" = "0" ] || VISUAL="fail"
  elif [ "$DRY_RUN" = "0" ]; then
    VISUAL="fail"
  fi
  log "P5 visual: $VISUAL"
fi

# ═══════════════════════════ P6 helpers ═══════════════════════════════════
# ⚠ upload_via_github 已删除（2026-08-11, #372）：
#   https://github.com/upload/policies/assets 是浏览器拖拽上传端点，
#   非 REST comment-attachment API（2026-07-31 已验证不存在），
#   字面量 Bearer *** 占位符永远无法认证 → 该通道不可修复，弃用。
#
# gist 是唯一官方 REST 通道（gh gist create --public）。raw URL 格式：
#   https://gist.githubusercontent.com/<user>/<gist_id>/raw/<file>
# 解析失败（网络/auth 缺 gist scope）→ return 1 → P6 循环回退本地路径
# 文案（_upload failed — see /tmp/...），comment 仍发布，不崩溃。
upload_via_gist() {
  local png="$1"
  local gist_url user id fname
  gist_url="$(gh gist create --public "$png" 2>/dev/null | grep -Eo 'https://gist\.github\.com/[^ ]+' | head -1)" || return 1
  [ -n "$gist_url" ] || return 1
  user="$(printf '%s' "$gist_url" | sed -E 's#https://gist\.github\.com/([^/]+)/.*#\1#')"
  id="$(printf '%s' "$gist_url" | sed -E 's#.*/([^/]+)$#\1#')"
  fname="$(basename "$png")"
  [ -n "$user" ] && [ -n "$id" ] || return 1
  echo "https://gist.githubusercontent.com/$user/$id/raw/$fname"
}
# ═══════════════════════════ P6 EVIDENCE ══════════════════════════════════
if [ "$NO_COMMENT" = "1" ] || [ "$DRY_RUN" = "1" ]; then
  log "P6 evidence: skipped (--no-comment / --dry-run)"
else
  log "P6 evidence: building comment"
  {
    echo "## 🖼 本地 E2E 验证 (PR #$PR_NUM)"
    echo ""
    echo "| 层 | 结果 |"
    echo "|----|------|"
    echo "| L0 编译 | $([ "$COMPILE" = "0" ] && echo ✅ || echo ❌/SKIP) |"
    echo "| L1 逻辑 | $([ "$LOGIC" = "0" ] && echo ✅ || echo ❌/SKIP) |"
    echo "| L2 运行时 | $([ "$RUNTIME" = "0" ] && echo ✅ || echo ❌/SKIP) |"
    echo "| L3 视觉 | $VISUAL |"
    echo ""
    echo "### 截图证据"
    echo ""
    for png in "$OUT/shots/"*.png; do
      [ -f "$png" ] || continue
      name="$(basename "$png")"
      url="$(upload_via_gist "$png")" || true
      echo "**$name**"
      echo ""
      if [ -n "$url" ]; then
        echo "![$name]($url)"
      else
        echo "_upload failed — see /tmp/e2e-$PR_NUM/shots/$name"
      fi
      echo ""
    done
  } > "$OUT/comment.md"
  maybe gh pr comment "$PR_NUM" --repo "$GH_REPO" --body-file "$OUT/comment.md" \
    && log "P6 evidence: comment posted" || log "P6 evidence: comment failed (gh error)"
fi

# ═══════════════════════════ BASELINE (optional) ══════════════════════════
BASELINE_RESULT=""
if [ "$BASELINE" = "1" ]; then
  log "baseline: L1 on default branch ($DEFAULT_BRANCH)"
  WT_MAIN="$WORKTREE_ROOT/wt-main-$PR_NUM"
  if [ -d "$WT_MAIN" ]; then
    git -C "$REPO_ROOT" worktree remove "$WT_MAIN" --force 2>/dev/null || true
  fi
  maybe git -C "$REPO_ROOT" worktree add --detach "$WT_MAIN" "$DEFAULT_BRANCH" \
    || log "baseline: worktree add failed"
  if [ -f "$WT_MAIN/$SUBPROJECT/tests/run_tests.gd" ]; then
    ( cd "$WT_MAIN" && maybe "$GODOT" --path "$SUBPROJECT/" --headless --script tests/run_tests.gd \
        > "$OUT/baseline.log" 2>&1 )
    BASELINE_RESULT=$?
    log "baseline: exit=$BASELINE_RESULT"
  else
    BASELINE_RESULT="unavailable"
  fi
  git -C "$REPO_ROOT" worktree remove "$WT_MAIN" --force 2>/dev/null || true
  log "baseline: worktree removed"
fi

# ═══════════════════════════ P7 SUMMARY ═══════════════════════════════════
OVERALL=0
# Layer exit codes: 0=pass, 1=fail, 2=unavailable (test file missing).
# Only a real failure (1) makes the run red; unavailable layers warn only.
[ "$COMPILE" = "1" ] && OVERALL=1
[ "$LOGIC" = "1" ] && OVERALL=1
[ "$RUNTIME" = "1" ] && OVERALL=1
if [ "$VISUAL" = "fail" ]; then OVERALL=1; fi

python3 - "$SUMMARY" "$PR_NUM" "$BRANCH" "$SUBPROJECT" "$COMPILE" "$LOGIC" "$RUNTIME" "$VISUAL" "$BASELINE_RESULT" <<'PY' >/dev/null 2>&1 || true
import json, sys
summary_path, pr, branch, sub, compile_, logic, runtime, visual, baseline = sys.argv[1:]
json.dump({
    "pr": pr, "branch": branch, "subproject": sub,
    "layers": {
        "L0_compile": compile_, "L1_logic": logic,
        "L2_runtime": runtime, "L3_visual": visual,
    },
    "baseline": baseline,
    "summary": summary_path,
}, open(summary_path, "w"), indent=2)
PY

log "P7 summary: $SUMMARY"
log "overall: $([ "$OVERALL" = "0" ] && echo ✅ PASS || echo ❌ FAIL)"
exit "$OVERALL"
