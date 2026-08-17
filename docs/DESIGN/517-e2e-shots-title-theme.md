# DESIGN: [Follow-up] e2e_shots.json 01_title 断言过时 — 世界隐藏后无 theme 色

> **Parent Issue:** #517
> **Agent:** game-plan-agent
> **Date:** 2026-08-17
> **Approach:** B — 反向断言（`--theme-absent`，确认 PRD §4.4 推荐方案；light 修复，无方案分歧）
> **Reference PRD:** docs/PRD/517-e2e-shots-title-theme.md（research PR #518，已合并）
> **所有权:** `content_ownership: mechanical`（测试 fixture 断言维护 = 机械可测，无品味决策）
> **深度:** light（depth/light 标签）—— 文件域 4（e2e_shots.json / analyze_bmp.py / run-e2e-review.sh / 2 个 pipeline 测试文件描述），无新文件、无迁移、无弃用 → **不产 TASKS 文档**（低于阈值）
> **并行上下文:** 改动集中在 `scripts/e2e/` + `scripts/run-e2e-review.sh` L3 段 + `mini-pong/e2e_shots.json`，与并行 implement 的 `.gd` 场景改动零交集（analyze_bmp.py 无其他并行改动预期）

---

## 1. 架构概述

### 1.1 设计核心

**analyze_bmp.py 新增第 5 个 flag-gated 断言 `--theme-absent RRGGBB`（镜像 `_theme_present()`：stride 5 / 容差 32 / 0 个采样点命中才通过，语义「世界隐藏」）；run-e2e-review.sh L3 段从 plan.json 的 shots 数组按 PNG 文件名（= shot name）查 shot 级 theme 配置——`theme_absent` 优先 → `theme_color: null` 显式跳过 → 缺省回退顶层 THEME（现状）；mini-pong/e2e_shots.json 的 `01_title` 增加 `"theme_absent": "4a90d9"`。02_midgame / 03_gameover 不动（正断言保留）。**

```bash
# L3 逐 PNG 决策（run-e2e-review.sh 改造后）
plan.json shots[] ──按 shot name 匹配 PNG 文件名──► 01_title
                                                        │  shot.theme_absent="4a90d9"
                                                        ▼
                                        python3 analyze_bmp.py 01_title.png \
                                            --min-colors 3 --name 01_title \
                                            --theme-absent 4a90d9   ← 反向断言（0 命中才过）
                                        02_midgame / 03_gameover ──► 缺省回退顶层 THEME
                                            → --theme 4a90d9（正断言，现状不变）
```

设计哲学：
1. **对称性（反向 = 正向的镜像）** — `_theme_absent()` 复用 `_theme_present()` 同一采样实现（stride 5 / 容差 32），只是把「任一命中 → True」翻转为「0 命中 → True」。行为可预期，与正向断言共享参数语义（PRD §2.3「反向断言应复用同一采样逻辑」）。
2. **shot 级优先 + 顶层回退（向后兼容）** — resolve_plan.py 的 shots 数组原样透传（已核实 `resolve()` 对每个 shot `shots.append(s)` 原样复制），shot 级字段天然可达 runner 消费端，**无需改 resolve**；其他 game 副本 / 模板无 shot 级字段时自动回退现状全局行为。
3. **互斥 fail-fast** — 同 shot 同时声明 `theme_color` 与 `theme_absent` → runner 报错退出 L3（配置矛盾必须显式暴露，禁止静默取一）（PRD §5.2-4）。
4. **伪失败变真回归检测** — 世界隐藏逻辑（#508 `_set_world_visible`）未来若回归（MENU 世界重现），01_title 反向断言变红 = 正确捕获回归（这正是 B 优于 A 的核心价值，PRD §4.4-3）。
5. **最小变更（light）** — 1 个 fixture shot + 1 个 analyzer flag + runner ~15 行 + 2 处 pipeline 单测描述，无新增文件、无生产代码改动（PRD §3.2）。

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码）

