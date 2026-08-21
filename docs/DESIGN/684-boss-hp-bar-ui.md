# Design: [UI] 敌人 Boss 血条 UI（只狼式顶部血条 + 架势条组合）

> **Parent Issue:** #684（feature / workflow/plan / priority/high / ui / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **推荐组合全项确认采纳** —— 4.1-A 独立名字 Label（`EnemyNameLabel` + `set_enemy_display_name()`）/ 4.2-A 条级白闪 Tween（机械，`_HudBar.set_break_flash()`；碎裂提示 B 留 `# DRAFT` 候选，implement 不实现）/ 4.3-A `set_boss_mode(bool)` 新 API 分档（零签名破坏）/ 4.4-A 纯条不显数字（百分比文本 B 留 `# DRAFT` 候选）。方案 B/C 否决理由同 PRD §4。
> **Reference PRD:** `docs/PRD/684-boss-hp-bar-ui.md`（research PR #698 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/682-elite-boss-ai.md` §2.5（EnemyHealthBar 基底，#695 已交付——本设计在其上**纯 UI 呈现层增量**：名字 / 崩解闪白 / 分档，零新数据管道）；`docs/DESIGN/576-hud-stance-bars.md`（#576 HUD 母体，风格/色板/`_HudBar` 契约）；`docs/GAME_DESIGN/shandong-wolf/02-CONSTANTS.md`（# DRAFT 常量表，本 issue 需增行）
> **所有权:** `content_ownership: mechanical`（名字 Label 节点结构/布局锚点/闪白状态机/分档三态显隐/信号接线全部机械可验；**唯一 taste 环节 = 敌人名字文案、闪白时长与颜色定值、碎裂提示与百分比文本去留，全部标 `# DRAFT` 只读候选，定稿归 #584/#576 human-review 通道**——agent 禁止替用户定稿）
> **深度:** standard（GitHub 无 depth 标签；PRD 头标注 depth: standard）—— 涉及文件 **6**（4 .gd + 1 测试 + 1 e2e_shots.json）+ **6 项实现子任务跨 5 子系统**（常量 / 名字 Label / 闪白状态机 / 分档 API / 装配接线 / 测试与 E2E）→ **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统，照 #683/#661 先例）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-684，branch `plan/684-boss-hp-bar-ui`）；**#584（OPEN, status/human-review）并行定稿 DRAFT 数值** —— 本设计全部新值按「候选集+影响+情感断言」# DRAFT 协议标注，实现前须查 #584 状态；**#682（#695 merged）的 EnemyHealthBar/EnemyStanceBar 为本设计基底**；`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/` 零影响；战斗数据源（combat_entity / enemy_ai / combat_judge）**零改动**——本设计只消费既有 4 信号（hp_changed / stance_changed / stance_broken / died），零新信号源
> **红线:** 只动 PRD §3.1 列出的 6 文件；**绝不修改既有公有 API 签名**——`set_target_enemy(entity)` / `bind_player(entity)` / `set_debug_*` / `show_debug_hint` 保持原样（#682 红线延续，main_battle L185-187 与既有测试零改动）；**不引入 `_process` 轮询、不引入贴图/tscn**（#576 零贴图契约 + TF-1 静态断言延续）；**不裁决 `# DRAFT` 数值**；**不新增战斗信号源**；`project.godot`、`game-env/manifest.yaml` 不改；**不写可运行测试文件**（只产出 DESIGN/TASKS 文档 + 测试用例描述）；PR body 用 `Parent #684`（不带冒号）

---

## 1. 架构总览

**问题本质是「#695 已交付主体、缺口集中在呈现层三处」：** ① 顶部双条组合（EnemyHealthBar 240×10 @12 + EnemyStanceBar @26）与信号驱动（hp_changed/stance_changed）已由 #695 落地，AC1/AC2/AC4 实质满足；② 剩余增量 = **敌人名字 Label（缺失）**、**架势崩解条级闪白（缺失，现仅有文字提示）**、**Boss/杂兵呈现分档（未设计）**、**HP 百分比呈现方式（未裁决）**——全部是既有信号的**纯消费端增量**，无新数据管道、无新文件。

**设计哲学：结构 agent 全权机械工程 + taste 通道只读候选；四个决策点共享同一批文件与同一次实现窗口，合并实现避免重复返工。**

1. **名字 = 独立 Label 节点**——`_make_hint_label` 同构（零 tscn 零贴图、锚点 0.5、`OVERRUN_TRIM_ELLIPSIS`），血条上方（offset_top 候选 0..4），boss 档可见、杂兵档隐藏、空串隐藏；
2. **崩解反馈 = 条级白闪状态机**——`_HudBar` 新增 `set_break_flash()`：崩解瞬间填充/描边转 `HUD_STANCE_BREAK_FLASH_COLOR`（默认月白，sekiro「崩解白闪」基准），Tween 淡出回常态（候选 0.12/0.18/0.25s）；与处决文字提示**正交**（互不遮挡）；碎裂提示（PRD 4.2-B）留 taste 候选，implement 不实现；
3. **分档 = `set_boss_mode(bool)` 新 API**——既有 `set_target_enemy(entity)` 签名零改动；true = 名字+血条+架势条全显；false = 血条+名字隐藏、仅保留小架势条（现状位置）；幂等；注入时读取档位；
4. **HP 百分比 = 纯条呈现**——血条长度即百分比（`set_segments` 天然百分比语义，Sekiro 自身不显数字）；数字文本（PRD 4.4-B）留 taste 候选。

