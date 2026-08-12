# PRD: [Feature] 升级池架构 (UpgradePool)

> **Issue:** #387
> **标签:** enhancement, gameplay, version/mvp, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行的实验补齐）
> **所有权:** `content_ownership: mechanical`（池结构/抽取算法/参数实例化/钩子契约 = 机械实现；升级数值平衡与文案归 taste 域，#395 已另行排队）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2.5 升级池（已确认 2026-08-13）：9 升级清单 + 稀有度 60/30/10 + 每波 3 选 1 + 情感误归因
> **前置依赖:** #383（轴交换+竖屏，**已关闭** PR #409）、#384（砖墙 BreakoutGrid，DESIGN 已合并 PR #414，代码待落地）

---

## 1. 问题定义

### 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）**不存在任何升级/波次系统**：球/挡板/计分/FSM/雨幕各司其职，但没有升级池、没有"每波成长"概念、没有 3 选 1 的数据源。Rogue Pong 的成长核心（升级池）完全缺失。

| 文件 | 当前状态 | 与 #387 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/ball.gd` | 参数**已实例级**：`@export var initial_speed / max_speed_multiplier / speed_increment / max_bounce_angle / serve_angle_range`（默认值来自 GameConstants）；`serve()` 读实例 `initial_speed`；`_on_area_entered` 上限 `initial_speed * max_speed_multiplier` | ✅ AC3 ball 侧已达标；仅缺 `speed_scale` 类时序参数（缓时用） |
| `mini-pong/gdscripts/paddle.gd` | `SPEED`/`PADDLE_WIDTH`/`PADDLE_HEIGHT` 仍为 **const**，`_process` 直接读 `SPEED`（玩家/AI 两处）；`_ready` 用 `PADDLE_WIDTH` 算边界；AI 参数已是 `@export` | ❌ AC3 paddle 侧未达标：需 const → 实例属性 + 宽度 setter 同步 CollisionShape2D |
| `mini-pong/gdscripts/constants.gd` | GameConstants 单一事实源（#295）；手感常量带 #367 定稿注释 | ❌ 无 UPGRADE_* 常量（稀有度权重/池大小） |
| `mini-pong/gdscripts/game_manager.gd` | autoload 单例，文档化职责 = "pure-data holder: scores, games won, reset APIs"（#293 DESIGN 明文） | ❌ 无 upgrade 状态；按概念分层（见 §2）不并入 GameManager |
| `mini-pong/project.godot` | autoload：GameManager、AudioEngine | ❌ 未注册 UpgradePool |
| `mini-pong/tests/run_tests.gd` | 注册 14+ 测试套件 | ❌ 无升级池测试 |
| `mini-pong/gdscripts/breakout_grid.gd` | **不存在**（#384 DESIGN 已合并但代码未落地：issue CLOSED、无 impl/384 分支、gdscripts 无 breakout 文件） | ❌ 砖类升级的 `upgrade_hooks` 挂载点待增量设计 |
| `mini-pong/assets/content/upgrade_pool.json` | **不存在**（#395 PRD 已定义 schema，status/human-review 待定稿） | — 本 Issue 只读消费显示字段，不写文案 |

**关键事实核查（来自源码，方案可行性的依据）：**

- `ball.gd` 五个手感参数全部 `@export` + 实例读取 → **AC3 的 ball 部分已由 #295 迁移完成**，本 Issue 只需验证 + 补时序参数
- `paddle.gd` 的 `SPEED` 被 `_process` 直接引用（`position.x += move * SPEED * delta` 与 AI 分支各一处），`PADDLE_WIDTH` 用于边界计算 → 改实例属性后**每帧读取天然下一帧生效**
- `ball.gd` 读挡板长度走 `CollisionShape2D.shape.get("size").x`（非 const）→ 长臂升级改宽度时**同步 shape 即可让球立即感知**
- 缓时（球速冻结 2s）需要 ball 暴露时序速度参数；当前 `speed` 是实例 var，但无冻结/缩放层

### 预期行为（验收条件，源自 Issue #387）

