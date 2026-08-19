# PRD #582 — [Rendering] 雪夜氛围（雪幕 / 冷月光 / 水墨晕染 / 血色 vignette）

> **Issue:** #582
> **标签:** enhancement, graphics, content, workflow/research, version/mvp
> **深度:** standard（GitHub 无 depth label；分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=11 标注 `depth: standard` → §1–6 + §8 必填，§7 含实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **所有权:** `content_ownership: taste-draft`（taste-ownership-domains B3 视觉/艺术方向——配色、光效强度、粒子密度；agent 草稿 = 符合审美坐标的实现，用户经 E2E 截图裁决 ≥70% 定稿；PR 用 `Parent #582` 不写 Closes，assign 用户定稿）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死；mini-pong 脚本仅作模式参考）
> **研究选项:** Obsidian 知识库已搜索（`~/Documents/Obsidian Vault/`，wiki+raw grep 雪/月光/水墨/氛围/只狼/黑白）+ 开源调研（GitHub repo 检索 + Godot Asset Library API + godotshaders 社区，见 §6.2）+ brief（`docs/RAW/shandong-wolf-brief.md` §审美坐标/§画面实现路径）+ GDD（`docs/GAME_DESIGN/shandong-wolf/01-OVERVIEW.md`）+ 配方（game-to-issues `references/visual-implementation-path.md` §1–5）+ #572 落地代码（origin/main 实测）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=11，estimate 3d，priority medium）
> **前置依赖:** #572（CLOSED，merged #599/#600）— constants.gd + state_machine.gd + Game autoload + 测试三入口已合入 origin/main；#583 战斗场景依赖本 issue（dep edge 11→12）

---

## 1. 问题定义

### 1.1 现状（shandong-wolf 氛围现状，2026-08-19 侦查 origin/main）

| 文件 / 能力 | 状态 | 说明 |
|------------|:----:|------|
| `shandong-wolf/gdscripts/constants.gd` | ✅ 已存在（#572） | `WolfConstants`（class_name），5 个手感 # DRAFT 分区（弹反窗口/架势回复/两条命/刀伤害/帧节奏），格式 = 候补值注释 + 该值影响什么 + 情感断言；**无氛围参数分区** |
| `shandong-wolf/gdscripts/game.gd` | ✅ 已存在（#572） | Game autoload 锚点（`[autoload] Game="*res://gdscripts/game.gd"`），preload constants；无渲染职责 |
| `shandong-wolf/gdscripts/state_machine.gd` | ✅ 已存在（#572） | 通用状态机基类（本 issue 不涉及） |
| `shandong-wolf/scenes/Main.tscn` | ✅ 存在 | 纯标题场景（8 节点，CanvasLayer layer=1：TitleLabel「山东抗日之狼」/SubtitleLabel「雪夜 · 大刀 · 山东村」/VersionLabel/PostMergeProbeLabel）；**零视觉氛围**——无雪幕、无冷月光、无水墨、无 vignette；窗口 1280x720 固定（`resizable=false`） |
| 全屏渲染层 | ❌ 无 | 无 CanvasModulate、无全屏 shader 覆盖层、无 CanvasLayer 分层约定（现有仅 UI layer=1） |
| 玩家低血信号 | ❌ 不存在 | 玩家实体（#575，backlog 未实现）→ `low_health` 信号契约需本 PRD 先行定义（参数契约→执行层模式，Patch 19） |
| 开源方案 | ❌ 无成熟可复用 | 调研结论见 §6.2 |

**核心缺口：** 雪夜是本游戏『第一印象』（brief §审美坐标：苍白、清冷、大地如墨），但当前启动画面（标题场景）与后续战斗场景均无任何氛围层——雪幕 / 冷月光 / 水墨晕染 / 血色 vignette 四层系统全部缺失，且无渲染分层约定与氛围参数集中地。本 issue 交付 = 四层氛围组件 + 参数集中（constants.gd 氛围分区）+ 场景无关挂载约定 + E2E 截图裁决机制。

### 1.2 验收条件（源自 Issue #582 body，映射到各阶段 agent）