```ascii
★ Issue #684 本设计（shandong-wolf HUD 呈现层增量，hud.gd 纯代码，零 tscn/贴图）
┌──────────────────────────────────────────────────────────────────────┐
│ Hud (CanvasLayer, layer=1)                                            │
│ ├─ EnemyNameLabel (Label, 新)                                          │
│ │    anchor 0.5 · width=HUD_ENEMY_NAME_WIDTH(240) · offset_top=2      │
│ │    text ← set_enemy_display_name(name)（taste 文案 # DRAFT）         │
│ │    visible = _boss_mode and name != ""                              │
│ ├─ EnemyHealthBar (_HudBar, #695 既有)  @12..22  暗红粗条 240×10       │
│ ├─ EnemyStanceBar (_HudBar, #695 既有)  @26..32  小架势条 240×6        │
│ │    + set_break_flash()（新）：崩解闪白 → Tween 淡出回常态              │
│ └─ ExecutePromptLabel / KillPromptLabel（#576 既有，不改）             │
│                                                                        │
│ 分档状态: _boss_mode: bool（新）——set_boss_mode(true/false) 写入        │
│           set_target_enemy 注入时按档位初始化三态显隐                    │
│                                                                        │
│ 数据流（§4）: CombatEntity 信号 ──► Hud ──► 条/名字（全为既有信号消费端） │
│   hp_changed      ──► EnemyHealthBar.set_segments        ✅ 既有       │
│   stance_changed  ──► EnemyStanceBar.set_segments        ✅ 既有       │
│   stance_broken   ──► EnemyStanceBar.set_break_flash() + 处决文字  ← 新 │
│   died(final)     ──► 名字隐藏 + 双条隐藏 + 击杀提示        ← 名字联动新 │
└──────────────────────────────────────────────────────────────────────┘
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的处理 |
|------|:---:|:---:|------|
| EnemyHealthBar 顶部暗红条 + hp_changed 订阅（`hud.gd`） | #682（#695 merged） | ✅ | **改（additive）**：不动既有布局/接线；仅并入分档显隐 + 新增名字联动 |
| EnemyStanceBar 下移 @26 + stance_changed 订阅（`hud.gd`） | #682 | ✅ | **改（additive）**：新增 `set_break_flash()` 闪白状态机（`_on_enemy_stance_broken` 增订触发） |
| `HUD_ENEMY_*` / `HUD_*` 色板常量（`constants.gd`） | #576 + #682 | ✅ | **改（追加分区）**：新增名字/闪白 5 项 `# DRAFT` 常量（候选集注释） |
| `set_target_enemy` / `_disconnect_enemy` / `_on_enemy_died`（`hud.gd`） | #576 | ✅ | **改（内部）**：显隐逻辑收敛到 `_apply_enemy_visibility()`（三态联动），签名零改动 |
| 敌人装配（`main_battle.gd` `_build_hud`） | #585（#666 merged） | ✅ | **改（+2 行，可选）**：`set_boss_mode(true)` + `set_enemy_display_name(...)` |
| E2E 截图驱动（`e2e_hud_capture.gd` / `e2e_shots.json`） | #576 | ✅ | **改**：新增 3 截图态（BOSS_BAR / STANCE_BREAK_FLASH / MINION_MODE） |
| 战斗数据源（`combat_entity.gd` / `enemy_ai.gd` / `combat_judge.gd`） | #575/#577 | ✅ | **零改动**——本设计只读消费 4 信号，零新信号源 |

---

## 2. 新组件 — 详细设计

> 本 issue 无独立新文件（与 #682「无新文件」先例一致）；「新组件」= hud.gd 内新增的 2 个节点/状态 + 1 个公有 API。

### 2.1 EnemyNameLabel（敌人名字 Label）

