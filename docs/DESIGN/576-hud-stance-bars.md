# Design: 血条与架势条极简 HUD（两段式血条 / 玩家与敌人架势条 / 击杀与处决提示）

> **Parent Issue:** #576
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4 六决策点**全部确认采纳方案 A** —— ①两段式血条 = **单条双段同轴**（段1 全宽 100 + 段2 半宽 50 首尾相接，活性段月白高亮/非活性段墨黑暗显）；②敌人架势条 = **顶部中央细条**（`set_target_enemy()` 注入时显示；MVP 无锁定系统，「当前锁定敌人」= 注入的战斗目标）；③低血 vignette = **HUD 发 `low_health_changed(enabled)` 信号**，#585 组装接线到 #582 `set_low_health()`（信号源缺口裁决：低血判定归属本层——HUD 是 `hp_changed` 唯一消费方，issue 字面「HUD 仅发信号」）；④提示文字 = **Label + 信号驱动显隐 + Tween 淡入淡出**（处决窗口 3s = `STANCE_BREAK_RECOVERY_SEC` 只读；击杀 1.5s Timer 隐藏；文案 B2 候选 5 选 1 待用户定稿）；⑤渲染技术栈 = **纯 Control + StyleBoxFlat/_draw() 程序化绘制，零贴图**（AC4 + issue 画面实现路径字面）；⑥HUD 层级 = **CanvasLayer layer=1**（#562 标题 UI 同层约定）
> **Reference PRD:** `docs/PRD/576-hud-stance-bars.md`（research PR #620 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/575-combat-entity-state-machine.md`（CombatEntity 6 信号契约 + 两段血 `_active_life` 语义——数据与事件源）；`docs/DESIGN/582-snow-night-atmosphere.md`（CanvasLayer 层级约定：1=HUD/标题、2=水墨、3-5=雪幕、10=vignette）；`docs/DESIGN/574-stick-figure-silhouette-animation.md`（E2E CaptureRig 模式：`/root/CaptureRig.current_state` + auto_cycle 兜底 + settle_frames）；mini-pong #392/#448（信号驱动零轮询 + StyleBoxFlat 程序化 UI + TF-1 静态断言——**模式参考，不复制代码**，游戏隔离红线）
> **所有权:** `content_ownership: taste-draft`（B3 视觉方向 + B2 UI 文案：agent 出带 taste 方向的草稿，草稿达标即 merge，review agent 打 `status/human-review` + assign 用户定稿；`HUD_LOW_HP_RATIO` 等新阈值、提示文案、配色点缀全部标 # DRAFT/候选清单**待用户裁决**；信号契约/布局锚点/边沿触发/单例守卫等机制结构**机械定稿**）
> **深度:** light（PRD 标注 `depth: light`，分解 JSON id=5）—— 仅产出 **DESIGN** 文档，**不产 TASKS**（skill 判定：depth/light → SKIP；本层为单组件 + 1 测试文件 + 2 修改文件的浅变更）
> **并行上下文:** worktree 并行 —— constants.gd 为**追加式新增「HUD」分区**（新开 `# ── HUD (#576) ──`，不触碰既有 9 分区任何一行，与 #584 调参面板/其他 issue 无同区改写冲突）；新文件全部独立命名（`hud.gd` / `test_hud.gd` / `e2e_hud_capture.*`）；唯一共享文件 = `tests/run_tests.gd`（追加一行 `_run()`，当前 #577/#580/#585 均未开始，无并发改写）；#582（PR #613 OPEN）为只读消费端——本层**零引用**其节点，仅发同名语义信号

---

## 1. 架构总览

**问题本质是「战斗数据层已合入，UI 层零存在」。** shandong-wolf 经 #618（#575）已交付 `CombatEntity`（215 行，6 信号契约：`hp_changed(hp_1, hp_2, active_life)` / `stance_changed(stance, stance_max)` / `stance_broken(entity)` / `state_changed(from, to)` / `died(entity, final)` / `revived(entity)`），经 #609（#584）已交付全量 # DRAFT 数值（`LIFE_1_MAX=100` / `LIFE_2_ABS=50` / `POSTURE_BREAK_THRESHOLD=100` / `STANCE_BREAK_RECOVERY_SEC=3.0`）。但 `gdscripts/` 无任何 UI 代码——无 hud.gd、无 StyleBoxFlat 先例、`Main.tscn` 纯标题场景。**本 issue 交付 = 战斗读数的「克制」UI 层**：玩家两段式血条、玩家/敌人架势条、击杀与处决提示文字，全部程序化绘制零贴图，并补上低血 vignette 的**信号源缺口**（issue body 明示「HUD 仅发信号」）。

**设计哲学：HUD 是纯消费方——只读信号画条 + 发一个低血信号，零判定、零轮询、零贴图。**
1. **信号驱动、零 `_process` 轮询**：所有更新由 `hp_changed` / `stance_changed` / `stance_broken` / `died` / `revived` / `state_changed` 信号 + Tween/Timer 驱动——沿用 mini-pong TF-1 静态断言（源码无 `_process(`），「HUD 不抢戏」的机器守卫。
2. **一条线一个信息**：血条 = 两段式单条（段1 满管 + 段2 半管同轴），架势条 = 细条（玩家：血条下方；敌人：顶部中央）——信息密度克制（Obsidian 体验引擎「信号 vs 噪声」「如果界面被注意到，它就失败了」）。
3. **低血是唯一色彩例外**：常态苍白月白 `#e8e6e3` + 墨黑，活性段 <30% 时血色点缀 + `low_health_changed` 信号 → #582 SW-011 vignette——「克制不是无色，是颜色只在该出现时出现」。
4. **零贴图零 tscn**：全部 Control 代码创建，`_HudBar` 内部类 `_draw()` 自绘——AC4「无外部 UI 图像资源」字面满足，headless 可实例化可断言。
5. **单例守卫**：Hud 加入 `hud` group；重复实例化时第二实例 `queue_free()`——战斗场景组装（#585）幂等安全。

