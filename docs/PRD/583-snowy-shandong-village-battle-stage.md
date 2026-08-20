# PRD #583 — [Scene] 雪夜山东村战斗场景（单场景 MVP 舞台）

> **Issue:** #583
> **标签:** enhancement, workflow/research, scene, content, version/mvp
> **深度:** standard（GitHub 无 depth label；分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=12 标注 `depth: standard` → §1–6 + §8 必填，§7 含实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-20
> **所有权:** `content_ownership: mechanical`（场景几何/碰撞/出生点布局 = 机械工程；构图/配色裁决 = taste-draft，E2E 截图交用户裁决——AC5 显式要求）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`~/Documents/Obsidian Vault/`：wiki grep 只狼/场景/雪 → `wiki/游戏设计理念.md`（只狼「机制作为修辞」灵感来源 + 「场景互动作为代入接口」）、`wiki/原始材料-开发笔记.md`（双雪涛/如龙0 参考条目）；`/Volumes/Obsidian/Knowledge Ocean/` 卷本次 I/O 超时不可达（fts_read: Operation timed out），已记录不影响结论）+ 设计 brief（`docs/RAW/shandong-wolf-brief.md` §审美坐标/§画面实现路径）+ GDD（`docs/GAME_DESIGN/shandong-wolf/01-OVERVIEW.md`、`12-ATMOSPHERE-SNOW-NIGHT.md`）+ 配方（`agents/skills/game-to-issues/references/visual-implementation-path.md` §2 月光/§3 水墨/§4 黄土/§6 剪影）+ 同链 issues（#572/#574/#582 前置、#573 移动模型、#581 敌人 AI waypoints 契约、#585 组装）+ 开源调研（GitHub API 3 组查询 + Godot Asset Library API，见 §6.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=12，estimate 3d，priority high，milestone mvp）
> **前置依赖:** #572（CLOSED，#599/#600 merged：constants.gd + state_machine.gd + Game autoload）、#574（CLOSED，#612 merged：火柴人剪影 + 11 态动画）、#582（CLOSED，#613 merged：雪夜氛围四层 + 层契约 + 唯一 moon 守卫）——全部已满足

---

## 1. 问题定义

### 1.1 现状（2026-08-20 worktree 侦查 @ origin/main 59609d4）

| 文件 / 能力 | 状态 | 说明 |
|------------|:----:|------|
| `shandong-wolf/scenes/Main.tscn` | ✅ 存在 | 标题场景 + **Atmosphere 实例已挂载**（#582/#613 上 main）：WorldBackdrop（layer 0 ColorRect，`NIGHT_BG_COLOR` #d8dce4）+ CanvasLayer UI(layer=1) + Atmosphere 四层（雪幕 3-5 / 水墨 2 / 血色 10 / 唯一 Moonlight layer 0） |
| 战斗舞台场景 | ❌ 不存在 | **SW-012 本体缺失**——无 `battle_stage.tscn` 或等价文件；#585 组装（SW-013）等待本场景交付 |
| 平台 / 碰撞体 | ❌ 不存在 | 无 StaticBody2D、无 CollisionShape2D；玩家/敌人均为 CharacterBody2D（`player_controller.gd` 加速度移动 `velocity.y = 0.0`；`enemy_ai.gd` 同构）——**需要物理地面才能 move_and_slide** |
| 出生点 | ❌ 不存在 | 无 Marker2D 约定；#581 DESIGN §2 明确「#583 场景 → `EnemyAI.waypoints` @export（出生点 + 巡逻路径坐标）」——出生点坐标是本场景对 #581 的**接口契约** |
| 月亮天体视觉 | ❌ 不存在 | #582 的 Moonlight 是 CanvasModulate（全局光照，唯一 moon 守卫 C3），**不是月亮天体**；「苍月悬顶」构图无视觉载体 |
| 场景参数集中地 | ❌ 不存在 | constants.gd 已有氛围分区（#582）与 AI 分区（#581），**无场景分区**（平台尺寸/高差/色板/月亮参数） |
| 相机 | ❌ 不存在 | 无 Camera2D；场景 2400px > 窗口 1280px（`resizable=false` + stretch canvas_items），无相机则只能看到左侧 1280px——**可通行/战斗可见性缺口**（边界决策见 §4.4） |
| E2E 截图计划 | ⚠️ 存在但无场景组 | `e2e_shots.json` 有 stick_figure / atmosphere 组；**无 battle_stage 组**（AC5 需要） |