| # | 验收条件 | 负责阶段 | 本 PRD 的保障措施 |
|---|---------|---------|------------------|
| AC1 | 雪幕粒子数 200±10%，三层视差（远景 0.2x/中景 0.5x/近景 1.0x）且近景雪更大（scale 1.5x 远景 0.5x） | implement + test | §4.1 方案 A：3×GPUParticles2D + Parallax2D（scroll_scale 0.2/0.5/1.0）；test_atmosphere 断言粒子总数 180–220、三层 scale/scroll_scale |
| AC2 | CanvasModulate 色温 #b8c4d9，场景整体呈冷月色调 | implement + 用户裁决 | §4.2 方案 B（候选 A/C 见 Spike 3）；断言节点存在 + color 值；观感由 E2E 截图 |
| AC3 | 水墨 shader 在全屏生效，边缘暗角 alpha ≤0.3（不遮挡战斗读图） | implement + test | §4.3 方案 A；uniform `edge_alpha ≤ 0.3` 硬断言 |
| AC4 | 玩家 low_health 信号触发血色 vignette 平滑 0.5s 渐变（alpha 0→0.35） | implement + test | §4.4 方案 A：CanvasLayer + shader + Tween 0.5s；debug_trigger 兜底（#575 未建） |
| AC5 | E2E 截图提交用户裁决：雪夜氛围 ≥70%『黑白电影/水墨画』质感且不干扰战斗可读性 | implement + 用户 | §5.1 AC5：实现 PR 附截图 + issue 评论 + assign 用户（taste-draft 校准接口：视觉参数 + 截图对比） |

**注（issue body 内部不一致的裁决）：** body 功能描述写「分近景远景**两层**视差」，但画面实现路径与 AC1 均写**三层**（0.2x/0.5x/1.0x）。**以 AC1 三层为准**（验收条件优先 + 画面实现路径详细级更高）。

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家首启（标题场景 = 第一印象） | 每次启动 | 雪夜氛围随 Main.tscn 首帧成立：雪幕飘落 + 冷月色调 + 水墨质感，先于任何玩法传达『雪夜大刀』基调 |
| B | 战斗场景（#583，dep edge 11→12） | #583 实现时 | 氛围层场景无关复用（同一 `atmosphere_layer.tscn`），无需重写；月亮视觉节点归 #583 |
| C | 用户裁决（taste-draft） | 实现 PR 合并前 | E2E 截图 → issue 评论 → 用户主观评分 ≥70% 黑白电影/水墨质感 → 参数定稿 |
| D | 后续调参（Boss 战雪势加大，配方 §1 `snow_wind`） | 未来 feature | constants.gd 氛围分区 + @export 调参，无需改代码结构 |

### 1.4 范围边界（与既有 PRD / 后续 issue 去冲突，Patch 14）

| PRD / Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|------------|---------|------------------|
| #572（骨架，CLOSED） | constants.gd 结构 + Game autoload + 测试三入口 | ❌ 不重建地基；只**追加**「氛围参数」# DRAFT 分区（照既有分区格式） |
| #583 [Scene] 战斗场景（deps 含本 issue） | 场景几何（雪地平台/草屋剪影/山峦枯树）+ **月亮节点（圆 + 光晕）** | ❌ 不做场景搭建、不建月亮视觉节点；只交付**场景无关**的氛围层组件（CanvasModulate 色温 ≠ 月亮节点） |
| #575 玩家实体（backlog） | 玩家状态机/生命值/`low_health` 信号**发射端** | ❌ 不实现玩家实体；只定义 `set_low_health()` 消费契约 + debug 触发 |
| #576 [UI] HUD | 血条/架势条（水墨极简，月白 #e8e6e3） | ❌ 不设计 HUD；氛围色与 HUD 冷色系保持一致（#b8c4d9 vs #e8e6e3） |
| #584 战斗数值 DRAFT | 手感数值候补表 + 定稿（A1 域） | ❌ 氛围参数定稿走本 issue E2E 用户裁决（B3 域），不并入 #584 |
| #586 E2E 剧本 | 6 关键帧录制 + 完整自动化 | ❌ 本 issue 仅需**单帧氛围截图**供裁决；完整剧本归 #586 |
| mini-pong #491/#527/#464/#217 | 雨幕/暗角/霓虹实现 | ❌ 不复制代码；rain_curtain.gd / vignette.gdshader / neon_glow.gdshader 仅作**模式参考**（§8 注明可读文件） |

### 1.5 预期行为（最小氛围语义）

