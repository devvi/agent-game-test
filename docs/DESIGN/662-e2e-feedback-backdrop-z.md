# Design: [Rendering] e2e_feedback_capture Backdrop 盖住火花 — 背景 z_index 显式化（-2 < 火花 -1 < 角色 0）

> **Parent Issue:** #662（bug / priority/medium / infrastructure / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **方案 A 确认采纳** —— 在 `e2e_feedback_capture.tscn` 的 Backdrop 与 `Main.tscn` 的 WorldBackdrop 上各加一行 `z_index = -2`（背景在火花下、角色 z=0 仍在火花之上——「粒子不盖角色」红线保持）；否决方案 B（改火花层级 = 破坏 C4 单测 + 粒子盖角色红线）与方案 C（截图脚本运行时 hack = 只修 E2E 表象，真实游戏根因不修，违反 E2E 驱动契约）
> **Reference PRD:** `docs/PRD/662-e2e-feedback-backdrop-z.md`（research PR #671 已合并 2026-08-20）
> **上游方案:** `docs/DESIGN/579-combat-feedback-system.md` §2.2（FeedbackSpark z_index 读 `FEEDBACK_SPARK_Z_INDEX=-1`，粒子不盖角色红线）；`scenes/battle_stage.tscn:49,54`（PlatformSilhouetteMid/Back 已有 z=-1/-2 负层级先例）
> **所有权:** `content_ownership: mechanical`（z_index 属性修改 = 纯机械工程：层级数值、绘制顺序、C4 断言全部机械可验；零 taste 环节——背景色/火花色/角色外观均不动）
> **深度:** standard（无 depth label；PRD 头标注 depth: standard）—— 涉及文件 **2**（均为 .tscn 单属性修改，< 10 文件、无迁移、无跨子系统子任务）→ **仅产出 DESIGN，不产 TASKS**（照 #624 先例）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-662，branch `plan/662-e2e-feedback-backdrop-z`）；改动仅落在 2 个 .tscn 场景文件（e2e rig + 组装主场景），与并行 implement 的组件脚本（gdscripts/）零交集；constants.gd / tests/ 零改动（火花 -1 硬约束不动）

---

## 1. 架构总览

**问题本质是「一个层级遗漏导致的可见性缺陷」：** #579 实现打击反馈时把火花钉死在 `z_index=-1`（`constants.gd:582 FEEDBACK_SPARK_Z_INDEX` + 单测 C4 断言——「粒子不盖角色」红线），但 #654/#666 后续添加的全屏背景 ColorRect（`e2e_feedback_capture.tscn` Backdrop、`Main.tscn` WorldBackdrop）未设 z_index（Godot 默认 0）——同一 CanvasLayer（layer 0）内 Godot 按 z_index 升序绘制，不透明背景（z=0, alpha=1）完整覆盖下层火花（z=-1）。**后果双重的**：官方 E2E 截图永远截不到火花（AC6 素材无法产出），且 #585 组装后真实战斗画面玩家同样看不到打击火花（AC2 四要素缺一）。

**设计哲学：只动背景层级，不动火花/角色层级；修复与项目既有负 z 用法同风格。**

1. **火花 -1 是硬约束，不可触碰**——constants.gd + feedback_spark.gd + C4 单测三方锁定，改火花 = 破坏已验收 AC；
2. **背景层级显式化**——背景 ColorRect 声明 `z_index=-2`（严格低于火花 -1），与 battle_stage.tscn 既有 `PlatformSilhouetteBack z=-2` 先例风格统一；
3. **最小 diff**——两个场景各一行属性修改，零运行时逻辑、零新文件、零测试文件改动；
4. **真实游戏与 E2E 同时修复**——Main.tscn 是玩家实际战斗场景，修 WorldBackdrop 即修用户可见缺陷，非仅截图问题。

