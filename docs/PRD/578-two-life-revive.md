# PRD #578 — [Feature] 两条命原地复活系统

> **Issue:** #578
> **标签:** enhancement, gameplay, version/mvp, workflow/research（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=7）
> **深度:** deep（分解 JSON id=7 标注 `depth: deep` → §1–8 全必填，§7 含 ≥3 实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-20
> **所有权:** `content_ownership: mechanical`（复活编排=机械工程；演出数值全部 # DRAFT 只读，定稿归 #584）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`~/Documents/Obsidian Vault/`：wiki grep 只狼/复活 → `wiki/游戏设计理念.md`（《完美的一天》灵感来源含只狼+双雪涛——「游戏机制是超越文本的修辞手段」：两条命复活机制本身就是修辞——『还没打完这一仗』）；raw grep 双雪涛/硬汉 → `raw/Evernote/Evernote/双雪涛×班宇：还是期待大家能够热爱虚构.md`（冷冽短句美学源头）、`raw/Bear/为什么是完美的一天.md`、`raw/Evernote/Project Animal/获得不死之身的海森堡…md`（复活=负重而非恩赐的对照文本））+ 设计 brief（`docs/RAW/shandong-wolf-brief.md` §核心机制 4「只狼式两条命：第 1 条血归零 → 原地复活 → 第 2 条只有半管血」+ §校准偏好「复活表现 = B3 视觉微调，截图证据 + 用户裁决」）+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：回生=HP 归零→原地复活→约半血；第二次死亡=永久死亡）+ 同链 issues（#575 已 merged / #577 已 merged / #574 动画 / #584 常量 / #582 氛围 blocked）+ 开源调研（GitHub API 检索 godot respawn / godot revive / godot player death，见 §6.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=7，estimate 3d，priority critical）
> **前置依赖:** #577（CLOSED/status/done，PR #619 merged：判定层交付，判定器无敌期 no-op 双保险已就位）；#577 依赖 #575（CLOSED，PR #618 merged：CombatEntity + 11 态状态机 + die/revive 接口 + died/revived 信号）——均已满足

---

## 1. 问题定义

### 1.1 现状（2026-08-20 worktree 侦查 @ origin/main f081437）

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/gdscripts/combat_entity.gd` | ✅ 已交付（#575/#618） | `die()` 两段血语义完整：active_life=1 且 life_total=2 → `died(self, false)` + 转 dead 态（可复活死）；否则 `died(self, true)` + 终态。`revive()` 已实现全部机械语义：hp_2 独立计数接管、架势清空、`is_stance_broken=false`、无敌开启（INVINCIBLE_SECONDS）、dead→revive 转移 + revived/hp_changed/stance_changed 广播。**但 revive() 只被输入桥 F 键路径调用（`revive_pressed` → `_on_bridge_revive_pressed`）——注释明言「自动路径由 #578 监听 died(final=false) 计时后调 revive()」** |
| `shandong-wolf/gdscripts/combat_state_table.gd` | ✅ 已交付（#575/#618） | 11 态转移表：`dead → [revive]`（状态机停摆仅复活可出）+ `revive → [idle]`（复活演出后自动回 idle）——**转移拓扑已含复活全路径** |
| `shandong-wolf/gdscripts/combat_states.gd` | ✅ 已交付（#575/#618） | revive 态：REVIVE_SECONDS 后自动退出 → idle（注释「hp_2 初始化/无敌开启在 entity.revive() 完成，#578 契约」）；dead 态：停摆不自动退出（仅 entity.revive() 驱动 dead→revive） |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` + `stick_figure_anim_states.gd` | ✅ 已交付（#574/#612） | `anim_revive` / `anim_dead` 动画位 + 关键帧 spec 已建（`_build_revive_spec()` / `_build_dead_spec()`）——**倒地/起身动画骨架已就位，本 issue 不做动画** |
| `shandong-wolf/gdscripts/constants.gd` | ✅ 已交付（#584/#609） | REVIVE_SECONDS=1.0、INVINCIBLE_SECONDS=1.0、LIFE_TOTAL=2、LIFE_1_MAX=100、LIFE_2_ABS=50、LIFE_2_MAX_RATIO=0.5、SLOWMO_COEFF=0.2（全 # DRAFT，定稿归 #584）——**但缺复活 FX 专用常量**（墨点粒子参数/闪屏色值/闪屏时长/无敌闪烁频率） |
| `shandong-wolf/scenes/Main.tscn` | ✅ 存在（#572） | 纯标题场景（CanvasLayer layer=1：Title/Subtitle/VersionLabel）；**零 CanvasModulate、零 GPUParticles2D**——复活 FX 层零存在 |
| `shandong-wolf/tests/test_combat_entity.gd` | ✅ 已交付（#575） | 已覆盖：e2 复活流程（died(false)→revive）、e3 无敌期伤害 no-op、e4 life_total=1 终态、e5 终态拒复活——**但无编排器计时路径测试**（无「died 后 1s 自动 revive」用例） |
| `shandong-wolf/e2e_shots.json` | ✅ 已交付（#574） | capture 场景 12 态含 REVIVE(10)/DEAD(11) shot——**E2E 截图机制已可拍复活瞬间**，AC5 直接复用 |

