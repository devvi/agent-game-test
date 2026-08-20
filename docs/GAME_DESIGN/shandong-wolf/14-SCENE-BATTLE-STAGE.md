# 战斗舞台场景 — 雪夜山东村单场景 MVP 舞台（#583/#646）

> 落盘依据：PR **#646**（feat(583) 雪夜山东村战斗场景，已 merge 2026-08-20）← DESIGN
> `docs/DESIGN/583-snowy-shandong-village-battle-stage.md`（plan PR #645 已 merge）。
> 上游：#583 单场景 MVP 舞台（PRD/DESIGN，`content_ownership: mechanical`——场景几何/碰撞/
> 出生点布局 = 机械工程；构图/配色 = taste-draft，AC5 E2E 截图归用户裁决）。
> ✅ 代码状态：#646 已合并，`battle_stage.tscn` / `e2e_battle_stage_capture.tscn` /
> `moon_glow.gdshader` / `test_battle_stage.gd` / constants.gd「场景参数」分区全部落地 **main**
> （2026-08-20）。机械部分（2400px 舞台/单一碰撞面/出生点/相机/层契约）已定稿；色板与月亮
> 参数仍属 taste 域（`# DRAFT`，归 #583 AC5 用户 E2E 截图裁决）。

## 1. 设计意图

**问题本质是「战斗没有发生地」。** #572（地基）/ #574（火柴人剪影）/ #582（雪夜氛围四层）
合入后，玩家与敌人已具备移动/战斗/动画能力，但**没有物理地面**（无 StaticBody2D，
`velocity.y = 0.0` + `move_and_slide()` 悬空执行）、**没有空间叙事**（草屋/枯树/苍月无视觉
载体）、**没有出生点坐标契约**（#581 DESIGN 显式要求「#583 场景 → EnemyAI.waypoints」）。
本场景 = 独立世界层场景 `battle_stage.tscn`，一次性补齐几何 + 碰撞 + 剪影 + 出生点 + 相机，
是 #585 组装（战斗闭环挂载）的前置依赖。

设计哲学四条（与 PRD §4 推荐方案逐项对齐，无分歧）：

1. **纯声明式几何**：场景根 BattleStage = Node2D 零脚本；全部坐标/尺寸写在 .tscn（红线：
   禁止脚本写死，可编辑）。
2. **参数单一事实源**：所有视觉/尺寸参数集中 constants.gd「场景参数」分区（`# DRAFT` 候补值 +
   情感断言），.tscn 手填坐标与常量一致，test 断言两者一致防双源漂移。
3. **程序化零贴图**：渲染全部 Polygon2D/Line2D/Mesh2D 程序化生成（开源调研结论：无成熟 2D
   platformer level 模板可复用 → 自行实现），零 .png/.jpg/.webp。
4. **可通行优先**：平台走「同一基准碰撞面 + 视觉分层高差」——碰撞面恒定是 `velocity.y=0`
   移动模型下 AC1「可通行无阻碍」的**唯一严格解**（单一连续 shape，无段间缝隙问题）。

## 2. 架构决策

| 决策点 | 采纳方案 | 否决方案 | 否决理由 |
|--------|---------|---------|---------|
| 平台 | A：单一连续碰撞面（Ground StaticBody2D 顶面 y = PLATFORM_Y_BASE）+ 视觉 3 段雪堆分层（高差 60-100px） | B：3 段拼接碰撞体 | 拼接有段间缝隙风险；A 无缝隙 + 满足「雪地 3 条平台」字面构图（AC1） |
| 月亮 | A：Mesh2D 径向渐变圆 + `moon_glow.gdshader` 光晕（同心 alpha 衰减） | 双层半透明圆（回退） | shader 主路径；回退仅用于编译失败/观感差，架构不变 |
| 物件布局 | 草屋×2（Polygon2D 墨色剪影 + 屋顶压雪 Line2D）+ 枯树×2（Line2D 骨架）= 4 ≤ 5 | 更多物件 | issue 硬约束「家具/物件 ≤5 防噪杂」；山峦/月亮属背景不计数 |
| 相机 | A：场景内 StageCamera（Camera2D，current=true，limits 0-2400） | 无相机/外部控制 | 2400px > 1280px 窗口，必须相机才能全貌可见（AC5 前提） |
| 出生点 | `PlayerSpawn` / `EnemySpawnA` / `EnemySpawnB`（Marker2D ×3，坐标 .tscn 声明） | 脚本写入 | 声明式红线 + #585 实例化契约 + #581 waypoints 数据源 |
| 色板（self-correct R1） | `STAGE_INK_COLOR` = **#4a5664**（实现期调亮） | 原候补 #1a1f26 | #1a1f26 染后 luma 0.055 < 30 违反 #624 F3（月光染后可见性）；#4a5664 染后 luma ≈ 39/255 ≥ 30 |