```
                    ★ Issue #576 本设计（shandong-wolf HUD 层）
┌──────────────────────────────────────────────────────────────────────────────┐
│ 新建（4 文件，全部 shandong-wolf/ 下）                                          │
│  gdscripts/hud.gd                  Hud（CanvasLayer layer=1）—— 全部 UI 组件  │
│                                    + 内部类 _HudBar（Control _draw() 自绘条）  │
│  tests/test_hud.gd                 AC1-4 + 边界/静态断言全量用例（§8）         │
│  gdscripts/e2e_hud_capture.gd      截图驱动场景（CaptureRig 模式 4 态）        │
│  scenes/e2e_hud_capture.tscn       E2E 截图场景（Backdrop + Hud 实例）         │
├──────────────────────────────────────────────────────────────────────────────┤
│ 修改（2 文件）                                                                │
│  gdscripts/constants.gd            追加「HUD」# DRAFT 分区 13 常量（§2.1）     │
│  tests/run_tests.gd                追加 _run(test_hud.gd)                     │
│  e2e_shots.json                    追加 hud group（4 shots，§2.4）            │
├──────────────────────────────────────────────────────────────────────────────┤
│ 消费方（0 改动，后续 issue 挂接）                                               │
│  #575 CombatEntity 信号 ──► 血条/架势条/提示（纯订阅）                          │
│  low_health_changed ──► #585 组装接线 ──► #582 AtmosphereController.set_low_health() │
│  #585 组装 ──► bind_player(player) + set_target_enemy(enemy)                  │
└───────────────────────────────────┬──────────────────────────────────────────┘
                                    ▼
      #575 CombatEntity（玩家/敌人各一实例）
      hp_changed/stance_changed ──► _HudBar.set_segments() 重绘（_draw 驱动）
      stance_broken(enemy)      ──► ExecutePromptLabel 显示（3s = STANCE_BREAK_RECOVERY_SEC）
      died(enemy, final=true)   ──► KillPromptLabel 显示（1.5s）+ 处决提示隐藏（击杀 > 处决）
      state_changed(player, attack/execute) ──► 处决提示提前隐藏
      活性条 < HUD_LOW_HP_RATIO ──► emit low_health_changed(true) ──( #585 接线 )──► #582 vignette
```

**与 PRD 方案裁决的一致性：** PRD §4.1/§4.2/§4.3/§4.4/§4.5/§4.6 六决策点全部推荐方案 A，本设计逐项确认采纳，无分歧。PRD §7 Spike 按 depth/light 跳过——本设计无需要实验裁决的架构分叉（StyleBoxFlat/`_draw()` 为 Godot 内建能力，mini-pong 同构先例已验证 headless 可编译可断言）。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-19 侦查，plan agent 已逐条核实 origin/main b477bc2） | 与 #576 的差距 |
|------|--------------------------------------------------|---------------|
| `shandong-wolf/gdscripts/combat_entity.gd` | ✅ `CombatEntity`（#618 已合入，215 行）：6 信号契约与 PRD §1.1 逐字一致（hp_changed/stance_changed/stance_broken/state_changed/died/revived）+ `_active_life` 两段血语义 + 变体 @export 参数 | ✅ 信号源**全部就绪**，本层纯订阅零改动 |
| `shandong-wolf/gdscripts/constants.gd` | ✅ `WolfConstants` 9 个 # DRAFT 分区；已含 SCREEN_WIDTH=1280/SCREEN_HEIGHT=720、LIFE_1_MAX=100、LIFE_2_ABS=50、POSTURE_BREAK_THRESHOLD=100、STANCE_BREAK_RECOVERY_SEC=3.0 | ❌ 无 HUD 分区（阈值/布局/配色）——追加式新增（§2.1） |
| `shandong-wolf/scenes/Main.tscn` | ✅ 纯标题场景（CanvasLayer layer=1 + CenterContainer + 4 Label） | **不修改**（红线，实例化归 #585） |
| `shandong-wolf/gdscripts/` | ❌ 无任何 UI 代码（无 hud.gd、无 ProgressBar/StyleBoxFlat 先例） | 本 issue 全部新建 |
| `#582`（SW-011 雪夜氛围） | ⛔ PR #613 OPEN（impl/582 分支）：`blood_vignette.gd.set_low_health(enabled)` 消费端契约已建 | 本层只发 `low_health_changed` 信号，零引用其节点；合入与否不影响功能（信号安全 no-op） |
| `shandong-wolf/e2e_shots.json` | ✅ 已有 stick_figure group（#574，12 态 CaptureRig 剧本） | ❌ 无 HUD 截图组——追加 hud group（§2.4） |
| `shandong-wolf/tests/run_tests.gd` | ✅ 已挂 7 套件（含 CombatEntity），`_run()` 模式 | ❌ 追加 `_run("res://tests/test_hud.gd", "Hud")` |
| `shandong-wolf/project.godot` | ✅ viewport 1280×720、resizable=false | ✅ 固定画布锚定即可，零改动 |
| `scripts/e2e/resolve_plan.py` | ✅ group 级键可提升到 resolved plan（L26「first activated group wins」） | ✅ hud group 可自带 main_scene 指向 e2e_hud_capture.tscn |
| `mini-pong/` | ✅ #392/#448 信号驱动 HUD 先例 | 仅作模式参考，**不复制**（游戏隔离红线） |

### 1.2 PRD 断言 vs 实际代码交叉对照