1. **雪幕**：3×GPUParticles2D（远景 0.2x / 中景 0.5x / 近景 1.0x Parallax2D 挂载），粒子 200±10%（远 60 / 中 60 / 近 80），飘落速度 20–40px/s（initial_velocity 向下 + 轻重力），近景 scale 1.5x / 远景 0.5x，白色 α70–90%，`snow_wind` 风向参数（默认 0，Boss 战可加大）。
2. **冷月光**：CanvasModulate 色温 #b8c4d9，「亮度 0.6」语义候选见 §4.2 / Spike 3（推荐色值换算单节点，避免组合语义漂移）。
3. **水墨晕染**：全屏 ColorRect + canvas_item shader（~20 行 GLSL）——smoothstep 径向边缘暗角 + 噪声扰动（墨色渗化抖动），暗角 alpha ≤0.3 硬约束；墨色参考 #1a1f26。
4. **血色 vignette**：CanvasLayer(layer=10) + 径向 shader，alpha 0→0.35，`low_health` 触发后 0.5s 平滑渐变（Tween）。
5. **参数集中**：全部进 `constants.gd` 氛围分区（# DRAFT + 候补值 + 情感断言，格式照 #572），controller 以 `@export` 调参（默认取常量）。
6. **E2E 裁决**：实现 PR 附截图，提交用户 ≥70% 评分。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（`~/Documents/Obsidian Vault/`，wiki + raw 全量 grep：`雪|月光|水墨|晕染|氛围|只狼|黑白`）。
- **命中笔记：**
  - **《独立游戏开发讨论》§四「雪夜项目的教训」**（wiki，2026-06-18 录音整理）与 **《2026-06-18 独立游戏开发与设计思路讨论》§三**：*「内容向游戏：需要阶段性起承转合，序章结尾草率就不行……不用憋太久，做 20-50% 就可以放出去」* → 支撑 MVP 氛围策略：四层系统**立住骨架 + 基础参数即可交付裁决**，终极精修后置（拒绝过度工程）。
  - **《体验引擎-glossary》Atmosphere（氛围）**：*「弥漫在整个体验中的情感背景，在没有特定事件吸引注意力时被感知」* → 直接支撑 AC3/AC5「不干扰战斗读图」：氛围是**被感知的背景层**而非注意力主角，alpha/对比度上限是硬约束而非可选项。
  - **《体验引擎-patterns》**：《BioShock》氛围开场案例（氛围开场立住世界基调）→ 佐证标题场景即挂氛围层的正确性（场景 A）。
  - **《九十年代素材与文化参考》**：地摊猎奇美学「氛围参考」（弱相关，仅佐证氛围=记忆点）。
- **Vault 无只狼/水墨 shader 技术笔记**（grep `只狼|水墨` 命中均为无关内容）→ 技术权威源 = brief §审美坐标（苍白/清冷/大地如墨、禁止五彩缤纷/阳光明媚/星光点缀）+ 配方 `visual-implementation-path.md` §1–5（雪幕/月光/水墨/血色四配方）+ mini-pong 同构先例（origin/main 实测存在）。

---

## 2. 设计意图

### 2.1 现状为何存在

| 原因 | 详情 |
|------|------|
| 骨架链路只交付「可运行」 | #559/#562/#563/#570 打通标题场景 + CI + E2E 冒烟，视觉氛围被有意推迟（骨架期克制原则，CUSGA 评选笔记语境） |
| 渲染层未排期 | #572 交付逻辑地基（constants/state_machine/autoload），渲染层排在本 issue |
| 配方刚定稿 | `visual-implementation-path.md` 2026-08-19 随 brief 迭代定稿 → 程序化配方（GPUParticles2D / CanvasModulate / canvas_item shader）刚具备落地条件 |

### 2.2 为何现在

1. **#572 已合入**（#599/#600）→ 氛围参数有 `constants.gd` 集中地 + Game autoload 锚点，参数红线（禁散落硬编码）可落地。
2. **雪夜 = 『第一印象』**（brief）→ 标题场景即首启画面，氛围层实例化进 Main.tscn 后 E2E 截图**立即可裁决**（taste-draft 校准接口就绪，无需等战斗场景）。
3. **#583 依赖本 issue**（dep edge 11→12）→ 氛围组件必须先于战斗场景落地，且必须场景无关化（#583 直接复用）。
4. **MVP 完成定义**（brief：可玩动作系统 + **雪夜像素氛围成立**）→ MVP 顺序上氛围先于/并行于战斗场景。

### 2.3 之前约束（继承 issue + brief + 配方，Patch 19）

