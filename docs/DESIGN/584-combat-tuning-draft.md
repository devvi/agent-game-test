# Design: [Taste] 战斗数值 DRAFT 集中表（手感候补值 + 一次性调参面板）

> **Parent Issue:** #584
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4 推荐组合**全部确认采纳**——§4.1 方案 A（内联 const + 三行注释）/ §4.2 方案 A（纯 Control 程序化自研面板）/ §4.3 方案 A（override dict + 静态读值函数）/ §4.4 方案 A（`OS.is_debug_build()` 运行时判定）/ §4.5 方案 C（JSON dump + E2E 截图双证据）；方案 B/C 显式否决，理由同 PRD §4（破坏 #572 const 消费模式 / 外部不稳定依赖 / 语言层面不可行）
> **Reference PRD:** `docs/PRD/584-combat-tuning-draft.md`（research PR #601 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/572-scaffold-main-entry.md`（constants.gd 5 分区骨架 + `const C = preload(...)` 消费模式 + test_constants.gd 防误定稿守卫）；`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`（2026-08-19 用户拍板的数值权威基准）
> **所有权:** `content_ownership: taste-draft`（人机共做 v4：agent 生成带只狼 taste 方向的草稿，review 达标后草稿 PR merge——PR body 用 `Parent #584` 不写 Closes——assign 用户实机定稿；**红线：实现期禁止把 DRAFT 值「顺手定稿」**）
> **深度:** standard（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=13 标注 depth: standard；GitHub 无 depth 标签）—— 6 文件 / 3 子系统（数值、面板、测试）× 8+ 独立子任务 → **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统，参照 #572 先例）
> **红线:** 只动 `shandong-wolf/` 下 6 文件（3 新建 + 3 修改，见 §3）；**绝不触碰** `mini-pong/`、`shandong-wolf/scenes/Main.tscn`、`shandong-wolf/project.godot`（F1 走 `_unhandled_input` 物理键直判，不占 InputMap）、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`；零美术资产/零插件/零 UI 图片；**禁止实现期把 # DRAFT 候补值转为正式值**（taste-draft 红线，用户裁决前 test_constants.gd 断言强制）

---

## 1. 架构总览

**问题本质是「数值无出处、调参靠改码重启」。** #572 已交付 constants.gd 5 分区骨架 + 占位值，但占位值拍脑袋（最典型：架势回复 0.8/s 与只狼基准 20-35/s 差 25-43 倍）、无「只狼基准 → 本项目候选」双栏标注、无候选集、缺 6 个 issue 要求参数（受击扣架势/弹反扣架势/回复延迟/敌人前摇/处决距离/慢动作系数/回生绝对血量），且项目没有任何运行中调参手段（constants 是 `const`，改一个参数 = 改代码重编译重启目测）。本 issue 交付 = **constants.gd 全量 DRAFT 候选值表（14 参数，全部带只狼出处）+ DebugCanvas 一次性调参面板（F1 开关、仅 debug build、热更新 + 候选对比导出）**。

**设计哲学：出处长在代码里 + 热更新走 override 回落。** 数值是品味草稿（taste-draft），可审查性 > 运行时灵活性——所以候选集与只狼基准直接写成 constants.gd 的三行注释（PRD §4.1-A），消费方 `C.NAME` 照旧；调参是调试手段不是运行时特性——所以热更新走 `DebugCanvas.get_value(name, default)` 静态读值函数（debug 查 override dict，release 首行 `OS.is_debug_build()` 判定直接回落 const，零开销零分支污染），面板只是 override dict 的写入端。开源尽调（PRD §4.2，4 组 GitHub 关键词）结论：无成熟运行中调参插件 → 自研最小纯 Control 面板（约 250 行），PR 中附调研表。

```
                     ★ Issue #584 本设计（shandong-wolf 数值草稿 + 调参基础设施）
┌───────────────────────────────────────────────────────────────────────────────────┐
│ 新建（3 文件，全部 shandong-wolf/ 下）                                               │
│  gdscripts/debug_canvas.gd   DebugCanvas（CanvasLayer，纯 Control 程序化面板）        │
│    ├─ PARAMS 表驱动 14 行 HSlider/SpinBox（StyleBoxFlat 白底 80% 透明，零图片）        │
│    ├─ F1 物理键 toggle（_unhandled_input，仅 debug build）                            │
│    ├─ 静态 override dict + get_value(name, default) 读值函数（Tuning 链路）           │
│    └─ JSON dump 导出（user://tuning_dump_<ts>.json，AC4 证据）                        │
│  tests/test_debug_canvas.gd  面板守卫单测（回落/联动/越界/一致性自检）                 │
│  docs/TASTE.md               shandong-wolf 建档占位（候补值表三件套，用户定稿后回填）   │
├───────────────────────────────────────────────────────────────────────────────────┤
│ 修改（3 文件）                                                                        │
│  gdscripts/constants.gd      5 分区全量「只狼基准→候选」三行注释 + 新增受击/敌人/处决分区 │
│  gdscripts/game.gd           _ready 条件实例化 DebugCanvas（仅 debug build）           │
│  tests/run_tests.gd          挂载 test_debug_canvas.gd（第 3 套件）                    │
│  tests/test_constants.gd     扩展：14 参数存在性 + 三行注释格式 + 候选集断言            │
├───────────────────────────────────────────────────────────────────────────────────┤
│ 验证（0 改动）: scenes/Main.tscn 保持纯声明式；project.godot 零改动；e2e_shots.json 零改动 │
└───────────────────────────────────┬───────────────────────────────────────────────┘
                                    ▼
              godot --path shandong-wolf/（启动链）
                ├─ [autoload] Game 初始化 → _ready 内 debug 判定 → 条件 add_child DebugCanvas
                ├─ F1（debug）→ 面板 toggle；改值 → override dict → 消费方 get_value 实时读
                └─ headless 三入口: check_compile / smoke_test / run_tests 全绿（3 套件）