| PRD 断言 | 实际代码（核实结果） | 设计裁决 |
|---------|---------------------|---------|
| CombatEntity 6 信号契约（hp_changed/stance_changed/stance_broken/died/state_changed/revived） | ✅ 属实（combat_entity.gd L40-45 逐字一致，含参数类型） | 直接订阅，纯消费方 |
| constants 含 LIFE_1_MAX/LIFE_2_ABS/POSTURE_BREAK_THRESHOLD/STANCE_BREAK_RECOVERY_SEC | ✅ 属实（100/50/100/3.0） | 只读消费；HUD 新常量追加新分区，不删改既有行 |
| 1280×720 resizable=false | ✅ project.godot L20-22 | 布局按固定画布锚点（左上 16,16 / 顶部中央） |
| e2e_shots.json 可承载多截图组 | ✅ resolve_plan.py group 级 main_scene 提升（first activated group wins） | hud group 自带 main_scene=e2e_hud_capture.tscn |
| run_tests.gd `_run()` 挂载模式 | ✅ 7 套件挂载 | 追加 test_hud 一行 |
| #582 `set_low_health()` 消费端已建 | ⛔ 代码在 impl/582 分支（PR #613 OPEN，未合入 main） | 本层只发信号零引用；未合入时信号安全 no-op（§5 失败 1） |
| **（PRD 未覆盖的设计点）** Hud 如何获得玩家实体 | PRD §8.3 API 仅列 set_target_enemy + debug 三件套，**无玩家绑定入口**；但 §3.1/§8.2 明言「订阅玩家实体信号」 | 设计裁决：新增 `bind_player(entity)` API（§2.2）——#585 组装时注入玩家 CombatEntity，订阅 hp_changed/stance_changed/died/revived；null 安全幂等 |
| **（PRD 未覆盖的设计点）** 处决提示「玩家攻击时提前隐藏」如何感知 | PRD §4.4 提及提前隐藏条件，但 §8.3 无对应 API/订阅说明 | 设计裁决：Hud 订阅玩家 `state_changed(from, to)`，to ∈ {attack, heavy_attack, execute} 时立即隐藏处决提示（§2.2 提示状态机） |

---

## 2. 新组件 — 详细设计

### 2.1 `gdscripts/constants.gd` — 追加「HUD」# DRAFT 分区（修改）

追加式新增分区（不触碰既有 9 分区任何一行），13 个常量，注释遵循 #572 规范（候补值 + 影响什么 + 情感断言）。全部标 `# DRAFT` 只读；taste 类（阈值/配色/文案时长）定稿归用户裁决（#584 调参面板可扩展挂入，非本层职责）。

| 常量 | 候补值 | 影响 | 情感断言 | 消费方 |
|------|--------|------|---------|--------|
| `HUD_LOW_HP_RATIO` | 0.30（候选 [0.25, 0.30, 0.35]） | 低血 vignette 触发阈值（活性条占比，严格小于） | 命悬一线才见血色——过早是焦虑，过晚是欺骗 | Hud 低血判定（§2.2） |
| `HUD_KILL_HINT_SECONDS` | 1.5（候选 [1.0, 1.5, 2.0]） | 击杀提示停留时长（含淡出） | 足够读完，不留恋 | KillPromptLabel Timer |
| `HUD_PLAYER_MARGIN` | Vector2(16, 16) | 玩家区块左上角边距 | 贴边不贴屏（细线呼吸感） | PlayerBarGroup 定位 |
| `HUD_STANCE_GAP` | 6.0 | 血条与玩家架势条间距 | 同组相关，不粘连 | 布局 |
| `HUD_BAR_WIDTH` | 240.0 | 血条/玩家架势条宽度 | 一条线的克制 | _HudBar size |
| `HUD_BAR_HEIGHT` | 10.0 | 血条高 | 细线不抢戏 | _HudBar size |
| `HUD_STANCE_HEIGHT` | 6.0 | 架势条高（玩家/敌人） | 比血条更细 = 次级信息 | _HudBar size |
| `HUD_ENEMY_BAR_WIDTH` | 240.0 | 敌人架势条宽 | 顶部中央细条（只狼首领条语义） | _HudBar size |
| `HUD_ENEMY_BAR_TOP` | 12.0 | 敌人架势条顶边距 | 贴顶不悬浮 | 布局 |
| `HUD_MOON_WHITE` | Color("#e8e6e3") | 常态描边/活性段填充 | 苍白月白（issue body 指定） | _HudBar |
| `HUD_INK_BLACK` | Color("#141414") | 背景/非活性段填充 | 墨黑（issue body 指定） | _HudBar |
| `HUD_BLOOD_RED` | Color("#8c2f2f") | 低血点缀（活性段填充+描边） | 血色只在该出现时出现 | _HudBar low 模式 |
| `HUD_HINT_FONT_SIZE` | 16 | 提示文字字号 | 克制的可读 | Label 字体 |

> 处决提示窗口**不新增常量**——复用 `STANCE_BREAK_RECOVERY_SEC=3.0`（#584 只读，PRD §4.4 字面）。

### 2.2 `gdscripts/hud.gd` — Hud（新增，CanvasLayer layer=1）

- **File:** `shandong-wolf/gdscripts/hud.gd`
- **class_name:** `Hud`（extends CanvasLayer）
- **节点结构（全部代码创建，零 tscn 零贴图）：**

```
CanvasLayer (Hud, layer=1)          ← 与 #562 标题 UI 同层约定（水墨 2 / 雪幕 3-5 / vignette 10）
└── PlayerBarGroup (Control, anchor 左上, offset=HUD_PLAYER_MARGIN(16,16))
    ├── PlayerHealthBar (_HudBar, size 240×10, 两段: [hp_1/LIFE_1_MAX, hp_2/LIFE_2_ABS], active=_active_life)
    └── PlayerStanceBar (_HudBar, size 240×6, offset y = 10+HUD_STANCE_GAP(6), 单段: stance/stance_max)
EnemyStanceBar (_HudBar, size 240×6, anchor 顶部中央: anchor_left/right=0.5, offset_x=-120..+120, offset_y=HUD_ENEMY_BAR_TOP, visible=false)
ExecutePromptLabel (Label, 隐藏, 中文 16px, 墨黑底 + 月白 1px 描边, 定宽 ~220px, text_overrun=TRIM_ELLIPSIS)
KillPromptLabel  (Label, 隐藏, 中文 16px, 墨黑底 + 月白 1px 描边, 定宽 ~120px, text_overrun=TRIM_ELLIPSIS)
```

**内部类 `_HudBar`（extends Control，`_draw()` 自绘条）：**