**核心缺口：** MVP 单场景战斗舞台整体缺失。玩家（#573/#574）与敌人（#581）已具备移动/战斗/动画能力，但**没有可以站立的雪地平台、没有战斗发生的空间叙事（村口/草屋/苍月）、没有出生点坐标契约**——#585 的「组装 MVP 战斗闭环」因此无从挂载。本 issue 交付 = 2400px 三平台雪地舞台（几何 + 碰撞）+ 草屋/枯树/山峦/月亮程序化剪影（≤5 物件）+ 玩家/2 敌人生成点 + 场景参数集中（constants.gd 场景分区）+ E2E 截图裁决机制。

### 1.2 约束继承（Patch 19 — 必须原样传递到 PRD，implement agent 读本文件而非 issue）

| 约束 | 内容 | 红线等级 |
|------|------|:---:|
| 引擎/目录 | Godot 4.7.1，全部路径前缀 `shandong-wolf/` | 🔴 硬 |
| 场景尺寸可编辑 | 场景尺寸与物件坐标全部声明在 `.tscn`（2400px 宽 / 平台高差 60-100px / 物件坐标），**禁止脚本写死坐标** | 🔴 硬 |
| 程序化渲染 | 地面=ColorRect 上覆白色雪层（alpha 0.6）；草屋=Polygon2D 墨色剪影 + 屋顶压雪线（Line2D 白色）；月亮=径向渐变 Mesh2D；**禁止外部贴图**（零美术资产红线，#572/#574/#582 延续） | 🔴 硬 |
| 审美坐标 | 黄土+雪：屋顶压雪、墙体墨色、枯树如骨；《地雷战》乡村空间感：横向扁平、屋舍低矮、苍月悬顶 | 🔴 硬 |
| 反例禁止 | 禁止日式鸟居/和风元素；禁止西式城堡；家具/物件 ≤ 5 个（防噪杂） | 🔴 硬 |
| 层契约（#582/#624 定稿） | 战斗场景几何挂 **layer 0 世界层**（唯一 Moonlight 染此层）；雪幕 3-5 / 水墨 2 / 血色 10 / UI 1 禁染；**全场景仅 1 个 CanvasModulate**（C3 守卫 test_atmosphere 拦截复犯）——本场景**禁止新增任何 CanvasModulate** | 🔴 硬 |
| 参数集中 | 所有视觉/场景参数进 constants.gd `# DRAFT` 分区 + 注释「候补值 + 影响什么 + 情感断言」（#572 红线延续） | 🔴 硬 |
| 开源优先 | 已调研（§6.2）：无成熟可复用模板，结论=程序化自建（与 issue 画面实现路径一致） | 🟡 流程 |

### 1.3 与 #585 的范围边界（Patch 14 去冲突）

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|-----------------|
| #585（组装 SW-013） | 将 SW-002~013 全部挂入 Main.tscn，实例化玩家/敌人实体（`bind_entity`/`player` 引用/judge 注入）、打通战斗闭环 | ❌ 不实例化角色实体、不写组装代码、不挂 HUD |
| #581（敌人 AI） | EnemyAI 行为 FSM + 感知 + 决策 | ❌ 不写 AI；本场景只提供 `waypoints` 数据坐标（出生点 + 巡逻路径）供 #585 配置 |
| #582（氛围） | 雪幕/月光/水墨/血色四层系统 | ❌ 不重复建氛围组件；本场景几何挂 layer 0 与之共存（Main.tscn 已挂 Atmosphere，场景文件内**不再挂第二份**） |
| #573（移动模型） | player_controller 加速度移动 | ❌ 不改移动模型（§4.1 方案 B/C 否决理由） |

**边界声明：** 本 issue 交付**独立的世界层场景文件**（`battle_stage.tscn` 或等价命名），含几何、碰撞、出生点 Marker、相机（§4.4）；氛围/角色/HUD 的挂载编排归 #585。

---

## 2. 设计意图

### 2.1 为什么现在做