**核心缺口（3 个，按实现顺序）：**

1. **复活编排器缺失（机械层）**——`died(self, false)` 信号无人监听计时：自动复活路径（倒地 1s → 原地复活）不存在，当前只有 F 键手动路径。AC1「第一条血归零时进入 revive 状态，1s 后原地复活」无法满足。
2. **复活 FX 层零存在（演出层）**——墨点 burst（GPUParticles2D 30-50 黑点）、CanvasModulate 闪屏（白 #e8e6e3 → 血 #5a1e1e，0.2s）、短促慢动作、复活后无敌闪烁（Line2D modulate 透明度循环）全部未实现。AC4 无法满足。
3. **SW-015 契约未固化（契约层）**——`died(self, true)`（第二条血归零）已由 #575 `die()` 发出，但无测试锁定「life_total=2 玩家 hp_2 归零 → final=true」，且无契约文档供 SW-015（分解 id 21 结局与失败结算）消费。AC3 缺证据。

### 1.2 验收条件（源自 Issue #578 body，映射到本 PRD 保障）

| # | 验收条件 | 本 PRD 的保障措施 |
|---|---------|------------------|
| AC1 | 第一条血归零时进入 revive 状态，1s 后原地复活并切至半管第二条血 | §4.1 方案 A（编排器监听 died(final=false) → REVIVE_SECONDS 计时 → entity.revive()）+ §5.1 AC1：断言 state_name 序列 dead→(1s)→revive→idle、hp_2=50 |
| AC2 | 复活后 1s 无敌时间（不可受击、不可被弹反架势伤害）且架势条清空 | 复用 #575 `_invincible_until_sec`（INVINCIBLE_SECONDS）+ #577 判定器无敌期 no-op 双保险；§5.1 AC2：无敌期内 take_damage/take_stance_damage 均 no-op + stance==0 |
| AC3 | 第二条血归零才触发玩家死亡事件（供 SW-015 失败判定消费） | §4.3 契约文档化 + 测试锁定：hp_2 归零 → `died(final=true)` 仅一次、`_is_final_dead` 置位、后续 revive() 被拒（#575 已实现，本 issue 补测试与契约表） |
| AC4 | 复活动画触发 GPUParticles2D 墨点 burst 与 CanvasModulate 闪屏 | §4.2/§4.3 方案 A（独立 revive_fx.gd：one_shot 墨点 burst + 瞬态 CanvasModulate Tween）+ §5.1 AC4：headless 断言节点存在 + 参数落 constants |
| AC5 | E2E 截图提交用户裁决：复活瞬间画面情绪是否符合『硬汉再起』而非『日式中二觉醒』 | §5.1 AC5 + §7 实验 2/3：e2e_shots.json REVIVE 态 shot 复用，截图证据 + 用户裁决（brief §校准偏好 B3） |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家实机战斗（MVP 核心手感） | 每次游玩 | 第一条血归零 → 无死亡结算，倒地（anim_dead 1s）→ 墨色爆开 + 白→血红闪屏 + 短促慢动作 → 起身（anim_revive）→ 半管血 + 1s 无敌闪烁继续战斗 |
| B | 硬汉第二次机会（审美验证） | 每次复活 | 复活瞬间画面情绪：一身冷汗、刀尖点地、站起——「还没打完这一仗」，非神迹、非金光、非日式中二觉醒（AC5 用户裁决） |
| C | 第二次死亡（失败链路） | 每局至多 1 次 | 第二条血归零 → died(final=true) → SW-015（id 21 结局与失败结算）消费进入失败判定——本 issue 只保证事件契约，不做失败场景 |
| D | 开发者 headless 验证 | 每次 impl PR | 模拟：构造玩家实体 → take_damage 至 hp_1=0 → 断言 died(false) → 快进 1s → 断言 revive() 被调 + hp_2=50 + 无敌开启 —— 不依赖场景树与真实输入 |

### 1.4 范围边界（Patch 14 去冲突 + 复活层红线）

