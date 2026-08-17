# PRD: [Feature] 游戏画面迭代 — 雨夜竞技场画面丰富化执行层（城市光晕/暗角/L2 反馈/波次色变/特殊砖视觉）

> **Issue:** #527
> **标签:** enhancement, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-17
> **深度:** depth/standard（Issue 无 depth 标签，按 #392/#449/#464/#476 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性（headless 下 shader 渲染、E2E 色数/theme 断言影响、砖 variant 与既有断言兼容）而包含 4 个轻量实验，每子系统独立实验）
> **所有权:** `content_ownership: mixed`（光晕/暗角/反馈/色变/变体的机制与常量结构 = mechanical 可测；光晕色调、暗角强度、色变 palette、铁砖配色 = taste-draft，走 human-review 定稿，零代码改动可调）
> **上游方案:** `docs/PLAN-rogue-pong.md` §3.1 分层（L0 氛围层 = 雨幕粒子 + **底部城市光晕** + **暗角(≤10%)**；L2 反馈层 = 破砖闪光/穿墙脉冲/得分弹出/挡板 squash）+ §5 v1 切片（**波次色变** + **特殊砖视觉 (铁砖/奖励砖)**）+ §1「克制优先」。这些规格已确认但**均未落地**（除雨幕 #389、背景呼吸 #449 外）
> **并行上下文:** wt-research-526（并行 research，upgrade-no-effect，无文件域交集）；wt-implement-513/517（已合入 main）。本 PRD 不触碰升级池/暂停/标题世界隐藏逻辑

---

## 1. 问题定义

### 1.1 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280，Forward+）已具备霓虹赛博基调（#289）、动态雨幕（#389）、背景呼吸（#449）、三色分层（#464）、霓虹 HUD（#392）与完整 MVP 玩法（砖墙/双分/波次/升级/转场/失败屏）。但 **PLAN-rogue-pong 已确认的画面规格仍有 5 个子系统未落地**，画面停留在「功能齐、氛围薄」的状态——与 issue「画面整体再丰富、酷炫一些，现在太简洁了」直接对应：

| 子系统 | 来源规格 | 当前状态 | 与 #527 的差距 |
|--------|---------|---------|---------------|
| L0 底部城市光晕 | PLAN §3.1「雨幕粒子 + 底部城市光晕 + 暗角(≤10%)」 | `Main.tscn` AtmosphereLayer 仅 `BgPulse`（#449 背景呼吸）+ `RainCurtain`（#389）两个子节点 | ❌ 光晕未落地：底部无城市灯火意象，雨夜竞技场只有「雨 + 呼吸」 |
| L0 暗角 vignette | PLAN §3.1「暗角(≤10%)」 | 全屏无任何边缘暗化 | ❌ 未落地：画面四边亮度与中心一致，缺乏聚焦感 |
| L2 反馈层 | PLAN §3.1「破砖闪光/穿墙脉冲/得分弹出/挡板 squash」 | 仅 `score_flash.gd`（#289 得分全屏闪烁 0.2s） | ❌ 破砖闪光/穿墙脉冲/得分弹出/挡板 squash 均未落地；击打-反馈链只有音效（#450）无视觉 |
| v1 波次色变 | PLAN §5 v1「波次色变」 | 砖恒为 `BRICK_NEON`（#ff9d45 琥珀橙，#464）；`breakout_grid.gd` 每波生成同色砖 | ❌ 未落地：波次推进无视觉身份变化，雨幕有情绪仪表盘而砖墙没有 |
| v1 特殊砖视觉 | PLAN §5 v1「特殊砖视觉 (铁砖/奖励砖)」 | `brick.tscn` 单一样式（ColorRect #ff9d45 + neon_glow_material）；`brick.gd` 无 variant 概念；`_spawn_brick()` 无 variant 参数 | ❌ 未落地：铁砖/奖励砖的玩法语义（#387 升级池相关）无视觉区分载体 |

**关键事实核查（来自源码 + 既有 PRD）：**

- **E2E 断言语义（#358/#466/#476/#517）**：`e2e_shots.json` 顶层 `theme_color: "4a90d9"` 应用于全部 shot；`01_title` 带 `theme_absent: 4a90d9`（#517 修复后 MENU 断言「无主题蓝」）；`02_midgame`/`03_gameover` 世界可见、断言 theme 存在 + 非黑 + 色数 + 帧间差异。**任何新增视觉元素不得在 MENU 引入 #4a90d9 系色，且需实测对 02_midgame 色数断言的影响（Spike 2）。**
- **#508 世界隐藏纪律**：MENU 态通过 `game_world` 组隐藏整个游戏世界（含 `AtmosphereLayer` → BgPulse + RainCurtain）。新 L0 元素（光晕/暗角）若挂在 AtmosphereLayer 并加入 `game_world` 组，则 **MENU 自动隐藏、PLAYING/GAME_OVER/PAUSED 可见** —— 与「对打时画面丰富」目标一致，且结构性保护 `01_title` 的 theme_absent 断言。
- **glow 已启用**：`world_environment.tscn` glow_intensity=0.6、glow_bloom=0.8（#289）。暗角 shader 输出暗色，glow 对暗色放大有限（低风险，Spike 1 验证）；城市光晕会被 glow 天然放大为「光晕」语义（#449 已验证同款机制）。
- **#464 三色语义是色变/变体的硬约束**：`PADDLE_NEON` #00e5ff（可控物=冷色）、`BRICK_NEON` #ff9d45（目标物=暖色）、BG 暗蓝灰（环境）。波次色变若侵入冷色域将破坏「暖=目标物」语义 → 色变范围限定暖色系（hue 20°–60°，Spike 2 验证）。
- **brick variant 挂载点**：`breakout_grid.gd:generate_wave()` 逐砖 `_spawn_brick(pos)`（229 行），无 variant 参数；`brick.gd` 仅 26 行（destroy 幂等 + AudioEngine 音效 #450）。variant 扩展 = `brick.gd` 增 `@export brick_variant` + grid 增传参，默认 0 全量兼容既有行为。
- **波次信号源**：`WaveController._advance_wave()` 推进波次（#386），GameManager 有 `wave_started(wave_index)`（#392 PRD 确认，先于 generate_wave 发出）；波次色变消费此信号或由 grid 在 generate_wave 时读取当前波 index。
- **L2 事件源**：`breakout_grid.gd` 已有 `brick_destroyed(brick, pos)`/`wall_cleared()`/`wall_generated(remaining)` 信号（#384/#392）；穿墙得分在 `scoring_manager.gd`（#385 dual-scoring，pierce 语义）；得分弹出复用 `GameManager.score_changed(p, a)`（#385）。
- **main 分支 L3 区域断言未合并**：`analyze_bmp.py`（main）仅 5 项 flag-gated 全局断言（非黑/色数/theme/帧差/theme-absent）；#466 的区域断言在阻塞中的 impl/466 分支。本 PRD 的 E2E 验收以 main 现状为准，但设计上兼容未来区域断言（暗角不落三区、色变不产生 4a90d9）。