- **文件:** `shandong-wolf/gdscripts/hud.gd`（`_create_nodes` 内新增创建）
- **节点结构（纯代码，零 tscn 零贴图，与 `_make_hint_label` 同构）:**
```ascii
Hud (CanvasLayer)
└── EnemyNameLabel (Label)                # 新: 血条上方中央名字
    ├─ anchor_left/right = 0.5
    ├─ offset_left/right = ±HUD_ENEMY_NAME_WIDTH/2 (=±120)
    ├─ offset_top = HUD_ENEMY_NAME_TOP (候选 0..4，默认 2)   → 2..30
    └─ offset_bottom = offset_top + 28.0
```
- **主题覆写:** `font_size = HUD_ENEMY_NAME_FONT_SIZE`（候选 [14, 16, 18]，默认 16 = HUD_HINT_FONT_SIZE 同级）；`font_color = HUD_MOON_WHITE`；**无底框**（克制风格，名字悬浮于条上方——与提示 Label 的墨黑底框区分，避免「三条黑框」叠罗汉）
- **文本行为:** `text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS`（超长名省略，复用 `_make_hint_label` 能力）
- **显隐规则:** `visible = _boss_mode and _enemy_display_name != ""`（集中由 `_apply_enemy_visibility()` 维护）
- **公有成员:**
```gdscript
var EnemyNameLabel: Label               # tests 直接访问（与 EnemyHealthBar 同模式）
var _enemy_display_name: String = ""    # 当前名字（taste 文案，默认空）
```
- **关键方法:**
```gdscript
func set_enemy_display_name(name: String) -> void:
    ## 新 API（PRD §4.1-A）: 设置敌人名字；空串隐藏；boss 档可见、杂兵档隐藏
    _enemy_display_name = name
    EnemyNameLabel.text = name
    _apply_enemy_visibility()
```
- **集成说明:** 创建于 `_create_nodes()`（`EnemyHealthBar` 创建之后）；销毁/清理走既有 `_exit_tree`（节点随 Hud 释放，无独立订阅）。

### 2.2 _HudBar 崩解闪白状态机（set_break_flash）

- **文件:** `shandong-wolf/gdscripts/hud.gd`（内层类 `_HudBar` additive 扩展）
- **状态属性（additive，默认行为零变化——玩家两条与既有 set_segments 路径不受影响）:**
```gdscript
# hud.gd 内层类 _HudBar 新增:
var _break_flash: bool = false           # 闪白激活态（headless 可断言）
var _break_flash_alpha: float = 0.0      # 1.0→0.0 淡出（_draw 读）
var _flash_tween: Tween = null           # 复用 _kill_tween 模式（外层 Hud 的私有方法不可达，内层自持）
```
- **关键方法:**
```gdscript
func set_break_flash() -> void:
    ## 新（PRD §4.2-A 机械）: 崩解瞬间填充/描边转 HUD_STANCE_BREAK_FLASH_COLOR，
    ## Tween 将 _break_flash_alpha 1.0→0.0 淡出（HUD_STANCE_BREAK_FLASH_SECONDS），
    ## finished 后 _break_flash = false。零 _process（Tween 驱动，同 _show_execute_hint 模式）。
    _break_flash = true
    _break_flash_alpha = 1.0
    if _flash_tween != null and _flash_tween.is_valid():
        _flash_tween.kill()
    _flash_tween = create_tween()
    _flash_tween.tween_property(self, "_break_flash_alpha", 0.0, C.HUD_STANCE_BREAK_FLASH_SECONDS)
    _flash_tween.finished.connect(_finish_break_flash)
    queue_redraw()

func _finish_break_flash() -> void:
    _break_flash = false
    queue_redraw()

func is_break_flashing() -> bool:
    return _break_flash
```
- **_draw 变更（additive，两处分支）:**
```gdscript
# 描边颜色分支:
var border_color: Color = C.HUD_BLOOD_RED if _low_hp_mode else C.HUD_MOON_WHITE
if _break_flash:
    border_color = C.HUD_STANCE_BREAK_FLASH_COLOR.lerp(border_color, _break_flash_alpha)
# 活性段填充分支（_fill_override / 低血 / 月白 既有三选一之后）:
if _break_flash:
    fill_color = C.HUD_STANCE_BREAK_FLASH_COLOR.lerp(fill_color, _break_flash_alpha)
```
- **竞争语义（PRD §5.2-4）:** flash 期间 `set_segments` 到达 → `_draw` 重绘读状态变量，flash 覆盖填充色；Tween 结束后 `set_segments` 重绘接管——**无竞态**（状态与绘制解耦）。
- **中断语义（PRD §5.2-9）:** died/换目标打断 → `set_break_flash` 再次调用或 `_finish_break_flash` 早退均安全；如需强制清理，`_HudBar` 提供 `clear_break_flash()`（kill tween + 双状态复位，`_on_enemy_died` 非 final 分支调用）。
```gdscript
func clear_break_flash() -> void:
    if _flash_tween != null and _flash_tween.is_valid():
        _flash_tween.kill()
    _break_flash = false
    _break_flash_alpha = 0.0
    queue_redraw()
```

### 2.3 set_boss_mode 分档 API（Hud）