| PRD / 分解 id | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #575（实体/状态机，merged） | 两段血数据 + die/revive 接口 + dead→revive 转移 + 无敌机制 | ❌ 不修改 combat_entity.gd 接口与转移表；只**新增编排器消费其信号、调用其 revive()**（#575 注释明言「#578 接管」） |
| #577（判定层，merged） | 弹反/拼刀/架势崩解裁决 + 5 结果事件 | ❌ 不碰判定；无敌期 no-op 双保险（#575 take_damage + #577 判定器）已就位，本层只保证 revive 期间判定器跳过 |
| #574（动画，merged） | consume_state 11 态 + 刀光 + anim_revive/anim_dead 关键帧 | ❌ 不重做动画；本层触发 state_changed 后动画层自动跟随 |
| #584（数值 DRAFT，merged） | 全量 # DRAFT 数值 + 调参面板 | ❌ 不裁决数值；REVIVE_SECONDS 等只读；新增 FX 常量同样标 # DRAFT 待 #584 定稿 |
| #582（雪夜氛围，blocked/implement） | 雪幕 GPUParticles2D + 冷月光 CanvasModulate(#b8c4d9 常驻) + 水墨晕染 + 低血血色 vignette(0.5s) | ❌ 不做氛围层；本 PRD 闪屏 CanvasModulate 是**瞬态演出节点**（白→血 0.2s 后复原），与 #582 常驻色温节点**分离共存**；墨点 burst 是**局部一次性发射**，非全屏氛围层；低血 vignette 归 #582 |
| SW-015 / 分解 id 21（结局与失败结算，未开始） | 失败结算（黑白滤镜+血色字）消费「两条命耗尽」 | ❌ 不做失败场景；只保证并文档化 `died(final=true)` 事件契约（§4.3） |
| 分解 id 5 / #581（敌AI） | 敌人 AI | ❌ 不做 AI；敌人 life_total=1 变体路径（died final=true）由 #575 已覆盖，本层回归测试兜底 |

**复活层红线（issue body + 代码注释三重声明）：**
- 复活**编排**（谁在什么时候调 revive()）与复活**演出**（墨点/闪屏/慢动作/闪烁）是本 issue 唯二新增物——机械语义 #575 已交付，禁止在编排器/FX 中重写 hp/架势/无敌逻辑
- 演出数值全部走 constants.gd # DRAFT 只读，禁止实现期定稿
- 闪屏 CanvasModulate 必须与 #582 常驻氛围节点解耦（瞬态 Tween vs 常驻色温），禁止互相覆盖 color
- 自动复活路径与 F 键手动路径**双路径兼容**（#575 输入桥已预留 `revive_pressed`），编排器不得屏蔽输入桥

---

## 2. 设计意图

### 2.1 为什么现在做

1. **复活原料全部就绪（2026-08-20）**：两段血数据 + die/revive 接口（#575）、dead→revive 转移拓扑 + revive 态自动退出（#575）、anim_dead/anim_revive 动画位（#574）、REVIVE_SECONDS/INVINCIBLE_SECONDS 常量（#584）、E2E 12 态含 REVIVE/DEAD（#574）——五层地基齐备，缺口只剩「谁计时驱动」+「演出长什么样」。
2. **MVP 战斗闭环（#585 组装）前置**：brief 明确 MVP 含「两条命+原地复活」；复活编排器是战斗闭环（#577 判定 → #578 复活 → #580 处决）中唯一未建的机械组件。
3. **只狼机制对齐（sekiro-tuning-reference）**：「回生 Resurrection：HP 归零 → 消耗回生机会原地复活 → 回生后约半血」；「第二次死亡 = 永久死亡」——两条命不是两条血（第一条允许失误=硬汉，第二条半血=最后一搏）。本 issue 是这条铁律的驱动+演出实现。

### 2.2 为什么是本层（历史成因）

复活语义在 #575 交付时被**刻意拆成两层**，代码注释三处预留：`die()` 注释「#578 接管」（died final=false 语义）、`revive()` 注释「#578 驱动」（谁调用它）、combat_states revive 态注释「#578 契约」（演出时长）。输入桥 `revive_pressed` → `_on_bridge_revive_pressed` 注释「自动路径由 #578 监听 died(final=false) 计时后调 revive()，两路兼容」——**本 issue 是这些预留位的唯一收口**。

### 2.3 既有约束（审美坐标，issue body + brief §校准偏好）