### 1.2 预期行为（验收条件，源自 Issue #527「画面整体再丰富、酷炫一些」）

1. [ ] **AC1 — L0 底部城市光晕落地** — AtmosphereLayer 新增光晕节点（city_glow.gd），PLAYING 态可见、MENU 态隐藏（game_world 组纪律）；颜色避开 #4a90d9 容差 32（theme_absent 保护）；亮度低于所有游戏元素（#464 环境层纪律延续）
2. [ ] **AC2 — L0 暗角落地（≤10%）** — 全屏边缘暗化，中心区域不变暗；暗角峰值暗度 ≤10%（alpha 上限，保证 E2E 非黑断言安全）；实现方式经 Spike 1 定稿（shader 或渐变叠加）
3. [ ] **AC3 — L2 反馈层 ≥2 项落地** — 破砖闪光 / 穿墙脉冲 / 得分弹出 / 挡板 squash 中至少实现 2 项（推荐破砖闪光 + 穿墙脉冲，Spike 4 定稿）；统一 Tween 动效（150–300ms，不弹跳，PLAN §3.3 纪律）
4. [ ] **AC4 — v1 波次色变落地** — 砖色随波次在**暖色系**内变化（palette 表驱动，波 1 保持琥珀橙教学色）；不侵入 PADDLE 冷色域（hue ≥ 186° 禁止）；02_midgame 色数断言增量在阈值内（Spike 2 实测）
5. [ ] **AC5 — v1 特殊砖视觉落地（≥1 种变体）** — `brick.gd` 增 `@export brick_variant: int`（0=普通/1=铁砖/2=奖励砖接口预留），至少铁砖（1）有明确视觉区分（颜色/glow 显式设定，避免 #464 glow 强制同色教训）；默认 variant=0 时既有渲染逐字节不变
6. [ ] **AC6 — headless 无脚本错误 + run_tests.gd 全绿** — `--headless --quit` 无错误；既有测试（test_neon/test_visual_contrast/test_main_scene/test_constants 等）零回归；新增纯函数可单测
7. [ ] **AC7 — E2E L1–L3 全绿** — `scripts/run-e2e-review.sh --with-visual`：01_title theme_absent 保持（世界隐藏纪律）、02_midgame/03_gameover 非黑/色数/theme/帧差 4 重断言通过
8. [ ] **AC8 — PR files 仅含本 Issue 文件域** — 白名单 = 5 子系统各自核心文件（§4.6 推荐表），不混入升级池/暂停/雨幕/标题等其他 issue 文件

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 对打进行中（PLAYING） | 持续 | 底部城市灯火光晕缓慢呼吸，四角轻微暗角聚焦中央战场；拆砖瞬间砖块闪光、穿墙得分全屏脉冲——「雨夜竞技场」从「功能齐」变成「有氛围」 |
| B | 波次推进 | 每波 | 砖墙从琥珀橙渐变为橙红/金黄（暖色系内），波次身份肉眼可辨；铁砖以灰蓝色调从墙中跳出，视觉上「这块不一样」 |
| C | 暂停/菜单（PAUSED/MENU） | 每局多次 | 暂停时 PauseOverlay（layer=10）在氛围之上，光晕/暗角不干扰可读性；MENU 世界隐藏纪律保持（#508），标题画面依旧简洁 |

### 1.4 技术约束（继承 Issue #527 + PLAN-rogue-pong + 既有架构）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 project.godot，720×1280 竖屏，Forward+） |
| 分层纪律 | L0 氛围层（AtmosphereLayer, layer=0）< L1 世界 < L2 反馈 < L3 UI（GDD22 + PLAN §3.1）；新 L0 元素挂 AtmosphereLayer；新 L2 元素不高于 layer 2 |
| #508 世界隐藏 | 新 L0 元素节点必须加入 `game_world` 组（MENU 自动隐藏）；不得破坏 01_title theme_absent 断言 |
| #464 三色语义 | 波次色变限暖色系（hue 20°–60°）；特殊砖变体色不得与 PADDLE_NEON（#00e5ff 冷色）混淆；环境亮度低于游戏元素 |
| constants.gd 分区纪律 | 只**新增** `CITY_GLOW_*`/`VIGNETTE_*`/`WAVE_COLOR_*`/`BRICK_VARIANT_*` 区；既有常量逐字节不动（#448/#449/#450/#464 并行先例） |
| E2E 断言 | theme_color 4a90d9 全局；新增色避开 #4a90d9（tol 32）；02_midgame 色数增量需 Spike 实测 |
| 动效纪律 | PLAN §3.3：统一 Tween 淡入/滑入 150–300ms，不弹跳不花哨 |
| 克制纪律 | Obsidian「抽象留白」+ CUSGA「堆砌反例」：丰富化 = 执行已确认规格，不新造特效；每个子系统有量化上限（暗角 ≤10%、色变限暖色系、反馈 ≤4 项） |
| 开源优先 | 不引入第三方资产；引擎内建（ColorRect/GPUParticles2D/CanvasItem shader/Color）实现（§1.5） |
| headless | `--headless --quit` 无脚本错误；run_tests.gd 全绿（AC6）；shader 方案需 Spike 1 验证 headless 安全 |