- **文件:** `shandong-wolf/gdscripts/hud.gd`（公有 API 新增）
- **状态属性:**
```gdscript
var _boss_mode: bool = false    # 新: 敌人呈现档位（true=名字+血条+架势条全显）
```
- **关键方法:**
```gdscript
func set_boss_mode(enabled: bool) -> void:
    ## 新 API（PRD §4.3-A）: 幂等设置敌人呈现档位；同值早退；
    ## 无目标实体时仅记录档位（set_target_enemy 注入时读取）。
    if enabled == _boss_mode:
        return
    _boss_mode = enabled
    _apply_enemy_visibility()

func _apply_enemy_visibility() -> void:
    ## 内部: 三态显隐唯一收敛点（#695 双条隐藏逻辑并入此处，签名零改动）
    if _target_enemy == null:
        EnemyNameLabel.visible = false
        EnemyHealthBar.visible = false
        EnemyStanceBar.visible = false
    elif _boss_mode:
        EnemyNameLabel.visible = _enemy_display_name != ""
        EnemyHealthBar.visible = true
        EnemyStanceBar.visible = true
    else:
        EnemyNameLabel.visible = false
        EnemyHealthBar.visible = false
        EnemyStanceBar.visible = true   # 杂兵档: 仅保留小架势条（现状位置）
```
- **`set_target_enemy` 增订（内部，签名不变）:** 有效实体分支末尾调用 `_apply_enemy_visibility()` 替代原两行 `visible = true`；null 分支改为调用 `_apply_enemy_visibility()`（原两行隐藏并入）。**注意:** 分段的 `set_segments` 初始化保留在显隐之前（先数据后显隐，保证杂兵档下小架势条也有初始值）。
- **`_on_enemy_died` 增订（内部）:** `final=true` → 隐藏名字（并入既有双条隐藏）；`final=false`（防御分支）→ 名字清空 + 双条清 0 + `EnemyStanceBar.clear_break_flash()`。

---

## 3. 既有组件修改

### 3.1 文件清单总表

| 类别 | 文件 | 变更性质 | 内容摘要 |
|------|------|:---:|------|
| 修改 | `shandong-wolf/gdscripts/hud.gd` | 修改（additive） | EnemyNameLabel 创建 + `set_enemy_display_name()`；`_HudBar.set_break_flash()` 闪白状态机；`set_boss_mode()` + `_apply_enemy_visibility()` 三态显隐；`_on_enemy_stance_broken` 增订闪白；`_on_enemy_died`/`set_target_enemy` 增订名字联动；debug API `set_debug_stance_break()` |
| 修改 | `shandong-wolf/gdscripts/constants.gd` | 修改（追加分区） | 「Boss 血条 UI」分区 5 项 `# DRAFT` 常量（§3.2-1 表） |
| 修改 | `shandong-wolf/tests/test_hud.gd` | 修改 | 名字 Label 布局/显隐断言、闪白状态机断言、分档三态显隐断言（§8 场景 A/B/C）；既有 T1-T28/B1-B5 零改动 |
| 修改 | `shandong-wolf/gdscripts/e2e_hud_capture.gd` | 修改 | enum 扩展 3 态（BOSS_BAR=4 / STANCE_BREAK_FLASH=5 / MINION_MODE=6）+ digit 键 4-6 + CYCLE_SEQUENCE 扩展 + `_drive_state` 分支 |
| 修改 | `shandong-wolf/e2e_shots.json` | 修改 | hud group 追加 3 shots（05_boss_bar / 06_stance_break_flash / 07_minion_mode） |
| 修改（可选） | `shandong-wolf/gdscripts/main_battle.gd` | 修改（+2 行） | `_build_hud` 内 `set_target_enemy` 后追加 `set_boss_mode(true)` + `set_enemy_display_name(...)` |
| 修改（可选） | `shandong-wolf/tests/test_main_assembly.gd` | 修改 | 装配断言：boss 档下 EnemyHealthBar/EnemyNameLabel 可见 |

### 3.2 各文件修改细节（implement agent 据此可写码）

#### 3.2-1 constants.gd（追加「Boss 血条 UI」分区，放 HUD 分区之后）

| 常量 | 默认 | 候选集 | 情感断言 / 依据 |
|------|:---:|------|------|
| `HUD_ENEMY_NAME_WIDTH` | 240.0 | [200, 240, 280] | = 血条宽（240）同宽，名字与条对齐；超长走 OVERRUN_TRIM_ELLIPSIS |
| `HUD_ENEMY_NAME_FONT_SIZE` | 16 | [14, 16, 18] | = HUD_HINT_FONT_SIZE 同级（克制）；只狼式读图名字可读但不抢戏 |
| `HUD_ENEMY_NAME_TOP` | 2.0 | [0.0, 2.0, 4.0] | 血条上方间距（血条 offset_top=12 → 名字 2..30）；0 = 贴条顶，4 = 更疏离 |
| `HUD_STANCE_BREAK_FLASH_SECONDS` | 0.18 | [0.12, 0.18, 0.25] | sekiro「崩解白闪」惩罚清晰 0.12-0.25s；0.12 偏瞬闪、0.25 偏强调——「崩解必须惩罚清晰，但不遮战斗」 |
| `HUD_STANCE_BREAK_FLASH_COLOR` | `HUD_MOON_WHITE` | [HUD_MOON_WHITE, HUD_BLOOD_RED.lightened(0.5)] | 只狼基准崩解白闪 = 月白（零新色相）；血红提亮候选为「血染白」变体，taste 裁决 |