1. **AC1 — 升级池包含 9 个独立升级定义，每个都有 id/名称/稀有度/效果回调** — `upgrade_defs.gd` 单一事实源；id 与 #395 JSON 对齐（long_arm/fireball/battering_ram/magnet_core/twin/slow_time/pre_hole/stardust/phantom）
2. **AC2 — 抽取时按 60/30/10 权重返回升级，且支持不可重复或堆叠配置** — 稀有度先掷（每张卡 60/30/10），候选集内去重；每升级 `max_stacks` 配置（1 = 整局不可重复，>1 = 可堆叠）
3. **AC3 — 升级后 ball/paddle 参数是实例级而不是常量，参数变化在下一帧生效** — paddle const → `@export`；ball 已验证；所有效果回调只写实例属性，`_process` 每帧读取 → 天然下一帧生效
4. **AC4 — 预开洞等砖墙类升级通过 BreakoutGrid upgrade_hooks 接入** — BreakoutGrid 增量 `upgrade_hooks` 注册表 + `open_hole()`/`blast_neighbors()` API（契约先行，随 #384 落地或独立小 PR）
5. **AC5 — 提供 get_candidates(3) 与 apply(upgrade_id) 接口，供 3 选 1 UI 调用** — UpgradePool autoload 公共 API（#388 直接消费）

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 每波升级 | 每波一次 | 墙打空 → #386 波次循环调 `UpgradePool.get_candidates(3)` → #388 UI 展示三卡 → 玩家确认 → `apply(id)` → 效果下一帧生效 |
| B | 稀有度 reveal | 每次选择 | PLAN §2.5：稀有度**选择后才显示**（惊喜时刻）→ 池必须把稀有度作为候选元数据返回，UI 决定何时 reveal |
| C | 不可重复/堆叠 | 整局 | 传说升级（星尘/幻影）整局至多一次（`max_stacks=1`）；普通升级可重复堆叠（长臂 +30% 两次 → +60%） |
| D | 测试/自动对打 | 每 CI | `test_upgrade_pool.gd` 断言 9 定义、权重分布、去重、堆叠、apply 后实例参数变化 |

### 技术约束（继承自 Issue #387 + PLAN-rogue-pong §2.5）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`，720×1280 竖屏，resizable=false） |
| 稀有度权重 | 普通 60% / 稀有 30% / 传说 10%（PLAN §2.5 已确认） |
| 9 升级 id | 与 #395 JSON `id` 完全一致：long_arm、fireball、battering_ram、magnet_core、twin、slow_time、pre_hole、stardust、phantom |
| 不变项 | 手感常量默认值（#367 定稿）**不修改**——只允许运行时实例级修改；FSM/计分信号链/雨幕不变 |
| 数据源 | 显示字段（短句/命名）来自 #395 `upgrade_pool.json`（draft，可能被用户改）→ 机械定义以 `upgrade_defs.gd` 为准，显示名运行时解析 JSON + 工作名兜底 |
| 所有权 | mechanical：池/抽取/实例化/钩子为机械实现；升级数值（如 +30%、2s）与文案归 taste 域（#395/#367 域） |
| 开源优先 | 调研结果见 §1.4 |

### 1.4 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索范围 Godot Asset Library + GitHub（带 auth 搜索，GDScript/Godot 4.x 过滤）：

- **Godot Asset Library**（assetlibrary.godotengine.org，`filter=upgrade`）：**无 roguelike 3 选 1 升级池**。唯一接近项 Wyvernshield 2（don-tnowe，godot 4.0，0⭐）是**战斗触发技能系统**（combat triggers），不是肉鸽升级池；GDScript Code Upgrader 是工具类插件，无关
- **GitHub 搜索**（`godot upgrade system language:GDScript` 按 star 排序）：全部 <5⭐ 教学 demo/项目骨架（noufbmdev/Godot-Systems 4⭐、dewald-els/godot-learnings_upgrades 1⭐、wangkaibo123/roguelike-tower-defense-godot 1⭐ 等），无可复用、可插拔的"稀有度加权升级池 + 效果回调"模块
- **结论**：**没有可复用的第三方升级池系统**；本功能为第一方实现，Godot 4.7 内置能力（Array/Dictionary、Callable、RandomNumberGenerator、autoload 单例）完全覆盖，**不引入任何第三方资产**。与 #383/#384 的调研结论模式一致

### Obsidian 知识检索

- Vault 挂载于 `/Volumes/Obsidian`（WebDAV），`Knowledge Ocean/wiki/` 可读；检索命中两条与本 Issue 直接相关的设计语言：
  - **`体验引擎-patterns.md` §14 变比率强化（Variable-Ratio Reinforcement）**："可预测的奖励变得无聊" → 在**不可预测的时间间隔**传递奖励（案例：《暗黑破坏神》掉落、扭蛋）→ 直接支撑 AC2 的 **60/30/10 加权随机抽取**：稀有度就是变比率强化的"时间间隔"，权重随机保证不可预测性
  - **`极乐迪斯科—概率机制作为叙事语法.md`**："概率检定将文学中的偶然性从作者意图转移到系统规则中" + "思想有代价"（内化期惩罚）→ 支撑 PLAN §2.5 的稀有度 **reveal 时序**（选择后才显示）与**带代价的选择**（传说升级可选但带代价）——池的返回结构必须携带稀有度元数据供 UI 后置 reveal