```gdscript
class _HudBar:
    extends Control
    ## 单条/多段同轴条：bg(墨黑 60% alpha) + 1px 月白描边(无圆角) + 逐段填充。
    ## 段数组与活性索引由 set_segments() 注入；queue_redraw() 驱动重绘（零 _process）。
    var _values: Array[float] = []
    var _maxes: Array[float] = []
    var _active_index: int = 0      # 活性段（高亮月白）；非活性段暗显墨黑
    var _low_hp_mode: bool = false  # 低血：活性段填充+描边转 HUD_BLOOD_RED

    func set_segments(values: Array[float], maxes: Array[float], active_index: int) -> void:
        _values = values; _maxes = maxes; _active_index = active_index
        queue_redraw()

    func set_low_hp_mode(enabled: bool) -> void:
        _low_hp_mode = enabled
        queue_redraw()

    func _draw() -> void:
        # 1) 背景: draw_rect(Rect2(Vector2.ZERO, size), HUD_INK_BLACK 60% alpha)
        # 2) 描边: draw_rect(Rect2(Vector2.ZERO, size), 边框色, false, 1.0)  # 1px, 无圆角
        # 3) 逐段填充: 段 i 宽 = size.x * clamp(value/max, 0, 1) * (段宽占比)
        #    —— 段1 全宽占比 = LIFE_1_MAX/(LIFE_1_MAX+LIFE_2_ABS)，段2 半宽占比 = LIFE_2_ABS/和
        #    —— i == _active_index → 填充色 = 月白（低血时血条段转 HUD_BLOOD_RED）；否则墨黑暗显
```

**信号：**

```gdscript
signal low_health_changed(enabled: bool)   # 边沿触发（活性条 < HUD_LOW_HP_RATIO 时恰好一次 true/false）
```

**状态属性：**

| 属性 | 初始值 | 说明 |
|------|--------|------|
| `_player: CombatEntity` | null | bind_player 注入；订阅 hp_changed/stance_changed/died/revived/state_changed |
| `_target_enemy: CombatEntity` | null | set_target_enemy 注入；订阅 stance_changed/stance_broken/died |
| `_low_health: bool` | false | 当前低血态（边沿触发基准，防每帧重发） |
| `_execute_hint_timer: Timer` | 代码创建 | 处决提示 3s 隐藏（STANCE_BREAK_RECOVERY_SEC）；重复触发重置 |
| `_kill_hint_timer: Timer` | 代码创建 | 击杀提示 1.5s 隐藏（HUD_KILL_HINT_SECONDS） |

**关键方法（签名与 PRD §8.3 一致 + 设计补全项）：**

| 方法 | 逻辑要点 |
|------|---------|
| `bind_player(entity: CombatEntity) -> void` | **设计补全（PRD §8.3 缺口，§1.2）**：幂等（重复绑定先断开旧连接）；订阅 `hp_changed` / `stance_changed` / `state_changed` / `died` / `revived`（`CONNECT_REFERENCE_COUNTED`）；null → 仅断开 |
| `set_target_enemy(entity: CombatEntity) -> void` | 幂等；换目标先断开旧敌人订阅；null → 隐藏 EnemyStanceBar；有效实体 → 订阅 stance_changed/stance_broken/died + 显示 EnemyStanceBar 并立即用当前 stance 值初始化 |
| `set_debug_hp(hp_1: float, hp_2: float, active_life: int) -> void` | E2E/单测驱动：等价于 `_on_player_hp_changed` 处理路径（画条 + 低血边沿判定） |
| `set_debug_stance(stance: float, stance_max: float) -> void` | E2E/单测驱动：玩家架势条直接更新 |
| `show_debug_hint(kind: String) -> void` | E2E/单测驱动：`"execute"` → 显示处决提示；`"kill"` → 显示击杀提示（走同一显隐逻辑） |
| `_on_player_hp_changed(hp_1, hp_2, active_life)` | ①两段条重绘：`PlayerHealthBar.set_segments([hp_1, hp_2], [LIFE_1_MAX, LIFE_2_ABS], active_life)`；②低血边沿：`active_max = active_life==1 ? LIFE_1_MAX : LIFE_2_ABS`；`ratio = active_hp/active_max`（max≤0 防御 → 1.0）；`low = ratio < HUD_LOW_HP_RATIO - 0.001`；`low != _low_health` → 更新基准 + `emit low_health_changed(low)` + `PlayerHealthBar.set_low_hp_mode(low)` |
| `_on_player_stance_changed(stance, stance_max)` | `PlayerStanceBar.set_segments([stance], [stance_max], 0)` |
| `_on_enemy_stance_changed(stance, stance_max)` | `EnemyStanceBar.set_segments([stance], [stance_max], 0)`（条可见性由 set_target_enemy 控制） |
| `_on_enemy_stance_broken(entity)` | 显示处决提示：文案（implement 选 1 草稿 + B2 候选清单进 PR）→ Label.visible + Tween 淡入（0.15s）→ `_execute_hint_timer.start(STANCE_BREAK_RECOVERY_SEC)`（重复触发 = 重置计时，幂等不叠加） |
| `_on_player_state_changed(from, to)` | **设计补全（§1.2）**：to ∈ {"attack", "heavy_attack", "execute"} → 立即隐藏处决提示（PRD §4.4「玩家攻击时提前隐藏」） |
| `_on_enemy_died(entity, final)` | final==true → 显示击杀提示（Tween 淡入 0.15s + `_kill_hint_timer.start(HUD_KILL_HINT_SECONDS)`）**且立即隐藏处决提示**（优先级：击杀 > 处决）；final==false → 仅隐藏处决提示 + 清空敌人架势条（MVP 无复活敌人，防御） |
| `_on_player_died(entity, final)` / `_on_player_revived(entity)` | 血条表现由 hp_changed 自动驱动（died 时 hp 已为 0）；revived 后 hp_changed(0, 50, 2) 到达 → 段2 半管亮起——**本层零额外逻辑**（克制） |
| `_exit_tree()` | 断开所有实体订阅（配合 CONNECT_REFERENCE_COUNTED 双保险，防悬垂引用） |
| `_ready()` | 加入 `hud` group；**单例守卫**：`get_tree().get_first_node_in_group("hud")` 存在且非 self → `queue_free()` |

**集成说明（#585 组装）：** `bind_player(player_entity)` + `set_target_enemy(enemy_entity)` 由 #585 在战斗场景实例化时注入；`low_health_changed` 由 #585 接线到 `AtmosphereController.set_low_health()`。本层不持有任何场景/氛围节点引用。

### 2.3 `gdscripts/e2e_hud_capture.gd` + `scenes/e2e_hud_capture.tscn` — E2E 截图驱动场景（新增）