> 全部 `# DRAFT` 只读：实现期选默认值，候选清单随 PR 提交，定稿归 #584/taste 通道。

#### 3.2-2 hud.gd（§2 已含伪代码，此处列改动点清单）

1. `_create_nodes()`：`EnemyHealthBar` 创建后追加 `EnemyNameLabel = _make_enemy_name_label()`（新私有方法，`_make_hint_label` 同构但无底框）。
2. 公有 API 新增：`set_enemy_display_name(name)` / `set_boss_mode(enabled)` / `set_debug_stance_break()`。
3. 内部新增：`_apply_enemy_visibility()` / `_make_enemy_name_label()`；`_boss_mode` / `_enemy_display_name` 状态。
4. `set_target_enemy`：有效/null 分支的显隐行替换为 `_apply_enemy_visibility()` 调用（分段初始化保留、顺序为先数据后显隐）。
5. `_on_enemy_stance_broken`：`EnemyStanceBar.set_break_flash()` 追加在 `_show_execute_hint()` 旁（正交，互不遮挡）。
6. `_on_enemy_died`：final → 隐藏名字并入；非 final → 名字清空 + `EnemyStanceBar.clear_break_flash()`。
7. `_HudBar`：`set_break_flash()` / `clear_break_flash()` / `is_break_flashing()` + `_break_flash` / `_break_flash_alpha` / `_flash_tween` 状态 + `_draw` 两处分支。

#### 3.2-3 main_battle.gd（`_build_hud` 末尾 +2 行，可选）

```gdscript
hud.bind_player(player_entity)
hud.set_target_enemy(enemy_entity)
hud.set_boss_mode(true)              # 新增: MVP 唯一敌人 = 精英 → Boss 档（名字+血条+架势条全显）
hud.set_enemy_display_name("…")      # 新增: taste 文案（# DRAFT 候选，进 PR 待用户定稿）
```

#### 3.2-4 e2e_hud_capture.gd

- enum 扩展：`NORMAL = 0, LOW_HP = 1, EXECUTE_HINT = 2, KILL_HINT = 3, BOSS_BAR = 4, STANCE_BREAK_FLASH = 5, MINION_MODE = 6`（既有 0-3 数值不动，向后兼容既有 shots）。
- `CYCLE_SEQUENCE` 扩展为 7 态（追加 3 新态）。
- `_unhandled_input` digit 键 4-6 → 新态。
- `_drive_state` 新分支：
  - `BOSS_BAR`：`set_target_enemy(_enemy)` + `set_boss_mode(true)` + `set_enemy_display_name("雪夜刀客")`（占位文案）+ `set_debug_hp(80,50,1)` + `set_debug_stance(40,100)`；
  - `STANCE_BREAK_FLASH`：先置 BOSS_BAR 同款，再 `hud.set_debug_stance_break()`（debug API 直接置 flash 态，绕开真实 Tween 时序——PRD §5.3-2）；
  - `MINION_MODE`：`set_target_enemy(_enemy)` + `set_boss_mode(false)` + `set_debug_stance(40,100)`。

#### 3.2-5 e2e_shots.json（hud group 追加 3 shots）

| shot | state | settle_frames | 说明 |
|------|:---:|:---:|------|
| `05_hud_boss_bar` | 4 (BOSS_BAR) | 10 | 名字+血条+架势条全显帧 |
| `06_hud_stance_break_flash` | 5 (STANCE_BREAK_FLASH) | 6 | debug 置位闪白帧（analyze_bmp 与 05 比色数/主题色） |
| `07_hud_minion_mode` | 6 (MINION_MODE) | 10 | 仅小架势条帧 |

---

## 4. 数据流

### 流程 1：Boss 档正常路径（MVP 唯一敌人 = 精英）

```
main_battle._build_hud
    ├─► hud.set_target_enemy(enemy_entity)          # 既有，零改动（分段初始化 + _apply_enemy_visibility）
    ├─► hud.set_boss_mode(true)                     # 新：_boss_mode=true → 名字+血条+架势条全显
    └─► hud.set_enemy_display_name("…")             # 新：taste 文案（# DRAFT）

CombatEntity 信号 ──► Hud
    hp_changed ──► EnemyHealthBar.set_segments        ✅ 既有（#695）
    stance_changed ──► EnemyStanceBar.set_segments    ✅ 既有（#695）
    stance_broken ──► EnemyStanceBar.set_break_flash() + _show_execute_hint()   ← 新增条级闪白
    died(final=true) ──► 名字隐藏 + 双条隐藏 + 击杀提示                            ← 名字联动新增
```