### 1.5 开源优先调研结果

调研时间 2026-08-17，检索 Godot Asset Library（godot_version=4.7）+ 社区：

- **城市光晕/背景光带**：Asset Library `city glow / neon background` 无运行时通用方案（均为编辑期材质或整场景示例）；本需求 = 渐变 ColorRect + 呼吸 alpha（#449 同构）或 GPUParticles2D 光带，引擎内建能力覆盖
- **暗角 vignette**：Godot 无内建 vignette 后处理；社区方案均为 CanvasLayer + 全屏 CanvasItem shader（约 10 行）或四角渐变 ColorRect——引擎内建能力覆盖，无需资产
- **特殊砖视觉变体**：无「Pong 砖 variant 视觉」addon；`@export` 枚举 + 显式 Color 映射为第一方标准做法（#464 已确立「显式颜色防 glow 覆盖」教训）
- **结论**：**无可直接复用的成熟方案**，第一方实现零依赖、headless 可测，符合「找不到合适方案再自行实现，并在 PR 中说明调研结果」。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（`~/Documents/Obsidian Vault/`，含 `raw/` + `wiki/`）。检索关键词「画面 / 视觉 / 酷炫 / 丰富 / 简洁 / 氛围 / 克制 / 美学」命中以下笔记：
- `wiki/体验引擎-patterns.md`「7. 抽象留白」：「丰富的视觉细节不给玩家想象力留空间 → 故意省略视觉细节」——**丰富化的边界纪律**：本 PRD 的每个子系统都设量化上限（暗角 ≤10%、色变限暖色系、反馈只做已确认 4 项），执行 PLAN 已确认规格 = 给想象力留空间，而非堆砌
- `wiki/体验引擎-patterns.md`：「沉浸感被 UI 破坏 → 隐形界面」——**反馈层为 gameplay 服务**：破砖闪光/穿墙脉冲是「结果可见性」，不是装饰；动效 150–300ms 不抢注意力
- `raw/Clippings/文字记录-CUSGA游戏评选作品评估-2026年7月3日.md`（:31 银发冒险家）：「美术做了很多很多东西…很多很满」→ **堆砌反例**：与玩法主题无关的丰富是扣分项；本 PRD 全部 5 子系统均来自 PLAN 已确认规格（主题相关）
- 同上（:36 附魔师）：「视觉反馈做的比较好」→ **L2 反馈层价值佐证**：反馈专业度是「画面不错」观感的重要组成
- 同上（:24 绿动速回梦）：「画面赛博朋克配色，较酷」→ 霓虹赛博配色方向获认可（与项目 TASTE.md 审美坐标一致）
- 同上（:18 color game）：「非常粗糙，但有一种奇妙的氛围感」→ **氛围 > 细节量**：光晕/暗角/色变买的是「氛围感」，不是「元素密度」
- `wiki/游戏设计理念.md`（:176）：「感性色彩」列为设计维度 → 色彩是情感编码载体：波次色变 = 雨幕情绪仪表盘（#389）的砖墙侧延伸，同一设计语言
- `wiki/90年代地摊文艺.md`：猎奇美学参考属标题/文案领域（#396 文案已用），本 PRD 不引入 gameplay 画面
- **Vault 缺口记录**：无「Pong 类游戏画面分层/霓虹氛围量化」专笔记；本 PRD 的量化约束（暗角 ≤10%、色变 hue 域）为项目内首创，已在本 PRD §1.2/§1.4 给出可复算值

### 1.7 范围边界（与相邻 PRD/Issue 解冲突）

| PRD/Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| #289 霓虹视觉系统 | glow/bloom、背景 #0a0a12、拖尾、发光轮廓、得分闪烁、中线 | ❌ 不重做基础视觉；不改 world_environment.tscn（test_neon TC2/TC3 文本断言） |
| #389 动态雨幕 | 雨幕粒子、RAIN_* 常量、雨量情绪映射 | ❌ 不碰 rain_curtain.gd / RAIN_* 常量 / 雨公式 |
| #392 霓虹 HUD | L3 UI 描边/投影/双区/波次号/剩余砖数 | ❌ 不碰 HUD/升级卡/UI 层 |
| #449 背景呼吸 | BgPulse 节点、BG_PULSE_* 常量、L0 背景呼吸 | ❌ 不碰 bg_pulse.gd / BG_PULSE_* 常量；光晕是**新增**独立节点（底部城市灯火意象），与呼吸基底正交 |
| #464 三色分层 | PADDLE_NEON/BRICK_NEON/BG 三色语义 + 对比度断言 | ❌ 不改三色常量值；波次色变/特殊砖在 BRICK_NEON 语义之上**扩展**（变体/色相偏移），默认砖仍 = BRICK_NEON |
| #465 雨幕修复 / #476 L3 回归修复 | 雨滴分布、clear_color 键名、L3 断言 | ❌ 无交集（不碰 project.godot [rendering] 段 / analyze_bmp.py） |
| #508 世界隐藏 | MENU 隐藏 game_world 组 | ✅ **继承其纪律**：新 L0 元素入 game_world 组（MENU 隐藏），不改变隐藏机制本身 |
| #513 暂停计分波 / #517 标题 theme 断言 | 暂停 UI、01_title 断言 | ❌ 无交集；但 AC7 保证 01_title theme_absent 不回归 |
| #526 升级无效果（并行 research） | 升级池生效性 | ❌ 无交集（不同文件域） |
| v2 城市天际线剪影 | PLAN §5 v2「城市天际线剪影 + 雨势随波次」 | ❌ **不做天际线剪影**（v2 范围）；本 PRD 只做 L0 底部光晕（v1/L0 规格），Spike 1 若验证光晕可平滑升级为剪影则记录接口建议 |