- **MVP 闭环的地理载体缺失**：brief MVP 范围「单场景战斗 + 雪夜像素氛围成立」——战斗必须发生在「雪夜山东村口」这个具体空间里，否则玩家/敌人只是悬浮在标题场景上的碰撞体。
- **前置链已闭合**：#572（地基）→ #574（火柴人）→ #582（氛围）全部合入 main；#581 敌人 AI 已交付并**显式把 waypoints 数据契约指向本场景**（#581 DESIGN §2「#583 场景 → EnemyAI.waypoints」）——场景是这条依赖链上最后一个未交付的机械件。
- **#585 阻塞等待**：组装 issue 的依赖清单含 #583，本场景交付后组装才能开始。

### 2.2 为什么场景形态如此设计

| 先前约束 | 来源 | 对场景的影响 |
|---------|------|------------|
| 「苍月悬顶」+「屋舍低矮横向扁平」 | brief §审美坐标 | 月亮放背景高处（约 y<150px 区域），草屋低矮（屋脊高 ≤120px），山峦/枯树做远景 Line2D 剪影——水平构图优先 |
| 「枯树如骨」「墙体墨色」 | brief §审美坐标 | 剪影色板统一墨色系（#1a1f26 系，与 #582 INK_COLOR 同源），雪层冷白（alpha 0.6）压顶 |
| 「场景互动作为代入接口」 | Obsidian `wiki/游戏设计理念.md`（只狼参考） | 场景不只是背景：3 平台 = 战斗移动空间，草屋/枯树 = 空间锚点（玩家方位感），月亮 = 情绪光源——#585 组装后玩家在「村口」而非「空白画布」上战斗 |
| 「环境低饱和 / 关键物高对比」 | visual-implementation-path §0 | 环境（平台/山/屋）冷墨低饱和；月亮冷白提亮（视觉焦点），与 #582 月光染后 luma≥30 约束相容 |
| 「参数集中 + # DRAFT」 | #572 红线 | 平台宽/高差/色板/月亮半径全部进 constants.gd 场景分区，taste 值归 #584 用户裁决体系 |

### 2.3 先前约束表

| 约束 | 细节 |
|------|------|
| 窗口 | 1280x720 固定（resizable=false），stretch canvas_items（#572 落地，不可改） |
| 层契约 | layer 0 = 世界层（本场景几何），唯一 Moonlight 在此（#582/#624，不可改） |
| 移动模型 | `velocity.y = 0.0`（无重力/跳跃，#573 定稿）——平台可通行性必须在此模型下成立 |
| 物件预算 | 家具/物件 ≤ 5（issue 硬约束） |
| 出生点契约 | 玩家出生点 ×1、敌人出生点 ×2（issue AC3）；`EnemyAI.waypoints` 坐标由本场景提供（#581 契约） |

---

## 3. 影响分析

### 3.1 直接影响的模块（新增为主）

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/scenes/battle_stage.tscn` | **新增** 战斗舞台场景（SW-012 本体） | 全新建：layer 0 世界层节点树（平台/草屋/枯树/山峦/月亮/出生点/碰撞/相机），纯声明式 |
| `shandong-wolf/gdscripts/constants.gd` | 新增「场景分区」常量段 | 追加式（不动既有 9+ 分区任何常量行，与 #584 调参面板无同区改写冲突）：平台/高差/色板/月亮/出生点坐标等 `# DRAFT` + 机械常量 |
| `shandong-wolf/scenes/e2e_battle_stage_capture.tscn` | **新增** E2E 截图像具场景 | instance battle_stage（+ Atmosphere 复用 #582 效果），供 AC5 用户裁决截图 |
| `shandong-wolf/e2e_shots.json` | 追加 `battle_stage` 组 | 新增 shot 条目（场景全景/近景平台/月亮构图），match 规则指向新场景文件 |
| `shandong-wolf/tests/test_battle_stage.gd` | **新增** 场景结构单测 | 断言：场景总宽 2400px、平台 3 段、出生点 Marker ×3、StaticBody2D 碰撞存在、无第二 CanvasModulate（C3 延续）、坐标来自 .tscn 非脚本写死 |
| `shandong-wolf/tests/run_tests.gd` | 追加一行 `_run()` 挂载 | 与 #581 同模式（追加式，无并发改写） |