| PRD 断言 | 实际代码（main @ 0ab8f99） | 设计裁决 |
|---------|--------------------------|---------|
| `theme_color` 是顶层全局键，无 shot 级覆盖机制 | ✅ `mini-pong/e2e_shots.json:9` `"theme_color": "4a90d9"` 位于顶层；3 个 shot 对象均无 theme 字段 | 新增 shot 级键 `theme_absent`（01_title），顶层键保留 |
| `resolve_plan.py` 仅透传顶层 `theme_color`，shots 原样透传 | ✅ `resolve_plan.py:24` `_PASSTHROUGH` 含 `theme_color`；`resolve()` 对激活组 shots 逐个 `shots.append(s)` 原样复制（含全部 shot 级字段） | **不改 resolve** —— shot 级字段天然进入 plan.json 的 `shots[]`，仅改 runner 消费端 |
| runner 单值 THEME 应用于所有 PNG（`run-e2e-review.sh:253-257`） | ✅ L3 段 `THEME="$(python3 -c '...plan.json...theme_color...')"` 单值读取；`for png in "$OUT/shots/"*.png` 循环内无条件 `args+=(--theme "$THEME")` | L3 循环内按 `$(basename "$png" .png)` 查 shot 配置，替代无条件传参（§3.1） |
| `analyze_bmp.py` 4 断言均为 flag-gated；`_theme_present()` stride 5 / 容差 32 | ✅ `analyze_bmp.py` `_theme_present()`（stride 5、tol=32）；CLI 手写 opts dict 解析；`--theme` 已存在；无 `--theme-absent` | 新增 `--theme-absent` 入 opts + `_theme_absent()` 镜像 + 与 `--theme` 互斥校验（§3.1） |
| `01_title` 实测 0 个 theme 像素（修复生效） | ✅ PRD §1.1 实测数据（PR #511 分支 0 px vs main 1328 px）；StartMenu 无 #4a90d9 系色 | 反向断言基线干净，当前不会误报（PRD §4.4-2） |
| `e2e_capture.gd` 不消费 theme_color | ✅ capture 仅读 shots 驱动截帧（`_capture(shot_name)` 生成 `<shot_name>.png`） | 改动不触及 capture；PNG 文件名 = shot name 的映射成立（PRD §2.3） |

### 1.3 设计裁决（PRD 缺口闭合 — plan agent 独立裁决）

**裁决 1（互斥校验双层布防）：analyzer 与 runner 都做互斥校验，职责不同。** PRD §5.2-4 要求 runner 校验、§8-1 要求 analyzer 与 `--theme` 互斥——两者不冲突：analyzer 对「CLI 直接调用同时传两 flag」报错（防御深度，exit 2）；runner 对「同一 shot 配置同时声明两者」报错并置 VISUAL_FAIL（主校验，fail-fast，PRD §5.2-4）。配置矛盾由 runner 拦截，CLI 滥用由 analyzer 拦截。

**裁决 2（`theme_color: null` 的语义）：显式 null = 跳过 theme 断言；键缺失 = 回退顶层。** 区分「显式声明 null」（`"theme_color" in shot and shot["theme_color"] is None` → 不传任何 theme flag，跳过）与「键不存在」（→ 顶层 THEME 回退）。这是 Approach A 的退化能力（PRD §4.1），与 B 的主路径共存：B 用 `theme_absent` 表达「断言隐藏」，null 表达「不关心」。runner 解析优先级：`theme_absent` 非空 → `--theme-absent`；`theme_color` 显式 null → 无 theme flag；`theme_color` 有值 → `--theme`；均缺省 → 顶层 THEME（现状）。

**裁决 3（未知 theme 命名空间键告警范围）：仅对 `theme*` 前缀的未知键告警，不误伤既有 shot 键。** PRD §5.2-5 要求「未知 shot 级键告警不静默」——但 shot 对象含大量既有键（`name/state/settle_frames/press/require/assert_text/deadline_s`），全量未知键告警会产生噪音。定案：runner 遍历 shot 配置中 `key.startswith("theme")` 的键，凡不在 `{theme_color, theme_absent}` 集合内 → stderr warning（如拼写错误 `theme_abset` 会被捕获），不中断（warning 级，PRD 原文「告警」非报错）。

**裁决 4（runner 与 analyzer 版本同步）：不探测，直接依赖同仓文件。** PRD §5.3-1 已论证：CI 与本地共用同一 repo 源码，`--theme-absent` 不存在的情况实际不会发生；runner 传未知 flag 时 analyze_bmp.py 手写解析器会打印 `unknown arg` 并 exit 2 → L3 自然 fail 且日志明确。不额外做 `--help` 探测（避免过度设计）。

