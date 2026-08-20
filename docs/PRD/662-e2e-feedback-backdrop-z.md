# PRD #662 — e2e_feedback_capture Backdrop 盖住火花（z=0 vs z=-1，E2E 截图无火花）

> **Parent Issue:** #662（bug / priority/medium / infrastructure / version/mvp）
> **Source:** issue body 已含根因分析（2026-08-20 579 rig 截图验证）——按 bug pre-investigation
> workflow edge case（issue body 即预调查），逐条核对声明后直接进入 PRD 编写。
> **游戏:** shandong-wolf（manifest `game.active`）｜**引擎:** Godot 4.7.1
> **深度:** 无 depth label → standard（§1–6 + §8 必写；§7 因已有 workaround 实测证据而保留）
> **日期:** 2026-08-21

---

## 1. 问题定义

### 1.1 预调查结论（bug pre-investigation，Patch 10）

| Issue 声称 | 预调查结果 | 证据 |
|-----------|-----------|------|
| 火花 z_index=-1（FEEDBACK_SPARK_Z_INDEX，「粒子不盖角色」红线） | ✅ **属实** | `gdscripts/constants.gd:582` `FEEDBACK_SPARK_Z_INDEX: int = -1`；`gdscripts/feedback_spark.gd:21` `_ready()` 中 `z_index = C.FEEDBACK_SPARK_Z_INDEX`；单测 `tests/test_reaction_controller.gd:507`（C4）断言 `spark.z_index == FEEDBACK_SPARK_Z_INDEX` |
| e2e_feedback_capture.tscn 的 Backdrop 未设 z_index（默认 0） | ✅ **属实** | `scenes/e2e_feedback_capture.tscn:10-12` Backdrop（ColorRect）仅 color/size，无 z_index 属性 → Godot 默认 0 |
| 火花被 Backdrop 完全盖住 → E2E 截图截不到火花（AC6 素材无法产出） | ✅ **机制确认** | 同 CanvasLayer（默认 layer 0）内 Godot 按 z_index 绘制：z=-1（GPUParticles2D）先画、z=0（不透明 ColorRect，alpha=1）后画 → 背景完全覆盖火花。issue body 附 579 rig 截图验证 + workaround 验证（Backdrop z 降到 -5 后火花可见） |
| 修复方向：Backdrop 加 z_index=-2 | ✅ **方向正确** | z=-2 < z=-1（背景在火花下）；角色（stick figure，z=0 默认）仍在火花（z=-1）之上 → 「粒子不盖角色」红线保持。`scenes/battle_stage.tscn:49,54` 已有 z_index=-1/-2 的先例（PlatformSilhouetteMid/Back） |

**结论：issue 描述与当前代码完全一致，无已修复部分、无 stale claims。Bug 仍存在（自 #654 引入，2026-08-19/20 579 实现）。**

### 1.2 扩展面（issue 未显式列出，同根因）

Issue 标题聚焦 `e2e_feedback_capture.tscn`，但根因（「背景 ColorRect z=0 盖住火花 z=-1」）影响**所有**含「全屏背景 + 火花」的场景：

| 场景 | 背景节点 | 火花来源 | 受影响？ |
|------|---------|---------|:-------:|
| `scenes/e2e_feedback_capture.tscn` | Backdrop（z=0 默认） | ReactionController._ready 代码创建 FeedbackSpark（z=-1） | ✅ **issue 主场景** |
| `scenes/Main.tscn`（#585 组装主场景） | WorldBackdrop（z=0 默认） | MainBattle._build_reaction() 创建 Reaction（z=-1 火花） | ✅ **同根因** |
| `scenes/e2e_main_assembly_capture.tscn`（instance Main.tscn） | WorldBackdrop（z=0 默认） | 同上 | ✅ **同根因**（assembly 组 02_parry_execute 截图同样无火花） |
| `scenes/e2e_hud_capture.tscn` | Backdrop（z=0 默认） | 无火花（Hud 在 CanvasLayer layer=1，EnemyStub 无负 z） | ❌ 无负 z 内容 |
| `scenes/e2e_stick_figure_capture.tscn` | Backdrop（z=0 默认） | ReviveFX/Atmosphere 均无 z_index（z=0），Player z=0 | ❌ 无负 z 内容 |
| `scenes/e2e_battle_stage_capture.tscn` | 无独立 Backdrop | 无火花 | ❌ |