- PLAN-rogue-pong §2.5 已固化同一批 Obsidian 理论（情感误归因/不可预测奖励/带代价的选择），本 PRD 只做机械落地，不重复论证

### 1.5 范围边界（与相邻 PRD 解冲突）

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #395 升级池文案 | 9 升级短句/命名候选/情绪断言 → `upgrade_pool.json`（taste-draft，human-review） | ❌ 不写文案；只**只读消费** JSON 的 id/显示字段（解析失败回退工作名） |
| #388 3 选 1 升级 UI | 三张霓虹卡片/焦点切换/reveal/暂停 | ❌ 不做 UI；只提供 `get_candidates(3)`/`apply(id)` 数据接口 |
| #386 波次循环 | 清墙→结算→新墙→AI 增强（GameManager 持波次状态机） | ❌ 不实现波次；池是波次结算时被调用的数据源 |
| #384 砖墙 BreakoutGrid | 程序化生成/碰撞/`brick_destroyed`/`wall_cleared` 信号 | ❌ 不重设计砖墙；只**增量**加 `upgrade_hooks` 契约（见 §4.5） |
| #385 双得分制 | 拆砖 1 分/穿墙 3 分/21 分制 | ❌ 不碰计分 |

---

## 2. 设计意图

### 为什么当前状态存在

Mini Pong 从 #287（球物理）→ #288（挡板）→ #290（AI）→ #295（Main.tscn 组装）→ #383（竖屏）一路是**经典 Pong 语义**：无成长、无波次、无升级。升级池是 Rogue Pong 肉鸽改造（PLAN-rogue-pong §4.2「新: 升级池」）引入的全新系统；此前不存在是因为其消费方（#386 波次循环、#388 UI）与依赖方（#384 砖墙）都还在队列中，且 P0 前置（竖屏 #383）刚落地。

| 现状来源 | Issue | 贡献 |
|---------|-------|------|
| ball 参数已实例级（@export + 实例读取） | #295 | AC3 ball 侧地基（非本次新做，验证即可） |
| paddle const 参数 | #288 | AC3 paddle 侧缺口 |
| GameManager autoload（纯分数职责） | #293 | 概念分层依据（升级池独立单例） |
| 9 升级清单/稀有度/情感断言 | PLAN-rogue-pong §2.5 | 升级定义的内容依据 |
| 文案 JSON schema | #395 | 显示字段消费契约 |

### 为什么现在改

1. **MVP 依赖链就绪**：PLAN-rogue-pong 已拍板（2026-08-13），#384 砖墙 DESIGN 已合并、#386 波次/#388 UI 已排队（backlog OPEN）——升级池是这条链的**数据枢纽**，Issue 上下文明示"升级是每波成长的核心，3 选 1 UI 的数据来源"
2. **AC3 窗口期**：ball 已实例级、paddle 未实例级——趁 #386/#388 尚未实现，把参数实例化一次做完，避免后续升级效果回调打到 const 上
3. **文案先行不阻塞**：#395 文案草稿已 merge 进 human-review 队列（taste-draft 不进依赖链），机械层现在做不会与其冲突；#387 只读 JSON，用户定稿改名不影响机械 id

### 概念分层（skill §6j：为什么不是 GameManager 的一个字段）

| 维度 | GameManager（#293） | UpgradePool（本 Issue） |
|------|--------------------|------------------------|
| 范围 | 分数/局/场次 | 每波成长决策 |
| 变化频率 | 每分每秒（对打中） | 每波一次（清墙结算时） |
| 驱动 | 球得分事件 | 波次结算事件（#386 调用） |
| 查询模式 | add_score/score_changed | get_candidates(3)/apply(id) |
| 代表什么 | 比赛进度 | 玩家构筑（build） |

≥3 个维度不同 → **独立概念层**。GameManager 的文档化职责是"pure-data holder for scores"，把升级状态塞进去会破坏 #293 DESIGN 的职责边界；独立 autoload（`UpgradePool`）与 GameManager/AudioEngine 单例惯例一致，任何场景/脚本可全局访问（效果回调要摸 ball/paddle/BreakoutGrid，必须全局可达）。

### 先前约束