复用 #574 CaptureRig 模式（e2e_capture.gd 轮询 `/root/CaptureRig.current_state` + auto_cycle 兜底 + settle_frames 覆盖 Tween 时长），**HUD 驱动零战斗场景依赖**——直接走 `set_debug_*` / `show_debug_hint` 公有 API（PRD §8.3 契约），信号源（#577/#580）未合入也能截全 4 帧。

- **File:** `shandong-wolf/gdscripts/e2e_hud_capture.gd`（extends Node2D，class_name E2EHudCapture）
- **驱动契约（与 framework/templates/e2e_capture.gd 兼容）：**
  - `current_state: int`（NORMAL=0 / LOW_HP=1 / EXECUTE_HINT=2 / KILL_HINT=3）——shot plan 的 state_node/state_property 轮询目标
  - `auto_cycle: bool` + `auto_cycle_frames: int`（e2e_capture.gd press 仅支持 enter/space/esc/方向键，digit 键不兼容 → autoplay.tweaks 开启自循环兜底，与 #574 同路径）
  - `_unhandled_input` digit 键 0-3 映射（人工/脚本注入备选）

| state | 驱动动作 | 截图内容 |
|:-----:|---------|---------|
| NORMAL | `set_debug_hp(80, 50, 1)` + `set_debug_stance(40, 100)` + `set_target_enemy(敌人桩)`（敌人 stance 60） | 常态：两段血条（段1 80% 月白、段2 暗显）+ 玩家架势条 + 敌人顶部中央架势条 |
| LOW_HP | `set_debug_hp(20, 50, 1)`（< 30%） | 低血：活性段血色点缀 + low_health_changed(true)（若 #582 已合入并经 #585 接线则 vignette 可见；未合入仅截 HUD 本体） |
| EXECUTE_HINT | `show_debug_hint("execute")` | 处决提示文字可见（3s 窗口内截图） |
| KILL_HINT | `show_debug_hint("kill")` | 击杀提示文字可见（1.5s 窗口内截图） |

- **File:** `shandong-wolf/scenes/e2e_hud_capture.tscn`
  - 根节点 `CaptureRig`（Node2D + e2e_hud_capture.gd）
  - `Backdrop`（ColorRect 1280×720，雪夜水墨底色 Color(0.1, 0.14, 0.18, 1)——与 #574 截图场景同底色，观感裁决有水墨上下文）
  - `Hud` 实例（CanvasLayer layer=1，脚本 hud.gd）+ 敌人桩 CombatEntity 实例（供 set_target_enemy 注入；不参与战斗逻辑）

### 2.4 `e2e_shots.json` — 追加 hud group（修改）

在既有 `groups` 内追加 `hud` group（不动 stick_figure group 任何 shot；group 级 main_scene 提升机制见 resolve_plan.py L26）：

```json
"hud": {
  "_comment": "#576 极简 HUD 观感裁决 4 帧（normal/low_hp/execute_hint/kill_hint）；驱动走 Hud 公有 debug API（set_debug_* / show_debug_hint），零战斗场景依赖；settle_frames 覆盖 Tween 淡入时长。",
  "main_scene": "res://scenes/e2e_hud_capture.tscn",
  "state_node": "/root/CaptureRig",
  "state_property": "current_state",
  "match": ["gdscripts/hud\\.gd", "gdscripts/e2e_hud_capture\\.gd", "scenes/e2e_hud_capture\\.tscn"],
  "shots": [
    { "name": "01_hud_normal",      "state": 0, "settle_frames": 10 },
    { "name": "02_hud_low_hp",      "state": 1, "settle_frames": 10 },
    { "name": "03_hud_execute_hint", "state": 2, "settle_frames": 10 },
    { "name": "04_hud_kill_hint",    "state": 3, "settle_frames": 10 }
  ]
}
```

---

## 3. 既有组件修改

### 3.1 新文件

| 文件 | 内容 | 规模预估 |
|------|------|:-------:|
| `shandong-wolf/gdscripts/hud.gd` | Hud（CanvasLayer layer=1）+ 内部类 _HudBar 自绘 + 提示 Label + 低血边沿 + 单例守卫 | ~300 行 |
| `shandong-wolf/tests/test_hud.gd` | AC1-4 + 边界/静态断言全量用例（§8） | ~350 行 |
| `shandong-wolf/gdscripts/e2e_hud_capture.gd` | CaptureRig 模式 4 态驱动（current_state + auto_cycle + digit 映射） | ~90 行 |
| `shandong-wolf/scenes/e2e_hud_capture.tscn` | CaptureRig + Backdrop + Hud 实例 + 敌人桩 | ~30 行 |

### 3.2 修改文件

| 文件 | 变更 | 原因 |
|------|------|------|
| `shandong-wolf/gdscripts/constants.gd` | 追加 `# ── HUD (#576) ──` # DRAFT 分区 13 常量（§2.1 表） | HUD 阈值/布局/配色单一事实源；只读，taste 定稿归用户（#584 面板可挂） |
| `shandong-wolf/tests/run_tests.gd` | `_run_tests()` 内追加一行：`_run("res://tests/test_hud.gd", "Hud")` | 挂载新套件（#572 模式） |
| `shandong-wolf/e2e_shots.json` | 追加 hud group（§2.4，4 shots + group 级 main_scene） | AC3 E2E 观感裁决截图剧本 |

### 3.3 移除/弃用文件

无（零删除）。

### 3.4 受影响的测试文件

| 测试文件 | 变更性质 |
|---------|---------|
| `shandong-wolf/tests/test_hud.gd` | **新增**（§8 全部用例） |
| `shandong-wolf/tests/run_tests.gd` | 追加一行挂载（§3.2） |
| 其余 7 套件（含 test_combat_entity.gd） | 不改；防回归跑全量即可（§8 场景 G） |

---

## 4. 数据流

### Flow 1：玩家受击 → 血条更新 + 低血边沿（正常路径）