**裁决 5（fixture 改动最小化）：01_title 仅新增 `theme_absent` 键，其余字段（assert_text 等）与 02/03 shot 一律不动。** 顶层 `theme_color` 保留（02/03 的正断言依赖它，PRD §5.1-AC2）。

## 2. 新组件

无新脚本/场景/资源文件（light 深度，全部为既有文件内扩展；PRD §3.2「新增文件：无」）。

---

## 3. 既有组件修改

### 3.1 修改文件

| 文件 | 变更 | 为什么 |
|------|------|--------|
| `mini-pong/e2e_shots.json` | `01_title` shot 增加 `"theme_absent": "4a90d9"`（保留既有 name/state/settle_frames/assert_text） | AC1 世界隐藏断言（PRD §8-3） |
| `scripts/e2e/analyze_bmp.py` | 新增 `--theme-absent RRGGBB` flag + `_theme_absent()` 镜像函数 + 与 `--theme` 互斥校验 + 文件头 docstring 更新 | AC1 反向断言能力（PRD §8-1） |
| `scripts/run-e2e-review.sh` | L3 段逐 shot 解析 theme 配置（`theme_absent` 优先 / `theme_color: null` 跳过 / 顶层回退 + 互斥与未知键校验） | shot 级配置消费端（PRD §8-2） |
| `tests/pipeline/test_e2e_analyze.py` | 新增反向断言正/反用例（§9 Scenario A） | AC4 单测（PRD §8-4） |
| `tests/pipeline/test_e2e_runner.py` | fake godot 像素生成按 shot 配置 + 新增 shot 级 theme 解析用例（§9 Scenario B） | AC4 单测（PRD §8-4） |

**analyze_bmp.py 变更后形态（伪代码，implement agent 据此落地）：**

```python
def _theme_absent(path: str, hex_color: str, tol: int = 32) -> bool:
    """True = theme color ABSENT everywhere (0 sampled hits).

    Mirror of _theme_present(): same stride-5 sampling, same tolerance.
    Encodes the "world hidden" semantics — the color must NOT appear.
    """
    return not _theme_present(path, hex_color, tol)
```

CLI 部分（opts dict 增加 `"--theme-absent": None`；断言段新增）：

```python
# 3. theme color (present / absent — mutually exclusive)
theme_arg = _s("--theme")
theme_absent_arg = _s("--theme-absent")
if theme_arg and theme_absent_arg:
    print("❌ --theme and --theme-absent are mutually exclusive")
    return 2
if theme_absent_arg:
    hexc = theme_absent_arg.lstrip("#")
    if _theme_absent(path, hexc):
        passes.append(f"theme #{hexc} absent (world hidden)")
    else:
        fails.append(f"theme #{hexc} FOUND — expected hidden (world visible?)")
elif theme_arg:
    theme = theme_arg.lstrip("#")
    if _theme_present(path, theme):
        passes.append(f"theme #{theme} present")
    else:
        fails.append(f"theme #{theme} NOT found")
```

**run-e2e-review.sh L3 段变更（伪代码，implement agent 据此落地）：**

```bash
# 现状（253-257 行附近）: THEME 单值 + 无条件 --theme
# 改为: 循环内按 shot name 解析 shot 级配置
for png in "$OUT/shots/"*.png; do
    name="$(basename "$png" .png)"
    args=(--min-colors 3 --name "$(basename "$png")")
    # 逐 shot 解析 theme 参数（python helper, 读 plan.json）
    shot_theme_args="$(python3 - "$OUT/plan.json" "$name" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
name = sys.argv[2]
shot = next((s for s in plan.get("shots", []) if s.get("name") == name), {})
top = plan.get("theme_color", "")
# 未知 theme* 键告警（裁决 3）
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
    pass  # 显式 null → 跳过 theme 断言（裁决 2）
elif tc:
    out += ["--theme", str(tc).lstrip("#")]
elif top:
    out += ["--theme", str(top).lstrip("#")]
print(" ".join(out))
PY
)"
    rc=$?
    if [ "$rc" -eq 3 ]; then
        log "  ❌ shot '$name' theme config error (mutually exclusive)"
        VISUAL_FAIL=1
        continue
    fi
    [ -n "$shot_theme_args" ] && args+=($shot_theme_args)
    # ...既有 diff-with / analyze 调用不变...
done
```