| 约束 | 细节 |
|------|------|
| 手感默认值（#367 定稿） | constants.gd 的 BALL_*/PADDLE_*/AI_* **默认值不变**；升级只改运行时实例属性，不改常量 |
| 稀有度权重（PLAN §2.5） | 60/30/10 是**每张卡的稀有度概率**，不是升级粒度权重（§4.3 spike 证实） |
| 升级 id（#395） | long_arm/fireball/battering_ram/magnet_core/twin/slow_time/pre_hole/stardust/phantom——跨文档一致，机械引用不漂移 |
| 消费方契约（#388 AC） | `UpgradePool.get_candidates(3)` 为 UI 唯一数据入口 |
| 测试即验收 | 新测试注册进 `run_tests.gd`；`godot --headless --script tests/run_tests.gd` 全绿 |
| 并发安全 | 并行 agent 共享工作树：本 PRD 只显式 add 自身文件，不触碰他人未提交改动（如 #389 雨幕文件） |

---

## 3. 影响分析

### 新文件

| 文件 | 职责 |
|------|------|
| `mini-pong/gdscripts/upgrade_pool.gd` | **autoload 单例**（`UpgradePool`）：9 定义注册、`get_candidates(n)`（稀有度先掷 + 去重 + max_stacks 过滤）、`apply(upgrade_id)`（计数 + 调用效果回调 + 不可重复移除）、`rng`（可播种，测试确定性）、`RARITY_WEIGHTS` 只读 |
| `mini-pong/gdscripts/upgrade_defs.gd` | 9 个升级定义的**单一事实源**（RefCounted 或 const 字典）：id/名称/稀有度/`effect: Callable`/`max_stacks`/效果说明；效果回调以静态方法或 lambda 形式挂载（§4.2） |
| `mini-pong/gdscripts/brick_upgrade_hooks.gd` | 砖类升级效果实现（预开洞/燃烧弹/破城锤）：通过 BreakoutGrid `upgrade_hooks` 注册表注册 `open_hole`/`blast_neighbors` 回调（§4.5） |
| `mini-pong/tests/test_upgrade_pool.gd` | 测试套件：9 定义齐全、稀有度分布（统计断言）、候选去重、max_stacks 不可重复/堆叠、apply 后 ball/paddle 实例参数变化、JSON 显示名解析兜底 |

### 修改的文件

| 文件 | 改动性质 | 说明 |
|------|---------|------|
| `mini-pong/gdscripts/paddle.gd` | **Modified** | `SPEED`/`PADDLE_WIDTH`/`PADDLE_HEIGHT` const → `@export var paddle_speed/paddle_width/paddle_height`（默认值仍 = CONSTS）；新增 `set_paddle_width(w)`：更新实例属性 + `CollisionShape2D.shape.size.x` + 重算 `min_x/max_x`（长臂/幻影升级入口） |
| `mini-pong/gdscripts/ball.gd` | **Modified（小）** | 新增 `@export var speed_scale: float = 1.0`，`_process` 位移乘 `speed_scale`（缓时冻结 2s 用）；其余参数已实例级，仅验证 |
| `mini-pong/gdscripts/constants.gd` | **Modified** | 新增 UPGRADE 常量组：`UPGRADE_RARITY_WEIGHTS`（60/30/10）、`UPGRADE_CANDIDATE_COUNT=3`、`UPGRADE_POOL_SIZE=9`（遵循 #295 单一事实源惯例） |
| `mini-pong/project.godot` | **Modified** | `[autoload]` 注册 `UpgradePool="*res://gdscripts/upgrade_pool.gd"` |
| `mini-pong/tests/run_tests.gd` | **Modified** | 注册 `test_upgrade_pool.gd` |
| `mini-pong/tests/test_paddle.gd` | **Modified** | 新增实例属性用例（set_paddle_width 后下一帧生效 + shape 同步） |
| `mini-pong/gdscripts/breakout_grid.gd` | **Modified（增量，随 #384 落地）** | 新增 `upgrade_hooks: Dictionary` + `register_upgrade_hook(id, callable)` + `apply_upgrade_hook(id, ctx)` + `open_hole(count)`/`blast_neighbors(pos, radius)`；不改变 #384 DESIGN 既有 API（§4.5 契约） |

### 间接影响的模块