```

**与 PRD 方案裁决的一致性：** §4.1–§4.5 各推荐方案全部确认采纳，无分歧。两处**设计细化**（非分歧，实现口径收窄）：① PRD §4.3-A 的「Tuning.get_value（静态函数或 Game autoload 方法）」——定案为 **DebugCanvas 脚本静态函数**（不新增 tuning.gd，保持 PRD §3.1 文件清单最小化；面板与读值同源，参数表即一致性自检对象）；② PRD §4.4-A 的「面板节点由 Main 场景或 Game autoload 条件 add_child」——定案为 **Game autoload**（Main.tscn 是 #572 红线不可改，project.godot 是 PRD §3.3 明确零改动，Game 是唯一既有挂接点，见 §1.2 交叉对照）。PRD §7 三个 Spike（F1/debug 判定实测 / 纯 Control 布局 1280x720 / override 热更新链路）为 implement Phase 1/4 执行项，结论对本设计无结构性影响。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-19 侦查，plan agent 已逐条核实） | 与 #584 的差距 |
|------|--------------------------------------------------|---------------|
| `shandong-wolf/gdscripts/constants.gd` | ✅ WolfConstants（RefCounted）：机械常量区 + 5 个 # DRAFT 分区（弹反窗口/架势回复/两条命/刀伤害/帧节奏）15 个常量，占位值**无只狼出处标注、无候选集** | ❌ 全量三行注释改造 + 新增受击/敌人/处决分区 7 参数 |
| `shandong-wolf/gdscripts/game.gd` | ✅ Game autoload 最小锚点（版本号 + preload constants，3 行逻辑） | ❌ 无 DebugCanvas 实例化逻辑 |
| `shandong-wolf/tests/test_constants.gd` | ✅ E1 五分区存在性 / E2 # DRAFT 标记 ≥5 且无「# 定稿」/ E3 机械常量断言 | ❌ 扩展为 14 参数存在性 + 三行注释格式 + 候选集断言 |
| `shandong-wolf/tests/run_tests.gd` | ✅ 挂载 2 套件（StateMachine / Constants），_pass/_fail 汇总 | ❌ 追加 `_run(test_debug_canvas.gd)` 第 3 套件 |
| `shandong-wolf/gdscripts/state_machine.gd` | ✅ StateMachineBase 三接口基类（#572） | 无改动（#575 职责） |
| `shandong-wolf/project.godot` | ✅ [autoload] Game 已注册；无 InputMap 战斗动作 | **零改动**（PRD §3.3：F1 走 _unhandled_input，不占 InputMap） |
| `shandong-wolf/scenes/Main.tscn` | ✅ 纯声明式标题场景（#562/#563/#570） | **零改动**（#572/#584 双重红线） |
| `shandong-wolf/e2e_shots.json` | ⚠️ 占位（states 空，无战斗场景可截） | **零改动**；AC4 证据以 JSON dump + 面板截图为主（§4 Flow 3 范围界定） |
| `docs/TASTE.md` | ⚠️ 存在但无 shandong-wolf 建档 | ❌ 新建 shandong-wolf 章节占位（三件套：候补值表/试玩剧本/定稿差异记录） |

### 1.2 PRD 断言 vs 实际代码交叉对照

| PRD 断言 | 实际代码（核实结果） | 设计裁决 |
|---------|---------------------|---------|
| constants.gd 5 分区占位值无出处 | ✅ 属实（POSTURE_RECOVERY_PER_SEC=0.8 与只狼 20-35/s 差 25-43 倍；无候选集注释） | §2.3 全量三行注释改造 + §3.1 新增分区 |
| issue body 要求参数在 #572 骨架中不存在 | ✅ 属实（POSTURE_HIT_COST / PARRY_COST / POSTURE_RECOVERY_DELAY / ENEMY_ATTACK_WINDUP / EXECUTE_RANGE / SLOWMO_COEFF / LIFE_2_ABS 均无） | §3.1 新增「受击/敌人/处决」分区 7 常量 |
| F1 用 `_unhandled_input` 物理键检测，不占 InputMap | ✅ project.godot 无 InputMap 战斗动作，F1 未被占用 | §2.1 `event.keycode == KEY_F1` 直判；未来冲突 → 集中改名点 InputMap 动作 |
| 面板节点由 Main 场景或 Game autoload 条件 add_child | ⚠️ Main.tscn 是 #572 红线**不可改**；project.godot PRD §3.3 明确零改动 | **挂 Game autoload**：game.gd `_ready()` 内 `if DebugCanvas.is_available(): add_child(...)`（+4 行，§3.1）——**PRD §3.1 文件清单扩展项**，PR 中说明 |
| PRD §4.3-A「Tuning.get_value（静态函数或 Game autoload 方法）」 | — | **静态函数挂 DebugCanvas**（class_name DebugCanvas），不新增 tuning.gd；PRD 中「Tuning」= 本设计 `DebugCanvas.get_value()` 静态入口（§2.2） |
| 消费方从 `C.NAME` 改为读值函数 | 现有消费方仅 Game（preload 版本号）；#575/#577 尚未实现 | 迁移是**约定**：§2.2 给最小迁移示例；#572 的 `C.NAME` 直读**不破坏**（默认值语义等价），仅新消费方建议走 get_value |
| test_constants.gd 现有断言可扩展 | ✅ 属实（get_script_constant_map + FileAccess 文本扫描模式已建立） | §3.2 扩展 E 场景（§8 Scenario A） |
| e2e 截图管线可复用 | ✅ 管线存在（#559 打通）但 e2e_shots.json states 为空（无战斗场景） | 本 issue **不改 e2e_shots.json**；AC4 证据 = JSON dump（必交）+ 面板截图（E2E 扩展或手动）+ 手感描述；战斗内效果截图顺延 #575/#577（PRD §5.3-4 / §8 风险） |

---

## 2. 新组件 — 详细设计

### 2.1 `shandong-wolf/gdscripts/debug_canvas.gd`（新建，调参面板）

- **文件:** `shandong-wolf/gdscripts/debug_canvas.gd`
- **类:** `class_name DebugCanvas`，`extends CanvasLayer`（layer=100，面板独立于游戏渲染层；CanvasLayer 是 Node，可挂 `_unhandled_input`）
- **节点结构（纯代码 `_build_ui()` 程序化构建，零 .tscn 零图片资产）:**

```
DebugCanvas (CanvasLayer, layer=100, visible=false, script=debug_canvas.gd)
└── PanelContainer (StyleBoxFlat: 白底 80% 透明度, 圆角 4px; offset 左上 (12,12))
    └── VBoxContainer (custom_minimum_size 440×0)
        ├── Label "战斗数值调参 #584 (DRAFT)"  (字号 16，写字板风格 SystemFont 候选)
        ├── ScrollContainer (custom_minimum_size 440×400)
        │   └── VBoxContainer (14 行参数行，行高 28px，全高 ≈ 14×28+标题+工具行 ≈ 460px ≤ 720 ✓)
        │       └── 参数行 i (HBoxContainer)
        │           ├── Label 参数名+候选集 (宽 170，右对齐，如 "弹反窗口 [8,10,12,14]")
        │           ├── HSlider (h_size_flags=expand, min/max/step 来自 PARAMS[i])
        │           └── SpinBox (宽 70，显示/输入当前值)
        └── HBoxContainer (底部工具行)
            ├── Button "导出 JSON"   → _export_dump()
            ├── Button "重置默认"    → _overrides.clear() + 全行回默认
            └── Button "隐藏 (F1)"   → visible = false