| 约束 | 详情 |
|------|------|
| 零贴图 / 程序化生成 | 全部 GPUParticles2D + shader，禁止外部美术资产（AC5 于 #572 的延续） |
| 参数集中 | 所有视觉参数必须集中 `constants.gd` # DRAFT，禁止散落硬编码（#572 红线延续） |
| 审美坐标 | 只狼苇名城雪夜 + 抗战黑白电影月光：苍白、清冷、大地如墨；**禁止五彩缤纷、阳光明媚、星光点缀** |
| 环境低饱和 / 关键物高对比 | 配方 §0：环境饱和度低、关键交互物（刀光/血色）高对比——玩家视线引导 |
| 开源优先 | issue 🔍 段：先调研成熟开源方案，找不到再自行实现，PR 说明调研结果（§6.2） |
| taste-draft 所有权 | PR 用 `Parent #N` 不写 Closes；assign 用户定稿；参数全 # DRAFT 候补值 |
| 引擎 / 窗口 | Godot 4.7.1；1280x720 固定窗口（resizable=false） |
| 版本 | mvp（estimate 3d，priority medium） |

---

## 3. 影响分析

### 3.1 直接影响文件

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/constants.gd` | 参数集中 | **追加**「氛围参数（# DRAFT 候补值，定稿 = 本 issue E2E 用户裁决）」分区：雪幕（SNOW_*）/月光（MOONLIGHT_*）/水墨（INK_*）/血色（BLOOD_*）四组常量 + 情感断言注释（照 #572 既有格式） |
| `shandong-wolf/scenes/Main.tscn` | 标题场景 | 实例化 `atmosphere_layer.tscn`（层级挂载）；标题文字对比度保持（AC2 验证点） |
| `shandong-wolf/e2e_shots.json` | E2E | 追加「雪夜氛围」单帧（供用户裁决；完整剧本归 #586） |
| `shandong-wolf/tests/run_tests.gd` | 测试入口 | 挂载 `test_atmosphere.gd`（当前为占位「skeleton — no tests yet」） |

### 3.2 新文件

| 文件 | 职责 |
|------|------|
| `shandong-wolf/gdscripts/atmosphere_controller.gd` | 氛围编排统一入口：驱动雪幕/月光/水墨/血色四子系统；`set_low_health(enabled)` 契约 API + `debug_trigger_low_health()`（#575 未建期兜底） |
| `shandong-wolf/gdscripts/snow_curtain.gd` | 三层雪幕控制器（GPUParticles2D ×3 + Parallax2D ×3）：速度/scale/风向调参；**禁改 amount**（rain_curtain 教训，见 §4.1） |
| `shandong-wolf/gdscripts/ink_wash.gdshader` | 全屏水墨 canvas_item shader（~20 行 GLSL：径向暗角 + 噪声渗化） |
| `shandong-wolf/gdscripts/blood_vignette.gd` + `blood_vignette.gdshader` | 血色 vignette（CanvasLayer layer=10 + ColorRect + 径向 shader + 0.5s Tween） |
| `shandong-wolf/scenes/atmosphere/atmosphere_layer.tscn` | 氛围层场景组件（场景无关，Main.tscn 与 #583 共用） |
| `shandong-wolf/tests/test_atmosphere.gd` | 参数存在性 + 三层视差/粒子数/scale + alpha 上限 + tween 时长 + shader 编译 |

### 3.3 间接影响

- `Game` autoload（game.gd）：可选提供 `Atmosphere` 访问点（非必须，控制器随场景组件即可）。
- **#583 战斗场景**：直接复用 `atmosphere_layer.tscn`（月亮视觉节点归 #583，无冲突）。
- **#575 玩家实体**：按 §8 契约发射 `low_health` 信号接入 `set_low_health()`。
- **#576 HUD**：调色板冷色系一致性（月白 #b8c4d9 ↔ HUD 月白 #e8e6e3）。
- **CI**：`check_compile.gd` 自动纳入新 .gd/.gdshader（#572 机制，零改动）。

### 3.4 数据流

```
WolfConstants（氛围分区 # DRAFT：SNOW_*/MOONLIGHT_*/INK_*/BLOOD_*）
    │ preload
    ▼