```
                    ★ Issue #662 本设计（shandong-wolf 背景层级修复）
┌────────────────────────────────────────────────────────────────────────────┐
│ 修复前（同一 CanvasLayer 0，z_index 升序绘制）                                 │
│   Backdrop/WorldBackdrop  z=0 (默认)  ColorRect, alpha=1  ← 后画，完全盖住 ↓ │
│   FeedbackSpark           z=-1        GPUParticles2D       ← 先画，被盖住 ✗ │
│   角色 stick figure       z=0 (默认)                                          │
├────────────────────────────────────────────────────────────────────────────┤
│ 修复后（方案 A：背景 z_index 0 → -2）                                        │
│   Backdrop/WorldBackdrop  z=-2        ← 先画（背景垫底）                      │
│   FeedbackSpark           z=-1        ← 中画（火花可见 ✅）                    │
│   角色 stick figure       z=0 (默认)  ← 后画（角色盖火花 ✅，红线保持）        │
├────────────────────────────────────────────────────────────────────────────┤
│ 修改（2 文件，各一行属性，全部 .tscn 声明式）                                   │
│  scenes/e2e_feedback_capture.tscn     Backdrop 节点加 z_index = -2           │
│  scenes/Main.tscn                     WorldBackdrop 节点加 z_index = -2      │
└────────────────────────────────────────────────────────────────────────────┘
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的处理 |
|------|:---:|:---:|------|
| FeedbackSpark（`gdscripts/feedback_spark.gd`，z=-1 硬约束） | #579 | ✅ merged | **零改动**——C4 断言保持（test_reaction_controller.gd:507） |
| `FEEDBACK_SPARK_Z_INDEX: int = -1`（constants.gd:582） | #579 | ✅ merged | **零改动** |
| e2e_feedback_capture.tscn Backdrop（ColorRect，z=0 默认） | #654 | ✅ merged（引入 bug） | 加 `z_index = -2`（本 issue 主场景） |
| Main.tscn WorldBackdrop（ColorRect，z=0 默认） | #666 | ✅ merged（引入 bug） | 加 `z_index = -2`（真实游戏修复） |
| battle_stage.tscn PlatformSilhouetteMid/Back（z=-1/-2） | #583 | ✅ merged | 负层级先例，风格参照，零改动 |
| e2e_main_assembly_capture.tscn（instance Main.tscn） | #585 | ✅ merged | 间接受益（WorldBackdrop 修复自动生效） |
| e2e_hud_capture / e2e_stick_figure_capture（Backdrop z=0） | #576/#574 | ✅ merged | **明确不改**（无负 z 内容，避免无谓 churn） |

### 1.2 核心缺口与修复决策（codebase 勘探确认，无 plan 新增缺口）

| PRD 断言 | 实际代码 | 结论 |
|---------|---------|------|
| 火花 z_index=-1 | constants.gd:582 + feedback_spark.gd:21 + C4 断言 | ✅ 属实，硬约束 |
| Backdrop 未设 z_index（默认 0） | e2e_feedback_capture.tscn Backdrop 仅 color/size | ✅ 属实 |
| WorldBackdrop 未设 z_index（默认 0） | Main.tscn WorldBackdrop 仅 anchors/mouse_filter/color | ✅ 属实（PRD §1.2 扩展面，issue 标题未显式列出） |
| 背景 z=0 盖住火花 z=-1 | 同 CanvasLayer 0 内 z_index 升序绘制，alpha=1 不透明覆盖 | ✅ 机制确认（issue body 579 rig 截图实测） |
| battle_stage 已有负 z 先例 | battle_stage.tscn:49,54 z=-1/-2 | ✅ 属实，方案 A 风格统一 |

**结论：PRD 与代码完全一致，无 stale claims、无已修复部分、无 plan 需要补的缺口。**

---

## 2. 修复设计 — 详细设计

> 本 issue 无新组件、无新文件、无脚本改动——修复 = 两个既有场景节点的单属性修改。

### 2.1 `scenes/e2e_feedback_capture.tscn` — Backdrop 加 z_index=-2（AC1）

**文件:** `shandong-wolf/scenes/e2e_feedback_capture.tscn`（#654 rig 场景）

**节点现状（~L10-12）：**

```
[node name="Backdrop" type="ColorRect" parent="."]
color = Color(0.847, 0.863, 0.894, 1)
size = Vector2(1280, 720)
```

**修改：** 节点属性块加一行 `z_index = -2`（Godot CanvasItem 属性，Control 继承自 CanvasItem，.tscn 声明式写法与 battle_stage.tscn:54 一致）：

```
[node name="Backdrop" type="ColorRect" parent="."]
z_index = -2
color = Color(0.847, 0.863, 0.894, 1)
size = Vector2(1280, 720)
```

**约束：** 仅加 z_index 属性；color/size/anchors 全部不动（背景渲染内容不变）。

### 2.2 `scenes/Main.tscn` — WorldBackdrop 加 z_index=-2（AC2）

**文件:** `shandong-wolf/scenes/Main.tscn`（#666 组装主场景，玩家真实战斗画面）

**节点现状（~L9-16）：**

```
[node name="WorldBackdrop" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
color = Color(0.847, 0.863, 0.894, 1)
```

**修改：** 节点属性块加一行 `z_index = -2`：

```
[node name="WorldBackdrop" type="ColorRect" parent="."]
z_index = -2
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
color = Color(0.847, 0.863, 0.894, 1)
```

**约束：** 仅加 z_index 属性；anchors/grow/mouse_filter/color 全部不动。

> ⚠️ **注意 z 值必须严格 -2，不能 -1：** 若设 -1 与火花同层，同层按树序绘制——Backdrop 在场景树中先于 ReactionController 声明的火花（代码创建），仍会盖住火花（PRD §5.3-3 失败路径）。

---

## 3. 既有组件修改

### 3.1 修改文件清单

| 文件 | 修改 | 动机 |
|------|------|------|
| `shandong-wolf/scenes/e2e_feedback_capture.tscn` | Backdrop 节点加 `z_index = -2` | AC1：E2E 官方截图能截到火花（#579 AC6 素材恢复） |
| `shandong-wolf/scenes/Main.tscn` | WorldBackdrop 节点加 `z_index = -2` | AC2：真实战斗画面打击火花可见（玩家可见缺陷修复） |

### 3.2 影响分析

| 文件/系统 | 影响 | 风险 |
|-----------|------|:----:|
| `gdscripts/feedback_spark.gd` / `constants.gd` | 零改动（火花 z=-1 保持） | 无 |
| `tests/test_reaction_controller.gd` | C4 断言不变，仍通过 | 无 |
| `scenes/e2e_main_assembly_capture.tscn`（instance Main.tscn） | 间接受益（WorldBackdrop 修复自动生效，assembly 组 02_parry_execute 截图恢复火花） | 无 |
| `scenes/e2e_hud_capture.tscn` / `e2e_stick_figure_capture.tscn` | 无负 z 内容，**不改**（避免无谓 churn） | 无 |
| `scenes/atmosphere/`（CanvasLayer 2-10）/ HUD（CanvasLayer 1） | 独立 CanvasLayer，不受 layer 0 z_index 影响 | 无 |
| `e2e_shots.json` | 无需改（feedback 组 shot 定义不变，场景修复后截图自动含火花） | 无 |

---

## 4. 数据流

### Flow 1: 正常路径（E2E 截图 与 真实战斗，修复后绘制顺序）

```
ReactionController.trigger_feedback(event, data)   (#579 单一入口)
        │
        ▼
FeedbackSpark.burst_at(...)  →  z_index = FEEDBACK_SPARK_Z_INDEX (-1)
        │
        ▼
CanvasLayer 0 同一画布绘制（z_index 升序，同层按树序）：
   ① Backdrop/WorldBackdrop  z=-2  ← 背景先画（本次修复 0 → -2）
   ② FeedbackSpark           z=-1  ← 火花可见 ✅
   ③ 角色 stick figure       z=0   ← 角色盖火花（粒子不盖角色红线保持 ✅）
        │
        ▼
e2e 截图 / 玩家画面：火花可见（苍白金 #ffd9a0 系像素存在）
```

### Flow 2: 失败路径（z 设错值）

```
若 z_index 误设 -1（与火花同层）：
   同层按树序 → Backdrop 先于火花声明 → 背景仍盖住火花 ✗
   → 必须严格 -2（PRD §5.3-3）
若漏改 Main.tscn（只改 rig）：
   E2E 截图有火花，但真实战斗火花仍不可见 → AC2 失败（PRD §5.3-1）
若误改火花层级（方案 B 方向）：
   C4 单测失败 + 粒子盖角色 → 红线破坏，revert（PRD §5.3-2）
```

---

## 5. 边界情况与错误处理

| 边界情况 | 缓解 |
|---------|------|
| e2e_hud / e2e_stick_figure rig 的 Backdrop 也是 z=0 默认 | 明确不改——它们无负 z 内容（Hud 在 CanvasLayer layer=1，EnemyStub 无负 z；stick figure rig 的 ReviveFX/Atmosphere 均 z=0）。未来若加入负 z 效果需同样处理（约定写入 §6 维护条款） |
| Atmosphere（CanvasLayer 2-10）/ HUD（CanvasLayer 1） | 独立 CanvasLayer，不受 layer 0 z_index 影响——修复零触碰 |
| battle_stage.tscn 已有 z=-1/-2 的 PlatformSilhouette | 与背景修复同层共存无冲突（silhouette 是局部 Polygon2D 不遮挡全局；背景 -2 与 silhouette -2 同值按树序绘制，视觉无差异） |
| 背景与火花同层（z 误设 -1） | z_index 必须严格 -2；实现后 grep 断言校验数值（§7 TC1/TC2） |
| 未来新增 E2E rig / 全屏背景节点 | 维护约定：全屏背景默认 `z_index=-2`（低于火花 -1）；层级约定「背景 < 火花 < 角色」记录于 DESIGN 579 §2.6（可选文档补充，非本 issue 强制） |
| 火花层级未来调整 | 需同步重审所有背景节点（背景 < 火花 < 角色三层约定）——C4 单测 + 本文档 §6 守卫 |

---

## 6. 集成点

> **Status 约定:** ⬜ = 待 implement agent 接线；✅ = implement 完成并验证。实现后须更新此表。

| 集成 | 本组件 | 目标 | How | Status |
|------|:---:|:---:|-----|:---:|
| E2E 截图链路 | e2e_feedback_capture.tscn Backdrop z=-2 | e2e_shots.json feedback 组（fb_parry_success / fb_stance_break / fb_execute） | 场景文件属性修改，截图管线零改动自动生效 | ⬜ pending |
| 真实战斗画面 | Main.tscn WorldBackdrop z=-2 | 玩家视角（#585 组装主场景） | 场景文件属性修改 | ⬜ pending |
| assembly 组截图 | Main.tscn WorldBackdrop z=-2 | e2e_shots.json assembly 组 02_parry_execute | instance Main.tscn 自动继承 | ⬜ pending |
| 火花层级守卫 | 无（反馈系统零改动） | tests/test_reaction_controller.gd C4 | 保持原断言（z_index == -1），回归验证 | ✅ 已有 |

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 工作量 |
|:----:|:------:|------|:------:|
| Phase 1（唯一） | P0 | 两个 .tscn 各加一行 `z_index = -2`（§2.1 + §2.2） | 0.1 人日 |

> 无依赖顺序问题——两处修改相互独立，可单次提交。实现 PR 的 E2E gate 见 §9 验证清单。

---

## 8. 测试用例描述

> **说明:** 本阶段只写测试**描述**，不写可运行测试文件（plan 阶段红线）。本 issue 是纯 .tscn 属性修复，无新单测可写；测试以**文本断言**（grep .tscn）+ **回归**（既有 C4）+ **渲染级**（E2E 截图火花像素）三层覆盖。用例编号 T1 起，便于 implement agent 对号入座。

### Scenario T: 文本断言（.tscn 属性级，implement PR 的 gate）

- **T1 Backdrop z_index 断言**: 读取 `scenes/e2e_feedback_capture.tscn`，定位 `name="Backdrop"` 节点属性块，断言含 `z_index = -2` 且数值严格为 -2（非 -1/0/缺失）。前置：§2.1 修复完成。预期：通过。
- **T2 WorldBackdrop z_index 断言**: 读取 `scenes/Main.tscn`，定位 `name="WorldBackdrop"` 节点属性块，断言含 `z_index = -2`。前置：§2.2 修复完成。预期：通过。
- **T3 无 .gd 改动守卫**: `git diff`（实现分支 vs main）不含任何 `gdscripts/` / `tests/` 文件。前置：修复完成。预期：diff 仅含 2 个 .tscn。**红线守卫**（PRD §8：不改 constants/feedback_spark/测试）。

### Scenario R: 回归（既有测试保持）

- **R1 C4 单测保持**: 运行项目测试套件（`godot --headless` 标准入口 `tests/run_tests.gd`），`test_reaction_controller.gd` 的 C4（`spark.z_index == FEEDBACK_SPARK_Z_INDEX` == -1）仍通过。前置：修复完成（未触碰任何测试文件）。预期：全绿，C4 pass 数不变。
- **R2 冒烟**: `godot --path shandong-wolf/ --headless --quit` 退出 0——两个 .tscn 属性修改不破坏场景加载（尤其 Main.tscn 首启链）。预期：退出码 0。

### Scenario E: 渲染级验证（implement 期真实渲染，非单测）

- **E1 feedback 组截图火花可见（AC6 素材恢复）**: 运行 E2E feedback 组（e2e_feedback_capture.tscn），fb_parry_success / fb_stance_break / fb_execute 三帧截图断言**存在苍白金 #ffd9a0 系像素**（火花色，PRD §8 验证清单 4——像素级：`r>g 且 r-b ≥ 0.15` 或色距容差命中 FEEDBACK_SPARK_COLOR 系）。前置：§2.1 修复 + 火花 burst 帧内截图（rig 冻结帧模式）。预期：三帧均含火花像素（修复前为 0）。
- **E2 assembly 组截图火花可见**: 运行 E2E assembly 组 02_parry_execute（e2e_main_assembly_capture.tscn instance Main.tscn），断言同 E1 火花像素存在。前置：§2.2 修复。预期：通过（验证 instance 继承）。
- **E3 真实战斗画面验证（可选，人工）**: 运行 Main.tscn 手动触发打击事件，肉眼确认火花可见且角色不被粒子遮挡。预期：火花在角色下方、背景之上可见。

### 既有用例影响清单

| 用例 | 影响 | 处置 |
|------|------|------|
| test_reaction_controller.gd C1-C5（火花 amount/emitting/z_index/color） | 无（未触碰 feedback_spark.gd） | 保持 |
| test_atmosphere / test_hud / test_stick_figure 等其余 18 套件 | 无（未触碰任何 .gd/tests） | 保持 |
| e2e_shots.json 各组（snow_night/hud/battle_stage/assembly） | 无（shot 定义未改；feedback/assembly 截图内容自动改善） | 保持 |

---

## 9. 验收条件映射（源自 PRD #662 §5.1）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | e2e_feedback_capture.tscn Backdrop 设 z_index=-2（背景在火花 -1 之下） | §2.1 | T1（grep 断言） |
| AC2 | Main.tscn WorldBackdrop 设 z_index=-2（真实战斗火花可见） | §2.2 | T2（grep 断言）+ E3 |
| AC3 | 火花层级不动（FEEDBACK_SPARK_Z_INDEX 仍 -1，feedback_spark.gd 无改动） | 红线（§2/§3） | T3（diff 守卫）+ R1 |
| AC4 | C4 单测仍通过（断言不变） | 零测试改动 | R1 |
| AC5 | 红线保持：角色 z=0 仍在火花 z=-1 之上（-2 < -1 < 0） | §4 Flow 1 | E1/E2 截图 + 层级推演 |
| AC6 | 官方截图恢复火花（#579 素材可产出） | §2.1 + 间接 §2.2 | E1（fb 三帧）+ E2（02_parry_execute） |

### 实现 PR 的 E2E gate（PRD §8 验证清单转述）

1. `grep -A3 'name="Backdrop"' scenes/e2e_feedback_capture.tscn` → 含 `z_index = -2`
2. `grep -A3 'name="WorldBackdrop"' scenes/Main.tscn` → 含 `z_index = -2`
3. 测试套件运行 → C4 通过（R1）
4. E2E feedback 组三帧 → 火花可见（E1，像素级断言）
5. E2E assembly 组 02_parry_execute → 火花可见（E2）

---

## 10. 明确不修改（与 PRD §8 红线对齐）

- ❌ `shandong-wolf/gdscripts/constants.gd`（FEEDBACK_SPARK_Z_INDEX=-1 保持）
- ❌ `shandong-wolf/gdscripts/feedback_spark.gd`（火花 z=-1 保持）
- ❌ `shandong-wolf/tests/`（C4 断言保持；本阶段也不写可运行测试文件）
- ❌ `scenes/e2e_hud_capture.tscn` / `e2e_stick_figure_capture.tscn`（无负 z 内容，避免无谓 churn）
- ❌ `e2e_shots.json`（shot 定义无需变）
- ❌ `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`framework/`、`docs/GAME_DESIGN/`（跨游戏/管线红线）
- ❌ 任何 .gd 脚本 / 判定逻辑 / 新场景 / 新资源（PRD §8：修复范围仅 2 个 .tscn 属性）
- ✅ `scenes/e2e_feedback_capture.tscn` 的 Camera2D / ReactionController / ext_resource 零改动（仅 Backdrop 加属性）
- ✅ `scenes/Main.tscn` 的 CanvasLayer / CenterContainer / 其余节点零改动（仅 WorldBackdrop 加属性）