### 流程 2：杂兵档路径（未来 #589 后注入方传 false）

```
set_target_enemy(enemy) + set_boss_mode(false)
    ──► _apply_enemy_visibility()
         EnemyNameLabel.visible = false
         EnemyHealthBar.visible = false
         EnemyStanceBar.visible = true（维持顶部小条，现状位置）
    stance_broken ──► EnemyStanceBar.set_break_flash()（小条同样闪白，反馈一致性）
```

### 流程 3：目标清除 / 死亡路径

```
set_target_enemy(null) ──► _apply_enemy_visibility() → 名字+血条+架势条全隐（三态联动）
died(final=false)（防御）──► 名字清空 + 双条清 0 + clear_break_flash()（无残影）
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解 |
|---|---------|------|
| 1 | `set_target_enemy(null)` | `_apply_enemy_visibility()` 三态全隐（名字+血条+架势条），与 #695 双条隐藏逻辑合并收敛 |
| 2 | `died(final=true)` | 名字 + 双条隐藏 + 击杀提示；`final=false` 防御分支 → 名字清空 + 双条清 0 + `clear_break_flash()` |
| 3 | `stance_broken` 与处决文字同时触发 | 条级白闪与文字提示正交（白闪仅条内，互不遮挡） |
| 4 | 崩解后 `stance_changed(0, max)` 与 flash Tween 竞争 | `_draw` 读状态变量：flash 覆盖填充色，Tween 结束后 `set_segments` 重绘接管——无竞态 |
| 5 | 名字超长 | `OVERRUN_TRIM_ELLIPSIS` 省略（复用 `_make_hint_label` 能力） |
| 6 | 杂兵档下 `stance_broken` | 小架势条同样闪白（反馈一致性；是否降级仅文字留 taste 裁决） |
| 7 | 非有限值 hp/stance（NaN/Inf） | `get_segment_fractions` 既有防御返回 0.0；flash 状态不受影响 |
| 8 | 重复 `set_boss_mode(true)` | 幂等（同值早退）；`set_boss_mode` 在 `set_target_enemy` 之前调用 → 注入时读档位（`_apply_enemy_visibility` 以当前 `_boss_mode` 为准） |
| 9 | flash Tween 被 died 打断 | `clear_break_flash()` / `_kill_tween` 模式复用，不留残影 |
| 10 | 窗口缩放/低分辨率 | 锚点 0.5 + offsets 相对布局（既有设计），名字 Label 同锚点自适应 |
| 11 | `set_enemy_display_name("")` 空串 | 名字隐藏（boss 档下也隐藏，`_enemy_display_name != ""` 判定） |
| 12 | 换目标（`set_target_enemy` 新实体） | `_disconnect_enemy` 既有断开旧订阅；名字由新注入的 display_name 决定；未设置则隐藏 |

---

## 6. 集成点

> **Status 约定：** ⬜ = pending（资源已创建，未接线）；✅ = connected（implement agent 验证）。implement agent 必须在本表接线时更新；review agent 验证所有 ⬜ 已解决或明确推迟再合入。

| 集成 | 本组件 | 目标 Issue | 方式 | Status |
|-------------|:---:|:---:|-----|:---:|
| `CombatEntity.stance_broken` → 条级闪白 | `_HudBar.set_break_flash()`（EnemyStanceBar） | #580/#684 | 信号订阅（`_on_enemy_stance_broken` 增订，既有连接） | ⬜ pending |
| `CombatEntity.hp_changed` → 血条（既有） | `EnemyHealthBar` | #682 | 信号订阅（#695 已接线，零改动） | ✅ connected |
| `CombatEntity.died` → 名字联动隐藏 | `EnemyNameLabel` | #684 | `_on_enemy_died` 增订（final/非 final 分支） | ⬜ pending |
| 装配注入档位 | `main_battle.gd _build_hud` | #585/#684 | `set_boss_mode(true)` + `set_enemy_display_name(...)`（+2 行） | ⬜ pending |
| E2E 截图驱动 | `e2e_hud_capture.gd` + `e2e_shots.json` | #684 | 新 3 态（BOSS_BAR/STANCE_BREAK_FLASH/MINION_MODE）+ debug API `set_debug_stance_break()` | ⬜ pending |
| 杂兵档铺路 | `set_boss_mode(false)` 调用方 | #589/#590（backlog） | 注入方按实体声明档位（本设计只提供 API，不实现内容） | ⬜ deferred |

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:---:|:---:|-----------|:---:|
| Phase 1 | P0 | `constants.gd` 新增 5 项 `# DRAFT` 常量（§3.2-1） | 0.5 天 |
| Phase 2 | P0 | `hud.gd`：EnemyNameLabel + `set_enemy_display_name()` + `_make_enemy_name_label()` | 1 天 |
| Phase 3 | P0 | `hud.gd`：`_HudBar.set_break_flash()` 状态机 + `_on_enemy_stance_broken` 增订 + `set_debug_stance_break()` | 1 天 |
| Phase 4 | P0 | `hud.gd`：`set_boss_mode()` + `_apply_enemy_visibility()` 三态显隐重构（`set_target_enemy`/`_on_enemy_died` 增订） | 1 天 |
| Phase 5 | P1 | `main_battle.gd` +2 行装配（Boss 档）+ `test_main_assembly.gd` 可选断言 | 0.5 天 |
| Phase 6 | P1 | `test_hud.gd` 用例（§8 场景 A-F）+ `e2e_hud_capture.gd` 3 新态 + `e2e_shots.json` 3 shots | 1 天 |