atmosphere_controller.gd（@export 调参，默认 = 常量）
    ├── snow_curtain.gd ──► 3×Parallax2D(0.2/0.5/1.0) ──► 3×GPUParticles2D
    │                         （initial_velocity/scale/alpha 调参，禁 amount）
    ├── CanvasModulate（color #b8c4d9，亮度 0.6 语义 §4.2）
    ├── ink_wash.gdshader（uniform: edge_alpha ≤0.3 / noise_amount / ink_color）
    └── blood_vignette.gd ──► ColorRect + shader（alpha 0→0.35，Tween 0.5s）
            ▲
            │ low_health 信号（#575 未来发射端）
            └── debug_trigger_low_health()（当前测试/E2E 兜底）

E2E 截图（headless 捕获）──► issue 评论 ──► 用户裁决 ≥70% ──► 参数定稿（taste-draft）
```

### 3.5 文档更新

- [x] `docs/PRD/582-snow-night-atmosphere.md`（本文件）
- [ ] `docs/GAME_DESIGN/shandong-wolf/` 场景结构表（实现合并后由 post-merge agent 更新）
- [ ] `visual-implementation-path.md` 无需变更（本 PRD 即其落地实例）

---

## 4. 方案对比（多子系统 PRD，Patch 19：4.1–4.4 各子系统独立对比）

### 4.1 雪幕（GPUParticles2D 三层视差）

**方案 A：3×GPUParticles2D + 3×Parallax2D（scroll_scale 0.2/0.5/1.0），controller 统一驱动 —— 推荐**

| 维度 | 内容 |
|------|------|
| Pros | 视差/scale/密度独立控制，直接满足 AC1（200±10%、0.2x/0.5x/1.0x、scale 0.5x/1.5x）；Parallax2D 是 Godot 4.7 原生视差节点，#583 相机移动时自动生效；参数可断言（test 读 material/scale/scroll_scale） |
| Cons | 3 节点需统一生命周期管理（一个 controller 负责，成本低） |
| Risk | Low |
| Effort | 0.5–1d |

**方案 B：单 GPUParticles2D + shader 内伪视差分层**

| 维度 | 内容 |
|------|------|
| Pros | 单节点 |
| Cons | AC1 的三层 parallax 与 scale 差异需 shader 手工模拟（按 y 分区），脆弱且难断言；速度差需 shader 内偏移，粒子大小差异受限；违背「三层视差」显式验收 |
| Risk | Med |
| Effort | 1–1.5d |

**推荐 A。** 关键约束（rain_curtain 教训，mini-pong `rain_curtain.gd` 头注释）：**调参禁改 `amount`**——Godot 改 amount 会重启粒子系统 → 可见跳变；密度/速度/大小一律经 initial_velocity / scale / color alpha 表达（`snow_wind` 调参同此路径）。粒子分配：远 60 / 中 60 / 近 80 = 200（AC1 中心值）。

### 4.2 冷月光（CanvasModulate）

**语义说明：** CanvasModulate 无独立 brightness 属性（仅 color）；「亮度 0.6」必须落在具体实现语义上。

| 方案 | 描述 | Pros | Cons | Risk / Effort |
|------|------|------|------|---------------|
| A | `CanvasModulate.color = #b8c4d9`（月白直用），亮度 0.6 由场景根 modulate(v=0.6) 组合 | 色温直观（AC2 字面值） | 双节点组合语义，调参需两处同步，易漂移 | Med / 0.5d |
| **B（推荐候选）** | 色值换算：`#b8c4d9 × 0.6 ≈ #6e7684` 作为 CanvasModulate.color | 单节点单一事实源；「亮度」内化进色值；断言直接 | 色值非 AC2 字面值（需注释换算过程） | Low / 0.5d |
| C | `color=#b8c4d9` + 全局 ColorRect 半透明冷灰叠加 | 可独立调亮度 | 多加一层覆盖，与水墨层叠加语义复杂 | Med / 0.5d |

**推荐 B（候选 A 备用），Spike 3 截图对比后并入 E2E 裁决（taste-draft）。** 参考配方（visual-implementation-path §2）的暗基底 `#2a3a4a` 与 issue AC2 的月白 `#b8c4d9` 冲突 → **以 issue AC2 为准**，`#2a3a4a` 记入候补值注释（供用户裁决时对照）。

### 4.3 水墨晕染（全屏 canvas_item shader）

**方案 A：全屏 ColorRect（CanvasLayer layer=2）+ canvas_item shader —— 推荐**