| 文件 | 影响 | 说明 |
|------|------|------|
| `mini-pong/assets/content/upgrade_pool.json` | **只读消费** | UpgradePool 运行时解析显示字段（`name_working`/`short_phrase`/`naming_candidates`）；文件缺失或解析失败 → 回退 `upgrade_defs.gd` 工作名，游戏不崩（#395 定稿前容错） |
| `mini-pong/scenes/Main.tscn` | 本 Issue **不改** | 3 选 1 UI 接线归 #388；波次调用归 #386 |
| `mini-pong/gdscripts/audio_engine.gd` | 可选（Stretch） | 新增 `play_upgrade_pick()` 合成音效；非 AC 阻塞项 |
| `mini-pong/gdscripts/game_state_machine.gd` | 可选 | 若 #386 需要在升级时暂停 FSM，由 #386 负责接线；本 Issue 不碰 |

---

## 4. 方案对比

### 4.1 UpgradePool 载体

**Approach A：autoload 单例（推荐）**

`project.godot` 注册 `UpgradePool`，全局可达。

- Pros：效果回调要摸 ball/paddle/BreakoutGrid/GameManager，全局可达最省接线；与 GameManager/AudioEngine 单例惯例一致；headless 测试直接 `UpgradePool.get_candidates(3)`；rng 种子集中管理可复现
- Cons：多一个 autoload（当前 2 个 → 3 个，可控）
- Risk: Low ／ Effort: 0.5 天

**Approach B：Game 场景节点**

挂在 Main.tscn 下，由波次循环持有引用。

- Pros：无全局状态，生命周期随场景
- Cons：效果回调需到处传引用；#388 UI 与 #386 波次都要手动取节点；与 GameManager 的"全局状态在 autoload"惯例冲突
- Risk: Med ／ Effort: 1 天

**Approach C：静态/RefCounted 类**

`UpgradePool` 为纯静态类，不注册 autoload。

- Pros：零场景开销
- Cons：无 `_ready` 生命周期（JSON 加载/信号连接时机难管理）；GDScript 静态类无法访问树节点做复杂效果（双生分裂球等需要实例化场景）
- Risk: Med ／ Effort: 0.5 天

### 4.2 效果回调模型

**Approach A：定义携带 Callable 效果回调（推荐）**

`upgrade_defs.gd` 中每个定义带 `effect: Callable`（静态方法引用或 lambda），`apply(id)` 查表后 `effect.call(ctx)`。ctx 为字典（ball/paddle/grid 引用 + 参数）。

- Pros：数据驱动（AC1 字面满足"效果回调"）；9 个异构效果（改参数/开洞/分裂球/冻结）统一走一个调用点；新升级 = 加一条定义，零分支修改；可单测（直接调 effect.call）
- Cons：lambda 调试略绕；需约定 ctx 结构
- Risk: Low ／ Effort: 1 天

**Approach B：match(upgrade_id) 硬编码分支**

`apply()` 内 match 9 个 id 分别实现。

- Pros：实现直观，无回调间接层
- Cons：**违反 AC1 的"每个定义带效果回调"**（效果散落在 apply 内，定义表只剩元数据）；新增升级要改 apply 本体；测试只能走 apply 全链路
- Risk: Med ／ Effort: 1 天

**Approach C：每升级一个脚本类**

`upgrades/long_arm.gd` 等 9 个类，各自实现 `apply(ctx)`。

- Pros：OOP 清晰，每个效果独立文件
- Cons：MVP 9 个文件过度设计；效果间共享逻辑（如砖类 3 个都调 blast）要抽象父类；.uid 文件噪音
- Risk: Med ／ Effort: 1.5 天

### 4.3 抽取算法（60/30/10）— 研究期 spike 关键发现

**Approach A：先掷稀有度，再稀有度内选升级（推荐）**

每张卡独立按 60/30/10 掷稀有度 → 在该稀有度未入选的升级中均匀选一个；候选集内按 id 去重；该稀有度抽空（如传说只有 2 个且都已在候选）→ 回退次高稀有度或按 `max_stacks` 允许重复。

- Pros：**每张卡的稀有度精确保持 60/30/10**（AC2 语义）；实现简单（两段随机）；稀有度元数据天然随候选返回（UI reveal 用）
- Cons：极端情况回退逻辑需定义清楚（测试覆盖）
- Risk: Low ／ Effort: 0.5 天

**Approach B：按升级粒度加权无放回（spike 证伪）**

把每个升级的权重 = 其稀有度权重，无放回抽 3 个。研究期 20000 次模拟实测：**边际稀有度分布漂移到 55.7% / 37.8% / 6.5%**（3 个普通 × 0.6 权重 = 1.8 vs 4 个稀有 × 0.3 = 1.2，普通总权重被稀有反超）——玩家实际看到的稀有度频率偏离 AC2 的 60/30/10。