> ⚠️ **真实游戏影响**：`Main.tscn` 的 WorldBackdrop 同样盖住 MainBattle 下 Reaction 的火花 —— 玩家在真实战斗画面中也看不到打击火花，不仅是 E2E 截图问题。这是比 issue 标题更广的用户可见缺陷（AC2 四要素之一缺失）。

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | E2E 反馈截图（#579 AC6） | 每次 e2e 运行 | 官方截图截不到火花 → 用户无法裁决『刀锋相撞』重量感 |
| B | 真实战斗（#585 组装后） | 每次打击 | 火花 z=-1 被 WorldBackdrop 盖住 → 玩家看不到打击反馈（AC2 四要素缺一） |
| C | assembly 组截图（#585 AC5） | 每次 e2e 运行 | 02_parry_execute 处决构图同样无火花 |

### 1.4 根因机制（代码级，非推测）

```
同 CanvasLayer（layer 0）内绘制顺序（z_index 升序，同层按树序）：
  z=-2  (若修复后)  Backdrop/WorldBackdrop  ColorRect（背景）
  z=-1                FeedbackSpark           GPUParticles2D（火花）← 当前被 z=0 背景盖住
  z=0   (默认)        角色 stick figure / 场景几何
```

- 火花 `z_index=-1` 是**硬约束**（constants + 单测 C4，改火花层级 = 违反「粒子不盖角色」红线）。
- 背景 ColorRect 是**默认 z=0**，且 alpha=1 不透明 → 完整覆盖下层火花。
- 修复只能动背景层级（z=0 → z=-2），不能动火花层级。

---

## 2. 设计意图

### 2.1 现状为何存在

| 原因 | 详情 |
|------|------|
| 火花负层级是刻意设计 | #579 issue「粒子不盖角色」红线 → 火花 z=-1（constants.gd:582 + 单测 C4 断言）。这是正确的游戏视觉决策 |
| 背景 z_index 被遗漏 | e2e rig 场景（#654）与 Main.tscn 组装（#666）添加全屏 ColorRect 背景时未考虑其与负 z 火花的相对层级 —— 背景 z=0 默认值与角色同层，高于火花 |
| 截图时未发现 | #654 的 rig 验证截图可能未在火花 burst 帧检查背景遮挡；issue 由 2026-08-20 579 rig 截图验证正式发现 |

### 2.2 为什么现在修

- **AC6 素材阻塞**：E2E 截图是用户裁决的唯一输入，无火花截图 = 反馈系统无法验收。
- **真实游戏可见缺陷**：#585 组装后 Main.tscn 成为主场景，玩家实际看不到打击火花。
- 修复成本极低（两个场景各一行 `z_index = -2`），零运行时逻辑改动。

### 2.3 既有约束（不得违反）

| 约束 | 详情 | 来源 |
|------|------|------|
| 火花 z_index 固定 -1 | 改火花层级 = 破坏 C4 单测 + 粒子盖角色红线 | constants.gd:582、test_reaction_controller.gd:507 |
| 角色层级保持 z=0 默认 | 角色在火花之上（z=0 > -1） | 视觉红线 |
| 不引入第三方 addon / 不碰判定逻辑 | 项目红线 | PRD #579 §8.5 |
| 背景 ColorRect 渲染内容不变 | 仅改层级属性，不动 color/size/anchors | — |

---

## 3. 影响分析

### 3.1 直接受影响文件

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `scenes/e2e_feedback_capture.tscn` | E2E rig | Backdrop 节点加 `z_index = -2` |
| `scenes/Main.tscn` | 组装主场景 | WorldBackdrop 节点加 `z_index = -2` |

### 3.2 新增文件

无（纯 .tscn 属性修改，零新文件）。

### 3.3 间接影响

| 文件/系统 | 影响 | 风险 |
|-----------|------|:----:|
| `gdscripts/feedback_spark.gd` | 无改动（火花 z=-1 保持） | 无 |
| `gdscripts/constants.gd` | 无改动（FEEDBACK_SPARK_Z_INDEX=-1 保持） | 无 |
| `tests/test_reaction_controller.gd` | C4 断言不变，仍通过 | 无 |
| `scenes/e2e_main_assembly_capture.tscn` | 间接受益（instance Main.tscn → WorldBackdrop 修复自动生效） | 无 |
| `scenes/e2e_hud_capture.tscn` / `e2e_stick_figure_capture.tscn` | 无负 z 内容，**不改**（避免无谓 churn） | 无 |

### 3.4 数据流影响

```
FeedbackSpark (z=-1)  ──►  CanvasLayer 0 绘制
                              │
Backdrop/WorldBackdrop ──►  z_index: 0 → -2  (修复)
                              │
                              ▼
                    绘制顺序: 背景(-2) → 火花(-1) → 角色(0)
                    火花可见 ✅ 角色仍盖火花 ✅（红线保持）
```

### 3.5 需更新文档

- [ ] `docs/DESIGN/579-combat-feedback-system.md`（§2.6 rig 说明补一句背景层级约定，可选）
- [x] 本 PRD（记录修复与验证方法）

---

## 4. 方案对比

