# Design: [Scene] 雪夜山东村战斗场景（单场景 MVP 舞台）

> **Parent Issue:** #583
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **Approach:** PRD §4.5 推荐组合**逐项确认采纳，无分歧** —— 平台 A（同一基准碰撞面 + 视觉分层高差 60-100px）/ 月亮 A（Mesh2D 径向渐变 + 光晕 shader，回退双层半透明圆）/ 物件布局（草屋×2 + 枯树×2 = 4 ≤ 5，山峦/月亮为背景不计数）/ 相机 A（场景内 Camera2D，limits 覆盖 2400px）/ 出生点命名（`PlayerSpawn` / `EnemySpawnA` / `EnemySpawnB`，Marker2D）
> **Reference PRD:** `docs/PRD/583-snowy-shandong-village-battle-stage.md`（research PR #644 已合并 2026-08-20）
> **上游方案:** `docs/DESIGN/582-snow-night-atmosphere.md`（层契约 layer 0 世界层 + 唯一 Moonlight + `atmosphere_layer.tscn` 复用约定 + C3 守卫）；`docs/DESIGN/581-enemy-ai.md`（`EnemyAI.waypoints` @export 数据契约）；`docs/DESIGN/572-scaffold-main-entry.md`（constants.gd `# DRAFT` 分区格式、run_tests 挂载模式、DESIGN 文档结构约定）
> **所有权:** `content_ownership: mechanical`（场景几何/碰撞/出生点布局 = 机械工程；构图/配色裁决 = taste-draft —— AC5 E2E 截图交用户裁决；PRD 所有权声明原样传递）
> **深度:** standard（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=12 标注 depth: standard；GitHub 无 depth 标签）—— 7 文件（4 新建 + 3 修改）/ 7 独立子任务（平台几何、剪影物件、月亮、出生点+相机、常量分区、E2E 截图、测试套件）跨多子系统 → **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-583，branch `plan/583-snowy-shandong-village-battle-stage`）；constants.gd 场景分区追加在**文件尾部**（#584 手感分区已在前部，同文件不同区域，main 侧无代码冲突预期）；Main.tscn 零改动（#585 组装时挂载 battle_stage）；e2e_shots.json 追加 `battle_stage` 组（与 stick_figure/snow_night/hud 组并存，追加式无并发改写）
> **红线:** 只动 `shandong-wolf/` 下 7 文件（见 §3）；**绝不触碰** `mini-pong/`、`scenes/Main.tscn`、`gdscripts/player_controller.gd`、`gdscripts/enemy_ai.gd`、`gdscripts/atmosphere_controller.gd`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`docs/GAME_DESIGN/`、`tests/check_compile.gd`、`tests/smoke_test.gd`（#572 机制自动纳入新脚本）；零外部美术资产/零贴图（AC2 + PRD 硬约束）；**禁新增 CanvasModulate**（#624 C3 守卫，全场景计数 == 1）；场景尺寸/坐标全部 .tscn 声明不写死；参数全部集中 constants.gd 场景分区 `# DRAFT` + 情感断言；物件 ≤5；禁日式和风/西式元素

---

## 1. 架构总览

**问题本质是「战斗没有发生地」。** #572（地基）/ #574（火柴人剪影）/ #582（雪夜氛围四层）已合入 main，Main.tscn 是标题场景 + Atmosphere 实例；玩家（#573/#574）与敌人（#581）已具备移动/战斗/动画能力，但**没有物理地面**（无 StaticBody2D，`player_controller.gd` 的 `velocity.y = 0.0` + `move_and_slide()` 悬空执行）、**没有空间叙事**（草屋/枯树/苍月无视觉载体）、**没有出生点坐标契约**（#581 DESIGN §2 显式要求「#583 场景 → EnemyAI.waypoints」）——#585 组装（SW-013）的依赖清单含本场景，战斗闭环无从挂载。本设计交付 = **独立世界层场景 `battle_stage.tscn`（几何 + 碰撞 + 剪影 + 出生点 + 相机，纯声明式）+ constants.gd 场景分区（# DRAFT）+ E2E 截图像具场景 + battle_stage 截图组 + 场景结构单测**。

**设计哲学：纯声明式几何 + 参数单一事实源 + 程序化零贴图 + 可通行优先。** 四个决策全部锚定 PRD §4 推荐方案：平台高差走「同基准碰撞面 + 视觉分层」（`velocity.y=0` 移动模型下唯一能**严格**满足 AC1「可通行无阻碍」的路径，PRD §4.1-A）；月亮是 Mesh2D 径向渐变圆（issue 指定路径，非 #582 CanvasModulate——后者是光照不是天体，且 C3 守卫禁止第二 CanvasModulate）；场景尺寸/物件坐标全部声明在 .tscn（红线：禁止脚本写死）；所有视觉/尺寸参数进 constants.gd 新增「场景参数」分区（`# DRAFT` 候补值 + 情感断言，格式照 #572/#582）；渲染全部 Polygon2D/Line2D/Mesh2D 程序化生成，零外部贴图（开源调研 PRD §6.2 结论：无成熟模板可复用 → 自行实现）。

**层级与挂载约定（PRD §1.2 层契约，与 #582/#624 定稿一致）：** 本场景几何挂 **layer 0 世界层**（唯一 Moonlight 染此层）；雪幕 3-5 / 水墨 2 / 血色 10 / UI 1 禁染；**全场景仅 1 个 CanvasModulate**（归属 Atmosphere 实例，battle_stage 内零 CanvasModulate）；#585 组装时把 battle_stage 挂入 Main.tscn 且**不重复挂 Atmosphere**（Main.tscn 已有）。