```

- **PARAMS 参数表（面板唯一数据源，14 行，驱动 UI 生成 + 一致性自检）:**

```gdscript
const PARAMS: Array[Dictionary] = [
    {"name": "PARRY_WINDOW_FRAMES",      "label": "弹反窗口(帧)",  "min": 4,  "max": 30, "step": 1,   "candidates": [8, 10, 12, 14],   "default": 12},
    {"name": "POSTURE_RECOVERY_PER_SEC", "label": "架势回复/s",   "min": 5,  "max": 50, "step": 1,   "candidates": [20, 25, 30, 35],  "default": 25},
    {"name": "POSTURE_RECOVERY_DELAY",   "label": "回复延迟(s)",  "min": 0.5,"max": 3.0,"step": 0.1, "candidates": [1.0, 1.5, 2.0],    "default": 1.5},
    {"name": "POSTURE_BLOCK_COST",       "label": "格挡扣架势",   "min": 1,  "max": 30, "step": 1,   "candidates": [8, 10, 12],       "default": 10},
    {"name": "PARRY_COST",               "label": "弹反扣架势",   "min": 0,  "max": 5,  "step": 1,   "candidates": [0, 1, 2],         "default": 1},
    {"name": "POSTURE_HIT_COST",         "label": "受击扣架势",   "min": 5,  "max": 60, "step": 1,   "candidates": [30, 35, 40],      "default": 35},
    {"name": "POSTURE_BREAK_THRESHOLD",  "label": "架势上限",     "min": 50, "max": 200,"step": 5,   "candidates": [],                "default": 100, "derived": true},
    {"name": "LIFE_1_MAX",               "label": "第一条命HP",   "min": 50, "max": 200,"step": 5,   "candidates": [100, 120],        "default": 100},
    {"name": "LIFE_2_ABS",               "label": "回生后HP",     "min": 20, "max": 100,"step": 5,   "candidates": [40, 50, 60],      "default": 50},
    {"name": "SWORD_DAMAGE_LIGHT",       "label": "轻击架势伤",   "min": 1,  "max": 30, "step": 1,   "candidates": [10, 12, 15],      "default": 12},
    {"name": "SWORD_DAMAGE_HEAVY",       "label": "重击架势伤",   "min": 10, "max": 80, "step": 1,   "candidates": [25, 30, 40],      "default": 30},
    {"name": "ENEMY_ATTACK_WINDUP",      "label": "敌前摇(帧)",   "min": 4,  "max": 30, "step": 1,   "candidates": [12, 15, 18],      "default": 15},
    {"name": "EXECUTE_RANGE",            "label": "处决距离(m)",  "min": 0.5,"max": 3.0,"step": 0.1, "candidates": [1.0, 1.2, 1.5],    "default": 1.2},
    {"name": "SLOWMO_COEFF",             "label": "慢动作系数",   "min": 0.1,"max": 0.5,"step": 0.05, "candidates": [0.1, 0.2, 0.3],   "default": 0.2},
]
```

- **静态成员（Tuning 读值链路，消费方入口）:**

```gdscript
static var _overrides: Dictionary = {}   # 参数名 → 当前 override 值（面板写入，进程内有效）

## 读值入口（PRD §4.3-A「Tuning」）：debug + override 存在 → 返回 override；否则回落默认。
## 消费方示例: var window := DebugCanvas.get_value("PARRY_WINDOW_FRAMES", C.PARRY_WINDOW_FRAMES)
static func get_value(param_name: String, default_value: Variant) -> Variant:
    if not OS.is_debug_build():
        return default_value                    # release 零开销回落（首行判定，无 dict 查询）
    if _overrides.has(param_name):
        return _overrides[param_name]
    return default_value                        # debug 但面板从未打开 → 回落 const

## 纯函数裁决（可测缝隙，test_debug_canvas.gd 直接喂 dict 断言）
static func _resolve_value(param_name: String, default_value: Variant, overrides: Dictionary) -> Variant:
    if overrides.has(param_name):
        return overrides[param_name]
    return default_value

static func is_available() -> bool:
    return OS.is_debug_build()                  # Game autoload 实例化判定点（单一决策点）
```

- **关键方法（实例）:**

```gdscript
func _ready() -> void:
    if not OS.is_debug_build():
        queue_free()                            # 双保险：即使被误实例化也自毁（AC3）
        return
    _build_ui()                                 # 程序化构建 14 行参数行 + 工具行

func _unhandled_input(event: InputEvent) -> void:
    if not OS.is_debug_build():
        return
    var key := event as InputEventKey
    if key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
        visible = not visible                   # F1 toggle；面板打开不暂停游戏（实时手感）

func _on_param_changed(param: Dictionary, value: float) -> void:
    # 硬 range 约束（PRD §5.2-2）：越界值拒绝写入（SpinBox 已限制，此处双保险）
    if value < param.min or value > param.max:
        return
    _overrides[param.name] = value
    _apply_derived_rules(param.name, value)     # 联动规则（§2.1 下方）

func _apply_derived_rules(changed: String, value: float) -> void:
    # 只狼铁律：架势上限 = 当前 HP 上限 → 双向联动（PRD §5.2-7）
    if changed == "LIFE_1_MAX":
        _overrides["POSTURE_BREAK_THRESHOLD"] = value
        _sync_row("POSTURE_BREAK_THRESHOLD", value)   # 面板行同步显示
    elif changed == "POSTURE_BREAK_THRESHOLD":
        _overrides["LIFE_1_MAX"] = value
        _sync_row("LIFE_1_MAX", value)
    # LIFE_2_MAX_RATIO（#572 既有 const）派生展示：ratio = LIFE_2_ABS / LIFE_1_MAX（消费方经 get_value 读时派生，见 §2.2）

func _export_dump() -> void:
    var data := {
        "meta": {"game_version": WolfConstants.GAME_VERSION, "ts": Time.get_datetime_string_from_system(), "group": "manual"},
        "params": _overrides.duplicate(),       # 14 参数当前生效值（含联动后的派生值）
    }
    var path := "user://tuning_dump_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
    FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(data, "\t"))
    # 覆盖写：dump 只落盘不自动加载（PRD §5.2-6：MVP 不做持久化加载）