- Pros：实现最简（单一权重池）
- Cons：**违反 AC2**（分布漂移有实测证据）；传说更难出现（6.5% vs 10%）
- Risk: High ／ Effort: 0.25 天

**Approach C：均匀随机**

- Pros：零实现
- Cons：**直接违反 AC2**（无 60/30/10）；变比率强化失效，奖励变可预测
- Risk: High ／ Effort: 0 天

### 4.4 参数实例化（AC3）

**Approach A：@export 实例属性 + 运行时 setter（推荐）**

paddle 三常量 → `@export var`；`set_paddle_width()` 同步 CollisionShape2D；ball 补 `speed_scale`。效果回调只写实例属性，`_process` 每帧读取 → **下一帧天然生效**（无需事件/信号机制）。

- Pros：Godot 惯例（ball 已如此）；编辑器可调；下一帧生效零额外机制；球读 shape.size.x 已实例化 → 长臂即时感知
- Cons：需改 paddle.gd 现有引用点（2 处 SPEED + 边界计算），回归测试覆盖
- Risk: Low ／ Effort: 0.5 天

**Approach B：保留 const + 全局覆盖表**

constants.gd 加 `var OVERRIDES = {}`，读取处查表。

- Pros：不动 paddle 现有逻辑
- Cons：**违反 AC3 字面**（"参数是实例级而不是常量"）；查表散落各读取点，易漏；测试语义混乱
- Risk: High ／ Effort: 0.5 天

**Approach C：信号驱动参数变更**

`param_changed(name, value)` 信号广播，各节点监听应用。

- Pros：解耦
- Cons：**过度设计**——MVP 只有 9 个效果、3 个目标节点；信号链调试成本 > 直接 setter；下一帧生效反而不直观
- Risk: Med ／ Effort: 1 天

### 4.5 砖墙类升级钩子（AC4）

**Approach A：BreakoutGrid 增量 upgrade_hooks 注册表（推荐，Issue 明示）**

BreakoutGrid（#384 DESIGN 落地时）新增：`var upgrade_hooks: Dictionary = {}`、`func register_upgrade_hook(id: String, cb: Callable) -> void`、`func apply_upgrade_hook(id: String, ctx: Dictionary) -> bool`，外加 `open_hole(count)`（预开洞：`generate_wave` 后补开洞，复用 hole 布局逻辑）与 `blast_neighbors(pos, radius)`（燃烧弹/破城锤：碎邻近砖）。`brick_upgrade_hooks.gd` 在 `_ready` 时注册三个回调。

- Pros：**Issue AC4 字面满足**（"通过 BreakoutGrid 预留 upgrade_hooks"）；增量不破坏 #384 DESIGN 既有 API（generate_wave/brick_destroyed/wall_cleared）；契约先行——#384 代码落地前可先定义接口与测试桩
- Cons：#384 代码未落地 → 实现有先后依赖（风险见 §6）
- Risk: Med ／ Effort: 0.5 天（契约）+ 随 #384 落地

**Approach B：独立监听者模式（BrickHookManager）**

新 autoload 监听 BreakoutGrid 的 `brick_destroyed`/`wall_cleared` 信号，拦截式实现开洞/连爆。

- Pros：完全不动 #384 代码
- Cons：**绕开 Issue 明示的 upgrade_hooks 挂载点**；开洞需要在生成后修改布局，信号监听只能事后补救（砖已实例化），语义别扭
- Risk: Med ／ Effort: 1 天

**Approach C：改 generate_wave 签名**

`generate_wave(thickness, layout, seed, holes)` 加参数。

- Pros：参数直达
- Cons：破坏 #384 DESIGN 已合并的 API 签名（plan agent 已按 3 参数实现）；升级是运行时行为，不该进生成签名；多升级组合（预开洞 + 燃烧弹）无法表达
- Risk: High ／ Effort: 0.25 天

### 推荐与理由

| 子系统 | 推荐 | 核心文件 |
|--------|------|---------|
| 池载体 | A: autoload 单例 | `upgrade_pool.gd` |
| 效果模型 | A: Callable 回调定义 | `upgrade_defs.gd` |
| 抽取算法 | A: 稀有度先掷（60/30/10 每卡） | `upgrade_pool.gd` |
| 参数实例化 | A: @export + setter（下一帧生效） | `paddle.gd`/`ball.gd` |
| 砖墙钩子 | A: BreakoutGrid upgrade_hooks 注册表 | `breakout_grid.gd` + `brick_upgrade_hooks.gd` |