## 2. 设计意图

### 2.1 为什么现状如此

| 约束 | 细节 |
|------|------|
| MVP 切片优先功能 | PLAN §5：MVP = 砖墙/双分/波次/升级/雨幕/转场/失败屏（功能闭环）；画面规格 §3.1 已确认但执行被切片排到 v1 |
| 视觉基础先行落地 | #289（基调）→ #389（雨）→ #449（呼吸）→ #464（三色）→ #392（HUD）逐步补齐，但「丰富化」类目（光晕/暗角/反馈/色变/变体）尚无 issue 承接 |
| 克制优先原则 | PLAN §1「克制优先」+ Obsidian 反例约束 → 画面规格宁可少而精，不一次性堆满 |

### 2.2 为什么现在改

1. **MVP 已全部落地**（最后 #390/#391 波次转场/失败屏已合入 main，2026-08 中旬），进入 v1 画面执行期——issue #527 是 v1 画面规格的承接者
2. **「太简洁」的根因是规格未执行而非缺规格**：PLAN §3.1/§5 明确写了光晕/暗角/反馈/色变/特殊砖，全部未落地；执行已确认规格 = 最小正确路径（不发明、不越权）
3. **技术前提已就绪**：#464 三色语义（色变/变体的颜色约束）、#389 雨幕（氛围层同构）、#450 音效（反馈链已有声音半边）、#508 世界隐藏（L0 元素 MENU 纪律）——5 个子系统的挂载点全部存在

### 2.3 既有约束（表）

| 约束 | 来源 | 对本 PRD 的影响 |
|------|------|----------------|
| 克制优先 | PLAN §1 / Obsidian | 只执行已确认规格，每个子系统设量化上限 |
| 三色语义 | #464（已落地） | 色变限暖色系；变体色避开冷色域 |
| 动效纪律 | PLAN §3.3 | Tween 150–300ms，不弹跳不花哨 |
| 世界隐藏 | #508（已落地） | 新 L0 元素入 game_world 组 |
| E2E 断言 | #358/#517（已落地） | 新增色避开 4a90d9；色数增量 Spike 实测 |
| constants 分区 | 项目惯例 | 只新增区，既有区逐字节不动 |
| taste 定稿 | TASTE.md / B5 流程 | 光晕色调/暗角强度/色变 palette/铁砖配色 = taste-draft，human-review 定稿 |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/gdscripts/constants.gd` | 常量 | 新增 `CITY_GLOW_*`（色调/周期/振幅）、`VIGNETTE_*`（暗度上限/边缘宽度）、`WAVE_COLOR_*`（暖色系 palette 表）、`BRICK_VARIANT_*`（变体色映射）4 个新区；既有区逐字节不动 |
| `mini-pong/scenes/Main.tscn` | 场景 | AtmosphereLayer 挂 `CityGlow` + `Vignette` 节点（入 game_world 组）；L2 层挂 `FeedbackFX` 节点 |
| `mini-pong/gdscripts/city_glow.gd` | **新文件** | L0 底部城市光晕：渐变光带 + 正弦呼吸（#449 模式同构），颜色避开 4a90d9 |
| `mini-pong/gdscripts/vignette.gd` | **新文件** | L0 暗角：全屏边缘暗化（Spike 1 定稿 shader 或渐变叠加），暗度 ≤10% |
| `mini-pong/gdscripts/feedback_fx.gd` | **新文件** | L2 反馈控制器：消费 `brick_destroyed`/穿墙得分/`score_changed` 信号，统一 Tween 动效 |
| `mini-pong/gdscripts/brick.gd` | 脚本 | 增 `@export brick_variant: int`（0=普通/1=铁砖/2=奖励砖接口）+ 变体颜色/glow 显式映射（默认 0 行为不变） |
| `mini-pong/scenes/brick.tscn` | 场景 | 若变体需独立材质实例则扩展（或全部由 brick.gd 运行时设置，Spike 3 定稿） |
| `mini-pong/gdscripts/breakout_grid.gd` | 脚本 | `_spawn_brick()` 增 variant 传参（按波 index/布局注入）；波次色变 palette 应用点 |

### 3.2 新文件清单

| 文件 | 用途 | 归属子系统 |
|------|------|-----------|
| `mini-pong/gdscripts/city_glow.gd` | L0 城市光晕控制器 | 4.1 |
| `mini-pong/gdscripts/vignette.gd` | L0 暗角控制器 | 4.2 |
| `mini-pong/gdscripts/feedback_fx.gd` | L2 反馈统一控制器 | 4.3 |
| `mini-pong/tests/test_visual_enrichment.gd`（可选） | 纯函数断言（palette 范围/暗度上限/变体映射） | 全部 |

### 3.3 间接受影响模块

| 模块 | 影响 |
|------|------|
| `e2e_shots.json` / analyze_bmp.py | **不改文件**；02_midgame 截帧内容变化（光晕/暗角/色变/变体砖可见）→ 4 重断言需实测通过（AC7） |
| `test_visual_contrast.gd`（#464） | 默认砖保持 BRICK_NEON → 三色断言不回归；变体砖不在三色断言域内（AC5 设计保证） |
| `test_neon.gd` TC2/TC3 | world_environment.tscn 零改动 → 不回归 |
| `test_main_scene.gd` TC1-x | 新增节点是 additive-safe（#449 先例）；若有 has_node 断言冲突则同步更新（AC6） |
| `score_flash.gd`（#289） | L2 反馈控制器可复用其 flash API 模式，不修改其文件（避免破坏 test_neon TC9） |
| `docs/TASTE.md` | 新常量（光晕色调/暗角强度/palette/铁砖配色）走 taste-draft → 定稿后追加品味档案条目 |
| `docs/PLAN-rogue-pong.md` | 落地进度打勾（§3.1/§5 对应项） |

### 3.4 数据流影响

```
WaveController._advance_wave() (wave index)
    │
    ├──► BreakoutGrid.generate_wave(thickness, layout, seed)
    │        ├── palette 选色: WAVE_COLOR_PALETTE[index % n]  → 砖 ColorRect color（暖色系内）
    │        └── _spawn_brick(pos, variant)  → brick.gd @export brick_variant（铁砖/奖励砖）
    │
    └──► GameManager.wave_started(wave_index) ──► (可选) CityGlow 呼吸相位/强度联动