> 依赖序：Phase 1 → 2/3/4 可并行（同文件需 sequential 实现，建议 2→3→4 顺序避免同文件冲突）→ 5 依赖 4 → 6 依赖 2/3/4。

---

## 8. 测试用例描述

> **只描述不写码**（plan 红线：可运行测试文件归 implement agent）。既有用例（test_hud T1-T28 + B1-B5）全部零改动保持全绿——本设计新增断言全部 additive。

### 场景 A：EnemyNameLabel 布局与显隐（AC1 补充「敌人名字」）

- **A1 布局锚点**：`_spawn_hud` 后断言 `EnemyNameLabel` 非空；`anchor_left/right == 0.5`；`offset_left == -HUD_ENEMY_NAME_WIDTH/2`（120）；`offset_top == HUD_ENEMY_NAME_TOP`（2）；`font_size` 覆写 == 16；无 StyleBoxFlat 底框（`get_theme_stylebox("normal") == null` 或等价断言）。
- **A2 boss 档显示**：`set_target_enemy(entity)` + `set_boss_mode(true)` + `set_enemy_display_name("雪夜刀客")` → `EnemyNameLabel.visible == true` 且 `text == "雪夜刀客"`。
- **A3 杂兵档隐藏**：`set_boss_mode(false)` 后同名字 → `EnemyNameLabel.visible == false`（血条同样隐藏、小架势条可见）。
- **A4 空串隐藏**：`set_enemy_display_name("")` → visible == false（boss 档下也隐藏）。
- **A5 超长名省略**：`set_enemy_display_name` 传入 50 字串 → `text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS`（不断言实际像素截断，只断言行为配置）。
- **A6 null 目标清名字**：`set_target_enemy(null)` → EnemyNameLabel.visible == false（三态全隐）。

### 场景 B：架势崩解闪白状态机（AC3）

- **B1 崩解触发闪白**：`set_target_enemy(entity)` + `set_boss_mode(true)` 后 `entity.stance_broken.emit(entity)` → `EnemyStanceBar.is_break_flashing() == true` 且 `ExecutePromptLabel.visible == true`（条级闪白与文字提示正交并存）。
- **B2 Tween 结束复位**：`EnemyStanceBar._flash_tween.custom_step(HUD_STANCE_BREAK_FLASH_SECONDS)`（0.18）→ `is_break_flashing() == false`、`_break_flash_alpha == 0.0`。
- **B3 闪白期间重绘接管**：flash 置位后 `set_segments([0.0],[1.0],0)` → `get_segment_fractions() == [0.0]`（数据路径不受 flash 影响，无竞态）。
- **B4 died 打断无残影**：flash 置位后 `died(final=true)` → `is_break_flashing() == false`（或 `clear_break_flash` 路径复位）。
- **B5 玩家条不受影响**：玩家 `stance_changed` 触发 → `PlayerStanceBar.is_break_flashing() == false`（闪白只作用于敌人架势条）。
- **B6 debug 置位**：`set_debug_stance_break()` → `EnemyStanceBar.is_break_flashing() == true`（E2E 驱动路径，绕开真实 Tween 时序）。

### 场景 C：Boss/杂兵分档三态显隐（issue 补充「分档」）

- **C1 先档后注入**：`set_boss_mode(false)` → `set_target_enemy(entity)` → `EnemyHealthBar.visible == false`、`EnemyNameLabel.visible == false`、`EnemyStanceBar.visible == true`（注入时读档位）。
- **C2 先注入后档**：`set_target_enemy(entity)` → `set_boss_mode(true)` → 三组件全部可见。
- **C3 反复切换**：true→false→true 循环 3 次 → 最终 true 全显；无异常无残留。
- **C4 幂等**：`set_boss_mode(true)` 连续两次 → 状态一致（同值早退，无双重 Tween/信号）。
- **C5 null 三态全隐**：`set_target_enemy(null)` → 名字 + 血条 + 架势条全部不可见。

### 场景 D：信号链路回归（AC2，既有 #695 用例全绿）