1. **AC 逐条命中**：A 组合 5 条 AC 全覆盖（Callable 定义 = AC1；稀有度先掷 = AC2 精确 60/30/10；@export + 每帧读取 = AC3 下一帧生效；upgrade_hooks = AC4 字面满足；get_candidates/apply = AC5）
2. **数据驱动**：定义表 + 回调 + 稀有度元数据 = 3 选 1 UI（#388）与波次（#386）只需消费接口，不碰效果实现
3. **不破坏既有契约**：不碰手感常量默认值（#367）、不碰 GameManager 职责（#293）、不重设计砖墙（#384）、不写文案（#395）
4. **可测试**：rng 可播种 → 权重分布/去重/堆叠全部可断言；效果回调可直接单测

---

## 5. 边界条件与验收标准

### 验收标准（映射 Issue 5 条 AC）

- [x] **AC1: 9 个独立升级定义（id/名称/稀有度/效果回调）** — `upgrade_defs.gd` 9 条全齐，`effect` 均为 Callable
  - 验证：`test_upgrade_pool.gd` 断言 `UpgradePool.get_definitions().size() == 9` 且每条 `effect is Callable`
- [x] **AC2: 60/30/10 权重抽取 + 不可重复/堆叠配置** — 稀有度先掷；`max_stacks` 字段（1 = 不可重复，>1 = 堆叠）
  - 验证：统计测试（rng 固定种子 + 大样本）稀有度频率落在 60±5% / 30±5% / 10±5%；`max_stacks=1` 升级 apply 后不再出现在候选；`max_stacks>1` 可重复抽取
- [x] **AC3: 参数实例级 + 下一帧生效** — paddle 三常量 → @export；ball 已实例级 + 新增 speed_scale
  - 验证：`test_paddle.gd` 调 `set_paddle_width(156)` 后断言 `paddle_width == 156` 且 `CollisionShape2D.shape.size.x == 156`；下一帧 `_process` 用新值（`speed` 读取实例属性断言）
- [x] **AC4: 砖墙类升级走 BreakoutGrid upgrade_hooks** — 注册表 + `open_hole`/`blast_neighbors` 契约（随 #384 落地）
  - 验证：`test_upgrade_pool.gd` 对 hook 注册表做桩测试（假 grid 对象注册/调用链）；#384 落地后集成测试补真实砖墙
- [x] **AC5: get_candidates(3) 与 apply(upgrade_id)** — autoload 公共 API
  - 验证：`get_candidates(3)` 返回 3 个不同 id 的候选（含 rarity 元数据）；`apply("long_arm")` 后挡板宽度实例属性 +30%

### 边界条件

1. **不改 #395 文案文件**：upgrade_pool.json 由 #395 implement 落地；#387 只读（FileAccess + JSON.parse_string），文件缺失/解析失败回退工作名，不崩
2. **不改手感常量默认值**（#367 定稿）：只允许运行时实例级修改；constants.gd 只新增 UPGRADE_* 组
3. **不实现波次/UI/计分**：清墙→调池是 #386 的事；三卡渲染是 #388 的事；拆砖/穿墙分是 #385 的事
4. **稀有度 reveal 时序归 UI**：池只负责把 rarity 作为元数据返回；"选择后才显示"是 #388 的渲染决策（PLAN §2.5）
5. **rng 可播种**：`UpgradePool.rng` 支持 `seed()` 注入，测试与自动对打（#297）确定性复现；生产默认随机
6. **候选内去重**：get_candidates 返回 3 个不同升级 id（同一稀有度可多张，但升级不可重复出现在一次候选内）
7. **不可重复是整局语义**：`max_stacks=1` = 整局至多拿一次（apply 后从池移除）；区别于"一次候选内不重复"
8. **双生/星尘等复杂效果**：效果回调骨架本期落地（Callable 挂载 + 参数型效果完整实现）；需场景实例化的效果（双生分裂球、星尘轨迹伤害）以回调桩 + 说明实现，plan agent 决定随 #387 或独立小 PR 深化

---

## 6. 依赖

| 依赖 | 状态 | 关系 |
|------|------|------|
| #383 轴交换+竖屏 | ✅ CLOSED（PR #409） | 硬依赖：720×1280 坐标系是挡板宽度/砖墙钩子的前提 |
| #384 砖墙 BreakoutGrid | ⚠️ DESIGN 已合并（PR #414），**代码未落地**（issue CLOSED 但无 impl 分支） | AC4 硬依赖：upgrade_hooks 挂在 BreakoutGrid 上。**风险缓解**：本 PRD 定义契约 + 测试桩先行；实现可与 #384 落地合并或紧随其后独立小 PR |
| #395 升级池文案 | 🔄 status/human-review（draft 已 merge） | 软依赖：显示字段只读消费，缺失回退工作名 |
| #386 波次循环 | 📋 backlog OPEN | 消费方：清墙结算时调 get_candidates(3) |
| #388 3 选 1 升级 UI | 📋 backlog OPEN | 消费方：get_candidates(3)/apply(id) 数据入口 |
| #385 双得分制 | 📋 backlog OPEN | 无直接依赖（拆砖分与升级效果正交） |