- ~20 行 GLSL：`smoothstep` 径向边缘暗角 + `fract(sin(dot(...)))` hash 噪声扰动（墨色渗化抖动）+ COLOR 合成；墨色参考 `#1a1f26`（配方 §3）。
- Pros：零后处理管线；headless 编译安全（mini-pong `vignette.gdshader` 同构已验证）；`edge_alpha ≤ 0.3` 直接断言（AC3）；静态背景单 pass。
- Cons：覆盖层语义需层级约定（被 UI layer=1 之上的关键反馈层盖住）。
- Risk：Low；Effort：0.5d。

**方案 B：BackBufferCopy + 后处理 pass**

- Pros：可做真模糊/渗化。
- Cons：多 pass 开销 + headless/CI 风险；水墨「渗化」用噪声扰动即可达意，无需真模糊（配方 §3 明示）。
- Risk：Med；Effort：1.5d。

**推荐 A。** AC3 硬约束（暗角 alpha ≤0.3 不遮挡读图）+ 配方 §3「静态背景单 shader 覆盖」明确。

### 4.4 血色 vignette（CanvasLayer）

**方案 A：CanvasLayer(layer=10) + ColorRect + 径向 shader（mini-pong `vignette.gdshader` 改血色版）+ Tween 0.5s —— 推荐**

- alpha 0→0.35（AC4 硬上限，shader uniform 断言）；0.5s 平滑渐变（Tween，ease 可 taste）。
- Pros：独立层独立职责；契约干净（`set_low_health(enabled)`）；径向暗角与战斗读图不冲突（中央透明）。
- Cons：多一层 CanvasLayer（成本可忽略）。
- Risk：Low；Effort：0.5d。

**方案 B：与 ink_wash 合并为单 shader 双模式**

- Cons：血色（事件态）与水墨（常态）职责耦合；层级/状态切换复杂；低血时才出现的需求与常驻水墨冲突。
- Risk：Med；Effort：1d。

**推荐 A。** low_health 契约：`AtmosphereController.set_low_health(enabled: bool)`（内部 0.5s tween）；#575 玩家实体未来 emit `low_health` 信号 → controller 连接；当前 `debug_trigger_low_health()` 供测试/E2E 驱动（参数契约→执行层模式，Patch 19）。

### 4.5 挂载策略（场景组件 vs autoload）

| 方案 | 描述 | Pros | Cons | Risk / Effort |
|------|------|------|------|---------------|
| **A（推荐）** | `atmosphere_layer.tscn` 场景组件，实例化进 Main.tscn | 场景无关（#583 复用同一 .tscn）；渲染层随场景生命周期；层级直观 | 每场景需显式实例化（约定写入 §8） | Low / 0.5d |
| B | AtmosphereController 注册 autoload（project.godot `[autoload]`） | 全局常驻，无需实例化 | 纯逻辑场景也常驻渲染节点；违背「氛围是场景渲染层」的 Godot 惯例 | Med / 0.5d |

**推荐 A。**

### 4.6 推荐汇总表

| 子系统 | 推荐 | 核心文件 | 关键约束 |
|--------|------|---------|---------|
| 雪幕 | A：3×GPUParticles2D + Parallax2D | `snow_curtain.gd` | 禁改 amount；200±10%（60/60/80）；视差 0.2/0.5/1.0；scale 0.5/1.5 |
| 冷月光 | B（候选 A/C，Spike 3 裁决） | `atmosphere_controller.gd` | 色温 #b8c4d9（换算 #6e7684≈×0.6）；单节点 |
| 水墨 | A：ColorRect + shader | `ink_wash.gdshader` | 暗角 alpha ≤0.3；~20 行 GLSL；墨色 #1a1f26 |
| 血色 | A：CanvasLayer + shader + Tween | `blood_vignette.gd/.gdshader` | alpha 0→0.35；0.5s；`set_low_health()` 契约 |
| 挂载 | A：场景组件 | `atmosphere_layer.tscn` | Main.tscn 实例化；#583 复用 |

---

## 5. 边界条件与验收标准

### 5.1 验收条件（AC checklist，源自 issue body）