> 可选轻量脚本：若月亮光晕需运行时参数（§4.2 方案 A 的 shader），新增 `shandong-wolf/gdscripts/moon_glow.gdshader`（CanvasItem shader，静态零成本）；优先纯声明式，脚本越少越好。

### 3.2 间接影响

| 文件 | 影响 |
|------|------|
| `shandong-wolf/scenes/Main.tscn` | 本 issue **不改**；#585 组装时挂载 battle_stage |
| `shandong-wolf/gdscripts/player_controller.gd` / `enemy_ai.gd` | 零改动（碰撞面使 move_and_slide 生效，属被动受益） |
| `shandong-wolf/gdscripts/atmosphere_controller.gd` | 零改动（层契约共存；C3 守卫保护） |
| `docs/GAME_DESIGN/shandong-wolf/` | post-merge agent 新增 `14-SCENE-BATTLE-STAGE.md`（落盘约定） |

### 3.3 数据流

```
project.godot run/main_scene = Main.tscn（#585 组装后）
    │
    ▼
Main (Node2D)
    ├── WorldBackdrop (layer 0 ColorRect, NIGHT_BG_COLOR)      ← #582 既有
    ├── Atmosphere (instance, 唯一 Moonlight 染 layer 0)        ← #582 既有
    └── BattleStage (instance of battle_stage.tscn)             ← 本 issue 交付，layer 0
            ├── 平台 StaticBody2D + CollisionShape2D ──► 玩家/敌人 move_and_slide 落地 ✅
            ├── 草屋/枯树/山峦 Polygon2D/Line2D 剪影 ──► 月光染色后冷墨构图 ✅
            ├── Moon 天体 (Mesh2D 径向渐变 + 光晕) ──► 「苍月悬顶」视觉焦点 ✅
            ├── PlayerSpawn (Marker2D) ──► #585 实例化玩家
            ├── EnemySpawnA/B (Marker2D + waypoints) ──► #585 实例化敌人 + 配置 EnemyAI.waypoints
            └── Camera2D (limits 2400px) ──► 战斗视口跟随（§4.4）
```

### 3.4 需更新的文档

- [x] 本 PRD（research 交付）
- [ ] `docs/GAME_DESIGN/shandong-wolf/14-SCENE-BATTLE-STAGE.md`（post-merge agent 按落盘约定生成）
- [ ] `docs/DESIGN/583-*.md`（plan agent 后续）
- [ ] `shandong-wolf/e2e_shots.json` 注释（battle_stage 组 + AC5 裁决口径）

---

## 4. 方案对比

本 issue 是**单场景构建**（非多子系统 PRD），但存在 3 个独立决策点，各给方案对比 + 汇总推荐表。

### 4.1 平台高差与「可通行无阻碍」的落地方式

**背景张力：** issue 要求「雪地 3 条平台，长 2400px，**高差 60-100px**」，同时 AC1 要求「可通行无阻碍」；而 player_controller 是 `velocity.y = 0.0`（无重力/跳跃，#573 定稿）。真实高差平台与无竖直移动的角色存在结构性冲突。

| | 方案 A：同一可通行基准面 + 视觉分层高差（推荐） | 方案 B：真实高差 + 坡道连接 | 方案 C：真实高差 + 跳跃/重力 |
|---|----------------------------------------------|---------------------------|---------------------------|
| 描述 | 3 段平台**碰撞面同一基准 Y**（如 y=560），60-100px 高差以**视觉分层**表达：前景雪堆（低 60-100px 的白色 Polygon2D 雪层）+ 中景平台剪影 + 背景平台，形成「雪原起伏」错觉；单一连续 StaticBody2D 碰撞面 | 3 段平台真实错落 60-100px，段间用 ≤30° 坡道连接，碰撞面为多段 | 3 段平台真实错落，给 player_controller 加跳跃/重力 |
| Pros | ✅ AC1 严格成立（零阻塞）；✅ 零角色控制器改动；✅ 碰撞面简单可靠；✅ 视觉仍表达「雪地高差」 | ✅ 高差真实（可站不同高度） | ✅ 高差真实 + 未来可扩展垂直玩法 |
| Cons | 高差是视觉性的（无真实攀爬/落差跳） | ⚠️ `velocity.y=0` 在坡道上无竖直分量，move_and_slide 上坡行为**未验证**（可能卡坡/沿面滑落）；改控制器=超场景范围 | ❌ 违反 issue「场景仅含…基础碰撞体」机械范围；动 #573 已定稿移动模型；拖累 #585 闭环时序 |
| Risk | **Low** | **High** | **High** |
| Effort | 1-2d | 3-4d（含控制器验证/修复） | 4d+（含新功能 + 调参 + 测试） |