## 3. 节点树（battle_stage.tscn 定义，main 实测）

```text
BattleStage (Node2D)                                    # 根，layer 0 世界层，零脚本
├── Ground (StaticBody2D)                               # 单一连续碰撞面（方案 A 核心）
│   └── CollisionShape2D                                # RectangleShape2D: 2400 × 24，顶面 y = PLATFORM_Y_BASE
├── PlatformVisual (Node2D)                             # 视觉分层高差（60-100px），零碰撞
│   ├── SnowDriftFront (Node2D) ── SnowDrift1/2/3 (Polygon2D)   # 前景雪堆 3 段，白色 α0.6
│   ├── PlatformSilhouetteMid (Polygon2D)               # 中景平台剪影（墨色）
│   └── PlatformSilhouetteBack (Polygon2D)              # 背景平台剪影（远景降饱和）
├── Houses (Node2D)
│   ├── HouseLeft (Node2D, x≈300)
│   │   ├── Hut (Polygon2D)                             # 草屋墨色剪影，屋脊 ≤120px 低矮扁平
│   │   └── RoofSnowLine (Line2D)                       # 屋顶压雪线：白色，沿屋脊折线
│   └── HouseRight (Node2D, x≈1900) ── Hut + RoofSnowLine
├── Trees (Node2D)
│   ├── TreeLeft (Line2D, x≈900)                        # 枯树如骨：枝杈骨架，墨色
│   └── TreeRight (Line2D, x≈1500)
├── Mountains (Line2D)                                  # 山峦远景：多层折线剪影（背景，不计数）
├── Moon (MeshInstance2D)                               # 苍月悬顶：QuadMesh 径向渐变
│   └── MoonGlow (MeshInstance2D)                       # 光晕：moon_glow.gdshader 或双层半透明圆（回退）
├── PlayerSpawn (Marker2D)                              # 玩家出生点（#585 实例化玩家）
├── EnemySpawnA (Marker2D)                              # 敌人 1 出生点
├── EnemySpawnB (Marker2D)                              # 敌人 2 出生点
└── StageCamera (Camera2D)                              # current=true，limits 覆盖 0-2400
```

**职责：** 单场景 MVP 战斗舞台的全部几何/碰撞/空间叙事/出生点/相机，零脚本、零新增
CanvasModulate、零外部贴图。E2E 截图像具场景 `e2e_battle_stage_capture.tscn` 以
CaptureRig 模式 instance 本场景 + Atmosphere（复用 #582 唯一 Moonlight），驱动
`e2e_shots.json` 的 `battle_stage` 组 3 shot（全景 / 平台近景 / 月亮构图）。

## 4. 参数（constants.gd「场景参数」分区，§3.2 声明参考值）

> 坐标/尺寸的**实际声明唯一事实源是 .tscn**；本分区为声明参考值（test 断言两者一致防漂移）。
> 定稿机制：E2E battle_stage 组截图 → 用户 AC5 裁决（taste-draft，构图/配色归用户）。

| 分组 | 常量 | 值 | 状态 | 意图 |
|------|------|----|:----:|------|
| 舞台尺寸 | `STAGE_WIDTH_PX` | 2400 | 机械定稿 | AC1 场景总宽；> 窗口 1280px → 必须配相机 |
| 舞台尺寸 | `STAGE_VISUAL_SEGMENTS` | 3 | 机械定稿 | AC1 雪地平台 3 段（视觉分段，碰撞单一连续面） |
| 平台 | `PLATFORM_Y_BASE` | 560.0 | # DRAFT | 碰撞顶面基准 Y（角色站立高度） |
| 平台 | `PLATFORM_THICKNESS_PX` | 24.0 | # DRAFT | 碰撞体厚度 |
| 平台 | `SNOW_DRIFT_DEPTH_MIN/MAX` | 60.0 / 100.0 | # DRAFT | 视觉雪堆深度（AC1 高差 60-100px，非碰撞） |
| 平台 | `PLATFORM_SEGMENT_OVERLAP_PX` | 4.0 | # DRAFT | 拼接式边缘重叠防缝隙（单一 shape 时仅断言参考） |
| 色板 | `STAGE_INK_COLOR` | #4a5664 | # DRAFT | 墨色主体（self-correct R1 调亮，染后 luma ≈ 39 ≥ 30） |
| 色板 | `SNOW_LAYER_COLOR` | (0.92, 0.95, 0.98, 0.6) | # DRAFT | 雪层冷白，alpha 0.6 字面约束 |
| 色板 | `MOUNTAIN_COLOR` | #536171 | # DRAFT | 山峦远景，较主体淡一档 |
| 色板 | `MOON_COLOR` | #b8c4d9 | # DRAFT | 月亮冷白，同源 MOONLIGHT_COLOR_TARGET |
| 月亮 | `MOON_RADIUS_PX` | 42.0 | # DRAFT | 月亮主体半径 |
| 月亮 | `MOON_POSITION_Y` | 140.0 | # DRAFT | 苍月悬顶（y < 150 区域） |
| 月亮 | `MOON_GLOW_STRENGTH` / `MOON_GLOW_RADIUS_RATIO` | 0.35 / 2.2 | # DRAFT | 光晕峰值 alpha / 半径 = 主体 × 2.2 |
| 物件 | `HOUSE_RIDGE_HEIGHT_MAX` | 120.0 | 机械定稿 | 屋脊高度上限（低矮扁平，地雷战乡村空间感） |
| 物件 | `OBJECT_BUDGET_MAX` | 5 | 机械定稿 | 物件 ≤5 硬约束（草屋 2 + 枯树 2 = 4） |