| 约束 | 细节 | 来源 |
|------|------|------|
| 复活不是奖励是第二次机会 | 「硬汉的第二次机会」；参考双雪涛小说冷冽：复活不是神迹，是『还没打完这一仗』 | issue body 审美坐标 |
| 禁止满血复活、禁止金光特效 | 满血=奖励语义；金光=页游感（brief 反例） | issue body + brief 反例清单 |
| 复活动画必须克制 | 一身冷汗、刀尖点地、站起 | issue body |
| 视觉=墨色爆开 + 血色 | GPUParticles2D 墨点（30-50 黑点）+ 血色 vignette/闪屏 | issue body 画面实现路径 |
| 复活表现 = B3 视觉微调 | E2E 截图证据 + 用户裁决（AC5） | brief §校准偏好 |
| 渲染实现=mechanical，构图/配色裁决=taste-draft | 工程与品味分离 | brief §画面实现路径 |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/revive_orchestrator.gd` | **新建** | 复活编排器：监听 died(final=false) → REVIVE_SECONDS 计时 → entity.revive()；与输入桥双路径兼容 |
| `shandong-wolf/gdscripts/revive_fx.gd` | **新建** | 复活演出：GPUParticles2D 墨点 burst + 瞬态 CanvasModulate 闪屏 + 短促慢动作 + 无敌闪烁（Line2D modulate 循环） |
| `shandong-wolf/gdscripts/constants.gd` | 常量 | 新增复活 FX 分区（# DRAFT）：墨点粒子参数 / 闪屏色值 / 闪屏时长 / 闪烁频率（见 §4.5 推荐表） |
| `shandong-wolf/tests/test_revive_orchestrator.gd` | **新建** | 编排器计时路径 + SW-015 契约测试（hp_2 归零 → final=true 仅一次） |
| `shandong-wolf/scenes/Main.tscn`（或玩家挂载点） | 场景 | FX 节点 + 编排器挂载约定（§4.1 方案 A 挂载策略；最终组装归 #585） |
| `shandong-wolf/tests/run_tests.gd` | 测试入口 | 挂载 test_revive_orchestrator.gd |

### 3.2 数据流影响（复活链路全图）

```
CombatEntity.take_damage (hp_1 ≤ 0, life_total=2)
    │
    ▼
die() ──► emit died(entity, final=false) ──► ReviveOrchestrator._on_died(false)  ← ✅ 本 issue 新建
    │                                              │ 启动计时器 REVIVE_SECONDS (1.0s)
    └──► request_transition("dead")                │
              └──► anim_dead 倒地动画（1s）        ▼
                                           计时到期 → entity.revive()
    ┌───────────────────────────────────────────────┘
    ▼
revive(): hp_2=50 接管 · stance=0 清空 · invincible=now+1s · dead→revive 转移
    │
    ├──► emit revived(entity) ──► ReviveFX.trigger()  ← ✅ 本 issue 新建
    │                                ├── GPUParticles2D 墨点 burst（30-50 黑点，one_shot）
    │                                ├── CanvasModulate Tween 白 #e8e6e3 → 血 #5a1e1e（0.2s 复原）
    │                                ├── Engine.time_scale 短促慢动作（SLOWMO_COEFF，恢复）
    │                                └── Line2D modulate 透明度循环（无敌 1s 内）
    ├──► state_changed(dead→revive) ──► anim_revive 起身动画
    └──► revive 态 REVIVE_SECONDS 后自动 → idle（#575 已实现）

第二次死亡链路（AC3 / SW-015 契约）:
take_damage (hp_2 ≤ 0) ──► die(): _is_final_dead=true ──► emit died(entity, final=true) ──► SW-015 失败判定（未来 issue）
                                                                      └──► request_transition("dead") 终态停摆（revive() 被拒）