```
                 ★ Issue #583 本设计（shandong-wolf 战斗舞台场景 SW-012）
┌──────────────────────────────────────────────────────────────────────────────┐
│ 新建（4 文件，全部 shandong-wolf/ 下）                                         │
│  scenes/battle_stage.tscn            战斗舞台本体（纯声明式，layer 0 世界层）    │
│  scenes/e2e_battle_stage_capture.tscn  E2E 截图像具场景（instance battle_stage）│
│  gdscripts/moon_glow.gdshader        月亮光晕 shader（可选，回退双层半透明圆）    │
│  tests/test_battle_stage.gd          场景结构单测（AC1-AC4 断言载体）           │
├──────────────────────────────────────────────────────────────────────────────┤
│ 修改（3 文件）                                                                │
│  gdscripts/constants.gd   尾部追加「场景参数」# DRAFT 分区（平台/色板/月亮/高差） │
│  e2e_shots.json           追加 battle_stage 组（全景/平台近景/月亮构图 3 shot） │
│  tests/run_tests.gd       _run_tests() 追加 _run(test_battle_stage.gd)       │
├──────────────────────────────────────────────────────────────────────────────┤
│ 验证（0 改动）: check_compile / smoke_test 由 #572 机制自动纳入新增 .gd/.gdshader│
└───────────────────────────────────┬──────────────────────────────────────────┘
                                    ▼
            godot --path shandong-wolf/（#585 组装后 main_scene = Main.tscn）
              ├─ Main (Node2D)
              │   ├─ WorldBackdrop (layer 0 ColorRect)        ← #582 既有，零改动
              │   ├─ Atmosphere (instance atmosphere_layer)   ← #582 既有，唯一 Moonlight
              │   └─ BattleStage (instance battle_stage.tscn) ← 本 issue 交付（#585 挂载）
              │        ├─ Ground: StaticBody2D + CollisionShape2D（单一连续碰撞面，基准 Y）
              │        │    └─ 视觉分层: 前景雪堆 Polygon2D（低 60-100px）+ 中/背景平台剪影
              │        ├─ Houses×2: Polygon2D 墨色剪影 + Line2D 屋顶压雪线（x≈300/1900）
              │        ├─ Trees×2: Line2D 枯树骨架（x≈900/1500）
              │        ├─ Mountains: Line2D 多层远景剪影（背景，不计数）
              │        ├─ Moon: Mesh2D 径向渐变 + moon_glow 光晕（y≈120-160，苍月悬顶）
              │        ├─ PlayerSpawn / EnemySpawnA / EnemySpawnB (Marker2D ×3)
              │        └─ StageCamera (Camera2D, limits 2400px, current=true)
              └─ headless 三入口 + E2E battle_stage 组截图: 全绿 + 截图附 PR → 用户 AC5 裁决
```