## 5. 层契约与挂载约定（与 #582/#624 定稿一致）

- 本场景几何挂 **layer 0 世界层**，被 Atmosphere 唯一 Moonlight（CanvasModulate #6e7684）
  被动染色；雪幕 3-5 / 水墨 2 / 血色 10 / UI 1 禁染。
- **全场景 CanvasModulate 计数 == 1**（C3 守卫，#624 延续）：月亮是 MeshInstance2D（天体）
  不是光照，battle_stage 内零新增 CanvasModulate。
- **#585 组装时**把 battle_stage instance 进 Main.tscn 根节点，**不重复挂 Atmosphere**
  （Main.tscn 已有 #582 实例）——本 issue 不改 Main.tscn。

## 6. 数据流

### Flow 1: 场景加载（#585 组装后）

```text
Main.tscn 加载 → BattleStage 实例 _ready（纯声明式）
  → Ground StaticBody2D + CollisionShape2D 就位（layer 0）
  → 视觉层就位: 雪堆/平台剪影/草屋/枯树/山峦/月亮（全部 layer 0，被唯一 Moonlight 染色）
  → StageCamera current=true，limits 0-2400 → 战斗视口成立
  → 玩家/敌人（#585 实例化）置于 PlayerSpawn/EnemySpawnA/B → move_and_slide 落地（碰撞面生效）
  → #585 配置 EnemyAI.waypoints（本场景坐标）→ 敌人巡逻/追击/攻击闭环
```

### Flow 2: E2E 截图裁决（AC5 taste-draft 路径）

```text
e2e_battle_stage_capture.tscn 加载（BattleStage + Atmosphere 同屏）
  → e2e_shots.json battle_stage 组 3 shot（全景/平台近景/月亮构图）
  → PNG 附实现 PR + 用户裁决地域感（无日本/西化元素）
  → 认可 → 色板/月亮参数定稿；不认可 → 改 constants 候补值 + 同步 .tscn → 重跑截图（# DRAFT 迭代）
```

## 7. 集成点契约

| 集成 | 契约 | 状态 |
|------|------|:----:|
| 场景挂载 | battle_stage instance 进 Main.tscn 根节点（#585 组装，不重复挂 Atmosphere） | ⬜ 显式延期至 #585 |
| 出生点 | PlayerSpawn / EnemySpawnA / EnemySpawnB 坐标 → #585 实例化玩家/敌人实体 | ⬜ 显式延期至 #585 |
| waypoints 数据 | 场景坐标 → `EnemyAI.waypoints` @export（#581；空数组 = 原地等待不报错） | ⬜ 显式延期至 #585 |
| 氛围共存 | 几何挂 layer 0 被动染色；零新增 CanvasModulate（C3 守卫） | ✅ connected（#646 验证） |
| E2E 截图 | `battle_stage` 组 3 shot（AC5 用户裁决输入物） | ✅ connected（#646 实现 PR 附截图） |
| 参数单一事实源 | constants 场景分区 ↔ .tscn 声明坐标，test A2/A3 断言一致 | ✅ connected（#646 验证） |

## 8. 红线与约束

- **零外部贴图**：battle_stage.tscn 无 ext_resource 指向 .png/.jpg/.webp（全程序化）。
- **禁新增 CanvasModulate**（C3 守卫全场景计数 == 1，月亮非光照）。
- **坐标/尺寸全部 .tscn 声明**，脚本零写死；constants 分区仅为声明参考值。
- **物件 ≤5**；禁日式鸟居/和风元素、禁西式城堡（地域感红线，AC5 裁决口径）。
- 不触碰：`mini-pong/`、`scenes/Main.tscn`（#585 组装时挂载）、`player_controller.gd` /
  `enemy_ai.gd` / `atmosphere_controller.gd`（零改动，被动受益或层契约共存）。
