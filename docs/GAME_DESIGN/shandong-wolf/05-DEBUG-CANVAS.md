# DebugCanvas — 战斗数值调参面板（#584）

> 落盘依据：PR #609（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/584-combat-tuning-draft.md`。
> 一句话定位：**调参是调试手段，不是运行时特性**——面板只存在于 debug build，release 零开销、零分支污染。

## 1. 设计意图

战斗数值是品味草稿（taste-draft，#584），需要「低成本校准」：改参数 → 实机打一局 → 判断手感。
而 #572 的 constants 全是 `const`，改一个参数 = 改代码重编译重启目测，校准成本过高。
本面板提供**运行中热更新**：F1 开关、14 参数 HSlider/SpinBox、override dict 实时生效、
JSON dump 导出候选对比证据（AC4）。定稿仍归 #584 用户实机裁决——面板只是裁决工具，不替代裁决。

## 2. 架构决策

| 方案 | 内容 | 裁决 |
|------|------|:----:|
| A（采纳） | 纯 Control 程序化自研面板（CanvasLayer layer=100，零 .tscn 零图片资产） | ✅ 开源尽调（4 组 GitHub 关键词）无成熟运行中调参插件；约 250 行自研满足 |
| A（采纳） | F1 物理键 `_unhandled_input` 直判（`keycode == KEY_F1`），不占 InputMap | ✅ project.godot 零改动（#584 红线） |
| A（采纳） | `OS.is_debug_build()` 运行时判定 debug/release | ✅ release 首行回落 const，零 dict 查询零分支污染 |
| A（采纳） | 静态 override dict + `get_value(name, default)` 静态读值函数 | ✅ 消费方一行接入；`C.NAME` 直读不破坏（默认值语义等价） |
| A（采纳） | JSON dump 导出（`user://tuning_dump_<ts>.json`，只落盘不自动加载） | ✅ AC4 候选对比证据；MVP 不做持久化加载 |

挂载点：**Game autoload** 条件实例化（Main.tscn / project.godot 均为红线零改动，Game 是唯一既有挂接点）——
`game.gd _ready()` 内 `if DebugCanvasScript.is_available(): add_child(DebugCanvasScript.new())`。

## 3. 参数表（PARAMS —— 面板唯一数据源）

14 个 tunable 参数集中定义在 `debug_canvas.gd` 的 `PARAMS` 表，**驱动 UI 生成 + 一致性自检**。
每个参数 = HSlider/SpinBox 一行 + Label 候选集。所有值为 **# DRAFT 候补**，定稿归 #584（用户实机裁决）。

| # | 参数 | 只狼基准 | 候选集 | DRAFT 默认 | 影响什么 |
|---|------|---------|--------|:---:|---------|
| 1 | `PARRY_WINDOW_FRAMES` | ~12 帧（0.2s @60fps） | [8, 10, 12, 14] | 12 | 弹反判定窗——越短越硬核，越长越宽容 |
| 2 | `POSTURE_RECOVERY_PER_SEC` | 20-35/s | [20, 25, 30, 35] | 25 | 架势回复节奏阀——太快无脑弹反，太慢龟缩 |
| 3 | `POSTURE_RECOVERY_DELAY` | 脱战 1.5s | [1.0, 1.5, 2.0] | 1.5 | 停防后多久开始回复（喘息窗口） |
| 4 | `POSTURE_BLOCK_COST` | 8-12/次 | [8, 10, 12] | 10 | 长按格挡的架势代价 |
| 5 | `PARRY_COST` | 0（精准奖励） | [0, 1, 2] | 1 | 弹反成功扣架势（默认 1 防无脑弹反，用户裁决 0/1/2） |
| 6 | `POSTURE_HIT_COST` | 30-40/次 | [30, 35, 40] | 35 | 受击扣架势——血+架势双重惩罚，逼玩家进攻 |
| 7 | `POSTURE_BREAK_THRESHOLD` | = 当前 HP 上限 | 派生（恒等于 LIFE_1_MAX） | 100 | 架势崩解阈值 → 可处决 |
| 8 | `LIFE_1_MAX` | 100%（20 格） | [100, 120] | 100 | 第一条命容错血量 |
| 9 | `LIFE_2_ABS` | 回生后约半血 | [40, 50, 60] | 50 | 第二条命绝对血量（命悬一线） |
| 10 | `SWORD_DAMAGE_LIGHT` | 轻击 10-15 | [10, 12, 15] | 12 | 轻击架势伤害 |
| 11 | `SWORD_DAMAGE_HEAVY` | 重击 25-40 | [25, 30, 40] | 30 | 重击架势伤害 |
| 12 | `ENEMY_ATTACK_WINDUP` | 危攻击 14-18 帧 | [12, 15, 18] | 15 | 敌人攻击前摇（可读性） |
| 13 | `EXECUTE_RANGE` | 忍杀触发 = 近身 | [1.0, 1.2, 1.5] | 1.2 | 处决触发距离 |
| 14 | `SLOWMO_COEFF` | 处决 hit-stop 慢动作 | [0.1, 0.2, 0.3] | 0.2 | 处决慢动作系数（Engine.time_scale，clamp 下限 0.1 防冻结） |