```
#577 判定层 → entity.take_damage(12) → #575 emit hp_changed(88, 50, 1)
  → Hud._on_player_hp_changed(88, 50, 1)
      → PlayerHealthBar.set_segments([88, 50], [100, 50], 1) → queue_redraw() → 段1 88% 月白 / 段2 暗显
      → 活性条 = hp_1/LIFE_1_MAX = 0.88 ≥ 0.30 → low=false，_low_health 已 false → 不发射（无重复）
  → 持续受击至 hp_1=25 → ratio=0.25 < 0.30-0.001 → low=true ≠ _low_health(false)
      → _low_health=true → emit low_health_changed(true) → (#585 接线) → #582 set_low_health(true) → vignette 渐显
      → PlayerHealthBar.set_low_hp_mode(true) → 活性段血色点缀
```

### Flow 2：架势涨落 → 双架势条（玩家 / 敌人）

```
#577: entity.take_stance_damage(10) → #575 emit stance_changed(stance, stance_max)
  → 玩家：Hud._on_player_stance_changed(stance, 100) → PlayerStanceBar.set_segments([stance],[100],0)
  → 敌人（target_enemy 已注入）：Hud._on_enemy_stance_changed(stance, 100) → EnemyStanceBar 同轴更新
  → stance ≤ 0 → #575 break_stance() → emit stance_broken(enemy) → Flow 3
```

### Flow 3：架势崩解 → 处决提示（#577/#580 事件源，本层只显示）

```
#575 emit stance_broken(enemy)
  → Hud._on_enemy_stance_broken(enemy)
      → ExecutePromptLabel 文案（B2 草稿）→ visible + Tween 淡入 0.15s
      → _execute_hint_timer.start(STANCE_BREAK_RECOVERY_SEC = 3.0)  # 重复 stance_broken → 重置计时（幂等）
  → 分支 A（#580 处决成功）：玩家 state_changed(_, "execute") → 立即隐藏处决提示
  → 分支 B（玩家攻击打断）：玩家 state_changed(_, "attack"/"heavy_attack") → 立即隐藏
  → 分支 C（3s 超时）：Timer 超时 → Tween 淡出 0.3s → 隐藏
```

### Flow 4：敌人死亡 → 击杀提示（优先级：击杀 > 处决）

```
#575 emit died(enemy, true)
  → Hud._on_enemy_died(enemy, true)
      → KillPromptLabel 文案（B2 草稿）→ visible + Tween 淡入 0.15s
      → _kill_hint_timer.start(HUD_KILL_HINT_SECONDS = 1.5)
      → ExecutePromptLabel 立即隐藏（处决提示让位；不等待其 Timer）
      → EnemyStanceBar 隐藏（敌人已终态）
  → 1.5s 后 Timer 超时 → Tween 淡出 0.3s → 隐藏
```

### Flow 5：回生切换（active_life 1→2）— 无跳变无闪烁

```
#578: entity.revive() → #575 emit revived + hp_changed(0, 50, 2)
  → Hud._on_player_hp_changed(0, 50, 2)
      → set_segments([0, 50], [100, 50], 2) → 段1 0% 暗显、段2 50/50 全宽亮起（月白）
      → 活性条 = hp_2/LIFE_2_ABS = 1.0 ≥ 0.30 → low=false（若此前 true 则边沿发射 false → vignette 渐隐）
      → 条总视觉长度不变（段2 已在位）——回生瞬间无条长突变
```

### Flow 6：敌人释放 / 无目标（防御路径）