- [x] **AC1：雪幕粒子数 200±10%，三层视差，近景更大** — 断言：test_atmosphere 数 GPUParticles2D 节点 = 3，amount 合计 180–220（远 60/中 60/近 80），Parallax2D scroll_scale = [0.2, 0.5, 1.0]，近景 scale 1.5x / 远景 0.5x
- [x] **AC2：CanvasModulate 色温 #b8c4d9，冷月色调** — 断言：节点存在 + color 值（方案 B：`#6e7684` 带换算注释）；观感由 E2E 截图（含标题文字可读性）
- [x] **AC3：水墨 shader 全屏生效，暗角 alpha ≤0.3** — 断言：uniform `edge_alpha ≤ 0.3`（不遮挡战斗读图硬约束）
- [x] **AC4：low_health 触发血色 vignette 0.5s 平滑渐变（0→0.35）** — 断言：`debug_trigger_low_health()` 后 Tween 时长 0.5s、终点 alpha 0.35（读取渐变曲线采样）
- [x] **AC5：E2E 截图提交用户裁决（≥70% 黑白电影/水墨质感 + 不干扰可读性）** — implement PR 附 headless 截图 + issue 评论 + assign 用户（taste-draft 定稿机制）
- [ ] **附加红线**：参数全部集中 constants.gd 氛围分区 # DRAFT + 情感断言；零外部美术资产；禁 amount 直改

### 5.2 边缘情形

1. **amount 被误改/漂移** → test 断言 180–220 区间，越界 CI 红（rain_curtain 教训的守卫）。
2. **三层视差屏幕边缘穿帮**（1280x720 下近景层覆盖不足）→ 层尺寸 ≥ 视口 + margin（配方 §1 惯例），test 或人工截图复核。
3. **headless CI 编译 shader** → check_compile 自动纳入新 .gd/.gdshader，语法错误即红（#572 机制）。
4. **CanvasModulate 提亮后标题文字对比度下降** → AC2 实现期验证标题可读（E2E 截图含标题场景），必要时墨色加深补偿。
5. **low_health 信号缺失期（#575 未实现）** → `debug_trigger_low_health()` 兜底；契约文档化（§8），#575 实现时按契约接入。
6. **#583 战斗场景复用时的层级冲突**（月亮节点/雪幕先后、相机视差联动）→ 层级约定写入 §8（CanvasLayer 2=水墨 / 3–5=雪幕远中近 / 10=血色；UI layer=1 不动）。
7. **水墨暗角叠加雪幕近景导致叠加 alpha 超标** → 径向设计保证画面中央读图区不受影响；叠加后边缘 alpha 上限验证。
8. **性能预算**：200 粒子 GPU 开销可忽略；全屏 shader 单 pass；1280x720 目标 ≥55fps（帧耗时断言可选）。

### 5.3 失败路径

1. **shader 编译失败** → check_compile 红 → 本地 headless 复现修 shader（mini-pong 先例可对照）。
2. **E2E 截图黑屏/全白**（CanvasLayer 层级/覆盖错误）→ 层级断言 + 人工截图复核。
3. **用户裁决 <70%** → 参数迭代（# DRAFT 机制：改 constants 候补值 → 重跑 E2E → 再裁决），不重写架构（taste-draft 队列模式）。
4. **Tween 不触发（信号未连）** → test 断言 0.5s 渐变曲线 + debug 触发路径。

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #572（constants.gd / Game autoload / 测试三入口） | ✅ CLOSED，merged #599/#600 | Low |
| #583 战斗场景 | ⏳ 依赖本 issue（dep edge 11→12） | 反向依赖，不阻塞本 issue |
| #575 玩家实体（low_health 信号源） | ⏳ backlog | Med：信号缺失 → `debug_trigger_low_health()` 兜底 |
| 开源方案 | 无成熟（§6.2） | Low：自行实现 + 项目内同构先例 |

### 6.2 开源调研结果（issue 🔍 段要求——PR 必须说明）

| 渠道 | 查询 | 结果 | 结论 |
|------|------|------|------|
| GitHub repo | `godot snow` / `godot snowflakes` | 8 个结果全部 ≤2★（Swarkin/Godot-SnowflakesAddon 1★、realjf/godot-snow-demo 2★、qewqew-games/godot-snowflakes 0★ 等），均为 demo/教学性质，无维护无文档无测试 | ❌ 不可复用 |
| Godot Asset Library | `snow`（4.x） | 1 条无关结果（schmove，作者名含 snow） | ❌ 无 |
| Godot Asset Library | `ink`（4.x） | 0 条 | ❌ 无 |
| godotshaders 社区 | snow / ink-wash | 检索不可达/无收录雪夜水墨方案 | ❌ 无 |