### 3.2 受影响测试文件（只列描述，不写代码）

| 测试文件 | 影响 | 处理 |
|---------|------|------|
| `tests/pipeline/test_e2e_analyze.py` | 既有 4 断言用例**不受影响**（`--theme-absent` 是新增 flag，缺省时行为不变）；新增反向断言正/反用例（§9 Scenario A） | 扩展（不删不改既有用例） |
| `tests/pipeline/test_e2e_runner.py` | fake godot 像素生成逻辑需按 shot 配置区分（theme_absent shot 不画 theme 色块，否则反向断言在集成场景必红）；新增 shot 级解析用例（§9 Scenario B） | 扩展（fake godot 部分小改 + 新用例） |
| `tests/pipeline/test_e2e_resolve.py` | resolve 零改动 → 仅确认无回归 | 无改动（全量跑一遍验证） |

### 3.3 移除/弃用文件

无。

---

## 4. 数据流

### Flow 1: 正常路径 — 01_title 反向断言（AC1）

```
run-e2e-review.sh L3（--with-visual）
  → 读取 $OUT/plan.json（resolve_plan.py 已把 e2e_shots.json 的 shots 原样透传）
  → for png in $OUT/shots/*.png:  png = 01_title.png
      → shot = plan.shots[01_title] → theme_absent = "4a90d9"
      → args += (--theme-absent 4a90d9)
      → analyze_bmp.py 01_title.png --min-colors 3 --name 01_title --theme-absent 4a90d9
          ├── 非黑断言: black_ratio ≤ 50%（StartMenu UI 亮色背景）→ pass
          ├── 色数断言: color_buckets ≥ 3 → pass
          ├── 反向 theme 断言: _theme_absent() = not _theme_present() → 0 命中 → pass
          │     （#508 修复生效: MENU 隐藏 game_world → 无 #4a90d9 像素）
          └── 帧差断言: 与 prev（无, 首帧）→ 跳过
      → ✅ L3 视觉层 pass
```

### Flow 2: 正常路径 — 02_midgame / 03_gameover 正断言（AC2）

```
02_midgame.png → shot 无 theme_absent / theme_color 字段 → 回退顶层 THEME="4a90d9"
  → args += (--theme 4a90d9)
  → analyze_bmp.py: _theme_present() stride5/容差32 → PLAYING 世界可见 → BgPulse/玩家板 #4a90d9 命中 → pass
03_gameover.png → 同上（世界保持可见, #508 仅 MENU 隐藏）→ pass
```

### Flow 3: 回退路径 — shot 无任何 theme 配置（其他 game 副本 / 模板）

```
shot 无 theme_absent 且无 theme_color 键 → 顶层 THEME 回退 → 传 --theme（现状行为）
→ 向后兼容: 未迁移的 e2e_shots.json 行为零变化（PRD §3.3）
```

### Flow 4: 错误路径 — 配置矛盾 fail-fast

```
01_title 同时声明 theme_color 与 theme_absent
  → runner python helper exit 3 → log ❌ + VISUAL_FAIL=1 → L3 fail（不静默取一）
  → impl agent 修复 fixture 后重跑
```

---

## 5. 边界情况与错误处理