brick.destroy() ──► grid._on_brick_destroyed() ──► brick_destroyed(brick, pos)
    │                                                  │
    │                                                  ▼
    │                                           FeedbackFX._on_brick_destroyed() → 破砖闪光（Tween 150-300ms）
    ▼
穿墙得分（scoring_manager, #385 pierce 语义）──► FeedbackFX._on_pierce() → 穿墙脉冲
    │
    ▼
GameManager.score_changed(p, a) ──► FeedbackFX._on_score() → 得分弹出（可选，Spike 4 定稿）

AtmosphereLayer（layer=0, game_world 组）
    ├── BgPulse（#449 既有）     ← 呼吸基底
    ├── RainCurtain（#389 既有） ← 雨幕
    ├── CityGlow（新增）         ← 底部城市光晕
    └── Vignette（新增）         ← 四角暗角 ≤10%
    （MENU 态整组隐藏 → 01_title theme_absent 结构性安全）
```

### 3.5 文档更新清单

- [ ] `docs/PRD/527-visual-enrichment.md`（本 PRD）
- [ ] `docs/TASTE.md`：taste-draft 常量定稿后追加（光晕色调/暗角强度/色变 palette/铁砖配色）
- [ ] `docs/PLAN-rogue-pong.md`：§3.1 L0/L2、§5 v1 对应项标记落地
- [ ] 实现阶段 DESIGN 文档（plan agent 产出，本 PRD §8 交接）

## 4. 方案对比

> 多子系统 PRD（Patch 19 规则）：5 个子系统各自独立方案对比，§4.6 汇总推荐组合。

### 4.1 L0 底部城市光晕

**Approach A — 渐变 ColorRect + 呼吸 alpha（静态光带）**
- 描述：AtmosphereLayer 底部全宽 ColorRect，垂直渐变（底部亮→向上透明），alpha 正弦呼吸（周期可配，复用 #449 `compute_alpha` 模式）；颜色 = taste-draft 定稿的霓虹暖/青暗色调（避开 4a90d9）
- Pros：零粒子开销；与 BgPulse 同构（已证 headless 安全）；glow 天然放大为「光晕」
- Cons：静态意象（无「城市灯火」动态细节）
- Risk：Low（纯 ColorRect + Tween）
- Effort：S（0.5–1 天）

**Approach B — GPUParticles2D 底部光带（动态粒子）**
- 描述：底部发射缓慢上升的暖色粒子流，模拟城市灯火/尘埃，粒子数可配
- Pros：动态、与雨幕（#389）同技术栈；「城市」意象更生动
- Cons：headless 粒子渲染需实测；与雨幕粒子叠加的性能/视觉干扰需调参；E2E 帧间差异断言更敏感
- Risk：Med（粒子 + 断言稳定性）
- Effort：M（1–2 天）

**Approach C — 城市天际线剪影（提前执行 v2 规格）**
- 描述：底部剪影多边形 + 窗口灯火，即 PLAN §5 v2「城市天际线剪影」
- Pros：视觉最强，一步到位
- Cons：**越界**（v2 范围，§1.7 明确不做）；资产/多边形制作成本高；与 v2 未来 issue 冲突
- Risk：High（范围违规）
- Effort：L（2–3 天）

**→ 推荐 A**：克制纪律（§1.6）+ 低风险 + 与 #449 同构。Spike 1 若验证粒子无断言风险，A 可平滑升级 B（接口预留）。

### 4.2 L0 暗角 vignette（≤10%）

**Approach A — CanvasLayer + 全屏 CanvasItem shader**
- 描述：全屏 ColorRect 挂 vignette shader（边缘暗化、中心透明），uniform 控制暗度（≤0.10）与边缘宽度；挂 AtmosphereLayer（game_world 组）
- Pros：单节点、参数化（暗度/宽度可配 = mechanical 可测）；标准做法
- Cons：shader 需 headless 编译验证（Spike 1）；glow 对暗色边缘的交互需实测
- Risk：Low–Med（shader 编译）
- Effort：S（0.5–1 天）

**Approach B — 四角 4 个渐变 ColorRect 叠加**
- 描述：四个角各一个径向渐变 ColorRect（无 shader）
- Pros：零 shader 依赖，headless 绝对安全
- Cons：4 节点 + 角落衔接瑕疵；渐变控制粗（无法精确「中心不变暗」）
- Risk：Low
- Effort：S（0.5–1 天）

**Approach C — 仅上下线性暗条**
- 描述：顶部/底部两条线性渐变（非四角）
- Pros：最小实现；竖屏攻防纵深（Y 轴）聚焦
- Cons：左右边缘无暗角，画面聚焦感不完整
- Risk：Low
- Effort：XS（0.25 天）

**→ 推荐 A**（标准 vignette），B 为 headless 失败时的 fallback（Spike 1 定稿）。

### 4.3 L2 反馈层（破砖闪光/穿墙脉冲/得分弹出/挡板 squash）

**Approach A — 统一 FeedbackFX 控制器**
- 描述：`feedback_fx.gd` 消费既有信号（brick_destroyed → 破砖闪光；穿墙得分 → 全屏脉冲；score_changed → 得分弹出；挡板击球 → squash 拉伸可选），统一 Tween 150–300ms；独立于各系统，可单测
- Pros：集中可测；不侵入 brick/paddle/score_flash 既有代码（零回归风险）；符合 PLAN §3.3 动效纪律
- Cons：新文件 + 信号接线；穿墙脉冲与 ScoreFlash（#289）视觉重叠需区分（脉冲=全屏色带 vs 闪烁=全屏色罩）
- Risk：Low
- Effort：M（1–2 天）

**Approach B — 各系统内联实现**
- 描述：brick.gd 内联闪光、scoring_manager 内联脉冲、paddle.gd 内联 squash
- Pros：无需新文件
- Cons：分散耦合；改既有文件 → 破坏 test_neon TC8/TC9、test_main_scene 等断言风险；动效不一致
- Risk：Med（回归面大）
- Effort：S–M

**Approach C — 最小集（只做破砖闪光 + 穿墙脉冲）**
- 描述：按优先级只落地 2 项，得分弹出/挡板 squash 延后
- Pros：范围最小；穿墙脉冲是「穿墙分 +3」的爽点放大器（#385 双得分制的视觉兑现）
- Cons：反馈层不完整
- Risk：Low
- Effort：S（0.5–1 天）

**→ 推荐 A（控制器结构）+ C（范围）**：统一控制器保证一致性与可测性，首期落地破砖闪光 + 穿墙脉冲；得分弹出/挡板 squash 留接口（Spike 4 验证后追加）。

### 4.4 v1 波次色变（暖色系）

**Approach A — 暖色系 palette 表驱动**
- 描述：`WAVE_COLOR_PALETTE: Array[Color]`（琥珀 #ff9d45 → 橙红 → 金黄 → 暖橙，hue 20°–60° 内 4–6 色），`generate_wave()` 按 `index % n` 选色写入砖 ColorRect；波 1 恒为 BRICK_NEON（教学色稳定）
- Pros：机械可测（palette 范围断言）；语义保持（#464 暖=目标物）；每波身份清晰
- Cons：色变幅度有限（暖色系内），「酷炫」感弱于全色域
- Risk：Low（Spike 2 验证 E2E 断言）
- Effort：S（0.5 天）

**Approach B — 连续色相插值（每波 hue += 固定步长）**
- 描述：`BRICK_NEON.hue + wave_index * step` 连续偏移
- Pros：实现最简
- Cons：跨波差异小（肉眼难辨）；断言困难；步长越界需 clamp（冷色域污染风险）
- Risk：Med
- Effort：XS

**Approach C — 全色域轮换（蓝/绿/紫）**
- 描述：每波换大色相（含冷色）
- Pros：视觉最「酷炫」
- Cons：**破坏 #464 三色语义**（目标物=暖色；冷色砖与 PADDLE 混淆，直接踩中 #464 修复的坑）；用户可读性回归
- Risk：High（语义违规）
- Effort：S

**→ 推荐 A**：语义安全 + 可测 + 每波有身份。全色域（C）作为 taste 讨论记录在案但明确不采纳。

### 4.5 v1 特殊砖视觉（铁砖/奖励砖）

**Approach A — brick_variant 枚举 + 显式色映射**
- 描述：`brick.gd` 增 `@export brick_variant: int`（0=普通/1=铁砖/2=奖励砖）；`constants.gd` `BRICK_VARIANT_COLORS` 显式映射（铁砖=灰蓝冷调但非 PADDLE 青、奖励砖=金绿）；grid `_spawn_brick(pos, variant)` 按波/布局注入（首期铁砖按波次概率或固定列注入，Spike 3 定稿）；**显式 color 设置**（#464 教训：glow 材质会强制同色，必须同时设材质 glow_color 或换材质实例）
- Pros：数据驱动；默认 0 全量兼容既有行为；为 v1 玩法（铁砖不可破坏/奖励砖加成）预留视觉载体
- Cons：glow 材质同色问题需处理（变体需独立材质实例或运行时改 glow_color，Spike 3 验证）
- Risk：Med（材质/断言交互）
- Effort：M（1–2 天）

**Approach B — 独立场景变体（brick_iron.tscn / brick_reward.tscn）**
- 描述：每变体独立 .tscn（复制 brick.tscn 改色）
- Pros：场景直观
- Cons：三份场景维护成本；ext_resource 重复；与 #384 单一 brick 场景架构冲突
- Risk：Med（维护）
- Effort：M

**Approach C — 仅 modulate 调色（无独立材质）**
- 描述：`modulate` 覆盖颜色
- Pros：实现最简
- Cons：**#464 已证伪**：glow 材质 glow_width=3.0 → 渲染 ≈93% glow 色，modulate 被覆盖 → 变体视觉不可见
- Risk：High（无效方案，历史教训）
- Effort：XS

**→ 推荐 A**：首期落地铁砖（1 种变体，AC5），奖励砖留 variant=2 接口；Spike 3 验证显式颜色/材质方案。

### 4.6 推荐组合表

| 子系统 | 推荐方案 | 核心文件 | Effort |
|--------|---------|---------|--------|
| L0 城市光晕 | A：渐变 ColorRect + 呼吸 | `city_glow.gd`（新）+ Main.tscn + constants.gd | S |
| L0 暗角 | A：CanvasItem shader（fallback B） | `vignette.gd`（新）+ Main.tscn | S |
| L2 反馈 | A 控制器 + C 范围（破砖闪光+穿墙脉冲） | `feedback_fx.gd`（新）+ Main.tscn | M |
| v1 波次色变 | A：暖色系 palette 表 | constants.gd + breakout_grid.gd | S |
| v1 特殊砖 | A：variant 枚举（铁砖先行） | brick.gd + brick.tscn + breakout_grid.gd + constants.gd | M |

组合原则：**执行 PLAN 已确认规格 + 克制纪律 + 语义安全（#464）**；总 Effort ≈ 3–5 天，可拆 2 个实现 PR（L0 批 / v1 批）。

## 5. 边界条件与验收标准

### 5.1 验收条件（AC，见 §1.2 详细清单）

- [x] **AC1** L0 城市光晕：PLAYING 可见 / MENU 隐藏（game_world 组）；色避开 4a90d9（tol 32）
- [x] **AC2** L0 暗角：峰值暗度 ≤10%；中心区域不变暗
- [x] **AC3** L2 反馈 ≥2 项（破砖闪光 + 穿墙脉冲）；Tween 150–300ms
- [x] **AC4** 波次色变：暖色系 palette（hue 20°–60°）；波 1 = BRICK_NEON；不侵入冷色域
- [x] **AC5** 特殊砖：brick_variant @export；铁砖视觉落地；variant=0 渲染逐字节不变
- [x] **AC6** headless 无错误；run_tests.gd 全绿；既有测试零回归
- [x] **AC7** E2E L1–L3 全绿（01_title theme_absent / 02_midgame 4 重断言）
- [x] **AC8** PR files 白名单（5 子系统核心文件 + 新测试，不混入其他 issue）

### 5.2 边界用例

1. **MENU 态**：新 L0 元素（光晕/暗角）随 game_world 组隐藏 → 01_title 截帧无新色、theme_absent 保持（结构性保证，非依赖断言）
2. **PAUSED 态**：PauseOverlay（layer=10）在光晕/暗角之上绘制 → 暂停文字可读性不受影响（分层结构性保证，GDD22）
3. **波次色变 × #464 语义**：色变 hue 域 [20°,60°] 与 PADDLE_NEON hue 186° 距离 ≥126° → 「暖=目标物」语义保持；palette 越界由常量断言拦截（test_visual_enrichment 纯函数）
4. **特殊砖 × test_visual_contrast**：默认砖（variant=0）保持 BRICK_NEON → 三色断言零回归；铁砖色（灰蓝调）不在三色断言域（新增色，断言不覆盖）
5. **暗角 × E2E 非黑断言**：暗角 alpha ≤0.10 → 边缘像素亮度 ≥ 黑阈值（(10,10,18) 基底 + 90% 透出 ≈ (10,10,18) 不变）→ 非黑断言安全（Spike 1 验算）
6. **HOLES/MIXED 布局**：洞/缝列不实例化砖 → variant 注入只作用于实际 spawn 的砖；变体不影响布局逻辑（#384 零改动）
7. **波 1 教学墙**：首波厚度 1 行（WAVE_START_THICKNESS）→ 色变从波 2 开始（palette index 0 = BRICK_NEON 恒为波 1），教学期颜色稳定
8. **穿墙脉冲 × ScoreFlash**：脉冲（全屏色带扫过）与闪烁（全屏色罩 0.2s）视觉区分；同帧触发时脉冲优先（FeedbackFX 内部仲裁）

### 5.3 失败路径

1. **暗角 shader headless 编译失败** → fallback Approach B（四角渐变 ColorRect，零 shader）；Spike 1 前置验证避免实现期返工
2. **02_midgame 色数断言超阈值**（palette 引入过多新色）→ palette 收敛（4 色内）/色变仅作用于 glow 色调（不动基底色）；Spike 2 实测定稿
3. **铁砖 glow 强制同色**（#464 教训复发）→ 变体砖换独立材质实例（复制 neon_glow_material 改 glow_color）或运行时 set_shader_parameter；Spike 3 前置验证
4. **穿墙脉冲与既有帧差断言冲突**（脉冲帧差异过大）→ 脉冲 alpha 收敛 / 仅 PLAYING 态触发（E2E 02_midgame settle 后脉冲已回落）；Spike 4 实测
5. **MENU 态新元素未隐藏**（组归属遗漏）→ 01_title theme_absent 失败 → 立即修复组归属（AC7 拦截）

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 | 本 PRD 如何使用 |
|------|------|------|----------------|
| #464 三色分层（PADDLE_NEON/BRICK_NEON） | ✅ CLOSED（PR #469） | Low | 色变/变体的颜色约束与挂载语义 |
| #384 砖墙（brick.tscn/breakout_grid.gd） | ✅ CLOSED（随 #393 落地） | Low | variant 注入点（_spawn_brick） |
| #389 雨幕 / #449 背景呼吸 | ✅ CLOSED（PR #472/#473） | Low | L0 层结构、呼吸模式同构 |
| #392 HUD（含 wall_generated 信号） | ✅ CLOSED | Low | 信号消费先例（get_node_or_null 容错模式） |
| #508 世界隐藏（game_world 组） | ✅ CLOSED（PR #511） | Low | 新 L0 元素入组纪律 |
| #385 双得分制（pierce 语义） | ✅ CLOSED | Low | 穿墙脉冲事件源 |
| #358/#466/#476/#517 E2E 断言体系 | ✅ CLOSED | Med | AC7 断言约束（色数/theme/非黑） |

**依赖链 ASCII：**

```
PLAN-rogue-pong §3.1/§5（画面规格，已确认）
    │
    ├──► #289 霓虹基调 ──► #389 雨幕 ──► #449 背景呼吸 ──┐
    ├──► #384 砖墙 ──► #464 三色分层 ────────────────────┤
    ├──► #385 双得分 ──► #392 HUD（信号先例）────────────┤
    └──► #508 世界隐藏（组纪律）─────────────────────────┘
                                                          ▼
                                              ★ #527 画面丰富化执行层（本 PRD）
                                                          │
                                                          ▼
                                          plan → implement（DESIGN + 实现 PR）