```

- **集成说明:** check_compile 自动纳入（gdscripts/ 扫描）；Game autoload `_ready()` 条件实例化（§3.1）；消费方 #575/#577 一行接入 `DebugCanvas.get_value("NAME", C.NAME)`；E2E 截图前强制 `visible=false` 保证确定性（§5 边界 4）。

### 2.2 Tuning 读值链路（消费方迁移约定）

PRD §4.3-A 的「Tuning」在本设计落为 **DebugCanvas 静态读值函数**。消费方迁移约定（最小示例，PRD §8 要求的防理解偏差样板）：

```gdscript
# 旧（#572 模式，仍然有效）:  const C = preload("res://gdscripts/constants.gd"); C.PARRY_WINDOW_FRAMES
# 新（#575/#577 推荐）:
const C = preload("res://gdscripts/constants.gd")
const DebugCanvas = preload("res://gdscripts/debug_canvas.gd")
# 读值（debug 热更新优先，release 回落 const 默认）:
var parry_window: int = DebugCanvas.get_value("PARRY_WINDOW_FRAMES", C.PARRY_WINDOW_FRAMES)
```

**派生参数消费规则（消费方无需感知联动，读值函数统一裁决）：**

| 消费参数名 | 裁决规则 | 说明 |
|-----------|---------|------|
| `POSTURE_BREAK_THRESHOLD` | override 有该键 → 返回；否则 override 有 `LIFE_1_MAX` → 返回；否则 `C.POSTURE_BREAK_THRESHOLD` | 只狼铁律：架势上限 = 当前 HP 上限（面板双向联动保证两键同值） |
| `LIFE_2_MAX_RATIO` | override 有 `LIFE_2_ABS` → 返回 `LIFE_2_ABS / LIFE_1_MAX有效值`；否则 `C.LIFE_2_MAX_RATIO` | #572 既有 ratio 语义兼容：面板只调绝对血量 LIFE_2_ABS，ratio 派生 |

**实现提示:** `get_value` 读值**禁止缓存**（每次实时查 dict）——消费方每帧/每次判定读，面板改值下一帧即生效（PRD §7 实验 3 契约）。release 路径首行 `OS.is_debug_build()` 判定返回 default，无 dict 查询无分支污染（PRD §4.3-A 要求）。

### 2.3 constants.gd 全量 DRAFT 值表（§3.1 改造的完整规格）

> 以下为 implement 期 constants.gd 的**完整 DRAFT 值规格**（PRD §8 步骤 1 要求「DESIGN 须明确全量值表」）。每个参数 = 三行注释（只狼基准 / 候选集 / 偏离理由）+ `# # DRAFT` 标记。**任何值改动 = 偏离本表，须在 PR 说明理由。**

**分区一：弹反窗口**

```gdscript
# ── 弹反窗口（# DRAFT 候补值，待 #584 用户定稿）──
# PARRY_WINDOW_FRAMES
#   只狼基准: ~12 帧（0.2s @60fps，偏宽松=容错手感来源）
#   候选集: [8, 10, 12, 14]（默认 12 = 只狼基准；8/14 为容错两极备选）
#   偏离理由: 无——只狼基准直接采纳
const PARRY_WINDOW_FRAMES: int = 12            # # DRAFT
const PARRY_WINDOW_SECONDS: float = 0.2        # # DRAFT（派生展示 = FRAME_RHYTHM_BASE 换算，不重复定义来源）
```

**分区二：架势回复（改造——占位 0.8/s 与只狼基准差 25-43 倍，全量重写）**

```gdscript
# ── 架势回复（# DRAFT 候补值，待 #584 用户定稿）──
# POSTURE_RECOVERY_PER_SEC
#   只狼基准: 20-35/s（脱战/停防 1.5s 延迟后快速回复；回复太快=无脑弹反，太慢=龟缩——节奏阀）
#   候选集: [20, 25, 30, 35]（默认 25 = 区间中位；宽容 35 / 严苛 20）
#   偏离理由: 无——只狼基准区间直接采纳
const POSTURE_RECOVERY_PER_SEC: float = 25.0   # # DRAFT
# POSTURE_RECOVERY_DELAY
#   只狼基准: 脱战 1.5s 延迟后开始回复（原地喘息=只狼的停防）
#   候选集: [1.0, 1.5, 2.0]（默认 1.5 = 只狼基准）
#   偏离理由: 无
const POSTURE_RECOVERY_DELAY: float = 1.5      # # DRAFT
# POSTURE_BLOCK_COST
#   只狼基准: 中（8-12/次，长按格挡的代价）
#   候选集: [8, 10, 12]（默认 10 = 区间中位）
#   偏离理由: 无
const POSTURE_BLOCK_COST: float = 10.0         # # DRAFT
# POSTURE_BREAK_THRESHOLD
#   只狼基准: = 当前 HP 上限（满则架势崩解 → 可处决；血越多越扛架势——只狼铁律）
#   候选集: 派生——恒等于 LIFE_1_MAX（面板双向联动，无独立候选）
#   偏离理由: 无（联动规则见 DESIGN §2.1 _apply_derived_rules）
const POSTURE_BREAK_THRESHOLD: float = 100.0   # # DRAFT
```

**分区三：两条命数值（改造——新增 LIFE_2_ABS 绝对血量，ratio 保留派生语义）**

```gdscript
# ── 两条命数值（# DRAFT 候补值，待 #584 用户定稿）──
# LIFE_TOTAL
#   只狼基准: 回生机制（HP 归零 → 消耗回生机会原地复活；第 2 条 = 最后一搏）
#   候选集: [2]（两条命结构，机械语义，骨架期定稿）
#   偏离理由: 无
const LIFE_TOTAL: int = 2                      # # DRAFT
# LIFE_1_MAX
#   只狼基准: 100%（20 格）——第一条命是容错，允许失误
#   候选集: [100, 120]（基准 100；120 为高容错实验候选，面板 range 50-200 开放）
#   偏离理由: 无（只狼基准 100 直接采纳）
const LIFE_1_MAX: float = 100.0                # # DRAFT
# LIFE_2_ABS
#   只狼基准: 回生后约半血（40-60 绝对血量 = 命悬一线）
#   候选集: [40, 50, 60]（默认 50 = 半血基准）
#   偏离理由: 无（绝对血量替代 ratio 作为面板参数；LIFE_2_MAX_RATIO 保留为派生展示）
const LIFE_2_ABS: float = 50.0                 # # DRAFT
const LIFE_2_MAX_RATIO: float = 0.5            # # DRAFT（派生展示 = LIFE_2_ABS / LIFE_1_MAX，消费方经 get_value 读派生值）
```

**分区四：刀伤害（改造——候选集补齐）**

```gdscript
# ── 刀伤害（# DRAFT 候补值，待 #584 用户定稿）──
# SWORD_DAMAGE_LIGHT
#   只狼基准: 轻击连段 10-15 架势伤害（处决导向，架势伤害为主）
#   候选集: [10, 12, 15]（默认 12 = 区间中位）
#   偏离理由: 无
const SWORD_DAMAGE_LIGHT: float = 12.0         # # DRAFT
# SWORD_DAMAGE_HEAVY
#   只狼基准: 重击 25-40 架势伤害
#   候选集: [25, 30, 40]（默认 30 = 区间中位）
#   偏离理由: 无
const SWORD_DAMAGE_HEAVY: float = 30.0         # # DRAFT
# SWORD_DAMAGE_EXECUTE
#   只狼基准: 忍杀 = 一击必杀（架势崩解或 HP 归零后处决，无视架势）
#   候选集: [999.0]（机械语义：处决 = 无视架势终结，骨架期可定稿）
#   偏离理由: 无（数值本身无手感意义，语义即值）
const SWORD_DAMAGE_EXECUTE: float = 999.0      # # DRAFT
```