**与 PRD 方案裁决的一致性：** PRD §4.1–§4.4 四个决策点推荐方案 A/A/A/A，§4.5 汇总。本设计逐项确认采纳，无分歧；PRD §7 三个 Spike（月亮光晕渲染变体 / 全宽走查 / Mac 帧率基准）为 implement Phase 0 执行项，其中 Spike 1 结论直接决定 moon_glow.gdshader 主路径与双层圆回退路径的选择（架构不变，仅视觉实现细节）。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-20 侦查，plan agent 已逐条核实 origin/main @ 034666c） | 与 #583 的差距 |
|------|-----------------------------------------------------------------------|---------------|
| `shandong-wolf/scenes/Main.tscn` | ✅ 标题场景 + WorldBackdrop(layer 0, NIGHT_BG_COLOR #d8dce4) + CanvasLayer UI(layer=1) + **Atmosphere 实例已挂载**（#582/#613） | ❌ 本 issue **不改**；#585 组装时挂载 battle_stage |
| `shandong-wolf/scenes/battle_stage.tscn` | ❌ **不存在**（SW-012 本体缺失） | ✅ 全新建（本设计 §2.1） |
| `shandong-wolf/gdscripts/player_controller.gd` | ✅ 加速度移动 + `velocity.y = 0.0` + `move_and_slide()`（#573） | ❌ 零改动（碰撞面使 move_and_slide 落地生效，被动受益） |
| `shandong-wolf/gdscripts/enemy_ai.gd` | ✅ `@export var waypoints: Array`（空数组=原地等待不报错；#581/#638） | ❌ 零改动；waypoints 数据坐标由本场景 .tscn 提供（§6 集成点） |
| `shandong-wolf/gdscripts/constants.gd` | ✅ `WolfConstants`：手感 5 分区 + 输入层 + 受击/敌人/处决 + 氛围分区（#582）+ AI 分区（#581）；**无场景分区** | ❌ 尾部追加「场景参数」分区（平台/色板/月亮/高差常量，§3.2） |
| `shandong-wolf/gdscripts/atmosphere_controller.gd` | ✅ 氛围编排 + `set_low_health()` 契约 + 唯一 Moonlight（#582） | ❌ 零改动（层契约共存；C3 守卫保护） |
| `shandong-wolf/scenes/atmosphere/atmosphere_layer.tscn` | ✅ 氛围层场景组件（雪幕 3 层/月光/水墨/血色） | ❌ 零改动；e2e_battle_stage_capture 复用实例化（§2.2） |
| `shandong-wolf/e2e_shots.json` | ✅ stick_figure（12 shot）/ snow_night（1 单帧）/ hud（4 shot）三组 | ❌ 追加 `battle_stage` 组（3 shot，§3.3） |
| `shandong-wolf/tests/run_tests.gd` | ✅ 挂载 11 个套件（`_run_tests()` 内 `_run(...)` 行） | ❌ 追加 `_run("res://tests/test_battle_stage.gd", "BattleStage")` |
| `shandong-wolf/tests/test_atmosphere.gd` | ✅ 含 C3 守卫（CanvasModulate 计数 == 1 断言，#624） | ❌ 零改动；新测试同样断言（§8 C4） |
| `shandong-wolf/project.godot` | ✅ Godot 4.7.1，resizable=false + stretch canvas_items | ❌ 零改动（#585 组装时改 main_scene） |

### 1.2 PRD 断言 vs 实际代码（Gap 分析）

| PRD 断言 | 实际代码（origin/main 034666c 核实） | 设计裁决 |
|----------|--------------------------------------|---------|
| 「#581 DESIGN §2 明确 #583 场景 → `EnemyAI.waypoints` @export（出生点 + 巡逻路径坐标）」 | ✅ `enemy_ai.gd` 第 4 行 `@export var waypoints: Array = []` 存在，空数组原地等待不报错 | 本场景 .tscn 提供 `waypoints` 数据坐标（出生点 + 巡逻路径），§6 集成点表登记；EnemyAI 零改动 |
| 「#582 的 Moonlight 是 CanvasModulate（全局光照），不是月亮天体」 | ✅ `atmosphere_layer.tscn` 含 `Moonlight (CanvasModulate)`，C3 守卫拦截第二实例 | 本场景月亮 = Mesh2D 径向渐变圆（非 CanvasModulate），§2.1.5；测试断言全场景 CanvasModulate 计数 == 1 |
| 「无平台 / 无碰撞体」 | ✅ 确认：shandong-wolf/ 下无任何 StaticBody2D/CollisionShape2D 引用 | 新建 Ground StaticBody2D + CollisionShape2D（§2.1.1） |
| 「无 Camera2D；2400px > 1280px 窗口」 | ✅ 确认：Main.tscn 无 Camera2D（标题场景不需要） | 新建 StageCamera（§2.1.7），声明式 limits=2400px |
| 「场景参数集中地缺失」 | ✅ 确认：constants.gd 无场景分区 | 尾部追加场景分区（§3.2） |
| 「E2E 截图计划无 battle_stage 组」 | ✅ 确认：e2e_shots.json 三组均与战斗场景无关 | 追加 battle_stage 组（§3.3） |
| 「出生点 Marker2D 约定缺失」 | ✅ 确认：无 Marker2D | 新建 ×3（PlayerSpawn/EnemySpawnA/EnemySpawnB，§2.1.6） |

---

## 2. 新组件 — 详细设计

### 2.1 battle_stage.tscn — 战斗舞台场景（SW-012 本体）

- **File:** `shandong-wolf/scenes/battle_stage.tscn`
- **Node structure（根节点 BattleStage = Node2D，纯声明式，无脚本）：**

```
BattleStage (Node2D)                                    # 根，position (0,0)，layer 0 世界层
├── Ground (StaticBody2D)                               # 单一连续碰撞面（方案 A 核心）
│   └── CollisionShape2D                                # RectangleShape2D: 2400 × 24，顶面 y = PLATFORM_Y_BASE
├── PlatformVisual (Node2D)                             # 视觉分层高差（60-100px），零碰撞
│   ├── SnowDriftFront (Polygon2D)                      # 前景雪堆：白色 α0.6，y 低于基准面 60-100px
│   ├── PlatformSilhouetteMid (Polygon2D)               # 中景平台剪影：墨色 #1a1f26 系
│   └── PlatformSilhouetteBack (Polygon2D)              # 背景平台剪影：墨色更淡（远景降饱和）
├── Houses (Node2D)
│   ├── HouseLeft (Node2D, x≈300)
│   │   ├── Hut (Polygon2D)                             # 草屋墨色剪影，屋脊 ≤120px，低矮扁平
│   │   └── RoofSnowLine (Line2D)                       # 屋顶压雪线：白色，沿屋脊折线
│   └── HouseRight (Node2D, x≈1900)
│       ├── Hut (Polygon2D)
│       └── RoofSnowLine (Line2D)
├── Trees (Node2D)
│   ├── TreeLeft (Line2D, x≈900)                        # 枯树如骨：枝杈骨架，墨色
│   └── TreeRight (Line2D, x≈1500)
├── Mountains (Line2D)                                  # 山峦远景：多层折线剪影（背景，不计数）
├── Moon (Mesh2D)                                       # 苍月悬顶：径向渐变圆（§2.1.5）
│   └── MoonGlow (Mesh2D 或 shader 光晕层)              # 光晕：moon_glow.gdshader 或第二层半透明圆（回退）
├── PlayerSpawn (Marker2D)                              # 玩家出生点（#585 实例化玩家）
├── EnemySpawnA (Marker2D)                              # 敌人 1 出生点（#585 实例化 + waypoints 配置）
├── EnemySpawnB (Marker2D)                              # 敌人 2 出生点
└── StageCamera (Camera2D)                              # current=true，limits 覆盖 2400px（§2.1.7）
```

- **职责：** 单场景 MVP 战斗舞台的全部几何/碰撞/空间叙事/出生点/相机，**零脚本、零 CanvasModulate、零外部贴图**；全部坐标/尺寸在 .tscn 声明（可编辑，不写死）。
- **State Properties：** 无脚本 → 无运行期状态；参数经 constants.gd 场景分区提供**声明参考值**（.tscn 手填坐标与常量一致，test 断言两者一致防漂移）。
- **Key Methods：** 无（纯声明式；`_ready` 链由 Godot 原生节点完成）。
- **Integration notes：** #585 组装时 instance 进 Main.tscn 根节点（不重复挂 Atmosphere）；玩家/敌人实体在 #585 实例化并放置在 PlayerSpawn/EnemySpawnA/B 坐标；EnemyAI.waypoints 从本 .tscn 的巡逻路径 Marker 坐标读取（§6）。

#### 2.1.1 平台几何（方案 A：同一基准碰撞面 + 视觉分层高差）

- **结构：** `Ground (StaticBody2D)` 单一连续碰撞面 + `CollisionShape2D (RectangleShape2D)`；顶面统一在 `PLATFORM_Y_BASE`（基准 Y），全长 2400px。**无段间缝隙问题**（单一 shape 而非 3 段拼接）——但视觉上仍画 3 段平台（雪堆起伏 + 平台剪影分段），满足 issue「雪地 3 条平台」的字面构图。
- **碰撞参数（constants 场景分区 §3.2）：** `STAGE_WIDTH_PX = 2400`、`PLATFORM_Y_BASE`（候补 560）、`PLATFORM_THICKNESS_PX`（候补 24）、`PLATFORM_VISUAL_SEGMENTS = 3`。
- **视觉高差（60-100px 的落地方式）：** `SnowDriftFront` 为 3 段白色 Polygon2D 雪堆，顶面贴近碰撞面、底面比基准面低 `SNOW_DRIFT_DEPTH_MIN/MAX`（60/100px 候补），形成「雪原起伏」错觉；`PlatformSilhouetteMid/Back` 为 2 层墨色平台剪影（分别比基准面高/低 30-50px），强化三层纵深。**碰撞面恒定 = AC1「可通行无阻碍」在 `velocity.y=0` 模型下严格成立**（PRD §4.1-A 核心论点）。
- **Edge overlap：** 单一 shape 无拼接缝隙；若未来改 3 段拼接，相邻段重叠 ≥4px（PRD §5.2-1 采纳为 test 断言）。

#### 2.1.2 草屋剪影（Polygon2D 墨色 + 屋顶压雪线）

- **结构：** `HouseLeft/HouseRight`，每个含 `Hut (Polygon2D)` + `RoofSnowLine (Line2D)`。
- **几何：** 屋体矩形 Polygon2D（墨色 `STAGE_INK_COLOR` ≈ #1a1f26 同源）+ 三角屋顶 Polygon2D（同色）；屋脊高 ≤ `HOUSE_RIDGE_HEIGHT_MAX`（候补 120px，PRD 约束「屋舍低矮」）；宽扁（横向扁平，地雷战乡村空间感）。
- **屋顶压雪：** `RoofSnowLine (Line2D)` 白色（`SNOW_LAYER_COLOR`，alpha 0.6 同雪层），沿屋脊与檐口画折线（压雪线视觉：屋顶边缘积雪）。
- **位置：** 左右两侧 x≈300 / x≈1900（PRD §4.3 建议），y 底边贴平台碰撞面。

#### 2.1.3 枯树（Line2D 骨架剪影）

- **结构：** `TreeLeft/TreeRight (Line2D)`，如骨枝杈：主干 + 2-3 级分杈（`points` 折线声明在 .tscn），width ≈ 3-5px，墨色（`STAGE_INK_COLOR`）。
- **位置：** 平台边缘/屋旁 x≈900 / x≈1500（PRD §4.3）。

#### 2.1.4 山峦（Line2D 多层远景）

- **结构：** `Mountains (Line2D)` 单节点多层折线（或多条 Line2D 子节点），远景剪影，墨色更淡（降饱和 `MOUNTAIN_COLOR`），位于地平线上方（y < 300 区域）。
- **计数口径：** 背景层**不计数**（issue「家具/物件」语义，PRD §4.3 口径：山峦/月亮属背景）。

#### 2.1.5 月亮（Mesh2D 径向渐变 + 光晕，方案 A）

- **结构：** `Moon (Mesh2D)` 径向渐变圆 + `MoonGlow`（光晕层）。
- **主路径（Spike 1 预期）：** Moon = Mesh2D + 径向渐变（ShaderMaterial 或 GradientTexture 程序化）；光晕 = `moon_glow.gdshader`（CanvasItem shader，同心 alpha 衰减，~20 行，零外部资源）。
- **回退路径（shader 编译失败/观感差）：** MoonGlow = 第二层更大半透明圆（同构图，零 shader 依赖，PRD §4.2 方案 A 回退）；**不阻塞 AC2**。
- **色值：** 月亮主体冷白 `MOON_COLOR`（#b8c4d9 同源 MOONLIGHT_COLOR_TARGET，PRD §4.2）；位置高处 y≈120-160px（苍月悬顶），x≈居中偏右（构图焦点）。
- **层契约：** 挂 layer 0（被唯一 Moonlight 染色，与 #582 契约一致）；**非 CanvasModulate**（C3 守卫：全场景 CanvasModulate 计数 == 1，本场景零新增）。

#### 2.1.6 出生点（Marker2D ×3）

- **结构：** `PlayerSpawn` / `EnemySpawnA` / `EnemySpawnB`（Marker2D），坐标声明在 .tscn。
- **契约（#585/#581 对接）：** #585 组装时在 PlayerSpawn 实例化玩家实体、在 EnemySpawnA/B 实例化 2 个敌人实体；`EnemyAI.waypoints` 数据坐标由本 .tscn 提供（EnemySpawnA/B 自身 + 巡逻路径 Marker，或 .tscn 内手填 waypoints 数组——实现期二选一，test 断言 waypoints 非空且与出生点同基准 Y）。
- **布局断言：** 出生点不与草屋/枯树包围盒相交、不落入平台内部（PRD §5.2-3，test §8 B3）。

#### 2.1.7 相机（Camera2D，方案 A）

- **结构：** `StageCamera (Camera2D)`，`current = true`、`position_smoothing_enabled = false`（硬切，PRD §4.4-A 注明可关闭平滑）、`limit_left/right = 0/2400`、`limit_top/bottom` 覆盖视口高（含 margin，防贴边露白，PRD §5.2-2）。
- **职责：** 2400px 场景在 1280px 窗口下的全貌跟随；E2E 截图/手动运行即见全貌（AC5 前提）；#585 若需战斗聚焦逻辑可再调整（非本 issue 范围）。

### 2.2 e2e_battle_stage_capture.tscn — E2E 截图像具场景

- **File:** `shandong-wolf/scenes/e2e_battle_stage_capture.tscn`
- **Node structure：**

```
CaptureRig (Node2D)                                    # 根（e2e_capture.gd 驱动契约: state_node/state_property）
├── BattleStage (instance of battle_stage.tscn)        # 本体（layer 0 几何 + 相机）
├── Atmosphere (instance of atmosphere_layer.tscn)     # 复用 #582 氛围（唯一 Moonlight + 雪幕 + 水墨）
└── CaptureDummy (Node2D, script=e2e_battle_stage_capture.gd)  # 驱动桩: current_state 轮询 + settle 控制
```

- **职责：** 供 e2e harness 驱动的截图场景——全景/平台近景/月亮构图 3 shot（AC5 用户裁决输入物）；instance battle_stage + Atmosphere 复用 #582 效果（PRD §3.1 / §5.2-7：capture 场景加载顺序中唯一 moon 归属 Atmosphere，battle_stage 几何被动染色，断言染后效果而非节点归属）。
- **驱动契约（与 framework e2e_capture.gd 兼容）：** `current_state: int` 属性轮询目标 + `settle_frames` 匹配（3 shot 均为静态构图，settle 帧数取 15-30）。
- **Integration notes：** e2e_shots.json `battle_stage` 组 `main_scene` 指向本场景；若 #586 harness 未接入，实现 PR 用 headless 截图脚本产出 3 张 PNG 附 PR。

### 2.3 moon_glow.gdshader（可选，月亮光晕）

- **File:** `shandong-wolf/gdscripts/moon_glow.gdshader`
- **shader_type：** `canvas_item`（headless 编译安全，mini-pong vignette/ink_wash 同构已验证）。
- **职责：** 月亮光晕——同心 alpha 衰减（冷白 #b8c4d9 系），`hint_range` 约束强度/半径（taste-draft 参数，constants 场景分区 `MOON_GLOW_*` 提供默认）。
- **回退：** 若 Spike 1 截图对比不达标或编译问题，删除 shader 改用双层半透明圆（§2.1.5 回退路径），架构不变。

---

## 3. 既有组件修改

### 3.1 文件清单总表

| 类别 | 文件 | 变更性质 |
|------|------|---------|
| 新建 | `shandong-wolf/scenes/battle_stage.tscn` | SW-012 本体（§2.1，纯声明式） |
| 新建 | `shandong-wolf/scenes/e2e_battle_stage_capture.tscn` | E2E 截图像具场景（§2.2） |
| 新建 | `shandong-wolf/gdscripts/moon_glow.gdshader` | 月亮光晕 shader（§2.3，可选；Spike 1 裁决） |
| 新建 | `shandong-wolf/tests/test_battle_stage.gd` | 场景结构单测（§8 用例描述） |
| 修改 | `shandong-wolf/gdscripts/constants.gd` | 尾部追加「场景参数」# DRAFT 分区（§3.2） |
| 修改 | `shandong-wolf/e2e_shots.json` | 追加 `battle_stage` 组（§3.3） |
| 修改 | `shandong-wolf/tests/run_tests.gd` | 挂载 test_battle_stage.gd（§3.4） |
| 移除/弃用 | 无 | — |
| 受影响测试 | `shandong-wolf/tests/test_atmosphere.gd` | 不改（C3 守卫继续保护；新测试 C4 同样断言） |
| 受影响测试 | `shandong-wolf/tests/test_constants.gd` | 不改（场景分区断言归 test_battle_stage.gd，防跨套件耦合，同 #582 模式） |

### 3.2 constants.gd — 追加「场景参数」分区（文件尾部，格式照 #572/#582 既有分区）

```gdscript
# ── 场景参数（# DRAFT 候补值，定稿 = #583 E2E 截图用户裁决）──
#   分区: 舞台尺寸 STAGE_* / 平台 PLATFORM_* / 色板 *COLOR / 月亮 MOON_* / 物件 HOUSE_* TREE_* MOUNTAIN_*
#   定稿机制: implement PR 附 battle_stage 组 3 shot 截图 → 用户 AC5 裁决（taste-draft；构图/配色归用户）
#   硬约束: 坐标/尺寸声明在 .tscn（本分区为声明参考值，test 断言一致防漂移）；物件 ≤5；零外部贴图

# ── 舞台尺寸（机械常量，骨架期定稿）──
#   候补值: 场景总宽 2400px（issue AC1 字面值）；视觉平台 3 段；高差 60-100px（视觉分层，非碰撞）
#   该值影响什么: 战斗移动空间宽度——2400px > 窗口 1280px，必须配 Camera2D 才能全貌可见
#   情感断言: 横向扁平、屋舍低矮——地雷战乡村空间感（横向构图优先，禁止竖向高塔/城堡）
const STAGE_WIDTH_PX: int = 2400          # AC1: 场景总宽（.tscn 根节点宽度声明参考值）
const STAGE_VISUAL_SEGMENTS: int = 3      # AC1: 雪地平台 3 段（视觉分段，碰撞单一连续面）

# ── 平台（# DRAFT 候补值，待 #583 用户裁决）──
#   候补值: 基准 Y=560（碰撞顶面）；厚度 24px；视觉雪堆深度 60-100px（高低错落 3 段）；相邻段重叠 ≥4px（防缝隙，若改拼接式）
#   该值影响什么: 角色站立高度 + 雪原起伏观感——碰撞面恒定是 AC1「可通行无阻碍」在 velocity.y=0 模型下的唯一严格解
#   情感断言: 雪原起伏但脚下踏实——视觉有高低错落，角色行走零阻塞
const PLATFORM_Y_BASE: float = 560.0          # # DRAFT（碰撞顶面基准 Y）
const PLATFORM_THICKNESS_PX: float = 24.0     # # DRAFT（碰撞体厚度）
const SNOW_DRIFT_DEPTH_MIN: float = 60.0      # # DRAFT（视觉雪堆深度下界，AC1 高差 60px）
const SNOW_DRIFT_DEPTH_MAX: float = 100.0     # # DRAFT（视觉雪堆深度上界，AC1 高差 100px）
const PLATFORM_SEGMENT_OVERLAP_PX: float = 4.0 # # DRAFT（拼接式边缘重叠，防缝隙；单一 shape 时仅作断言参考）

# ── 色板（# DRAFT 候补值，待 #583 用户裁决；#1a1f26 同源 INK_COLOR，与 #582 水墨一致）──
#   候补值: 墨色 #1a1f26（墙体/枯树/平台剪影，染后 luma ≥30 约束 #624 F3）；雪层冷白 α0.6；月亮冷白 #b8c4d9 同源
#   该值影响什么: 冷墨色调整体观感——AC2 硬约束「整体为冷墨色调」；色板过黑 → 月光染后 luma < 30 违反 #624
#   情感断言: 大地如墨、雪压屋顶——黄土+雪的组合（屋顶压雪、墙体墨色、枯树如骨）
const STAGE_INK_COLOR: Color = Color("#1a1f26")   # # DRAFT（墨色主体，同源 INK_COLOR）
const SNOW_LAYER_COLOR: Color = Color(0.92, 0.95, 0.98, 0.6)  # # DRAFT（雪层冷白，alpha 0.6 字面约束）
const MOUNTAIN_COLOR: Color = Color("#232a33")    # # DRAFT（山峦远景，较主体淡一档）
const MOON_COLOR: Color = Color("#b8c4d9")        # # DRAFT（月亮冷白，同源 MOONLIGHT_COLOR_TARGET）

# ── 月亮（# DRAFT 候补值，待 #583 用户裁决）──
#   候补值: 半径 42px；位置 y≈120-160（苍月悬顶）；光晕强度/半径（taste-draft）
#   该值影响什么: 「苍月悬顶」构图焦点——月亮是场景情绪光源（视觉焦点），染后与 #582 月光色温同源
#   情感断言: 苍月悬顶——冷白月亮是雪夜最亮的视觉锚点，构图焦点而非装饰
const MOON_RADIUS_PX: float = 42.0            # # DRAFT（月亮主体半径）
const MOON_POSITION_Y: float = 140.0          # # DRAFT（苍月悬顶，y<150 区域）
const MOON_GLOW_STRENGTH: float = 0.35        # # DRAFT（光晕峰值 alpha，shader hint_range 上界）
const MOON_GLOW_RADIUS_RATIO: float = 2.2     # # DRAFT（光晕半径 = 主体 × 2.2）

# ── 物件（机械布局参考，坐标在 .tscn 声明）──
#   候补值: 草屋 ×2（屋脊 ≤120px，x≈300/1900）；枯树 ×2（x≈900/1500）；山峦/月亮为背景不计数
#   该值影响什么: 物件预算（≤5 硬约束，防噪杂）+ 空间锚点（玩家方位感）
#   情感断言: 克制——4 件家具/物件是极限，多一件即噪杂（反例: 日式鸟居/西式城堡禁止）
const HOUSE_RIDGE_HEIGHT_MAX: float = 120.0   # 机械常量（屋脊高度上限，低矮扁平）
const OBJECT_BUDGET_MAX: int = 5              # 机械常量（物件 ≤5，issue 硬约束）
```

> ⚠️ 实现期说明：以上为**声明参考值**；实际坐标/尺寸**必须写在 .tscn**（红线：禁止脚本写死）。test 断言 constants 与 .tscn 一致（§8 A2/A3），防双源漂移。

### 3.3 e2e_shots.json — 追加 battle_stage 组

| 变更 | 内容 | 为什么 |
|------|------|--------|
| `groups` 追加 `battle_stage` 组 | `main_scene` = `res://scenes/e2e_battle_stage_capture.tscn`；`state_node/state_property` 指向 CaptureRig；3 shot：`01_stage_panorama`（全景，settle 30）/ `02_platform_closeup`（平台近景，settle 15）/ `03_moon_composition`（月亮构图，settle 15）；`_comment` 注明「#583 battle_stage 组供用户 AC5 裁决：地域感（无日本/西化元素）」 | PRD §3.1/§8.2：AC5 需要 battle_stage 截图组；v2 schema（groups[].shots[]）与既有三组兼容 |

> ⚠️ 实现期说明：若 #586 完整 harness 未接入（当前 shandong-wolf e2e 为占位态），实现 PR 用 `godot --path shandong-wolf/ --headless` + 截图脚本产出 3 张 PNG 附 PR——**PR 必须附截图**（AC5 用户裁决输入物，PRD §8.2-5）。

### 3.4 tests/run_tests.gd — 挂载新套件

| 变更 | 内容 | 为什么 |
|------|------|--------|
| `_run_tests()` 追加一行 | `_run("res://tests/test_battle_stage.gd", "BattleStage")` | 新套件纳入三入口（#572 模式，追加式无并发改写） |

---

## 4. 数据流

### Flow 1: 场景加载（正常路径）

```
#585 组装后 main_scene = Main.tscn
  → BattleStage 实例 _ready（纯声明式，无脚本）
  → Ground StaticBody2D + CollisionShape2D 就位（layer 0）
  → 视觉层就位: SnowDriftFront/PlatformSilhouette/草屋/枯树/山峦/月亮（全部 layer 0，被唯一 Moonlight 染色）
  → StageCamera current=true，limits 覆盖 2400px → 战斗视口成立
  → 玩家/敌人（#585 实例化）置于 PlayerSpawn/EnemySpawnA/B → move_and_slide 落地（碰撞面生效）
  → #585 配置 EnemyAI.waypoints（本场景坐标）→ 敌人巡逻/追击/攻击闭环
```

### Flow 2: E2E 截图裁决（AC5 路径）

```
e2e_battle_stage_capture.tscn 加载
  → CaptureRig 内 BattleStage + Atmosphere 同屏（唯一 moon 归属 Atmosphere，battle_stage 被动染色）
  → e2e harness（或 headless 截图脚本）按 battle_stage 组 3 shot 截图（全景/近景/月亮）
  → PNG 附实现 PR + issue 评论 + assign 用户 → 用户裁决地域感（无日本元素/无西化元素）
  → ≥70% 认可 → 定稿；<70% → 改 constants 候补值（色板/月亮参数）重跑（taste-draft 迭代，Flow 3）
```

### Flow 3: 调参/定稿（taste-draft 路径）

```
用户裁决 < 70% 或观感偏差
  → 改 constants.gd 场景分区候补值（STAGE_INK_COLOR / MOON_* / SNOW_DRIFT_DEPTH_*）——只改常量
  → 同步改 .tscn 声明坐标（test A2/A3 断言一致性防漂移）
  → 重跑 E2E 截图 → 再裁决（# DRAFT 机制吸收迭代）
```

### Flow 4: 失败路径（碰撞错位 / shader 编译失败）

```
平台 CollisionShape2D 与视觉雪层错位（角色悬空/穿地）
  → test B1 断言（角色站平台时 global_position.y 与顶面差 < 1px）红 → 修正 .tscn
  → 或 moon_glow.gdshader 语法错误 → check_compile 遍历 load 失败 → CI 红
  → 回退: 删除 shader 改双层半透明圆（§2.1.5 回退路径，不阻塞 AC2）
  → 修复 → 重跑三入口 + 截图复核（PRD §5.3-1/2）
```

---

## 5. 边界情况与错误处理

| 边界情况 | 缓解措施 |
|---------|---------|
| 平台段间缝隙（若改拼接式 3 段） | 单一连续 CollisionShape2D（方案 A 核心，无缝隙）；拼接式预留重叠 ≥4px + test A3 断言（PRD §5.2-1） |
| 窗口 stretch 与 2400px 场景（1280x720 固定窗口） | StageCamera limits 覆盖 0-2400 全宽 + 上下 margin；玩家贴边相机不越界露白（PRD §5.2-2，test D2） |
| 出生点与物件重叠（草屋/枯树遮挡） | 布局断言：PlayerSpawn/EnemySpawnA/B 与物件包围盒无交集、不在平台内部（PRD §5.2-3，test B3） |
| 月光染后可见性（luma ≥30，#624 F3） | 色板选墨色系但不过黑（#1a1f26 染后 ≈ 预期内）；test C3 断言染后 luma ≥30 |
| 月亮光晕 shader 编译失败/观感差 | 回退双层半透明圆（同构图，零 shader 依赖）；Spike 1 先行验证（PRD §5.2-5 / §7 E1） |
| C3 守卫误伤（CanvasModulate 计数 == 1） | 本场景**零新增 CanvasModulate**（月亮是 Mesh2D 不是光照）；test C4 断言全场景计数 == 1（#624 延续） |
| e2e capture 场景加载顺序（唯一 moon 归属） | capture 场景 instance battle_stage + Atmosphere；唯一 moon 归 Atmosphere（layer 0），断言染后效果而非节点归属（PRD §5.2-7） |
| 场景文件 uid/路径错误 | check_compile 遍历自动纳入（#572 机制），battle_stage.tscn 引用失败即红（PRD §5.3-1） |
| 碰撞体与视觉错位（角色悬空/穿地） | test B1（角色站平台 y 差 < 1px）+ E2E 截图人工复核（PRD §5.3-2） |
| 物件超预算（实现贪多 >5） | test A4 计数断言（草屋 2 + 枯树 2 = 4 ≤ 5）拦截（PRD §5.3-3） |
| 相机 limits 配置错误（空白/越界） | E2E 全景 shot 人工可见，列入 AC5 裁决（PRD §5.3-4） |
| 性能不达标（AC4 ≥60fps） | 场景零新增粒子、静态几何成本可忽略；Phase 0 Spike 3 Mac 基准（PRD §7 E3）；若不足降物件复杂度（≤5 内）而非降粒子预算（#582 红线） |

---

## 6. 集成点

> **Status convention：** ⬜ = pending（资源已创建，尚未连接到目标）。✅ = connected（implement agent 验证）。implement agent 必须在此表更新接线状态；review agent merge 前验证所有 ⬜ 已解决或显式延期。

| 集成 | 本组件 | 目标 | 如何连接 | 状态 |
|------|:---:|:---:|---------|:---:|
| 场景挂载 | `battle_stage.tscn` 实例 | Main.tscn 根节点 | #585 组装时 instance 进 Main.tscn（**不重复挂 Atmosphere**，Main.tscn 已有） | ⬜ pending（显式延期至 #585） |
| 出生点契约 | `PlayerSpawn` / `EnemySpawnA` / `EnemySpawnB` (Marker2D) | #585 玩家/敌人实例化 | #585 在 Marker 坐标实例化实体（bind_entity / player / judge 注入） | ⬜ pending（显式延期至 #585） |
| waypoints 数据 | battle_stage.tscn 巡逻路径坐标 | `EnemyAI.waypoints` @export（#581） | #585 从 .tscn 坐标配置 EnemyAI.waypoints（空数组=原地等待不报错，已核实） | ⬜ pending（显式延期至 #585） |
| 氛围共存 | battle_stage 几何（layer 0） | Atmosphere（#582，唯一 Moonlight 染 layer 0） | 层契约共存：几何挂 layer 0 被动染色；场景内**零 CanvasModulate**（C3 守卫） | ✅ connected（implement #583 验证） |
| E2E 截图 | e2e_battle_stage_capture.tscn + e2e_shots.json `battle_stage` 组 | #586 完整 harness / 用户 AC5 裁决 | #586 接入 harness 时自动生效；本 issue 实现 PR 用 headless 截图附 PR（AC5） | ⬜ pending（显式延期至 #586 或实现 PR 截图） |
| 测试挂载 | `tests/test_battle_stage.gd` | run_tests.gd | `_run_tests()` 追加 `_run(...)` 一行（§3.4） | ✅ connected（implement #583 验证） |
| 参数单一事实源 | constants.gd 场景分区（§3.2） | battle_stage.tscn 声明坐标 | .tscn 手填坐标与常量一致；test A2/A3 断言一致性防漂移 | ✅ connected（implement #583 验证） |

---

## 7. 实现阶段

| Phase | 优先级 | 组件 | 内容 | 估计 |
|:-----:|:------:|------|------|:----:|
| Phase 0 | P0 | Spike 验证（PRD §7 三实验） | ① 月亮光晕 3 变体截图（shader 同心衰减/双层圆/单圆）定主路径与回退；② 全宽走查（CharacterBody2D x=0→2400 零阻塞）；③ Mac 帧率基准（battle_stage + Atmosphere ≥60fps） | 0.5d |
| Phase 1 | P0 | constants.gd 场景分区 | 尾部追加「场景参数」# DRAFT 分区（§3.2 源码可直接采用） | 0.5d |
| Phase 2 | P0 | battle_stage.tscn 本体 | 平台（Ground StaticBody2D + 视觉分层）/ 草屋×2 + 屋顶压雪线 / 枯树×2 / 山峦 / 月亮（Mesh2D + moon_glow 或双层圆）/ Marker2D ×3 / StageCamera（§2.1 全树） | 1d |
| Phase 3 | P0 | E2E 组件 + 挂载 | e2e_battle_stage_capture.tscn（instance battle_stage + Atmosphere）+ e2e_shots.json battle_stage 组 + run_tests.gd 挂载（§2.2/§3.3/§3.4） | 0.5d |
| Phase 4 | P0 | 测试套件 | test_battle_stage.gd（§8 用例描述） | 0.5d |
| Phase 5 | P0 | E2E 截图 + 用户裁决 | headless 截图 3 shot 附 PR + issue 评论 + assign 用户（AC5；taste-draft 定稿接口） | 0.5d |

---

## 8. 测试用例描述

> 仅描述测试场景，不写可运行测试代码（plan 阶段红线；实现由 implement agent 完成，落 `shandong-wolf/tests/test_battle_stage.gd`，套件模式照 test_constants.gd / test_atmosphere.gd：`passed/failed` 计数 + `run()`）。

### Scenario A: 场景结构与参数集中（test_battle_stage.gd）
- **A1（场景可加载）**: `battle_stage.tscn` load + instantiate 成功（parse 错误即 FAIL）；根节点 BattleStage 存在。
- **A2（场景总宽 2400px，AC1）**: 断言场景可视宽度 == `STAGE_WIDTH_PX`（2400）——Ground CollisionShape2D 矩形宽 == 2400，且与 constants 一致（防双源漂移）。
- **A3（平台 3 段 + 单一碰撞面）**: 视觉平台分段数 == 3（SnowDriftFront 分段 Polygon2D 计数）；碰撞体为**单一连续** StaticBody2D + CollisionShape2D（非 3 段拼接，无缝隙结构性保证）；若实现为拼接式，相邻段重叠 ≥ `PLATFORM_SEGMENT_OVERLAP_PX`（4px）。
- **A4（物件预算 ≤5）**: 草屋 Polygon2D 节点数 == 2 + 枯树 Line2D 节点数 == 2 → 物件计数 4 ≤ `OBJECT_BUDGET_MAX`（5）；山峦/月亮不计数。
- **A5（零外部贴图）**: battle_stage.tscn 源码无 `ext_resource` 指向 .png/.jpg/.webp（仅 PackedScene 引用）；无 CanvasModulate 节点（C3 延续，全场景计数 == 1 由 C4 断言）。

### Scenario B: 碰撞与出生点（test_battle_stage.gd）
- **B1（碰撞体可阻挡）**: 放置 CharacterBody2D 于平台顶面 → `move_and_slide()` 后 `global_position.y` 与 `PLATFORM_Y_BASE` 差 < 1px（不穿透，AC3）；从平台边缘外下落（模拟无重力模型下被推出）不穿底。
- **B2（全宽走查零阻塞，AC1 + Spike 2）**: 驱动 CharacterBody2D 从 x=0 匀速移至 x=2400（velocity.y=0 模型），断言每帧位移连续（无碰撞卡顿/跌落/卡缝）；全程 y 保持 == PLATFORM_Y_BASE。
- **B3（出生点布局）**: Marker2D ×3（PlayerSpawn/EnemySpawnA/EnemySpawnB）存在且坐标在 .tscn 声明（非脚本写入）；与草屋/枯树包围盒无交集、不在平台内部（AC3，PRD §5.2-3）。

### Scenario C: 视觉与色板（test_battle_stage.gd）
- **C1（冷墨色调，AC2）**: battle_stage.tscn 中 Polygon2D/Line2D 主体颜色与 `STAGE_INK_COLOR`（#1a1f26 同源）色差 ≤10%（±0.1 RGB）；雪层 `SNOW_LAYER_COLOR` alpha == 0.6；月亮 `MOON_COLOR` 与 #b8c4d9 同源。
- **C2（月亮构图）**: Moon Mesh2D 存在；`MOON_POSITION_Y` < 150（苍月悬顶）；MoonGlow 存在（shader 或双层圆回退）。
- **C3（月光染后 luma ≥30，#624 F3）**: 模拟唯一 Moonlight 染色（#6e7684）后，平台/屋体采样色 luma ≥ 30（色板不过黑）。
- **C4（CanvasModulate 计数 == 1）**: 全场景（Main + battle_stage + Atmosphere 组装态）CanvasModulate 节点计数 == 1（#624 C3 守卫延续；battle_stage 自身零新增）。

### Scenario D: 相机（test_battle_stage.gd）
- **D1（相机存在 + current）**: StageCamera (Camera2D) 存在且 `current == true`；`limit_left == 0`、`limit_right >= STAGE_WIDTH_PX`（2400）。
- **D2（贴边不露白）**: 模拟相机移动到 x=0 与 x=2400 极限位，视口内无超出场景边界的空白（limits 含 margin，PRD §5.2-2）。

### Scenario E: 三入口回归（CI / 本地）
- **E1（check_compile）**: `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` 退出 0，count 覆盖新增 .gd/.gdshader（#572 自动纳入机制）。
- **E2（run_tests）**: `... --script tests/run_tests.gd` 退出 0，输出「TESTS: N passed, 0 failed」且 N ≥ 原 11 套件用例数 + 本套件 A-D 用例数；pass==0 → 退出非 0（防挂载遗漏静默绿）。
- **E3（主场景冒烟）**: `godot --path shandong-wolf/ --headless --quit` 退出 0（autoload + Main.tscn 启动链兼容，battle_stage 未挂载期不回归）。
- **E4（E2E 截图）**: e2e_battle_stage_capture 场景 3 shot（全景/平台近景/月亮构图）PNG 非黑屏非全白、文件非空（AC5 输入物；人工复核地域感）。

### Scenario F: 性能（AC4）
- **F1（Mac 帧率基准）**: battle_stage + Atmosphere 同屏 headless + 真实渲染各测 60s，帧时间均值换算 ≥60fps、1% low 无断崖（沿用 #582 fps 断言口径，PRD §7 E3）；若不足降物件复杂度（≤5 内）而非降粒子预算（#582 红线）。

---

## 9. 验收条件映射（源自 Issue #583 body）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | 场景总宽 2400px，地面平台 3 段，可通行无阻碍 | §2.1.1 单一碰撞面 + 视觉 3 段 + §3.2 STAGE_*/PLATFORM_* 常量 | A2/A3（宽度 + 分段 + 单一碰撞面）+ B2（全宽走查） |
| AC2 | 草屋/枯树/月亮/山峦剪影均以 Polygon2D/Line2D 程序化绘制且整体为冷墨色调 | §2.1.2–2.1.5 程序化剪影 + §3.2 色板 | C1/C2（色板断言 + 月亮构图）+ A5（零贴图）+ E4 截图用户裁决 |
| AC3 | 玩家出生点与 2 个敌人出生点正确放置，碰撞体可阻挡角色 | §2.1.6 Marker2D ×3 + §2.1.1 Ground 碰撞 | B1/B3（阻挡 + 布局）+ A2（宽度） |
| AC4 | 场景加载后帧率 ≥60fps（Mac 基准测试） | §2.1 纯静态几何零粒子 + §7 Phase 0 Spike 3 | F1（Mac 帧率基准） |
| AC5 | E2E 截图提交用户裁决：场景是否符合『雪夜山东村』的地域感（无日本元素、无西化元素） | §2.2 capture 场景 + §3.3 battle_stage 组 3 shot + §7 Phase 5 | E4 截图 + 用户主观评分（taste-draft：认可定稿，不认可走 Flow 3 参数迭代） |
| 附加红线 | 层契约（几何挂 layer 0，全场景 CanvasModulate 计数 == 1）；场景尺寸/坐标全部 .tscn 声明；参数集中 constants.gd 场景分区 # DRAFT + 情感断言；零外部美术资产 | §2.1 全树 + §3.2 + 文件头红线注释 | A5/C4（零贴图 + 计数）+ A2/A3（常量一致）+ implement PR diff 核查无 .png/.jpg 新增 |

---

## 10. 明确不修改（与 PRD §8 红线对齐）

- ❌ `mini-pong/` 任何文件（跨游戏红线）
- ❌ `shandong-wolf/scenes/Main.tscn`（#585 组装时挂载 battle_stage，本 issue 不改）
- ❌ `shandong-wolf/gdscripts/player_controller.gd` / `enemy_ai.gd` / `atmosphere_controller.gd`（移动模型/AI/氛围编排零改动，被动受益或层契约共存）
- ❌ `shandong-wolf/tests/check_compile.gd`、`smoke_test.gd`（#572 机制自动纳入新脚本，零改动）
- ❌ `shandong-wolf/tests/test_atmosphere.gd` / `test_constants.gd`（C3 守卫继续保护；新断言归 test_battle_stage.gd，防跨套件耦合）
- ❌ `game-env/manifest.yaml`、`.github/workflows/`、`scripts/`（管线参数化已自动跟随）
- ❌ `docs/GAME_DESIGN/`（`14-SCENE-BATTLE-STAGE.md` 落盘是 post-merge agent 职责）
- ❌ #585 组装 / #581 AI / #582 氛围 / #575 玩家实体 / #576 HUD / #586 完整 E2E 剧本（范围边界见 PRD §1.3）
- ❌ 任何外部美术资产 / 插件 addon / 像素帧 / 贴图（AC2 红线 + PRD 硬约束）
- ❌ 新增任何 CanvasModulate（#624 C3 守卫，全场景唯一 Moonlight 归 Atmosphere）
- ❌ 场景坐标/尺寸写死进脚本（全部 .tscn 声明，可编辑）
- ✅ constants.gd 既有分区（手感/氛围/AI）保持原样（只在文件尾部追加场景分区）