```
场景卸载或 set_target_enemy(null)
  → 断开旧敌人订阅（CONNECT_REFERENCE_COUNTED + _exit_tree 双保险）→ EnemyStanceBar.visible=false
  → 实体提前释放 → Godot 自动断开引用计数连接 → Hud._target_enemy 置 null（_exit_tree 兜底）→ 不崩溃不悬垂
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解措施 |
|---|---------|---------|
| 1 | 无 target_enemy / 敌人已释放 | EnemyStanceBar 默认 visible=false；set_target_enemy(null) 隐藏 + 断开订阅；实体释放经 CONNECT_REFERENCE_COUNTED + _exit_tree 双保险置 null——不报错不悬垂（PRD §5.2-1） |
| 2 | 回生切换（active_life 1→2） | hp_changed(0, 50, 2) → 段1 清空暗显、段2 亮起；条总长不变无跳变（PRD §5.2-2，Flow 5） |
| 3 | 低血阈值边界（恰好 30%） | 严格小于 + 0.001 容差：`ratio < HUD_LOW_HP_RATIO - 0.001` → 29.9% 发 / 30.0% 不发；单测 T6 锁死语义（PRD §5.2-3） |
| 4 | 处决提示重复触发（理论单次，防御） | Timer 重置幂等重显示：重复 stance_broken → 重置 3s 计时，不叠加不闪烁（PRD §5.2-4，T13） |
| 5 | 击杀提示与处决提示竞争 | 敌人 died 时处决提示**立即隐藏**、击杀提示显示——优先级：击杀 > 处决（PRD §5.2-5，T14） |
| 6 | died(final=false)（复活类敌人，MVP 无） | 不显示击杀文字；仅隐藏处决提示 + 清空敌人架势条（PRD §5.2-6，T15） |
| 7 | 玩家死亡 / 复活 | 血条表现由 hp_changed 自动驱动（died 时 hp=0 归零态）；revived → hp_changed 到达段2 半管亮起；本层零额外逻辑（PRD §5.2-7，T17/T18） |
| 8 | 数值异常（负 / NaN / 越界） | _HudBar 段宽 `clamp(value/max, 0, 1)`（max≤0 防御返回 1.0）；不除零不崩溃（PRD §5.2-8，#575 已先 clamp） |
| 9 | 多实例（重复实例化） | `_ready()` 单例守卫：`hud` group 已存在非 self 实例 → queue_free()（PRD §5.2-9，T21） |

### 失败路径

| # | 失败路径 | 缓解措施 |
|---|---------|---------|
| 1 | #582 未合入（vignette 消费端缺失） | low_health_changed 无监听者 → Godot 信号安全 no-op；HUD 功能不受影响；vignette 不显示 = 依赖链预期（#585 接线后闭环）；不阻塞本 issue 合入（PRD §5.3-1） |
| 2 | 实体提前释放（敌人被处决淡出） | 信号连接随对象释放断开（CONNECT_REFERENCE_COUNTED + _exit_tree 主动断开）；HUD 不持有悬垂引用（target_enemy 置 null + 隐藏敌人架势条）（PRD §5.3-2） |
| 3 | 文案长度溢出 | 提示 Label 定宽（处决 ~220px / 击杀 ~120px）+ `text_overrun_behavior = TRIM_ELLIPSIS`；超长候选文案不破坏布局（PRD §5.3-3） |
| 4 | E2E 截图依赖战斗状态机未就绪 | e2e_hud_capture 用 CaptureRig 模式（#574 已验证）：auto_cycle 兜底 + settle_frames 覆盖 Tween 时长；HUD 驱动走公有 debug API，零战斗场景依赖（PRD §5.3-4） |

---

## 6. 集成点

> **状态约定：** ⬜ = 待 implement 接线；✅ = 已连接（implement agent 完成后更新；review agent 验证）。

| 集成 | 本组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 玩家实体绑定 | `Hud.bind_player(player)` | #585 | 组装层实例化后调用；订阅 hp_changed/stance_changed/state_changed/died/revived | ⬜ 待 #585 |
| 敌人目标注入 | `Hud.set_target_enemy(enemy)` | #585 | 组装层注入战斗目标（MVP 单敌人战场 = 唯一敌人实例） | ⬜ 待 #585 |
| 低血 vignette 接线 | `low_health_changed(enabled)` | #582 / #585 | #585 胶水层 wire → `AtmosphereController.set_low_health()`；#582 未合入时信号 no-op | ⬜ 待 #585 |
| 处决事件源 | `stance_broken(entity)` | #577 / #580 | 信号订阅（本层只显示；判定/距离语义归 #577/#580） | ⬜ 待 #577/#580（未合入时 debug API 可驱动 E2E） |
| 死亡事件源 | `died(entity, final)` | #580 / #577 | 信号订阅（击杀提示 + 处决让位） | ⬜ 待 #577/#580 |
| 战斗实景帧含 HUD | e2e_shots.json hud group | #586 | 组装后实景帧叠加 HUD 观感 | ⬜ 待 #586 |

> 本 issue 交付可独立实例化/单测/截图驱动的组件与信号契约；所有场景内组装由 #585 完成（PRD §1.4 范围边界）。

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 依赖 | 预估 |
|:----:|:------:|------|------|:----:|
| Phase 1 | P0 | constants.gd 追加「HUD」分区 13 常量（§2.1） | 无 | 0.5h |
| Phase 2 | P0 | hud.gd：Hud 骨架 + _HudBar 自绘 + 布局锚点 + 提示 Label（§2.2） | Phase 1 | 3h |
| Phase 3 | P0 | hud.gd 信号接线：bind_player/set_target_enemy + 低血边沿 + 提示显隐状态机（§2.2） | Phase 2 | 2.5h |
| Phase 4 | P0 | test_hud.gd 全量用例（§8）+ run_tests.gd 挂载 + 全量回归 | Phase 2-3 | 3h |
| Phase 5 | P1 | e2e_hud_capture.gd/.tscn + e2e_shots.json hud group（§2.3/§2.4） | Phase 2-3 | 1.5h |

> Phase 2/3 可合并不拆分提交；Phase 5 可在 Phase 4 前先行（截图驱动依赖公有 debug API，不依赖测试套件）。

---

## 8. 测试用例描述

> **测试文件：** `shandong-wolf/tests/test_hud.gd`（挂载 run_tests.gd；测试写法沿用 test_state_machine.gd 模式：extends Object + passed/failed + `_assert`；Hud 是 CanvasLayer/Node 需 add 到 root 以便 _ready/_exit_tree 生效，或直接 new + 手动调 debug API——**纯 API 断言可免树**）。**只写描述，不写可运行测试代码（implement agent 职责）。**

### Scenario A：布局与两段式血条结构（AC1）
- Test 1 锚点断言：Hud 实例化后 PlayerBarGroup 位于 (16,16)（= HUD_PLAYER_MARGIN）；PlayerHealthBar size = (240, 10)（= HUD_BAR_WIDTH × HUD_BAR_HEIGHT）；窗口 1280×720 下全可见
- Test 2 两段条结构：`set_debug_hp(100, 50, 1)` → 段1 全宽、段2 半宽同轴（宽度比 100:50）；`set_debug_hp(50, 50, 1)` → 段1 半宽、段2 半宽
- Test 3 活性段：active_life=1 → 段1 高亮月白、段2 暗显；active_life=2 → 反（_HudBar._active_index 断言）
- Test 4 玩家架势条：位于血条正下方（间距 = HUD_STANCE_GAP=6）；size = (240, 6)（= HUD_STANCE_HEIGHT）
- Test 5 敌人架势条：锚定顶部中央（anchor 0.5）、size = (240, 6)、顶距 = HUD_ENEMY_BAR_TOP；无 target 时 visible=false

### Scenario B：低血信号边沿（AC2）
- Test 6 阈值下发射：`set_debug_hp(29.9, 50, 1)`（29.9% < 30%）→ 恰好一次 `low_health_changed(true)`
- Test 7 阈值上不发射：`set_debug_hp(30.0, 50, 1)`（严格小于 + 0.001 容差）→ 零发射
- Test 8 边沿恢复：30 → 29.9（true）→ 30.0（false）→ 30.0（无重复发射）；信号计数 = 2（恰好一次 true + 恰好一次 false）
- Test 9 半管活性条：active_life=2 时 `set_debug_hp(0, 14.9, 2)`（14.9 < 50×0.30=15）→ true；`set_debug_hp(0, 15.0, 2)` → false
- Test 10 低血视觉：低血态下 PlayerHealthBar 活性段填充色 = HUD_BLOOD_RED（_HudBar._low_hp_mode + 填充色断言）

### Scenario C：敌人架势条显隐（target_enemy）
- Test 11 set_target_enemy(敌人桩) → EnemyStanceBar visible=true；emit 敌人 stance_changed(60, 100) → 条值 60%
- Test 12 set_target_enemy(null) → 条隐藏；旧敌人后续 emit stance_changed 不再影响条（订阅已断开）
- Test 13 换目标：set_target_enemy(enemy2) → 旧敌人信号不再更新；enemy2 信号生效
- Test 14 重复注入幂等：set_target_enemy(同一实体) 两次 → 订阅不重复（信号回调次数 = 1）

### Scenario D：提示文字（处决 / 击杀 / 竞争）
- Test 15 处决提示显示：emit 敌人 stance_broken → ExecutePromptLabel visible + 文案非空；`_execute_hint_timer` 剩余时间 = STANCE_BREAK_RECOVERY_SEC
- Test 16 处决提示 3s 隐藏：await 3.0s+（或手动触发 Timer 超时）→ Label 隐藏
- Test 17 处决提示幂等：重复 emit stance_broken → 计时重置（剩余时间回到 3.0s）、Label 无闪烁无叠加
- Test 18 击杀提示：emit 敌人 died(enemy, true) → KillPromptLabel visible + 文案非空 + **ExecutePromptLabel 立即隐藏**；`_kill_hint_timer` 剩余 = HUD_KILL_HINT_SECONDS
- Test 19 击杀提示 1.5s 淡出：await 1.5s+ → KillPromptLabel 隐藏
- Test 20 died(final=false)：不显示击杀提示；若处决提示可见则隐藏；敌人架势条清空
- Test 21 玩家攻击提前隐藏：处决提示可见时 emit 玩家 state_changed(_, "attack") / "execute" → 立即隐藏

### Scenario E：回生 / 死亡 / 复活
- Test 22 回生切换：`set_debug_hp(0, 50, 2)` → 段1 空暗显、段2 全宽亮起；条总视觉长度与 (100,50,1) 时一致（无跳变）
- Test 23 玩家死亡：emit 玩家 died(player, false) → 不崩溃、血条归零态（hp_changed 已先行）；emit revived → `set_debug_hp(0,50,2)` 路径恢复
- Test 24 低血伴随回生：低血态（true）→ 回生 hp_changed(0, 50, 2)（ratio=1.0）→ 边沿发射 low_health_changed(false)

### Scenario F：静态断言（AC4 + TF-1 零轮询）
- Test 25 零贴图（AC4）：hud.gd 源码无 `load("res://*.png")` / `load("res://*.jpg")` / `Texture2D` / `Image` / `TextureProgressBar` 引用（读源码字符串断言）
- Test 26 零轮询（TF-1）：hud.gd 源码无 `_process(` / `_physics_process(` 出现
- Test 27 单例守卫：root 已有 Hud（group "hud"）时再 new 一个 Hud 加入场景 → 第二实例 queue_free（延迟帧后 is_queued_for_deletion）
- Test 28 数值异常防御：`set_debug_hp(-5, 50, 1)` / `set_debug_hp(NAN, 50, 1)` → 条宽 clamp [0,1]、不崩溃不除零

### Scenario G：全量回归
- Test 29 `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 8 套件全绿（含既有 7 套件防回归，重点 test_combat_entity.gd 信号契约无回归）

---

## 9. 验收条件映射（源自 Issue #576 body）

| # | 验收条件 | 本设计保障 | 覆盖用例 |
|---|---------|-----------|:-------:|
| AC1 | HUD 可在 1280x720 下正确定位，血条两段式与架势条分开显示 | §2.2 锚点布局（左上 16,16 玩家区块 + 顶部中央敌人架势条）+ _HudBar 两段同轴自绘 | T1-T5 |
| AC2 | 玩家血条低于 30% 时出现血色 vignette 提示（由 SW-011 渲染层实现，HUD 仅发信号） | §2.2 低血边沿判定（严格小于 + 0.001 容差）+ `low_health_changed(enabled)` 信号；#585 接线到 #582 `set_low_health()`（集成点表） | T6-T10 |
| AC3 | E2E 截图提交用户裁决：HUD 观感克制、与雪夜水墨背景融为一体（禁止光效/圆角/饱和堆砌） | §2.3/§2.4 e2e_hud_capture 4 帧（normal/low_hp/execute_hint/kill_hint）+ 雪夜水墨底色 Backdrop；1px 细线/无圆角/低饱和/零光效由 _HudBar 绘制规格保证 | E2E 剧本（§2.4） |
| AC4 | 无外部 UI 图像资源 | §2.2 纯 Control + StyleBoxFlat/_draw() 程序化绘制零贴图 | T25（静态断言） |

---

## 10. 明确不修改（与 PRD §8.5 红线对齐）

- ❌ 不引入任何 UI 贴图/外部图像资源（AC4；纯 Control + StyleBoxFlat/_draw()）
- ❌ 不修改 `scenes/Main.tscn`（标题场景红线；HUD 实例化归 #585）
- ❌ 不修改 `combat_entity.gd` / `input_controller.gd` / `stick_figure_*.gd` / `player_controller.gd` 等已合入代码（纯消费方，零改动）
- ❌ 不写战斗判定逻辑（弹反/拼刀/距离/崩解判定归 #577/#580）
- ❌ 不实现 vignette 渲染（归 #582 SW-011）；本层只发 `low_health_changed` 信号
- ❌ 不裁决 # DRAFT 数值（只读 constants；新 HUD 常量标 # DRAFT 待用户定稿）
- ❌ 不引入第三方 addon（#572 裁决 + PRD §6.2 调研：无成熟克制零贴图可复用方案）
- ❌ 不修改 mini-pong/ 任何文件（游戏隔离红线）
- ❌ 不加 `_process(` / `_physics_process(` 轮询（零轮询契约，TF-1 静态断言兜底）

## 附：开源调研结论（PRD §6.2 已调研，implement PR 须附说明）

PRD §6.2 结论直接引用：GitHub 检索（godot health bar / hud 模板按 star 排序）候选全部 texture/编辑器节点型且 ≤19⭐（Astridson/godot-segmented-bar ⭐19、vi4hu/godot_health_bar_2d ⭐10、JarLowrey/TextureProgressOfSubunits ⭐8、01rasmus/moba-health-bars-godot ⭐2 等），无成熟、克制、零贴图的水墨极简 HUD 方案；Niekvdm/godot-plugins-gtml ⭐87 为标记语言非 health bar 组件。按 issue body「开源优先，找不到再自行实现」→ **自研**：Godot 内建 Control + StyleBoxFlat/_draw()（1px 描边/半透明填充/零圆角）——内建能力零第三方依赖，mini-pong #392/#448 项目内已有同构先例。implement PR 须引用本调研结论，无需重复调研。