**推荐：方案 A。** 理由：(1) issue 所有权是 mechanical、范围是「场景」，方案 A 把交付锁定在 .tscn 声明式几何内；(2) AC1「可通行无阻碍」在 velocity.y=0 模型下只有方案 A 能**严格**满足；(3) 若未来需要真实高差玩法（跳跃/爬坡），应另立 gameplay issue（改 #573 移动模型），不混入场景 issue。视觉高差数据（60-100px）仍进 constants.gd 场景分区供 .tscn 引用。

### 4.2 月亮天体视觉（圆 + 光晕）

| | 方案 A：Mesh2D 径向渐变 + 光晕 shader（推荐） | 方案 B：Sprite2D + 程序化 NoiseTexture | 方案 C：复用 #582 CanvasModulate |
|---|--------------------------------------------|--------------------------------------|-------------------------------|
| 描述 | 月亮主体 = Mesh2D 径向渐变圆（issue 指定路径）；光晕 = CanvasItem shader 同心 alpha 衰减（或第二层更大半透明圆） | 运行时生成径向/噪点纹理贴 Sprite2D | 把 #582 的 Moonlight 当月亮 |
| Pros | ✅ issue 显式指定「月亮=径向渐变 Mesh2D」；✅ 纯程序化、静态零成本；✅ 与 #582 月光色温（#b8c4d9）同源 | 实现简单 | 零新增节点 |
| Cons | 需要一个 ~20 行小 shader | 偏离 issue 指定路径；运行时纹理生成 | ❌ **否决**：CanvasModulate 是光照不是天体；全场景仅 1 个 moon 是 #624 C3 守卫红线（test_atmosphere 拦截） |
| Risk | **Low** | Low | — |
| Effort | 0.5d | 0.5d | — |

**推荐：方案 A。** 月亮视觉节点挂 layer 0（被唯一 Moonlight 染色，与 #582 契约一致）；shader 失败回退 = 双层半透明圆（同构图，零 shader 依赖）。

### 4.3 物件布局（≤5 件硬约束）

| 物件 | 数量 | 实现 | 位置建议 |
|------|:---:|------|---------|
| 草屋剪影 | 2 | Polygon2D 墨色剪影 + 屋顶压雪线（Line2D 白色） | 左右两侧（x≈300 / x≈1900），低矮（屋脊 ≤120px） |
| 枯树 | 2 | Line2D 骨架剪影（如骨） | 平台边缘/屋旁（x≈900 / x≈1500） |
| 山峦 | 背景 | Line2D 多层剪影（远景，不计数为物件） | 地平线上方远景 |
| 月亮 | 背景 | Mesh2D 径向渐变（§4.2，不计数为物件） | 高处（y≈120-160px），苍月悬顶 |

**计数口径：** 家具/物件 = 草屋 2 + 枯树 2 = **4 ≤ 5** ✅；山峦/月亮属背景层不计数（issue「家具/物件」语义）。枯树若加至 3 棵仍 ≤5，但推荐 2 棵保持克制（「物件≤5 以免噪杂」）。

### 4.4 相机策略（2400px > 1280px 视口）

| | 方案 A：场景内 Camera2D（推荐） | 方案 B：留给 #585 | 方案 C：整场缩放 |
|---|-------------------------------|-----------------|-----------------|
| 描述 | battle_stage.tscn 内置 Camera2D（声明式，position/limits=2400px，可 `position_smoothing` 关闭=硬切），current=true | #585 组装时再加相机 | CanvasLayer/视口缩放把 2400px 压进 1280px |
| Pros | ✅ 场景自洽可独立验证（E2E 截图/手动运行即见全貌）；✅ 声明式零脚本 | 组装职责更纯粹 | 全貌可见 |
| Cons | 相机归属略越「几何」边界 | ❌ #585 组装前本场景**无法目视验证**（只能看到左 1280px），AC5 E2E 截图失真 | ❌ 缩放后角色/剪影过小，破坏「村口战斗」构图；拉伸与 stretch canvas_items 交互复杂 |
| Risk | Low | Med | Med |
| Effort | 0.5d | — | 1d |