- **D1 hp_changed 实时更新**：既有 B3 保持全绿（`hp_changed` → EnemyHealthBar fractions 更新）。
- **D2 stance_changed 实时更新**：既有用例保持全绿（含架势「恢复」走同路径自动覆盖）。
- **D3 died final=true**：名字 + 双条隐藏 + 击杀提示（既有 T18-T20 扩展断言名字）。
- **D4 died final=false**：名字清空 + 双条清 0 + 无残影（既有 T20 扩展）。
- **D5 静态契约延续**：T25/T26 断言延续——零贴图资源引用 + 零帧轮询（新代码全部信号 + Tween 驱动）。

### 场景 E：E2E 截图态（e2e_hud_capture.gd + e2e_shots.json）

- **E1 BOSS_BAR 态**：state=4 → 截图帧含名字 + 血条 + 架势条（非纯黑、主题色断言）；settle_frames 10。
- **E2 STANCE_BREAK_FLASH 态**：state=5 → debug 置位闪白帧；analyze_bmp 断言与常态帧（01/05）色数或主题色差异（闪白帧月白占比上升）。
- **E3 MINION_MODE 态**：state=6 → 仅小架势条（无名字无血条）。
- **E4 auto_cycle 扩展**：CYCLE_SEQUENCE 7 态循环不越界（_cycle_index 取模正确）。

### 场景 F：装配集成（main_battle.gd 可选）

- **F1 Boss 档装配**：`test_main_assembly.gd` 断言 `_build_hud` 后 `hud` 的 `_boss_mode == true`、`EnemyHealthBar.visible == true`、`EnemyNameLabel.visible == true`（display_name 非空时）。
- **F2 既有装配回归**：既有装配断言零改动全绿（`set_target_enemy` 签名未变）。

---

## 9. 验收条件映射（issue body 4 条 + 补充范围）

| # | 验收条件 | 本设计保障 | 验证 |
|---|---------|-----------|------|
| AC1 | 顶部显示敌人血条 + 架势条（只狼式布局） | 布局已由 #695 交付；**补敌人名字 Label**（§2.1，issue 字面「敌人名字 + 大血条」） | 场景 A1/A2 + 既有 B1/B2 全绿 |
| AC2 | 血条随伤害减少、架势随积攒/恢复实时更新 | #695 已交付，零改动（信号驱动；架势恢复走 `stance_changed` 同路径自动覆盖） | 场景 D1/D2 回归 |
| AC3 | 架势崩解时条有视觉反馈（闪白/色变） | **EnemyStanceBar 崩解闪白**（§2.2，sekiro「崩解白闪」机械实现）；碎裂提示 B 留 `# DRAFT` 候选 | 场景 B1-B6（headless 状态机）+ E2（E2E 闪白帧） |
| AC4 | 风格与 #576 HUD 一致（程序化绘制、同一色板） | 新元素零贴图零 tscn（`_HudBar`/Label 程序化）；新常量全引既有 `HUD_*` 色板（`HUD_STANCE_BREAK_FLASH_COLOR` 默认 = `HUD_MOON_WHITE` 零新色相） | D5 静态断言 + 代码审查 |
| 补充 | 敌人名字显示 | boss 档 `EnemyNameLabel` 可见、杂兵档隐藏；文案 `# DRAFT` 候选进 PR | A2-A5 |
| 补充 | Boss/杂兵分档 | `set_boss_mode(true)` 全显 / `false` 仅小架势条 / null 全隐 | 场景 C1-C5 |
| 补充 | HP 百分比 | 纯条呈现（推荐采纳，零改动）；数字文本 `# DRAFT` 候选 | 回归 D1 |

---

## 10. 明确不修改（与 PRD §1.4/§8 红线对齐）

| 文件/系统 | 不修改内容 |
|-----------|-----------|
| `combat_entity.gd` / `enemy_ai.gd` / `combat_judge.gd` | 战斗数据源零改动（本设计纯消费端，零新信号源） |
| `hud.gd` 既有公有 API 签名 | `set_target_enemy(entity)` / `bind_player(entity)` / `set_debug_*` / `show_debug_hint` 保持原样（#682 红线延续） |
| `hud.gd` 玩家区块 | 玩家双段血条 / 玩家架势条 / 低血信号 / 提示文字显隐逻辑零改动 |
| `_HudBar` 默认行为 | `set_segments` / `get_segment_fractions` / `get_segment_shares` / `get_active_index` / `set_low_hp_mode` 语义零变化（闪白为 additive 状态） |
| `main_battle.gd` 战斗逻辑 | 只加 `_build_hud` 两行装配；AI/判定/移动零改动 |
| `project.godot` / `game-env/manifest.yaml` / `mini-pong/` / `.github/workflows/` / `scripts/` / `framework/` | 零改动 |
| `tests/` 既有用例 | test_hud T1-T28 / B1-B5 零改动全绿（新增断言全部 additive） |
| 可运行测试文件 | 本阶段不写任何测试代码（plan 红线，测试实现归 implement agent） |
| `# DRAFT` 数值 | 名字字号/上边距/闪白时长/颜色候选不裁决，候选集随 PR 提交，定稿归 #584/taste 通道 |