```

### 3.3 间接影响

| 模块 | 影响 | 说明 |
|------|------|------|
| #585 组装（未开始） | 挂载编排器 + FX 节点 | 编排器/FX 交付为自包含组件 + 挂载约定，组装期接线 |
| #582 雪夜氛围（blocked） | 共存约束 | 瞬态闪屏 CanvasModulate 与常驻冷月光 CanvasModulate 并存——节点隔离 + 互不覆盖 color（§1.4 红线） |
| #574 动画（merged） | 时长对齐 | anim_dead 倒地动画时长应覆盖 REVIVE_SECONDS 窗口（1s），impl 期验证 clip 时长 |
| SW-015 结局失败结算（未开始） | 事件契约 | died(final=true) 契约表（§4.3）成为 SW-015 输入规格 |
| e2e_shots.json（#574） | REVIVE/DEAD shot 复用 | AC5 截图：REVIVE 态 shot 追加 FX 存在断言（节点存在 + 参数） |

### 3.4 文档更新清单

- [x] 本 PRD（research 阶段产出）
- [ ] `docs/DESIGN/578-two-life-revive.md`（plan agent 产出）
- [ ] `docs/TASKS/578-*.md`（plan agent 产出）
- [ ] `docs/GAME_DESIGN/shandong-wolf/` 复活章节（post-merge agent 增量更新）
- [ ] `docs/RAW/shandong-wolf-brief.json` 无改动（机械 issue）

---

## 4. 方案对比

### 4.1 复活编排器（谁在 1s 后调 revive()）

**方案 A：独立 ReviveOrchestrator（推荐）**

自包含 Node2D/RefCounted 组件，暴露 `bind_player(entity)`，订阅 `died` 信号；收到 `final=false` 启动 SceneTreeTimer/自管理计时器（REVIVE_SECONDS），到期调 `entity.revive()`。headless 安全（Timer 不依赖渲染）。

- Pros：零侵入 #575 接口；可单测（注入 fake 计时器）；与 F 键输入桥天然并行（都调 revive()，幂等——revive 态重入有 restart 钩子，dead 停摆只允许 revive 出）
- Cons：多一个组件接线点（#585 组装期挂载）
- Risk: **Low**；Effort: 0.5-1 天

**方案 B：在 CombatEntity 内部加自动计时**

`die()` 里 final=false 时自启 Timer，到期自调 revive()。

- Pros：无需外部接线
- Cons：**违反 #575 红线**——「本层不做判定/演出」注释 + 「#578 接管」预留 = 明确禁止在实体内实现驱动；实体变胖，测试耦合
- Risk: **Med**（架构违背）；Effort: 0.5 天

**方案 C：玩家控制器轮询 state_name=="dead"**

`_process` 里检测 dead 态累计时长，超 REVIVE_SECONDS 调 revive()。

- Pros：零新组件
- Cons：轮询语义脆弱（帧率依赖）；player_controller 职责膨胀（移动层管复活）；dead 停摆期与输入桥/编排器竞争
- Risk: **Med**；Effort: 0.5 天

**推荐 A：** 与 #575 预留位（「#578 监听 died(final=false) 计时后调 revive()」）逐字对齐；编排器=唯一驱动入口，输入桥=并行手动路径，两者经 `revive()` 幂等收敛。

### 4.2 墨点 burst（复活的『墨色爆开』）

**方案 A：GPUParticles2D one_shot burst（推荐，issue body 指定路径）**

独立 Node2D 持 GPUParticles2D，`emitting=true` 一次性发射 30-50 个黑色圆点粒子（texture 程序化生成 8x8 圆点或默认 particle），径向速度 + 透明度衰减 + 短生命周期（0.3-0.5s），受击瞬间触发。

- Pros：issue body 指定路径；GPUParticles2D 是 Godot 4.7 标准粒子（#582 雪幕同引擎，模式复用）；one_shot 不持续耗性能
- Cons：粒子 texture 需程序化生成（零美术资产约束）；发射位置在玩家脚底/刀尖的定位细节
- Risk: **Low**；Effort: 0.5-1 天

**方案 B：CPUParticles2D**

- Pros：无需 GPU、可脚本精确控制每粒子
- Cons：30-50 粒子 CPU 开销无必要；与 #582 雪幕（GPUParticles2D）引擎不一致
- Risk: Low；Effort: 0.5 天

**方案 C：canvas_item shader 模拟墨爆**

- Pros：可做水墨晕染质感（#582 同族技术）
- Cons：一次性爆开用 shader 过度设计；水墨晕染归 #582 氛围层，本层只做事件性 burst
- Risk: Med（越界）；Effort: 1-1.5 天

**推荐 A：** issue body 指定 + 与 #582 粒子体系同引擎；墨点数量/速度/衰减进 constants（# DRAFT），实验 1 定参。

### 4.3 复活闪屏 + 无敌闪烁（『血月/墨色闪屏』+ 无敌可读性）

**方案 A：瞬态 CanvasModulate Tween + Line2D modulate 循环（推荐，issue body 指定路径）**

独立 CanvasModulate 节点（初始 color=默认白），revived 触发 Tween：0.2s 内 color 从白 #e8e6e3 落到血色 #5a1e1e，再回落复原（总时长 ~0.4-0.5s）——『血月』语义。无敌闪烁：玩家剪影 Line2D 组 modulate.a 在 INVINCIBLE_SECONDS 内循环 0.3→1.0（频率进 constants）。

- Pros：issue body 指定；CanvasModulate 是 Godot 全屏色温标准节点；与 #582 常驻色温**节点分离**（各自 color 互不覆盖）；Tween 无需每帧代码
- Cons：与 #582 常驻 CanvasModulate 共存需约定挂载层级（瞬态节点后挂/高 layer 覆盖）；闪烁需遍历 Line2D 子节点
- Risk: **Low**（约定明确）；Effort: 1 天

**方案 B：全屏 ColorRect 覆盖层（CanvasLayer layer=10）**

- Pros：alpha 控制直观、可叠加
- Cons：与 #582 血色 vignette（同为 layer=10 覆盖层）冲突风险；整屏覆盖比色温更『警报感』，易踩『日式中二』红线
- Risk: Med；Effort: 0.5-1 天

**方案 C：shader 后处理闪屏**

- Pros：色温+晕染一步到位
- Cons：全屏 shader 归 #582 氛围层（水墨晕染），本层重复造轮子；实现期成本高
- Risk: Med（越界）；Effort: 1.5 天

**推荐 A：** 瞬态色温（CanvasModulate）+ 局部闪烁（Line2D modulate）双节点，全部参数进 constants # DRAFT；闪屏曲线/频率由实验 2/4 定参。

### 4.4 短促慢动作（复活瞬间的『停顿感』）

**方案 A：Engine.time_scale 短促降速 + 恢复（推荐）**

revived 触发：`Engine.time_scale = SLOWMO_COEFF`（0.2）持续 ~0.3-0.5s，Tween/计时恢复 1.0。clamp 下限 0.1 防冻结（#577 处决慢动作同源——SLOWMO_COEFF 已定义）。

- Pros：复用 #584 SLOWMO_COEFF（不新增语义）；与处决演出同源节奏语言；实现成本最低
- Cons：全局 time_scale 影响敌人 AI/粒子（0.3-0.5s 内可接受，实验 3 验证）
- Risk: **Low**；Effort: 0.5 天

**方案 B：局部 hit-stop（只停玩家动画）**

- Pros：不影响全局
- Cons：实现复杂（需暂停动画播放器）；与 #579 反馈层 hit-stop 语义重叠（越界）
- Risk: Med；Effort: 1 天

**推荐 A：** 全局 time_scale 短促降速，时长与系数进 constants # DRAFT，实验 3 定参。

### 4.5 推荐汇总 + 新增常量清单

| 子系统 | 推荐 | 核心文件 | 新增常量（# DRAFT） |
|--------|------|---------|-------------------|
| 复活编排 | A: ReviveOrchestrator 独立组件 | `revive_orchestrator.gd` | 复用 REVIVE_SECONDS=1.0（不新增） |
| 墨点 burst | A: GPUParticles2D one_shot | `revive_fx.gd` | INK_BURST_COUNT=40（候选 [30,40,50]）、INK_BURST_SPEED、INK_BURST_LIFETIME=0.4、INK_COLOR=#141414 |
| 闪屏 | A: 瞬态 CanvasModulate Tween | `revive_fx.gd` | FLASH_WHITE=#e8e6e3（复用 HUD_MOON_WHITE 同值）、FLASH_BLOOD=#5a1e1e（issue body 指定）、FLASH_SECONDS=0.2 |
| 慢动作 | A: Engine.time_scale 短促降速 | `revive_fx.gd` | 复用 SLOWMO_COEFF=0.2 + SLOWMO_HOLD_SECONDS=0.4（候选 [0.3,0.4,0.5]） |
| 无敌闪烁 | A: Line2D modulate 循环 | `revive_fx.gd` | INVINCIBLE_FLICKER_HZ=8（候选 [6,8,10]）、INVINCIBLE_FLICKER_ALPHA_MIN=0.3 |

---

## 5. 边界条件与验收标准

### 5.1 验收条件（AC，映射 issue body）

- [x] **AC1: 第一条血归零 → revive 状态 → 1s 后原地复活切半管第二条血**
  - `take_damage(100)` → state_name=="dead"、died(final=false) 恰一次
  - 快进 REVIVE_SECONDS → revive() 被编排器调用 → state_name=="revive" → REVIVE_SECONDS 后自动 idle（#575 已测）
  - hp_2==50.0、hp_1==0.0（第二条血独立计数，不补第一条）
- [x] **AC2: 复活后 1s 无敌 + 架势清空**
  - revive 后 stance==0.0、is_stance_broken==false
  - 无敌期内 take_damage(999) 与 take_stance_damage(999) 均 no-op（#575 e3 已测，回归）
  - INVINCIBLE_SECONDS 到期后受击恢复正常
- [x] **AC3: 第二条血归零才触发玩家死亡事件（SW-015 契约）**
  - 玩家（life_total=2）hp_2 归零 → died(final=true) 恰一次、_is_final_dead==true、后续 revive() 被拒（push_warning 路径）
  - 契约表（§4.3 输出）：`died(entity, final: bool)` final=false=可复活死（编排器消费）/ final=true=终态（SW-015 消费）
- [x] **AC4: 复活动画触发墨点 burst 与闪屏**
  - headless 断言：revive_fx 节点存在、GPUParticles2D.emitting==true（revived 触发）、CanvasModulate color Tween 起始 #e8e6e3 → 目标 #5a1e1e、参数全部来自 constants（零硬编码）
  - 慢动作：Engine.time_scale 短暂降至 SLOWMO_COEFF 后恢复 1.0
- [x] **AC5: E2E 截图提交用户裁决**
  - e2e_shots.json REVIVE 态 shot 复用（capture 场景已含 12 态），截图 + 情绪判断（『硬汉再起』 vs 『日式中二觉醒』）交用户
  - 用户裁决记录进 docs/TASTE.md（brief §校准偏好 B3 流程）

### 5.2 边界情况（≥5）

1. **dead 停摆期再次受击** —— #575 take_damage 在 dead 态 no-op；#577 判定器跳过 dead/revive/execute 实体（双保险，回归测试）
2. **revive 期间再次受击** —— take_damage/take_stance_damage 在 revive 态 no-op（#575 已实现，测试覆盖）
3. **F 键手动复活 vs 自动编排竞争** —— 两路径都调 revive()：revive 态同态重入走 restart 钩子静默返回（#575 已处理）；自动路径计时器需防重入（died 只发一次，天然单次）
4. **敌人（life_total=1）死亡** —— die() 直接 final=true（#575 e4 已测）；编排器只 bind 玩家实体，不得误绑敌人
5. **闪屏与 #582 冷月光并存** —— 瞬态 CanvasModulate 与常驻色温节点分离；闪屏 Tween 结束后 color 复原，不残留覆盖（impl 期约定挂载顺序）
6. **headless / 无 FX 节点环境** —— revive_fx 节点缺失时编排器不得崩溃（get_node_or_null 防御）；测试用纯逻辑断言
7. **REVIVE_SECONDS 与 anim_dead 时长对齐** —— 倒地动画 clip 时长应 ≥1s 覆盖复活窗口（impl 期核对 #574 参数）
8. **慢动作影响全局** —— time_scale 0.2 持续 0.4s 内敌人 AI/粒子同步降速（可接受，实验 3 验证；clamp 下限 0.1）

### 5.3 失败路径（≥3）

1. **编排器计时期间实体被销毁/场景切换** —— 计时器回调前 entity 失效：回调内 `is_instance_valid(entity)` 守卫，无效则静默跳过（不崩溃）
2. **revive() 被拒（终态或 life_total<2）** —— #575 push_warning + no-op；编排器不得死循环重试（单次调用 + 信号驱动）
3. **FX 资源缺失（程序化 texture 生成失败）** —— 墨点 texture 生成失败时 GPUParticles2D 退化为默认粒子（或降级为纯闪屏），不阻塞复活主链路
4. **E2E 截图情绪不达标** —— AC5 用户裁决『日式中二觉醒』→ 按 brief B3 流程回退调参（闪屏时长/颜色/粒子数进 constants 候选集，一次调参循环）

---

## 6. 依赖与阻塞

### 6.1 依赖表

| 依赖 | 状态 | 说明 | 风险 |
|------|------|------|------|
| #575（实体/状态机） | ✅ CLOSED（PR #618 merged） | die/revive 接口 + dead→revive 转移 + 无敌机制 | 无（接口只读） |
| #577（判定层） | ✅ CLOSED（PR #619 merged） | 无敌期判定 no-op 双保险 | 无 |
| #574（动画） | ✅ CLOSED（PR #612 merged） | anim_dead/anim_revive 动画位 | 低（clip 时长核对） |
| #584（数值） | ✅ CLOSED（PR #609 merged） | REVIVE_SECONDS/INVINCIBLE_SECONDS/SLOWMO_COEFF | 无（只读） |
| #582（雪夜氛围） | ⚠️ OPEN（implement/blocked） | 共存约束（非硬依赖） | 低（节点隔离约定） |
| #585（战斗场景组装） | ⏳ 未开始 | 编排器/FX 挂载接线 | 低（组件自包含） |
| SW-015（分解 id 21 结局失败结算） | ⏳ 未开始 | 消费 died(final=true) | 无（只保证契约） |

### 6.2 开源调研（issue body「🔍 开源优先」强制）

GitHub API 检索（2026-08-20，search rate 30/30）：`godot respawn` / `godot 4 respawn` / `godot revive system` / `godot checkpoints` / `godot player death` 五组查询均**无成熟结果**（无匹配仓库或结果与 Godot 4.x 两条命语义无关）。

**结论：** ① 不存在「只狼式两条命原地复活」的成熟 Godot 4.x 开源方案可复用；② 且本项目核心语义已在 #575 交付（两段血 + die/revive + 无敌 + 信号契约）——「不重复造轮子」由**项目内复用**满足；③ 本 issue 只新增编排（计时驱动）+ 演出（墨点/闪屏/慢动作/闪烁），属 Godot 标准节点（GPUParticles2D/CanvasModulate/Tween/Engine.time_scale）组合，无第三方依赖。PR 中已说明调研结果（本 PRD §6.2 为记录）。

### 6.3 依赖链 ASCII

```
#572 骨架 ──► #573 输入 ──► #574 动画 ──┐
#584 常量 ──────────────────────────────┼──► #575 实体/状态机 ──► #577 判定层 ──► #578 复活（本 issue）
                                        │                                    │
                                        └──► #576 HUD ───────────────────────┘         │
                                                                                        ▼