**分区五：帧节奏（改造——玩家侧保留，敌人前摇新增独立参数）**

```gdscript
# ── 帧节奏（# DRAFT 候补值，待 #584 用户定稿）──
# FRAME_ATTACK_WINDUP
#   只狼基准: 玩家攻击前摇可读、收招滞（轻击连段节奏）
#   候选集: [6, 8, 10]（默认 8 = #572 占位延续，玩家侧手感）
#   偏离理由: 无（玩家侧前摇偏短=操作响应优先）
const FRAME_ATTACK_WINDUP: int = 8             # # DRAFT
# FRAME_ATTACK_RECOVERY
#   只狼基准: 攻击后摇可惩罚（后摇长 = 进攻有风险）
#   候选集: [12, 14, 16]（默认 14 = #572 占位延续）
#   偏离理由: 无
const FRAME_ATTACK_RECOVERY: int = 14          # # DRAFT
const FRAME_RHYTHM_BASE: int = 60              # # DRAFT（基准帧率参考，机械常量语义）
```

**分区六：受击/敌人/处决（新增分区，issue body 要求参数）**

```gdscript
# ── 受击/敌人/处决（# DRAFT 候补值，待 #584 用户定稿，本分区为 #584 新增）──
# POSTURE_HIT_COST
#   只狼基准: 受击扣架势大（30-40/次）——血+架势双重惩罚，纯防御会崩架势，逼玩家进攻（只狼核心哲学）
#   候选集: [30, 35, 40]（默认 35 = 区间中位；宽容 30 / 严苛 40）
#   偏离理由: 无
const POSTURE_HIT_COST: float = 35.0           # # DRAFT
# PARRY_COST
#   只狼基准: 弹反成功扣 0（精准格挡的奖励——成功不扣血不扣架势）
#   候选集: [0, 1, 2]（默认 1 = 轻微消耗）
#   偏离理由: 只狼为 0；本项目保留 0-2 微调通道——默认 1 防「无脑弹反」惩罚余地，用户实机裁决 0/1/2
const PARRY_COST: float = 1.0                  # # DRAFT
# ENEMY_ATTACK_WINDUP
#   只狼基准: 危攻击前摇 14-18 帧（刺刀突刺=可识破的危攻击）；普通攻击前摇可读
#   候选集: [12, 15, 18]（默认 15 = 区间中位；12 = 快刀精英备选）
#   偏离理由: 无（issue body 指定 12-18 帧，与只狼 14-18 基本重合，取宽 12 下限）
const ENEMY_ATTACK_WINDUP: int = 15            # # DRAFT
# EXECUTE_RANGE
#   只狼基准: 忍杀触发 = 近身（架势崩解后玩家靠近即可处决）
#   候选集: [1.0, 1.2, 1.5]（默认 1.2 = issue body 指定）
#   偏离理由: 无
const EXECUTE_RANGE: float = 1.2               # # DRAFT
# SLOWMO_COEFF
#   只狼基准: 处决演出 = hit-stop + 特写慢动作（情绪峰值制造）
#   候选集: [0.1, 0.2, 0.3]（默认 0.2；0.1 = 最戏剧化，0.3 = 轻量演出）
#   偏离理由: 无（消费方 #577 处决演出在 Engine.time_scale 应用，clamp 下限 0.1 防冻结）
const SLOWMO_COEFF: float = 0.2                # # DRAFT
```

---

## 3. 既有组件修改

### 3.1 修改文件

| 文件 | 变更 | 性质 | 伪代码 |
|------|------|------|--------|
| `shandong-wolf/gdscripts/constants.gd` | 5 分区全量三行注释改造（只狼基准/候选集/偏离理由）+ 新增「受击/敌人/处决」分区 7 常量 + LIFE_2_ABS | 行为不变（const 值可被消费方继续直读）；注释/常量集变更 | §2.3 完整值表直接落地；**所有 DRAFT 值必须保持 `# # DRAFT` 标记** |
| `shandong-wolf/gdscripts/game.gd` | `_ready()` 条件实例化 DebugCanvas（PRD §3.1 清单扩展项，§1.2 已说明） | 行为新增（debug 下挂面板节点） | `const DebugCanvasScript = preload("res://gdscripts/debug_canvas.gd")` + `func _ready() -> void: if DebugCanvasScript.is_available(): add_child(DebugCanvasScript.new())` |
| `shandong-wolf/tests/run_tests.gd` | `_run_tests()` 追加第 3 套件挂载 | 行为变更（2 → 3 套件） | `_run("res://tests/test_debug_canvas.gd", "DebugCanvas")` |
| `shandong-wolf/tests/test_constants.gd` | E 场景扩展：14 参数存在性 + 三行注释格式 + 候选集断言 + 新增分区断言 | 断言增强（不破坏既有 E1-E3） | §8 Scenario A |

### 3.2 新文件清单

| 文件 | 说明 |
|------|------|
| `shandong-wolf/gdscripts/debug_canvas.gd` | DebugCanvas 调参面板（§2.1） |
| `shandong-wolf/tests/test_debug_canvas.gd` | 面板守卫单测（§8 Scenario B-D） |
| `docs/TASTE.md`（shandong-wolf 建档） | 候补值表三件套占位：§3.2 下方格式；用户定稿后回填差异记录（mini-pong #367 模式参考） |

> **TASTE.md 建档格式（三件套，mini-pong #367 先例）：** `## shandong-wolf` 章节下三小节：① 候补值表（14 参数 × 只狼基准/候选/当前草稿值，链接 constants.gd）；② 试玩剧本（3 组对比：基准/宽容/严苛的操作步骤 + 关注点：弹反容错/架势节奏/紧张感）；③ 定稿差异记录（用户裁决后：候选 → 定稿值 + 理由 + 日期）。

### 3.3 不修改（显式声明，防越界）