```

### 6.2 阻塞

无硬阻塞。软性依赖：E2E `--with-visual` 重跑需 Godot 图形环境（headless 不可跑 L3 截图，同 #466 惯例）。

### 6.3 准备清单

- [ ] Spike 1：暗角 shader headless 验证 + 非黑断言验算
- [ ] Spike 2：色变 palette 对 02_midgame 色数/theme 断言影响实测
- [ ] Spike 3：铁砖显式颜色/材质方案 + test_visual_contrast 兼容验证
- [ ] Spike 4：穿墙脉冲/破砖闪光信号接线 + 帧差断言实测
- [ ] taste-draft 常量（光晕色调/暗角强度/palette/铁砖配色）→ human-review 定稿

## 7. Spike / 实验

> 深度 standard，但因 5 子系统各有真实技术不确定性，按 #392/#449/#464 惯例包含 4 个轻量实验（每子系统独立，Patch 19 规则）。

**Experiment 1 — 暗角实现与 headless 安全（子系统 4.2）**
- Question：CanvasItem vignette shader 在 headless 下是否编译/运行安全？暗角 alpha 0.10 对 (10,10,18) 基底的非黑断言影响？
- Method：worktree 内建最小 shader + ColorRect，`godot --headless --quit` 跑通；用 analyze_bmp.py 对合成帧验算边缘像素亮度
- Expected：headless 无错；边缘亮度 ≥ 黑阈值（10,10,18 透出 90% ≈ 不变）
- Impact：定稿 Approach A（shader）或 fallback B（四角 ColorRect）

**Experiment 2 — 波次色变 palette 与 E2E 断言（子系统 4.4）**
- Question：暖色系 palette（4 色）注入后 02_midgame 色数断言是否超阈值？是否产生 4a90d9 系像素？
- Method：临时 palette 常量 + 跑 `run-e2e-review.sh --with-visual` 对比色数/theme 统计
- Expected：色数增量在阈值内（既有断言 min-colors 是下限非上限，实际风险 = 区域断言未合并的 main 现状下无上限）；无 4a90d9 像素
- Impact：palette 规模定稿（4 色 vs 6 色）；色变范围确认

**Experiment 3 — 铁砖显式颜色 vs glow 强制同色（子系统 4.5）**
- Question：brick_variant=1 铁砖如何绕过 glow_width=3.0 的 93% 同色覆盖（#464 教训）？独立材质实例 vs 运行时 set_shader_parameter？
- Method：两种方案各渲染一帧对比像素；验证 test_visual_contrast 对默认砖断言不回归
- Expected：显式 color + 独立 glow_color 生效；默认砖逐字节不变
- Impact：定稿变体材质方案（Approach A 细节）

**Experiment 4 — L2 反馈信号接线与帧差断言（子系统 4.3）**
- Question：穿墙脉冲/破砖闪光的信号消费链是否完整（pierce 语义在 scoring_manager 何处 emit）？脉冲帧对 02_midgame 帧差断言影响？
- Method：读 scoring_manager.gd 信号源 + 临时 FeedbackFX 最小实现跑 E2E
- Expected：事件源可寻址；脉冲在 settle 帧前回落，帧差断言安全
- Impact：定稿首期 2 项反馈（破砖闪光 + 穿墙脉冲）与触发条件

## 8. 延续上下文

**系统状态（plan agent 接手时）：**
- Mini Pong MVP 功能全落地；画面规格 PLAN §3.1/§5 中 5 项未执行项 = 本 PRD 范围
- 关键纪律已就位：#464 三色语义（色变/变体颜色约束）、#508 game_world 组（新 L0 元素 MENU 隐藏）、constants.gd 分区（只新增区）、E2E theme 4a90d9（新增色避开）
- main 分支 L3 区域断言未合并（impl/466 阻塞中）→ E2E 验收以 5 项全局断言为准；DESIGN 阶段若 466 合并需复查区域断言兼容

**主要风险：**
1. E2E 断言交互（色数/theme/非黑）——由 Spike 1/2/4 前置消解
2. glow 材质强制同色（#464 教训）——由 Spike 3 前置消解
3. taste-draft 常量定稿依赖 human-review（B5 流程）——光晕色调/暗角强度/palette/铁砖配色为可调常量，零代码改动

**下一步（plan agent）：**
1. 先跑 Spike 1–4（worktree 内，验证后写 DESIGN）
2. DESIGN 按 §4.6 推荐表出文件清单：`city_glow.gd` / `vignette.gd` / `feedback_fx.gd`（新）+ constants.gd 4 个新区 + Main.tscn 挂载 + brick.gd/brick.tscn/breakout_grid.gd variant 扩展
3. 建议拆 2 个实现 PR：PR-A（L0：光晕 + 暗角，低风险先合）、PR-B（v1：色变 + 铁砖 + L2 反馈，依赖 Spike 2/3/4 结果）
4. taste-draft 常量生成后交 human-review 定稿；定稿后追加 docs/TASTE.md 条目
5. 参考文件：`docs/PLAN-rogue-pong.md` §3.1/§3.3/§5、`docs/PRD/464-visual-three-color-layer.md`（三色约束先例）、`docs/PRD/449-bg-neon-breath.md`（L0 呼吸模式先例）、`docs/TASTE.md`（审美坐标）