**推荐：方案 A。** 相机节点属于场景几何范畴（声明式、零代码），且是 AC5 E2E 截图可裁决的前提；#585 组装时若需跟随逻辑（如战斗聚焦）可再调整。

### 4.5 推荐汇总

| 决策点 | 推荐 | 核心文件 |
|--------|------|---------|
| 平台高差 | A：同一基准碰撞面 + 视觉分层高差 | `battle_stage.tscn`（StaticBody2D 单面 + 雪层 Polygon2D） |
| 月亮 | A：Mesh2D 径向渐变 + 光晕 shader（回退双层圆） | `battle_stage.tscn` + `moon_glow.gdshader`（可选） |
| 物件布局 | 草屋×2 + 枯树×2（=4≤5），山峦/月亮为背景 | `battle_stage.tscn` |
| 相机 | A：场景内 Camera2D（limits 2400px） | `battle_stage.tscn` |
| 出生点命名 | `PlayerSpawn` / `EnemySpawnA` / `EnemySpawnB`（Marker2D，坐标进 .tscn） | `battle_stage.tscn` + constants 场景分区 |

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 映射 issue 验收条件）

- [x] **AC1: 场景总宽 2400px，地面平台 3 段，可通行无阻碍**
  - `battle_stage.tscn` 根节点/平台组宽度 = 2400（常量 `STAGE_WIDTH_PX`）
  - 3 段平台碰撞面同一基准 Y，段间无缝隙（相邻段边缘重叠 ≥4px 防掉落）
  - 全宽 move_and_slide 走查无阻塞（test_battle_stage 或手动验证）
- [x] **AC2: 草屋/枯树/月亮/山峦剪影均以 Polygon2D/Line2D 程序化绘制且整体为冷墨色调**
  - 色板断言：墨色系（#1a1f26 同源 INK_COLOR）±10%；雪层冷白 alpha 0.6；月亮冷白（#b8c4d9 同源 MOONLIGHT_COLOR_TARGET）
  - 零外部贴图（无 ext_resource 指向 .png/.jpg；仅 PackedScene 引用）
  - 物件计数 = 4 ≤ 5
- [x] **AC3: 玩家出生点与 2 个敌人出生点正确放置，碰撞体可阻挡角色**
  - Marker2D ×3（PlayerSpawn / EnemySpawnA / EnemySpawnB），坐标在 .tscn
  - 平台 StaticBody2D + CollisionShape2D 可阻挡（test：CharacterBody2D 站上平台不穿透）
  - 出生点不与物件/平台内部重叠
- [x] **AC4: 场景加载后帧率 ≥60fps（Mac 基准测试）**
  - battle_stage + Atmosphere 同屏基准 ≥60fps（场景零新增粒子，静态几何成本可忽略）
  - 基准方式：headless 加载 + 帧时间统计（沿用 #582 fps 断言口径）
- [x] **AC5: E2E 截图提交用户裁决：场景是否符合『雪夜山东村』的地域感（无日本元素、无西化元素）**
  - `e2e_battle_stage_capture.tscn` + e2e_shots.json `battle_stage` 组（全景/平台近景/月亮构图 3 shot）
  - 截图提交用户：构图/配色裁决（taste-draft，AC5 即裁决入口）
- [x] **附加红线：** 层契约（几何挂 layer 0，全场景 CanvasModulate 计数 == 1）；场景尺寸/坐标全部 .tscn 声明（grep 断言 gdscripts 无硬编码坐标）；参数全部集中 constants.gd 场景分区 # DRAFT + 情感断言；零外部美术资产

### 5.2 边界情况（≥5）