| 文件 | 原因 |
|------|------|
| `shandong-wolf/scenes/Main.tscn` | #572/#584 双重红线（面板挂 Game autoload，不需要场景改动） |
| `shandong-wolf/project.godot` | PRD §3.3 明确零改动（F1 走 `_unhandled_input` 不占 InputMap；不加 autoload） |
| `shandong-wolf/e2e_shots.json` | 占位空 states（无战斗场景）；AC4 证据以 JSON dump + 面板截图为主，截图管线**约定**面板隐藏态（§5 边界 4） |
| `shandong-wolf/gdscripts/state_machine.gd` | #575 职责，本 issue 不碰 |
| `mini-pong/` 全部 | 跨游戏红线 |
| `game-env/manifest.yaml` / `.github/workflows/` / `scripts/` | 管线配置非本 issue 职责（已参数化自动跟随） |
| `docs/GAME_DESIGN/` | GDD 补记是 post-merge agent 职责 |

---

## 4. 数据流

### Flow 1: F1 面板热更新（正常路径）
```
debug build 启动 → Game._ready() → DebugCanvas.is_available()==true → add_child(DebugCanvas)
用户按 F1 → _unhandled_input 捕获 KEY_F1 → visible = true（面板显示，游戏不暂停）
用户拖 HSlider（如弹反窗口 12 → 8）→ _on_param_changed → _overrides["PARRY_WINDOW_FRAMES"]=8
    └─ 联动: 若改的是 LIFE_1_MAX → POSTURE_BREAK_THRESHOLD 同步写入 + 面板行同步
消费方（#575/#577 判定）: DebugCanvas.get_value("PARRY_WINDOW_FRAMES", C.PARRY_WINDOW_FRAMES)
    └─ debug: _overrides 命中 → 返回 8（下一帧即生效，读值无缓存）
用户再按 F1 → visible = false（隐藏，override 保留进程内生效）
```

### Flow 2: 候选对比证据（AC4，正常路径）
```
面板「导出 JSON」→ user://tuning_dump_<ts>.json（meta + 14 参数当前值）
3 组对比: 基准组（全默认）→ 宽容组（弹反14/回复35/受击30）→ 严苛组（弹反8/回复20/受击40）
每组: 改值 → 导出 JSON → 面板截图（或 E2E 扩展）→ 手感描述（弹反容错/架势节奏/紧张感）
PR 附件: 3 份 JSON dump + 截图 + 对比表（PRD §4.5 方案 C 产物）
战斗场景未就绪（e2e_shots.json 空）→ 截图以面板画面为证，战斗内效果顺延 #575/#577（PRD §5.3-4）
```

### Flow 3: release 回落（fallback 路径）
```
release 导出模板 → Game._ready() → DebugCanvas.is_available()==false → 不实例化（无节点无 F1 响应）
消费方 get_value → 首行 OS.is_debug_build()==false → 直接返回 default（const 值）
    └─ 零 dict 查询、零 override 分支（PRD §4.3-A「release 零开销」契约）
即使 debug_canvas.gd 被误引用 → _ready 内 queue_free() 双保险（AC3）
```

### Flow 4: 参数越界 / 联动（edge-case 路径）
```
SpinBox 输入越界值（如弹反 100）→ _on_param_changed range 校验拒绝 → override 不写入（PRD §5.2-2）
SLOWMO_COEFF 输入 0 → clamp 下限 0.1（PRD §5.2-5：time_scale=0 冻结游戏含面板输入）
改 LIFE_1_MAX=150 → POSTURE_BREAK_THRESHOLD 联动=150（只狼铁律）→ 消费方 get_value 读派生值
```

---

## 5. 边界情况与错误处理

| Edge Case | Mitigation |
|-----------|------------|
| 1. F1 与未来战斗按键冲突（PRD §5.2-1） | F1 不在 InputMap 登记，`_unhandled_input` 物理键直判；若未来战斗用 F1 → 改 InputMap 动作 `toggle_debug_canvas`（集中改名点，本设计预留注释） |
| 2. 参数越界（PRD §5.2-2） | SpinBox/HSlider 硬 range 约束 + `_on_param_changed` 双保险校验；越界值拒绝写入 override（测试 D2） |
| 3. 面板打开时游戏状态（PRD §5.2-3） | 面板不暂停游戏（实时手感）；处决演出/慢动作期间改 SLOWMO_COEFF → override 写入但**不立即改 Engine.time_scale**（消费方 #577 下次演出读值时生效，避免时间轴错乱） |
| 4. E2E 截图时面板遮挡（PRD §5.2-4） | 截图确定性约定：E2E 截图前强制 `DebugCanvas.visible=false`（面板可见性由 F1 状态决定，截图脚本前置隐藏）；面板专属截图 state 单独开 |
| 5. 慢动作系数 = 0（PRD §5.2-5） | `Engine.time_scale=0` 冻结游戏（含面板输入）→ SLOWMO_COEFF clamp 下限 0.1（测试 D3） |
| 6. override 残留（PRD §5.2-6） | MVP 不做持久化：dump 只落盘不自动加载；「重置默认」按钮清空 `_overrides`；如需持久化 → v2「加载上次 dump」按钮（显式，本期不做） |
| 7. 两条命联动（PRD §5.2-7） | 只狼铁律：架势上限 = 当前 HP 上限 → 面板双向联动（LIFE_1_MAX ↔ POSTURE_BREAK_THRESHOLD）+ 读值函数派生裁决（§2.2 表） |
| 8. `OS.is_debug_build()` 误判（PRD §5.3-1） | 单一决策点 `is_available()`；test 断言当前环境返回 true；源码级断言含判定；E2E 前置强制隐藏兜底 |
| 9. override 参数名拼写错误（PRD §5.3-2） | 读值函数静默回落 default（不崩溃）；test_debug_canvas.gd C1 断言 PARAMS 14 个 name 与 constants const 名一致（启动自检） |
| 10. 面板 UI 超出 1280x720（PRD §5.3-3） | VBoxContainer + ScrollContainer（440×400 内滚动）；行高 28px 紧凑，全高 ≈ 460px ≤ 720 |
| 11. #575/#577 未实现导致无战斗画面可截（PRD §5.3-4） | AC4 证据范围收窄：JSON dump（必交）+ 面板截图 + 手感文字描述；战斗内效果截图顺延，不搭战斗 demo（PRD §8 风险红线） |
| 12. 消费方仍用旧 `C.NAME` 直读 | 兼容：默认值语义等价（get_value 回落即 const）；#572 消费方零破坏；新消费方建议走 get_value（§2.2 迁移约定） |
| 13. 实现期「顺手定稿」DRAFT 值 | 红线 + test_constants.gd A4 断言（# DRAFT 标记 ≥14 + 无「# 定稿」字样）——taste-draft v4 流程保障 |
| 14. run_tests 挂载遗漏静默绿 | run_tests 既有防静默绿：pass==0 → 退出非 0；新增第 3 套件挂载后 F3 断言计数 ≥ 3 套件 |

---

## 6. 集成点