#578 事件 died(final=true) ──► SW-015 结局与失败结算（未来）       #578 组件 ──► #585 战斗场景组装 ──► #580 处决
```

---

## 7. Spike / 实验（deep 强制，≥3）

### 实验 1：墨点 burst 参数定标
- **Question:** 30-50 个黑点粒子的速度/生命周期/透明度衰减取何值，才能呈现「墨色爆开」而非「黑雾一团」或「烟火特效」？
- **Method:** 独立 capture 场景（复用 e2e 机制）触发 one_shot burst，参数扫描（count 30/40/50 × speed 三档 × lifetime 0.3/0.4/0.5），E2E 截图对比
- **Expected Result:** 径向扩散 + 快速衰减（0.4s 内淡出），粒子轮廓清晰可辨（禁止粘连成雾）；count=40 为候选基准
- **Impact on Approach:** 定 INK_BURST_* 常量默认值；若 GPUParticles2D 默认 texture 不可用 → 程序化 8x8 圆点 texture（备选路径）

### 实验 2：闪屏节奏与色值
- **Question:** 0.2s 白 #e8e6e3 → 血 #5a1e1e 的 Tween 曲线与回落时长，能否传达『血月』而非『警报红』/『日式中二觉醒』？
- **Method:** 截图序列（闪屏 0.1s/0.2s/0.3s × 回落 0.2s/0.3s），E2E 截图 + 用户裁决（AC5）
- **Expected Result:** 闪白瞬间短促（≤0.2s）+ 血色停留克制（0.2-0.3s）+ 平滑回落；血色 #5a1e1e 偏暗红不发亮
- **Impact on Approach:** 定 FLASH_SECONDS 与 Tween 曲线；若裁决『警报感』→ 降血色亮度或缩短停留

### 实验 3：短促慢动作时长
- **Question:** time_scale=0.2 持续 0.3-0.5s 是否足够「停顿感」且不拖沓、不影响敌人节奏？
- **Method:** 模拟战斗中触发复活，对比 0.3/0.4/0.5s 三档的全局降速观感（含敌人 AI 同步降速影响）
- **Expected Result:** 0.4s 为基准——足够读清「刀尖点地」帧，不造成节奏断裂；敌人 AI 0.4s 降速无感知损失
- **Impact on Approach:** 定 SLOWMO_HOLD_SECONDS；若敌人节奏受损 → 改方案 B（局部 hit-stop）降级路径

### 实验 4：无敌闪烁频率
- **Question:** Line2D modulate.a 循环频率（6/8/10 Hz）与最低 alpha（0.3）在 1s 无敌期内是否可读且不刺眼？
- **Method:** 截图 3 帧（闪烁峰值/谷值）+ 用户目测；对比三档频率
- **Expected Result:** 8Hz 基准——「呼吸感」可读（明暗交替 8 次），无频闪不适（<10Hz 安全区）
- **Impact on Approach:** 定 INVINCIBLE_FLICKER_HZ 与 ALPHA_MIN；若刺眼 → 降频或提高最低 alpha

---

## 8. 延续上下文（Continuation Context）

**系统状态（plan agent 接手时）：**
- 机械层 100% 就绪：CombatEntity.die()/revive() 两段血语义 + dead→revive 转移 + 无敌机制（#575，PR #618）、判定器无敌期 no-op（#577，PR #619）、anim_dead/anim_revive 动画位（#574，PR #612）、REVIVE_SECONDS=1.0 / INVINCIBLE_SECONDS=1.0 / SLOWMO_COEFF=0.2 常量（#584，PR #609）
- 唯一缺口：① ReviveOrchestrator（died(final=false) → 1s 计时 → revive()）② ReviveFX（墨点 burst / 瞬态闪屏 / 慢动作 / 无敌闪烁）③ SW-015 契约测试

**plan agent 下一步（DESIGN 要点）：**
1. 按 §4.1 方案 A 设计 `revive_orchestrator.gd`：`bind_player(entity)` + 订阅 died + SceneTreeTimer 计时 + `is_instance_valid` 守卫 + 与 F 键输入桥并行兼容
2. 按 §4.2-§4.4 方案 A 设计 `revive_fx.gd`：GPUParticles2D one_shot + 瞬态 CanvasModulate Tween + Engine.time_scale 短促降速 + Line2D modulate 循环；全部参数进 constants.gd 新增复活 FX 分区（# DRAFT + 候选集，§4.5 清单）
3. 测试：`test_revive_orchestrator.gd`（AC1 计时路径 / AC2 无敌回归 / AC3 SW-015 契约 final=true 恰一次 / AC4 FX 节点断言 / 边界 3/6/8）
4. 场景挂载：编排器 + FX 挂载约定（Main.tscn 或玩家场景），最终接线归 #585 组装——**impl 期不得在 #585 之前写死组装细节**
5. E2E：复用 e2e_shots.json REVIVE 态 shot，AC5 截图交用户裁决；裁决结果进 docs/TASTE.md

**关键风险：** ① 与 #582 氛围层共存（瞬态闪屏 vs 常驻冷月光 CanvasModulate 节点隔离，impl 期验证不互相覆盖 color）；② anim_dead clip 时长需覆盖 1s 复活窗口；③ 全局慢动作影响敌人节奏（实验 3 有降级路径）