| Edge Case | 缓解 |
|-----------|------|
| title 屏未来引入 #4a90d9 系 UI 元素（如按钮高亮复用 PLAYER_NEON_BLUE） | 反向断言误报。当前 0 像素为基线（PRD 实测）；UI 改色时同步更新/移除 01_title 的 theme_absent——在 §10 记录该耦合（PRD §5.2-1） |
| stride 5 采样漏检/误检孤点 | 反向与正向共用同一采样实现（对称性），行为可预期；阈值固定「0 命中」（PRD §5.2-2） |
| shot 无 theme_absent / theme_color 字段 | 回退现有全局行为（顶层 THEME 正断言），向后兼容（PRD §5.2-3） |
| 同 shot 同时声明 theme_color 与 theme_absent | runner 互斥校验 exit 3 → fail-fast 报错，防配置矛盾（裁决 1 + PRD §5.2-4） |
| shot 级字段拼写错误（如 theme_abset） | runner 对 `theme*` 前缀未知键 stderr warning（裁决 3，PRD §5.2-5） |
| PAUSED 或未来新增 MENU 系 shot | 机制天然可复用：shot 级配置随 shot 走，resolve 去重后仍保留（PRD §5.2-6） |
| 模板 `framework/templates/e2e_shots.json` 同步 | 不强制（本 issue 只要求 mini-pong 副本）；模板使用者遇同问题按本 PRD 模式处理（PRD §5.2-7） |
| analyze_bmp.py 无 `--theme-absent` 参数（版本不同步） | 同仓源码实际不发生；若发生 → analyzer 打印 `unknown arg` exit 2 → L3 fail 且日志明确（裁决 4，PRD §5.3-1） |
| 容差/采样过松导致世界未隐藏仍通过 | 单测覆盖正/反用例：含 theme patch 的图正断言过 / 反向断言 fail；纯背景图反向断言过（§9 Test A1/A2，PRD §5.3-2） |
| runner 读不到 plan.json shots（plan 结构变化） | helper 对缺失 shots 返回空 → 顶层 THEME 回退（不崩溃），日志 warning 提示 shot 级配置未应用（PRD §5.3-3） |
| 世界隐藏回归（MENU 世界重现） | 01_title 反向断言变红 = 正确捕获回归（B 优于 A 的价值点），impl 阶段按真 bug 处理而非豁免（PRD §5.3-4） |

---

## 6. 按场景/组件配置

`mini-pong/e2e_shots.json` shot 级 theme 配置：

| Shot | theme_absent | theme_color（shot 级） | 效果 | 说明 |
|:----:|:---:|:---:|-----|------|
| `01_title` | `"4a90d9"`（新增） | 无 | `--theme-absent 4a90d9`（反向断言：世界隐藏） | MENU 状态世界隐藏（#508），断言 0 命中 |
| `02_midgame` | 无 | 无 | 回退顶层 → `--theme 4a90d9`（正断言） | PLAYING 世界可见，现状不变 |
| `03_gameover` | 无 | 无 | 回退顶层 → `--theme 4a90d9`（正断言） | GAME_OVER 世界可见，现状不变 |

> 顶层 `theme_color: "4a90d9"` 保留（02/03 回退依赖）；`01_title` 的 assert_text（VersionLabel v1.0.0）与 settle_frames 等既有字段不动。

---

## 7. 集成点

> **状态约定：** ⬜ = pending（implement agent 接线并更新）；✅ = 既有（无需新接线）；deferred = 明确延后。

| Integration | 我们的组件 | 目标 | 方式 | 状态 |
|-------------|:---:|:---:|-----|:---:|
| e2e_shots.json ↔ runner L3 | `01_title.theme_absent` | #517 | shot 级配置读取（按 PNG 文件名匹配 shot name） | ⬜ pending（implement 接线） |
| runner L3 ↔ analyze_bmp.py | `--theme-absent` flag | #517 | L3 循环逐 shot 传参（§3.1 helper） | ⬜ pending |
| resolve_plan.py ↔ runner | shots 数组透传 | #517 | 既有透传（resolve 零改动，裁决 §1.2） | ✅ 既有 |
| analyze_bmp.py ↔ `_theme_present` | `_theme_absent()` 镜像 | #517 | `not _theme_present(...)` 复用采样 | ⬜ pending（implement 实现） |
| 模板 `framework/templates/e2e_shots.json` | 无（不同步） | #517 | 模板保持同构，不强制同步（PRD §3.3） | ⬜ deferred |
| docs/PLAN-e2e-verification-v2.md | L3 断言清单补充反向断言 | #517 | 文档级补充（可选，非阻塞） | ⬜ deferred |

---

## 8. 实现阶段

light 特性，单阶段交付：

| Phase | 优先级 | 内容 | 依赖 |
|:-----:|:------:|------|------|
| Phase 1 | P0 | analyze_bmp.py `--theme-absent` → run-e2e-review.sh L3 逐 shot 解析 → e2e_shots.json 01_title 配置 → pipeline 单测落地 → `run-e2e-review.sh --with-visual` L3 全绿 | 无（#508/#511、#358、#466/#476 均已合入 main） |