> **Status 约定:** ⬜ = 待 implement 接线；✅ = implement 已连接。implement agent 必须更新本表。

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| 面板实例化 | DebugCanvas | 本 issue | Game autoload `_ready()` 条件 add_child（`is_available()`） | ⬜ pending |
| 数值消费 | WolfConstants → DebugCanvas.get_value | #575/#577 | `DebugCanvas.get_value("NAME", C.NAME)`（§2.2 迁移约定） | ⬜ pending |
| 慢动作/处决消费 | SLOWMO_COEFF / EXECUTE_RANGE | #577 处决演出 | 处决演出在 `Engine.time_scale` 应用 SLOWMO_COEFF（读值派生） | ⬜ pending |
| 候选对比证据 | DebugCanvas JSON dump | 本 issue AC4 | `user://tuning_dump_<ts>.json` + 面板截图 + 手感描述 | ⬜ pending |
| 单测挂载 | run_tests.gd | 本 issue | `_run("res://tests/test_debug_canvas.gd", "DebugCanvas")` | ⬜ pending |
| DRAFT 定稿 | WolfConstants | #584 用户 | 用户实机裁决 → 去 # DRAFT 标记 → TASTE.md 记录 → close（taste-draft 流程） | ⬜ pending |
| TASTE.md 建档 | docs/TASTE.md | 本 issue | shandong-wolf 章节占位（三件套），定稿后回填差异 | ⬜ pending |

---

## 7. 实现阶段

| Phase | Priority | Components | Estimate |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | constants.gd 全量 DRAFT 值表（§2.3 直接落地：5 分区三行注释改造 + 新增分区 7 常量）+ **Spike 1**（F1 物理键 + `OS.is_debug_build()` 在 headless/导出模板的行为实测） | 1d |
| Phase 2 | P0 | debug_canvas.gd（PARAMS 表 + `_build_ui()` 程序化构建 + F1 toggle + override dict + 联动规则 + JSON dump）+ **Spike 2**（纯 Control 布局 1280x720 可行性 + CJK 渲染） | 1.5d |
| Phase 3 | P0 | game.gd 条件实例化（+4 行）+ **Spike 3**（override 热更新链路端到端：假消费方每帧读值断言） | 0.5d |
| Phase 4 | P0 | test_constants.gd 扩展（Scenario A）+ test_debug_canvas.gd（Scenario B-D）+ run_tests.gd 挂载 | 0.75d |
| Phase 5 | P0 | 三入口全绿实测（compile/smoke/run）+ 3 组候选对比证据产出（JSON dump + 面板截图 + 手感描述，AC4 材料）+ TASTE.md 建档 | 0.5d |

> 依赖序：Phase 1 → 2（面板 PARAMS 表引用 constants 参数名）→ 3（面板存在后挂接）→ 4（依赖 1/2 的产物可断言）→ 5 收尾。Spike 1 结论若 F1 捕获不可靠 → 改 InputMap 动作（集中改名点不变，PRD §7 实验 1 回退路径）。总估 4.25d（PRD estimate 2d 偏乐观——含 3 个 Spike 与三入口排障，参照 #572 先例 2d→实际 2.5d 的偏差方向）。

---

## 8. 测试用例描述

> 仅描述测试场景，不写可运行测试代码（plan 阶段红线；实现由 implement agent 完成）。三入口 = check_compile / smoke_test / run_tests。

### Scenario A: constants DRAFT 完整性（test_constants.gd 扩展，AC1）

- **A1（14 参数存在性）**: `get_script_constant_map()` 断言以下 14 个常量全部存在：`PARRY_WINDOW_FRAMES` / `POSTURE_RECOVERY_PER_SEC` / `POSTURE_RECOVERY_DELAY` / `POSTURE_BLOCK_COST` / `PARRY_COST` / `POSTURE_HIT_COST` / `POSTURE_BREAK_THRESHOLD` / `LIFE_1_MAX` / `LIFE_2_ABS` / `SWORD_DAMAGE_LIGHT` / `SWORD_DAMAGE_HEAVY` / `ENEMY_ATTACK_WINDUP` / `EXECUTE_RANGE` / `SLOWMO_COEFF`；任一缺失 FAIL。
- **A2（三行注释格式）**: 源码文本扫描——每个 `const <NAME>` 上方注释块必须含「只狼基准:」且（「候选集:」或「偏离理由:」）；14 参数逐一断言（实现提示：按 `const NAME` 定位后回溯上方 6 行注释）。
- **A3（候选集非空且 ≥2）**: 每个参数注释中「候选集:」后括弧内候选数 ≥2（LIFE_TOTAL / SWORD_DAMAGE_EXECUTE 等机械语义参数豁免——断言豁免名单：`LIFE_TOTAL`、`SWORD_DAMAGE_EXECUTE`）。
- **A4（防误定稿守卫延续）**: 源码含 `# DRAFT` 标记 ≥14 处；不含「# 定稿」字样（#572 E2 守卫升级，taste-draft 红线）。
- **A5（新增分区存在）**: 源码含「受击/敌人/处决」分区注释行 + 7 个新常量（`POSTURE_HIT_COST` / `PARRY_COST` / `POSTURE_RECOVERY_DELAY` / `ENEMY_ATTACK_WINDUP` / `EXECUTE_RANGE` / `SLOWMO_COEFF` / `LIFE_2_ABS`）。
- **A6（默认值与 §2.3 表一致）**: 抽查关键默认：`PARRY_WINDOW_FRAMES==12`、`POSTURE_RECOVERY_PER_SEC==25`（旧占位 0.8 必须消失）、`POSTURE_HIT_COST==35`、`LIFE_2_ABS==50`、`ENEMY_ATTACK_WINDUP==15`、`EXECUTE_RANGE==1.2`、`SLOWMO_COEFF==0.2`。

### Scenario B: 读值回落链路（test_debug_canvas.gd，AC2/AC3）

- **B1（override 命中）**: `_resolve_value("PARRY_WINDOW_FRAMES", 12, {"PARRY_WINDOW_FRAMES": 8})` → 返回 8（debug 热更新语义）。
- **B2（无 override 回落）**: `_resolve_value("PARRY_WINDOW_FRAMES", 12, {})` → 返回 12（默认值回落）。
- **B3（未知参数名静默回落）**: `_resolve_value("TYPO_NAME", 12, {"PARRY_WINDOW_FRAMES": 8})` → 返回 12（拼写错误不崩溃，PRD §5.3-2）。
- **B4（release 路径判定）**: 断言 `is_available()` 在当前（debug）环境返回 true；源码级断言 debug_canvas.gd 含 `OS.is_debug_build()` 判定（release 不实例化的实现证据，AC3）。
- **B5（派生参数裁决）**: `_resolve_value("POSTURE_BREAK_THRESHOLD", 100, {"LIFE_1_MAX": 150})` → 返回 150（只狼铁律联动派生，§2.2 表）。