1. **平台段间缝隙**：段边缘对齐误差导致角色卡缝/掉落 → 相邻段重叠 ≥4px + 碰撞断言测试
2. **窗口 stretch 与 2400px 场景**：1280x720 固定窗口下 Camera2D limits 必须覆盖 2400px 全宽，玩家贴边时相机不越界露白（limits 含 margin）
3. **出生点与物件重叠**：草屋/枯树 Polygon2D 遮挡出生点或与碰撞体重叠 → 布局断言（出生点坐标与物件包围盒无交集）
4. **月光染后可见性**：layer 0 几何被 MOONLIGHT_COLOR_APPLIED 染色后 luma 必须 ≥30（#624 F3 约束）——色板选墨色系但**不得过黑**（#1a1f26 染后 ≈ 预期范围内，E2E 取色断言）
5. **月亮光晕 shader 编译失败**：回退双层半透明圆（同构图），不阻塞 AC2
6. **C3 守卫误伤**：test_atmosphere 断言 CanvasModulate 计数 == 1——本场景**不新增** CanvasModulate（月亮是 Mesh2D 不是光照），新测试同样断言
7. **e2e capture 场景加载顺序**：capture 场景 instance battle_stage + Atmosphere 时，唯一 moon 归属 Atmosphere（layer 0），battle_stage 几何被动染色——断言染后效果而非节点归属

### 5.3 失败路径（≥3）

1. **场景文件 uid/路径错误**：battle_stage.tscn 引用 constants.gd 失败 → check_compile 拦截（#572 机制自动纳入新脚本）
2. **碰撞体错位**：平台 CollisionShape2D 与视觉雪层错位（角色悬空或穿地）→ E2E 截图 + 手动走查；断言：角色站平台时 global_position.y 与平台顶面差 < 1px
3. **物件超预算**：实现时贪多（>5 物件）→ test_battle_stage 计数断言拦截（防噪杂反例）
4. **相机 limits 配置错误**：视口显示空白/越界 → E2E 全景 shot 人工可见，列入 AC5 裁决

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #572 地基（constants.gd/state_machine/game autoload） | ✅ merged #599/#600 | 无 |
| #574 火柴人（玩家视觉） | ✅ merged #612 | 无 |
| #582 氛围四层 + 层契约 | ✅ merged #613 | 无（本场景遵守 layer 0 契约） |
| #573 移动模型（velocity.y=0） | ✅ merged #611 | 中（§4.1 方案 A 规避） |
| #581 敌人 AI（waypoints 契约） | ✅ merged #638 | 无（出生点坐标即契约数据） |
| #584 常量调参（场景分区追加式） | ✅ merged #609 | 低（追加新分区，不触碰既有行） |

**依赖链：**

```
#572 ──► #574 ──► #582 ──► #583（本 issue）──► #585 组装
              └──► #573 ──► #581 ──┘
```

### 6.2 开源调研结果（issue「开源优先」要求，PR 中需说明）

| 渠道 | 查询 | 结果 | 结论 |
|------|------|------|------|
| GitHub API（sort=stars） | `godot 2d platformer level template` | 最高 ⭐4（Knight-Adventure 模板），均为教学/入门 demo | ❌ 无成熟可复用 |
| GitHub API | `godot snow winter environment 2d` | 无匹配仓库 | ❌ 无 |
| GitHub API | `godot 2d environment silhouette night` | 无匹配仓库 | ❌ 无 |
| Godot Asset Library API | `platformer`（godot_version=4） | 仅 Ultimate/Expandable Platformer **Controller**（角色控制器类，非关卡/环境）；Kenney 像素包（外部贴图，违反零资产红线） | ❌ 无匹配 |
| 社区参考 | 程序化剪影/水墨配方（visual-implementation-path §2-6，mini-pong 实弹验证） | 月亮/黄土/剪影配方可复用 | ✅ 采用 |

**结论：** 无成熟的开源 2D platformer level/environment 模板匹配「水墨雪夜山东村」程序化剪影路线（最接近的模板是角色控制器或像素贴图包，前者不需要、后者违反零外部贴图红线）。**自行程序化实现**，与 issue 画面实现路径一致。本结论写入 implement PR 说明。

### 6.3 准备清单