---

## 9. 测试用例描述（实现阶段据此编写，不在此写可运行测试）

> 约定：pipeline 单测沿用现有模式——`test_e2e_analyze.py` 用 `make_png()` 合成 PNG + `run_cli()` 子进程调用 analyzer；`test_e2e_runner.py` 用 FAKE_GODOT 环境变量 + fake godot 脚本（像素生成按 plan.json 配置）。L3 全绿验证用 `scripts/run-e2e-review.sh <PR_NUM> --subproject mini-pong --with-visual`。

### Scenario A: analyze_bmp.py 反向断言语义（AC1/AC4）

- **Test A1（含 theme 色 → 反向断言 fail）**：合成 64x64 PNG，左上 8x8 区域填 #4a90d9（其余渐变），`run_cli(png, "--theme-absent", "4a90d9")`。预期：exit 1，输出含 `theme #4a90d9 FOUND — expected hidden`。
- **Test A2（纯背景无 theme 色 → 反向断言 pass）**：合成无 #4a90d9 的渐变 PNG（如 PRD 实测 title 画面形态），`--theme-absent 4a90d9`。预期：exit 0，输出含 `theme #4a90d9 absent (world hidden)`。
- **Test A3（互斥校验）**：`run_cli(png, "--theme", "4a90d9", "--theme-absent", "4a90d9")`。预期：exit 2，输出 `mutually exclusive`（裁决 1 analyzer 层）。
- **Test A4（对称性）**：同一含 theme 的 PNG：`--theme 4a90d9` exit 0 且 `--theme-absent 4a90d9` exit 1（同一采样、互为镜像）。
- **Test A5（容差边界）**：合成色距 >32 的近似色（如 #4a92d9 之外）→ `--theme-absent` exit 0；色距 ≤32 的近似色 → exit 1（容差 32 语义与正向一致）。
- **Test A6（缺省行为不变）**：不带任何 theme flag 时既有 4 断言行为与改造前一致（无回归）。

### Scenario B: runner 逐 shot theme 配置解析（AC3/AC4）

- **Test B1（theme_absent 透传）**：plan.json 的 01_title 带 `theme_absent: "4a90d9"`，fake godot 生成 3 张 PNG（01_title 无 theme 色块、02/03 有），跑 runner L3。预期：analyzer 调用日志中 01_title 带 `--theme-absent 4a90d9` 且无 `--theme`；L3 pass。
- **Test B2（theme_color: null 跳过）**：01_title 带 `theme_color: null`。预期：analyzer 调用无任何 theme flag（裁决 2），L3 其余断言照跑。
- **Test B3（缺省回退顶层）**：shot 无 theme 字段。预期：仍传 `--theme <顶层值>`（现状行为，向后兼容）。
- **Test B4（互斥 fail-fast）**：01_title 同时声明 theme_color 与 theme_absent。预期：runner 报错、VISUAL_FAIL=1、L3 fail（裁决 1 runner 层）。
- **Test B5（未知 theme 键告警）**：01_title 带 `theme_abset: "4a90d9"`（拼写错误）。预期：stderr 出现 `unknown theme key` warning，L3 不因此 fail（裁决 3）。
- **Test B6（fake godot 像素按 shot 配置）**：fake godot 像素生成逻辑按 shot 的 theme_absent 决定是否画 theme 色块——theme_absent shot 不画 #4a90d9，否则集成场景反向断言必红（§3.2）。预期：生成像素与配置一致（可在 runner 测试内断言输出 PNG 或 analyzer 结果）。

### Scenario C: e2e_shots.json fixture 配置正确性（AC1/AC2）

- **Test C1（fixture 结构）**：解析 `mini-pong/e2e_shots.json`：01_title 含 `theme_absent: "4a90d9"` 且无 shot 级 theme_color；02_midgame / 03_gameover 无 theme_absent；顶层 `theme_color` 保留。
- **Test C2（JSON 合法）**：`python3 -m json.tool mini-pong/e2e_shots.json` 无错误（fixture 可被 resolve_plan.py 正常消费）。

### Scenario D: 既有测试不回归（AC4）