### 方案 A：背景节点显式设 z_index=-2（推荐）

在 `e2e_feedback_capture.tscn` 的 Backdrop 与 `Main.tscn` 的 WorldBackdrop 上各加一行 `z_index = -2`。

| 维度 | 评价 |
|------|------|
| 描述 | 背景 ColorRect 显式声明层级：背景(-2) < 火花(-1) < 角色(0)。与 battle_stage.tscn 已有 z=-1/-2 先例一致 |
| Pros | ① 一处一行，最小 diff；② 不动火花/角色层级，红线零风险；③ 声明式（.tscn 属性），无运行时逻辑；④ 与场景内既有负 z 用法（battle_stage silhouette）风格统一 |
| Cons | ① 依赖「背景永远低于火花」的隐式约定，未来新增背景节点需记得同样设置；② 需同时改两个场景 |
| Risk | **Low** — 纯属性修改；Hud/Atmosphere 均在独立 CanvasLayer（layer≥1），不受 layer 0 z_index 影响 |
| Effort | 0.1 人日 |

### 方案 B：火花 z_index 改为 ≥0（背景之上）

| 维度 | 评价 |
|------|------|
| 描述 | 把 FEEDBACK_SPARK_Z_INDEX 从 -1 改为 0 或更高，让火花盖过背景 |
| Pros | 单点修改（constants.gd） |
| Cons | ① **违反「粒子不盖角色」红线**——火花 z=0 与角色同层甚至更高，粒子可能盖住角色（单测 C4 断言直接失败）；② 需同步改单测，动摇已验收的设计决策；③ issue 明确要求背景在火花下、红线保持 |
| Risk | **High** — 破坏已验收 AC（粒子不盖角色红线是 #579 硬约束） |
| Effort | 0.1 人日（但需额外设计评审 + 单测修改） |

### 方案 C：运行时脚本修正（截图脚本把 Backdrop z 降到 -5）

| 维度 | 评价 |
|------|------|
| 描述 | 维持 issue 中提到的临时 workaround：截图驱动脚本在运行时改 Backdrop z_index |
| Pros | 不动场景文件 |
| Cons | ① workaround 性质，官方场景文件仍是错的（真实游戏画面火花仍不可见）；② E2E 驱动契约（`framework/templates/e2e_capture.gd`）只读节点属性、零修改游戏代码——运行时改节点违反该契约精神；③ 每次截图都依赖 hack，脆弱的隐式依赖 |
| Risk | **Med** — 只修 E2E 表象，不修真实游戏根因 |
| Effort | 0.2 人日 |

### 推荐：方案 A

1. **唯一修到根因的方案**：背景层级显式化，真实游戏与 E2E 同时修复。
2. **红线零风险**：火花 -1、角色 0 均不动，C4 单测保持通过。
3. **最小 diff + 项目先例**：battle_stage.tscn 已用 z=-1/-2 表达「背景层级」，风格一致。
4. 方案 B 破坏验收决策，方案 C 只掩盖表象——均不选。

---

## 5. 边界条件与验收标准

### 5.1 正常路径 AC

- [x] **AC1: e2e_feedback_capture.tscn Backdrop 设 z_index=-2** — 背景在火花（z=-1）之下
  - 验证：`grep -A3 'name="Backdrop"' scenes/e2e_feedback_capture.tscn` 含 `z_index = -2`
- [x] **AC2: Main.tscn WorldBackdrop 设 z_index=-2** — 真实战斗画面火花可见
  - 验证：`grep -A3 'name="WorldBackdrop"' scenes/Main.tscn` 含 `z_index = -2`
- [x] **AC3: 火花层级不动** — FEEDBACK_SPARK_Z_INDEX 仍为 -1，feedback_spark.gd 无改动
  - 验证：`git diff` 不包含 constants.gd / feedback_spark.gd / 任何 .gd
- [x] **AC4: C4 单测仍通过** — `tests/test_reaction_controller.gd` 的 `_test_c4_layer` 断言不变
  - 验证：运行 `godot --headless` 测试套件（或审阅 diff 确认未触碰测试文件）
- [x] **AC5: 红线保持** — 角色（z=0 默认）仍在火花（z=-1）之上，「粒子不盖角色」成立
  - 验证：层级关系 -2 < -1 < 0

### 5.2 边界情况