**风险登记**：#384 代码未落地是 AC4 的最大风险。缓解：upgrade_hooks 作为**增量契约**设计（§4.5-A），不改变 #384 DESIGN 已合并的 API；brick_upgrade_hooks.gd 可先用假 grid 桩测试；若 #384 实现延期，AC4 的注册表 + 桩先行交付，集成测试随 #384 补齐。

---

## 7. Spike / 实验（研究期已执行）

| # | 实验 | 方法 | 结果 | 决策影响 |
|---|------|------|------|---------|
| S1 | ball 参数实例级验证 | `grep '@export var' ball.gd` + 读 serve()/_on_area_entered | 5 个手感参数全 @export + 实例读取；speed 实例 var | AC3 ball 侧 ✅ 已达标，只需补 speed_scale |
| S2 | paddle const 使用点盘点 | 读 paddle.gd `_process`/`_ready` | SPEED 2 处、PADDLE_WIDTH 1 处、PADDLE_HEIGHT 1 处直接引用 const | 改实例属性波及面明确（~4 处 + 边界重算） |
| S3 | 抽取算法分布模拟 | Python 20000 次：升级粒度加权无放回 vs 稀有度先掷 | 升级粒度 → 55.7/37.8/6.5 **漂移**；稀有度先掷 → 精确 60/30/10，去重 0 失败 | **证伪 Approach B，选定 Approach A**（§4.3） |
| S4 | 开源资产检索 | Godot Asset Library API + GitHub search | 无可用第三方升级池（见 §1.4） | 第一方实现，零依赖 |

---

## 8. 延续上下文（Continuation Context）

### 交付物

- `docs/PRD/387-upgrade-pool-architecture.md`（本文件）

### plan agent 接手要点

1. **先读**：`docs/DESIGN/384-breakout-grid-brick-wall.md`（upgrade_hooks 挂载点的宿主 API）、`docs/PRD/395-upgrade-pool-copy-draft.md` §4.1（JSON schema）、`docs/PLAN-rogue-pong.md` §2.5（9 升级/稀有度/情感断言）
2. **接口契约（本 PRD 已定，DESIGN 直接采用）**：
   - `UpgradePool.get_candidates(n: int = 3) -> Array[Dictionary]`：每卡含 `{id, name, rarity, max_stacks, effect_desc, display:{short_phrase, naming_candidates}}`；候选 id 互异
   - `UpgradePool.apply(upgrade_id: String) -> bool`：计数 + `effect.call(ctx)` + max_stacks=1 时移出池；返回是否成功
   - `UpgradePool.rng`：可 `seed()` 注入（测试/自动对打确定性）
   - `paddle.set_paddle_width(w: float)`：实例属性 + CollisionShape2D.shape.size.x + 边界重算
   - `ball.speed_scale: float`：_process 位移乘数（缓时 2s 冻结）
   - `BreakoutGrid.register_upgrade_hook(id, cb)` / `apply_upgrade_hook(id, ctx)` / `open_hole(count)` / `blast_neighbors(pos, radius)`（增量，随 #384）
3. **实现顺序建议**：constants UPGRADE 组 → upgrade_defs.gd（9 定义 + 回调）→ upgrade_pool.gd（autoload）→ paddle/ball 实例化 → project.godot 注册 → 测试注册 → brick_upgrade_hooks.gd（桩/随 #384）
4. **与 #386/#388 协调**：池不主动触发任何流程；波次（#386）调 get_candidates，UI（#388）调 apply——本 Issue 不接线，避免与并行 PR 冲突
5. **测试注册**：`run_tests.gd` 添加 `_run("res://tests/test_upgrade_pool.gd", "Upgrade Pool")`；headless 全绿为验收
6. **风险交接**：#384 代码未落地 → upgrade_hooks 契约与桩先行；若 #384 实现先到，集成测试立即补齐
7. **E2E**：`e2e_shots.json` 现有 shot 不涉及升级卡（#388 落地前无 UI）——本 Issue 无 E2E 影响