- **Test D1**：`tests/pipeline/test_e2e_analyze.py` 既有 4 断言用例全绿（新增 flag 缺省不影响）。
- **Test D2**：`tests/pipeline/test_e2e_resolve.py` 全绿（resolve 零改动，透传无变化）。
- **Test D3**：全量 pipeline 单测套件（`python3 -m unittest discover -s tests/pipeline -v`）全绿。
- **Test D4**：`scripts/run-e2e-review.sh <PR_NUM> --subproject mini-pong --with-visual` L3 全绿（01_title 反向断言 + 02/03 正断言全过，AC3）。

---

## 10. 延续上下文（implement agent 交接）

**系统状态**：main @ 0ab8f99（PRD #517 已合入，research PR #518）。#508（PR #511）已 merge：`game_state_machine.gd` 含 `_set_world_visible()`，MENU 隐藏 game_world 组 → `01_title` 截帧 0 个 #4a90d9 像素；`mini-pong/e2e_shots.json` 顶层 `theme_color: "4a90d9"` 仍对全部 3 个 shot 生效 → L3 在 01_title 伪失败。`analyze_bmp.py` 4 断言 flag-gated（`_theme_present` stride 5 / 容差 32）；`run-e2e-review.sh` L3 段单值 THEME 无条件传 `--theme`；`resolve_plan.py` shots 原样透传（零改动）。

**实现要点**：
1. `scripts/e2e/analyze_bmp.py`：opts dict 增加 `"--theme-absent": None`；新增 `_theme_absent()`（`not _theme_present(path, hex, 32)`）；断言段按 §3.1 伪代码改造（互斥 exit 2 + absent 分支）；文件头 docstring 的 Usage 与断言清单更新为 5 项
2. `scripts/run-e2e-review.sh`：L3 循环内按 §3.1 helper 逐 shot 解析 theme 参数（优先级 theme_absent → theme_color:null 跳过 → theme_color 有值 → 顶层回退；互斥 exit 3 → VISUAL_FAIL；`theme*` 未知键 stderr warning）；**其余断言（非黑/色数/帧差）与 diff-with 链不动**
3. `mini-pong/e2e_shots.json`：01_title 增加 `"theme_absent": "4a90d9"`；02/03 与顶层键不动
4. 测试：§9 Scenario A 落地 test_e2e_analyze.py（A1–A6）、Scenario B 落地 test_e2e_runner.py（B1–B6，含 fake godot 像素按 shot 配置生成）；Scenario C/D 全量验证
5. 验证命令：`scripts/run-e2e-review.sh <PR_NUM> --subproject mini-pong --with-visual`（--with-visual 显式开启 L3）；pipeline 单测全绿

**风险**：title 屏未来引入 #4a90d9 系 UI 色 → 反向断言误报（改 UI 色时同步维护 01_title 的 theme_absent，见 §5 首行）；runner 与 analyzer 版本不同步（同仓文件，低风险，§5）。

**边界红线（PRD §8）**：不修改生产代码（ball/paddle/fsm 均不动）；不修改 02/03 shot 断言；不全局移除 theme_color；不新增脚本/文件；白名单提交仅限上述 5 个文件（worktree-commit.sh 强制）。**验收条件映射**：AC1 = §9 Test A1–A5 + B1 + C1 + D4（L3 全绿）；AC2 = B3 + C1 + D4（02/03 正断言保留）；AC3 = D4（--with-visual 显式重跑）；AC4 = D1–D3（pipeline 单测不回归）。

**参考文件**：`mini-pong/e2e_shots.json`（顶层 theme_color:9 / shots:44-52）、`scripts/run-e2e-review.sh`（L3 段 253-257 单值 THEME）、`scripts/e2e/analyze_bmp.py`（_theme_present:214-222 / CLI opts:240-260 / 断言段 3）、`scripts/e2e/resolve_plan.py`（_PASSTHROUGH:24 / resolve:55-72）、`tests/pipeline/test_e2e_analyze.py`（make_png:29-50 / run_cli:52-60）、`tests/pipeline/test_e2e_runner.py`（fake godot 像素:59-62 / GAME_PLAN:84-101）、`docs/DESIGN/508-title-screen-world-bleed.md`（上游世界隐藏设计）