### Scenario C: 参数表一致性自检（test_debug_canvas.gd）

- **C1（PARAMS ↔ constants 一致性）**: `DebugCanvas.PARAMS` 的 14 个 `name` 与 constants.gd const 名完全一致（双向集合相等，防拼写错误——启动自检，PRD §5.3-2）。
- **C2（range 覆盖默认）**: 每行 `min <= default <= max` 且 `step > 0`（面板可初始化为默认值）。
- **C3（候选集与面板 range 兼容）**: 每行 candidates 全部落在 `[min, max]` 内（SpinBox 能表达全部候选）。

### Scenario D: 面板行为（test_debug_canvas.gd）

- **D1（F1 toggle 语义）**: 断言 `_unhandled_input` 对 KEY_F1 pressed+非 echo 事件翻转 visible；其他键（如 KEY_F2）不响应（模拟 InputEventKey 构造调用）。
- **D2（越界拒绝）**: `_on_param_changed(PARAMS[0], 100)`（弹反窗口超 max=30）→ `_overrides` 不含该键（range 校验生效，PRD §5.2-2）。
- **D3（慢动作 clamp）**: `_on_param_changed(SLOWMO 行, 0.0)` → override 值为 0.1（clamp 下限，PRD §5.2-5）；`_on_param_changed(SLOWMO 行, 0.4)` → 0.4（上限内放行）。
- **D4（联动写入）**: `_on_param_changed(LIFE_1_MAX 行, 150)` → `_overrides["POSTURE_BREAK_THRESHOLD"] == 150`（双向联动，PRD §5.2-7）。
- **D5（dump JSON 合法性）**: `_export_dump()` 产出文件可被 `JSON.parse` 解析；`params` 含全部 14 个参数名；`meta.game_version == C.GAME_VERSION`（AC4 证据链可机器校验）。
- **D6（重置默认）**: 写入若干 override 后触发「重置默认」→ `_overrides` 清空；`get_value` 回落 const 默认。

### Scenario E: 三入口回归（CI / 本地）

- **E1（check_compile）**: `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` 退出 0，覆盖新增 debug_canvas.gd + test_debug_canvas.gd。
- **E2（smoke）**: `... --script tests/smoke_test.gd` 退出 0，Game autoload 初始化 + DebugCanvas 条件实例化无报错（debug 环境应实际创建面板节点）。
- **E3（run_tests）**: `... --script tests/run_tests.gd` 退出 0，输出「TESTS: N passed, 0 failed」且套件数 = 3（StateMachine / Constants / DebugCanvas）；pass==0 → 退出非 0。
- **E4（主场景冒烟）**: `godot --path shandong-wolf/ --headless --quit` 退出 0（autoload + Main.tscn 启动链兼容，面板不影响主场景）。

### Scenario F: AC4 证据材料（非自动化单测，PR 交付物）

- **F1（3 组 JSON dump）**: 基准组（全默认）/ 宽容组（PARRY_WINDOW_FRAMES=14, POSTURE_RECOVERY_PER_SEC=35, POSTURE_HIT_COST=30）/ 严苛组（PARRY_WINDOW_FRAMES=8, POSTURE_RECOVERY_PER_SEC=20, POSTURE_HIT_COST=40）三份 dump 文件参数差异符合 PRD §4.5 表。
- **F2（画面证据 + 手感描述）**: 面板截图（证明面板可运行、CJK 正常、14 行可读）+ 每组合 1-2 句手感描述（弹反容错 / 架势节奏 / 紧张感差异）；战斗内效果截图顺延 #575/#577（明确不搭战斗 demo）。

---

## 9. 验收条件映射（源自 Issue #584 body）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | constants.gd 内含完整 # DRAFT 数值表，每项标注「只狼基准 → 本项目候选」或偏离理由，禁止无出处数值 | §2.3 全量值表（14 参数三行注释 + 新增分区） | A1/A2/A3/A6（存在性 + 注释格式 + 候选集 + 默认值断言）+ review diff |
| AC2 | F1 调参面板运行时可修改 ≥10 个核心参数并实时生效 | §2.1 面板（14 行）+ §2.2 热更新链路（14 参数，13 可调 + 1 联动派生） | B1/B2/B5/D1-D4（读值命中/回落/联动/越界/clamp）+ Spike 3 端到端 |
| AC3 | 调参面板仅 debug build 可见，release 不编译 | §2.1 `is_available()` + `_ready` queue_free 双保险 + Game 条件实例化 | B4（is_available + 源码判定断言）+ E2（debug 下实际创建） |
| AC4 | PR 中附调参对比说明（至少 3 组候选对比手感差异） | §4 Flow 2 + §7 Phase 5（JSON dump + 截图 + 手感描述） | F1/F2（3 组 dump + 面板截图 + 描述） |
| AC5 | 最终数值由用户 E2E 实机裁决后从 # DRAFT 转为正式值 | taste-draft 流程（草稿 PR `Parent #584` 不写 Closes → assign 用户 + status/human-review → 用户裁决 → 去 DRAFT → TASTE.md → close） | issue 生命周期事件（assignee/label/close） |
| 附加 | 🔍 开源优先：调参面板先调研成熟插件 | PRD §4.2 调研表（4 组关键词，无成熟方案 → 自研） | implement PR 附调研表（§2 架构总览已引用） |
| 附加 | 画面实现路径：纯 Control + StyleBox + 写字板字体，不引入 UI 图片 | §2.1 节点结构（零 tscn 零图片） | implement PR diff 核查：无 .png/.jpg 新增 |

---

## 10. 明确不修改（与 PRD §8 红线对齐）

- ❌ `mini-pong/` 任何文件（跨游戏红线）
- ❌ `shandong-wolf/scenes/Main.tscn`（#572/#584 双重红线）
- ❌ `shandong-wolf/project.godot`（F1 不占 InputMap、不加 autoload——PRD §3.3）
- ❌ `shandong-wolf/e2e_shots.json`（占位空 states；AC4 证据范围见 §4 Flow 2）
- ❌ `shandong-wolf/gdscripts/state_machine.gd`（#575 职责）
- ❌ `game-env/manifest.yaml`、`.github/workflows/`、`scripts/`（管线参数化已自动跟随）
- ❌ `docs/GAME_DESIGN/`（post-merge agent 职责）
- ❌ 任何美术资产 / 插件 addon / UI 图片（AC 附加项）
- ❌ **任何 DRAFT 值「顺手定稿」**（去 # DRAFT 标记 / 改值为正式值 = test_constants A4 FAIL；taste-draft v4 红线，用户裁决前禁止）
- ✅ 唯一 PRD 清单扩展：`game.gd` +4 行（条件实例化，§1.2/§3.1 已论证——Main.tscn 与 project.godot 双红线下唯一挂接点）