**派生参数（消费方无需感知联动，读值函数统一裁决）：**

| 消费参数名 | 裁决规则 |
|-----------|---------|
| `POSTURE_BREAK_THRESHOLD` | override 有该键 → 返回；否则 override 有 `LIFE_1_MAX` → 返回；否则 `C.POSTURE_BREAK_THRESHOLD` |
| `LIFE_2_MAX_RATIO` | override 有 `LIFE_2_ABS` → 返回 `LIFE_2_ABS / LIFE_1_MAX有效值`；否则 `C.LIFE_2_MAX_RATIO` |

## 4. 读值链路（消费方入口）

override dict 写入端是面板，读取端是静态函数——**消费方只依赖函数，不依赖面板节点存在**：

```gdscript
static var _overrides: Dictionary = {}   # 参数名 → 当前 override 值（面板写入，进程内有效）

## 读值入口：debug + override 存在 → 返回 override；否则回落默认。
static func get_value(param_name: String, default_value: Variant) -> Variant:
    if not OS.is_debug_build():
        return default_value                    # release 零开销回落（首行判定，无 dict 查询）
    if _overrides.has(param_name):
        return _overrides[param_name]
    return default_value                        # debug 但面板从未打开 → 回落 const

static func is_available() -> bool:
    return OS.is_debug_build()                  # Game autoload 实例化判定点（单一决策点）
```

消费方迁移约定（#575/#577 推荐写法，`C.NAME` 直读不破坏）：

```gdscript
const C = preload("res://gdscripts/constants.gd")
const DebugCanvas = preload("res://gdscripts/debug_canvas.gd")
var parry_window: int = DebugCanvas.get_value("PARRY_WINDOW_FRAMES", C.PARRY_WINDOW_FRAMES)
```

**读值禁止缓存**（每次实时查 dict）——面板改值下一帧即生效，无需重启。

## 5. 数据流

**Flow 1 — F1 面板热更新（正常路径）：** debug 启动 → Game._ready() → `is_available()==true` → add_child(DebugCanvas) → 用户按 F1 → `_unhandled_input` 捕获 KEY_F1 → visible 翻转（**面板打开不暂停游戏**，实时手感）→ 拖 HSlider → range 校验 → `_overrides[name]=value` → 联动规则 → 消费方 get_value 下一帧读到新值。

**Flow 2 — 候选对比证据（AC4）：** 面板「导出 JSON」→ `user://tuning_dump_<ts>.json`（meta + 14 参数当前值）。3 组对比：基准组（全默认）/ 宽容组（弹反 14、回复 35、受击 30）/ 严苛组（弹反 8、回复 20、受击 40）→ 每组改值 → 导出 JSON → 截图 → 手感描述（弹反容错 / 架势节奏 / 紧张感）。战斗场景未就绪前，截图以面板画面为证。

**Flow 3 — release 回落（fallback）：** release 导出 → `is_available()==false` → 不实例化（无节点无 F1 响应）；消费方 get_value 首行 `OS.is_debug_build()==false` → 直接返回 const；即使 debug_canvas.gd 被误引用 → `_ready()` 内 `queue_free()` 双保险。

**Flow 4 — 越界 / 联动（edge-case）：** SpinBox 越界值 → range 校验拒绝写入；SLOWMO_COEFF 输入 0 → clamp 下限 0.1（time_scale=0 会冻结游戏含面板输入）；改 `LIFE_1_MAX` → `POSTURE_BREAK_THRESHOLD` 联动同值（只狼铁律：架势上限 = 当前 HP 上限，双向联动）。

## 6. 边界与纪律

- 面板是**一次性调参工具**：不参与战斗逻辑，无运行时特性；定稿后仍保留（候选对比需要）。
- E2E 截图前强制 `visible=false` 保证确定性（截图管线约定）。
- 定稿唯一通道：#584（用户实机裁决替换候补值 + 去 DRAFT 标记，test_constants 断言强制）。

## 7. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #584 | 战斗数值 DRAFT 集中表 + 一次性调参面板（本文件所属） | 草稿已合并（#609），待用户定稿 |