**结论：无成熟开源方案可复用 → 自行实现**（issue 允许「找不到再自行实现」）。项目内已有同构先例（mini-pong `rain_curtain.gd` 雨幕配方 / `vignette.gdshader` / `neon_glow.gdshader`，origin/main 实测存在），实现成本可控。

### 6.3 依赖链图

```
#572 骨架（CLOSED：constants.gd + autoload + 测试）
   │
   ▼
#582 本 issue（氛围四层 + 参数集中 + E2E 截图裁决）
   │
   ▼
#583 战斗场景（复用 atmosphere_layer.tscn + 月亮节点）
   │
   ▼
#585 组装 / #586 E2E 剧本（6 关键帧）
```

---

## 7. Spike / 实验（standard 深度含实验，3 项）

1. **全屏覆盖层方案验证（水墨）** — Question：ColorRect + canvas_item shader（方案 A）在 headless 编译 + 1280x720 实机截图的正确性；Method：最小 shader 挂全屏 ColorRect → `godot --headless --quit` 编译 + 截图对比 BackBufferCopy 路径；Expected：编译过、截图有径向暗角、无性能异常；Impact：确认方案 A 可行性，排除 CI 风险。
2. **三层雪幕观感验证** — Question：粒子分配 60/60/80、飘落 20–40px/s、scale 0.5/1.0/1.5 的纵深是否成立；Method：`snow_wind=0` 基线截图（近景大而快 / 远景小而慢）；Expected：三层纵深肉眼成立；Impact：参数进 constants 候补值，微调归用户裁决。
3. **CanvasModulate「亮度 0.6」语义对比** — Question：候选 B（`#6e7684` 单节点）vs 候选 A（`#b8c4d9` + modulate）同帧截图差异；Method：两实现各截图一张（同场景同帧）；Expected：语义最简者胜出（倾向 B），并入 E2E 裁决；Impact：锁定 AC2 实现语义（可并入 AC2 实现期，非阻塞）。

---

## 8. 交接上下文（给 plan agent）

- **系统现状**：shandong-wolf 骨架 + 逻辑地基（#572 已合入 origin/main），Main.tscn 纯标题场景（CanvasLayer layer=1 为 UI）；氛围四层全部待建；`constants.gd` 已有 5 个手感 # DRAFT 分区（格式：候补值注释 + 该值影响什么 + 情感断言）。
- **推荐组合**：§4.6 表——3×GPUParticles2D+Parallax2D 雪幕 / CanvasModulate 候选 B（#6e7684≈#b8c4d9×0.6）/ ColorRect+shader 水墨（alpha≤0.3）/ CanvasLayer(layer=10) 血色 vignette（0→0.35，0.5s）/ `atmosphere_layer.tscn` 场景组件实例化进 Main.tscn。
- **硬约束（实现不得违反）**：①禁改 `amount`（rain_curtain 教训）；②水墨暗角 alpha ≤0.3；③血色 alpha ≤0.35 + 0.5s 渐变；④粒子 200±10%（60/60/80）+ 视差 0.2/0.5/1.0 + scale 0.5/1.5；⑤参数全进 constants.gd 氛围分区 # DRAFT，禁止散落硬编码；⑥零外部美术资产。
- **契约 API（未来消费方）**：`AtmosphereController.set_low_health(enabled: bool)` + `debug_trigger_low_health()`；#575 玩家实体实现后 emit `low_health` 信号接入（发射端由 #575 负责，本 issue 只建消费端）。
- **层级约定**：CanvasLayer layer 2=水墨、3–5=雪幕（远/中/近）、10=血色 vignette；现有 UI layer=1 不动；#583 复用同一 .tscn 时照此约定。
- **定稿机制（taste-draft）**：参数 # DRAFT 候补值 → implement PR 附 E2E 截图 + issue 评论 → assign 用户裁决 ≥70% → 定稿；PR 用 `Parent #582` 不写 Closes。
- **测试**：`test_atmosphere.gd`（参数存在/粒子数/视差 scale/alpha 上限/tween 时长/shader 编译）+ `run_tests.gd` 挂载 + check_compile 自动纳入。
- **主要风险**：亮度 0.6 语义（Spike 3 定）；low_health 信号源未建（debug 兜底）；用户裁决迭代次数（# DRAFT 机制吸收）。
- **后续依赖**：#583 战斗场景依赖本 issue 的氛围层组件（复用 + 月亮节点）；#586 E2E 剧本将氛围帧纳入 6 关键帧。