- [ ] 阅读 `docs/GAME_DESIGN/shandong-wolf/12-ATMOSPHERE-SNOW-NIGHT.md`（层契约 + 常量）
- [ ] 阅读 `constants.gd` 氛围分区/AI 分区（追加场景分区时保持格式一致）
- [ ] 阅读 `e2e_shots.json` 现有组结构（追加 battle_stage 组）
- [ ] 阅读 `visual-implementation-path.md` §2/§4/§6（月亮/黄土/剪影配方）

---

## 7. Spike / 实验（standard 深度含实验，3 项）

### E1：月亮光晕渲染方案验证
- **问题**：Mesh2D 径向渐变圆 + 光晕 shader 在 Godot 4.7 CanvasItem 下是否达到「苍月」效果（冷白 + 柔和辉光），是否与唯一 Moonlight 染色叠加后仍成立
- **方法**：headless 场景渲染 3 变体（shader 同心衰减 / 双层半透明圆 / 单圆无光晕）各 1 帧截图对比
- **预期**：shader 变体辉光最自然；双层圆为可用回退
- **对方案的影响**：确认 §4.2 方案 A 主路径与回退路径

### E2：「可通行无阻碍」全宽走查验证
- **问题**：方案 A（同一基准碰撞面 + 视觉分层高差）是否在 velocity.y=0 模型下全宽零阻塞
- **方法**：test_battle_stage 驱动 CharacterBody2D 从 x=0 匀速移至 x=2400，断言无碰撞卡顿（帧位移连续性）
- **预期**：全程位移连续，无跌落/卡缝
- **对方案的影响**：确认 §4.1 方案 A；若失败则回到 §4.1 重新评估（预期不失败）

### E3：Mac 帧率基准
- **问题**：battle_stage（静态几何）+ Atmosphere（#582 粒子预算）同屏是否 ≥60fps
- **方法**：Mac 上 headless + 真实渲染各测 60s 帧时间均值/1% low
- **预期**：≥60fps（场景零新增粒子，几何静态成本可忽略）
- **对方案的影响**：确认 AC4；若不足则降物件复杂度（≤5 内）而非降粒子预算（#582 红线）

---

## 8. 交接上下文（Continuation Context）

### 8.1 系统状态

- main @ 59609d4：标题场景 + Atmosphere 四层已挂载；玩家（#573/#574）、敌人 AI（#581）、战斗判定（#577）、常量（#584）全部合入；**唯一缺失 = 战斗舞台场景（本 issue）**
- 层契约生效中：layer 0 世界层（唯一 Moonlight 染此层）、C3 守卫（CanvasModulate 计数 == 1）

### 8.2 交接给 plan agent 的要点

1. **交付物**：`battle_stage.tscn`（SW-012 本体，纯声明式）+ constants.gd 场景分区（# DRAFT）+ `e2e_battle_stage_capture.tscn` + e2e_shots.json `battle_stage` 组 + `test_battle_stage.gd`
2. **已定方案**：§4.5 汇总表——平台同基准碰撞面 + 视觉高差；月亮 Mesh2D 径向渐变（回退双层圆）；物件 4 ≤ 5；场景内 Camera2D（limits 2400px）；出生点 `PlayerSpawn`/`EnemySpawnA`/`EnemySpawnB`
3. **红线（implement 不可越）**：layer 0 归属 / 禁新增 CanvasModulate / 零外部贴图 / 坐标声明在 .tscn 不写死 / 参数进 constants.gd 场景分区 / 物件 ≤5 / 禁日式和风与西式元素 / 不改 player_controller 移动模型
4. **#585 对接契约**：出生点 Marker2D 命名约定（PlayerSpawn/EnemySpawnA/B）；`EnemyAI.waypoints` 数据坐标来源（本场景 .tscn）；组装时把 battle_stage 挂入 Main.tscn 且**不重复挂 Atmosphere**
5. **E2E 剧本**：`battle_stage` 组 3 shot（全景/平台近景/月亮构图）提交用户裁决——AC5 是 taste-draft 裁决入口，PR 不写 Closes、assign 用户
6. **GDD 落盘**：post-merge agent 按约定生成 `docs/GAME_DESIGN/shandong-wolf/14-SCENE-BATTLE-STAGE.md`
7. **主要风险**：月亮光晕 shader 效果（E1 验证，有回退）；平台段间缝隙（重叠 ≥4px + 断言）；月光染后 luma ≥30（色板不过黑）