1. **e2e_hud / e2e_stick_figure rig 的 Backdrop**：无负 z 内容，明确不改——避免无谓 diff；若未来加入负 z 效果需同样处理（记录于 §8）。
2. **Atmosphere（CanvasLayer 2-10）/ Hud（CanvasLayer 1）**：独立 CanvasLayer，不受 layer 0 z_index 影响——修复不触碰。
3. **battle_stage.tscn 已有 z=-1/-2 的 PlatformSilhouette**：与背景修复同层共存无冲突（背景 -2 与 silhouette -2 同值，按树序绘制，视觉无差异——silhouette 是局部 Polygon2D 不遮挡全局）。
4. **e2e_shots.json**：无需改（feedback 组 shot 定义不变，场景修复后截图自动含火花）。
5. **未来新增 E2E rig**：新增全屏背景节点时应显式设 z_index=-2（约定写入 DESIGN 579 §2.6 或本 PRD §8）。

### 5.3 失败路径

1. **漏改 Main.tscn**：真实战斗火花仍不可见——AC2 失败，需补。
2. **误改火花层级**：C4 单测失败 + 粒子盖角色——红线破坏，需 revert。
3. **把 z_index 误设为 -1**（与火花同层）：绘制顺序按树序，背景若在火花后声明会再次盖住火花——需设 -2（严格低于火花）。

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #654（579 E2E rig，引入 bug） | ✅ merged | 无——修复不依赖其改动 |
| #666（585 组装，引入 Main.tscn WorldBackdrop） | ✅ merged | 无 |

### 阻塞

无。本修复独立，不依赖任何未合并 PR。

### 依赖链

```
#579 (反馈系统) → #654 (E2E rig, 引入 Backdrop) ─┐
#585 (组装)     → #666 (Main.tscn WorldBackdrop) ─┼─► #662 (本修复: 背景 z=-2)
                                                  └─► 修复后: E2E 截图 + 真实战斗火花可见
```

### 准备

- [x] 确认 Godot 4.7.1 z_index 语义（同 CanvasLayer 升序绘制，Control 继承 CanvasItem.z_index）
- [x] 确认 battle_stage.tscn 已有负 z 先例（z=-1/-2）

---

## 7. Spike / 实验

> 保留（非 standard 强制）：issue body 已含**实测证据**，此处整理为已完成实验。

| # | 问题 | 方法 | 预期 | 实测结果 | 对方案影响 |
|---|------|------|------|---------|-----------|
| 1 | 火花是否真被背景盖住 | 579 rig 截图验证（issue body，2026-08-20） | 截图无火花 | ✅ 确认无火花 | 确认 bug 存在 |
| 2 | 背景降到负层级后火花是否可见 | 临时 workaround：Backdrop z 降到 -5 | 火花可见 | ✅ 已验证可见 | 证明「背景负层级」方向正确，方案 A 可行 |
| 3 | 负层级是否影响其他元素 | 层级推演（背景-2 / 火花-1 / 角色0） | 互不遮挡 | ✅ 与 battle_stage 既有 z=-1/-2 用法一致 | 方案 A 无副作用 |

---

## 8. 延续上下文（plan agent handoff）

### 系统状态

- `shandong-wolf`（game.active），Godot 4.7.1。
- Bug 存在于 `scenes/e2e_feedback_capture.tscn:10`（Backdrop）与 `scenes/Main.tscn:10`（WorldBackdrop）——两者均无 z_index（默认 0），盖住火花（z=-1）。
- 火花层级是硬约束：`constants.gd:582` + `feedback_spark.gd:21` + 单测 C4（test_reaction_controller.gd:507）。

### 修复范围（实现期唯一任务）

| 文件 | 行 | 修改 |
|------|----|------|
| `scenes/e2e_feedback_capture.tscn` | Backdrop 节点（~L10） | 加 `z_index = -2` |
| `scenes/Main.tscn` | WorldBackdrop 节点（~L10） | 加 `z_index = -2` |

### 红线（实现期禁止）

- ❌ 不改 `constants.gd` / `feedback_spark.gd` / 任何 .gd（火花 z=-1 保持）
- ❌ 不改 `tests/`（C4 断言保持）
- ❌ 不改 e2e_hud / e2e_stick_figure rig（无负 z 内容）
- ❌ 不改 `e2e_shots.json`（shot 定义无需变）

### 验证清单（实现 PR 的 E2E gate）

1. `grep -A3 'name="Backdrop"' scenes/e2e_feedback_capture.tscn` → 含 `z_index = -2`
2. `grep -A3 'name="WorldBackdrop"' scenes/Main.tscn` → 含 `z_index = -2`
3. 运行测试套件 → C4 通过（`godot --headless` 或项目标准测试入口）
4. E2E feedback 组截图（fb_parry_success / fb_stance_break / fb_execute）→ 火花可见（像素级验证：火花苍白金 #ffd9a0 系像素存在）
5. E2E assembly 组 02_parry_execute → 火花可见

### 已知边界（后续维护）

- 未来新增 E2E rig / 全屏背景节点：默认设 z_index=-2（低于火花 -1）。
- 若未来火花层级调整，需同步重审所有背景节点（约定：背景 < 火花 < 角色）。
