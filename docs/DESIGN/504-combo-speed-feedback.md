# DESIGN: [Test] 玩家板加速反馈 — 连击得分时板速+20%

> **Parent Issue:** #504
> **Agent:** game-plan-agent
> **Date:** 2026-08-15
> **Approach:** A — paddle 内聚连击状态机（确认 PRD §4 推荐方案；TF-1 时间源 = `_process(delta)` 累计、TF-2 语义 = 时间窗（AI 得分不重置）均按 PRD §7 实验结论采纳）
> **Reference PRD:** docs/PRD/504-combo-speed-feedback.md（research PR #505，已合并）
> **所有权:** `content_ownership: mechanical`（连击窗口 2s + 倍率 +20% + 恢复 = 机械可测；数值按 issue 字面执行，不做 taste 再校准）
> **深度:** depth/standard（Issue 无 depth 标签，按 #491/#495 惯例）—— 文件域 3（paddle.gd / constants.gd / test_paddle.gd）、无新文件、无迁移、无弃用 → **不产 TASKS 文档**（低于阈值：<10 文件、<5 迁移、<5 子系统）
> **并行上下文:** 无已知并发分支触碰 paddle.gd / constants.gd / test_paddle.gd（#500 改动在 framework/templates + tests/pipeline，与本文档文件域不重叠）

---

## 1. 架构概述

### 1.1 设计核心

**在 paddle.gd 玩家模式内聚一个「连击状态机」：`_ready()`（PLAYER 分支）只读消费 `GameManager.score_changed` 信号（null-guard），`_on_score_changed` 按玩家得分增量判定连击窗口，`_process(delta)` 递减计时器、过期复位，移动行按 `_combo_active` 乘算 `(1 + COMBO_SPEED_BONUS)`。** 零改动文件域外代码；AI 分支物理隔离。

```
GameManager.add_score(winner, amount, kind)          [#385 事件源，全 kind（boundary/brick/pierce）]
    │  score_changed.emit(player_score, ai_score)    (game_manager.gd:58)
    ▼
PlayerPaddle._on_score_changed(p, a)                 [paddle.gd 新增，仅 PLAYER 模式 + null-guard]
    ├── 重开检测: p < _last_player_score → 复位连击状态
    ├── 玩家得分 (p > _last_player_score)?
    │     ├── _combo_timer > 0  → 连击成立: _combo_active = true（窗口内再次得分）
    │     └── _combo_timer == 0 → 首分: _combo_active = false（0-1 分正常速度）
    │     两种情况均刷新 _combo_timer = combo_window_seconds (2.0s)
    └── AI 得分 → 不触碰计时器（时间窗语义，TF-2）

PlayerPaddle._process(delta)                         [PLAYER 分支，既有循环内]
    ├── _combo_timer = max(0, _combo_timer - delta)  （frozen early-return 之后 → 冻结期不衰减）
    ├── _combo_timer == 0 → _combo_active = false     （窗口过期 → 恢复）
    └── effective_speed = paddle_speed × (1.0 + (combo_speed_bonus if _combo_active else 0.0))
        position.x += move × effective_speed × delta → clamp

AI 板（同脚本 Mode.AI）: _ai_process(delta) 原样 —— 连击逻辑完全隔离在 PLAYER 分支（范围红线）
```

设计哲学：
1. **事件驱动，零轮询** — `score_changed`（#385）已覆盖全 kind 计分（含拆砖分，`scored` 只覆盖出界分，不可用）；只读消费即满足文件域红线（只改 paddle.gd / constants.gd / test_paddle.gd）
2. **确定性可测** — 时间源用 `_process(delta)` 累计（PRD TF-1 结论），测试直接调 `_process(0.016)` 快进 2.1s 断言恢复，与 test_paddle.gd 既有 TC-B1~F4 模式一致；不依赖真实时钟
3. **AI 隔离天然成立** — 连击状态只在 `Mode.PLAYER` 分支注册/生效；AI 分支代码零触碰（issue 范围红线：不动 AI 板）
4. **数值字面执行 + 可调参** — `+20%`/`2s` 按 issue 字面进 constants.gd 新区；paddle 侧 `@export` 默认接 CONSTS（#387 AC3 先例），后续 taste 校准（#367 域）零代码改动
5. **冻结语义优先（#294）** — `frozen` 时 `_process` early-return，计时不衰减、倍率不生效；解冻后按剩余窗口继续（PRD §5.2 边界 5）

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码）

| PRD 断言 | 实际代码（main @ 52f15c2） | 设计裁决 |
|---------|--------------------------|---------|
| `paddle.gd` 玩家模式每帧 `position.x += move * paddle_speed * delta`；`paddle_speed` 为 `@export`（默认 `CONSTS.PADDLE_SPEED=430.0`） | ✅ paddle.gd:92-102 `_process` PLAYER 分支：读输入 → `position.x += move * paddle_speed * delta` → `_apply_magnet` → clamp；:32 `@export var paddle_speed: float = CONSTS.PADDLE_SPEED` | 移动行乘算 `effective_speed`，其余不动 |
| `GameManager.score_changed(player_score, ai_score)` 对所有计分（boundary/brick/pierce、双方）emit | ✅ game_manager.gd:16 信号声明、:58 每次 `add_score` 后 emit（`_check_run_end()` 之前）；:102 `reset()` 清零 player_score | 事件源成立；「玩家得分」过滤用 `p > _last_player_score` 增量判定（含重开检测，见边界 6） |
| `scored(winner)` 只覆盖出界分 → 不可作连击事件源 | ✅ scoring_manager.gd 注释「拆砖分不触发 scored」；`score_changed` 全 kind | 连击只消费 `score_changed`，不碰 `scored` |
| `GameManager` autoload 在 paddle 测试外多处直用 | ✅ scoring_manager.gd 直用全局 `GameManager.add_score`；project.godot:20 `GameManager="*res://gdscripts/game_manager.gd"` | 沿用全局引用 + null-guard（headless 测试上下文 autoload 可能未实例化，见裁决 2） |
| `constants.gd` 追加新区不触碰既有行（test_constants.gd TC6 字面值断言） | ✅ constants.gd 末尾为 #450 Audio 区；test_constants.gd TC6-1~12 只断言既有常量精确值 | 文件末尾追加 `# ── Combo Speed Feedback (#504) ──` 区，零触碰既有行 |
| 无任何 combo/连击 符号存在于代码库 | ✅ `grep -ri "combo" mini-pong/` 零命中 | 全新机制，无历史包袱 |
| `player_paddle.tscn` 无导出覆盖 | ✅ player_paddle.tscn 仅脚本 + ColorRect + CollisionShape2D，无 `mode`/`paddle_speed` 覆盖 → 默认 PLAYER + 430 | 新增 `@export` 默认值生效，tscn 零改动 |
| paddle `_ready` 中 PLAYER 分支做 InputMap 绑定 | ✅ paddle.gd:55-74 | 信号连接放在同分支 `_ready` 末尾（InputMap 绑定之后），保持初始化顺序清晰 |
| FSM 冻结 `frozen` 时 `_process` early-return | ✅ paddle.gd:87-89 `if frozen: return` 位于 `_process` 顶部 | 计时递减放在 frozen early-return 之后 → 冻结期不衰减（PRD §8 措辞按 §5.2 边界 5 语义解释，见裁决 1） |

### 1.3 设计裁决（PRD 缺口闭合 — plan agent 独立裁决）

**裁决 1（计时递减位置）：在 `_process` 的 frozen early-return 之后、PLAYER 分支内递减。** PRD §8 写「`_combo_timer` 在 `_process` 递减（frozen early-return 前）」，与其 §5.2 边界 5「冻结期间计时不衰减」字面矛盾。按边界语义定案：`frozen` 时整帧 early-return → 计时不衰减、倍率不生效；解冻后按剩余窗口继续（冻结语义优先，#294）。递减代码置于 PLAYER 分支移动逻辑之前（同帧先衰减再移动，语义自洽）。

**裁决 2（测试驱动方式）：Scenario G 直接调 `_on_score_changed(p, a)` 驱动，不依赖 autoload 实例化。** headless `--script` 测试上下文（run_tests.gd）下 autoload 单例是否实例化取决于 MainLoop 类型，不可假设。`_on_score_changed` 是普通方法，直接调用即可确定性驱动连击状态；信号连接存在性由 null-guard 兜底（`GameManager != null and GameManager.has_signal("score_changed")`）。G10 专门覆盖「无 autoload 上下文 → 不崩、基速运行」。

**裁决 3（首分语义）：第一次得分不加速，但窗口立即起算。** issue 字面「0-1 分：正常速度」= 首分 `_combo_active` 保持 false；同时 `_combo_timer` 置 2.0 开始计窗 —— 2s 内第二次得分即连击成立。该语义使「0-1 分」与「连击窗口」无缝衔接（PRD §5.2 边界 1/2 一致）。

**裁决 4（AI 得分语义）：时间窗 —— AI 得分不触碰 `_combo_timer`。** PRD TF-2 实验结论：时间窗语义最简、贴合 issue 字面「2 秒内连续得分」（玩家得分间隔 < 2s 即连击，与中间 AI 得分无关）。若未来评审偏好回合重置，仅需在 `_on_score_changed` 加一行 AI 得分复位，改动局部化（§7 集成点留作可选扩展）。

**裁决 5（精确窗口边界）：`_combo_timer > 0.0` 为连击成立判据。** 得分瞬间 `_combo_timer = 2.0`；`_process` 每帧先衰减。t=2.0 整时衰减至 0 → 过期（不在窗口内）；t<2.0 在窗口内。测试用 1.999/2.001 双断言锁定边界（G5）。

---

## 2. 新组件

无新文件。连击状态机全部内聚于既有 `paddle.gd` PLAYER 分支；不新建脚本/场景/常量文件/资源。

---

## 3. 既有组件修改

### 3.1 `mini-pong/gdscripts/paddle.gd`（核心，唯一逻辑改动文件）

**新增成员（`# ── Combo Speed Feedback (#504) ──` 注释区，置于 AI state 区之后）：**

```gdscript
# ── Combo Speed Feedback (#504) ──
## 连击加速反馈：2s 窗口内玩家再次得分 → 板速 +20%（乘性叠加于 paddle_speed）。
## 数值默认接 CONSTS（#387 AC3 先例），编辑器可调参（taste 校准 #367 域零代码改动）。
@export var combo_window_seconds: float = CONSTS.COMBO_WINDOW_SECONDS
@export var combo_speed_bonus: float = CONSTS.COMBO_SPEED_BONUS

var _combo_timer: float = 0.0            # 剩余窗口秒数（delta 累计，确定性）
var _combo_active: bool = false          # 连击成立 → 板速 +20%
var _last_player_score: int = -1         # -1 = 尚未见过任何得分（首分判定 + 重开检测基准）
```

**`_ready()` 修改（PLAYER 分支末尾，InputMap 绑定之后追加）：**

```gdscript
if mode == Mode.PLAYER:
    # ... 既有 InputMap 绑定 ...
    # #504: 只读消费 score_changed（全 kind 事件源）；autoload 缺失/未接线 → 跳过（G10）
    if GameManager != null and GameManager.has_signal("score_changed"):
        GameManager.score_changed.connect(_on_score_changed)
```

**新增方法 `_on_score_changed(player_score: int, ai_score: int)`：**

```gdscript
## #504: 连击窗口判定。仅 PLAYER 模式；玩家得分增量 > 0 才推进状态。
func _on_score_changed(player_score: int, _ai_score: int) -> void:
    if mode != Mode.PLAYER:
        return
    # 重开检测（边界 6）: GameManager.reset() 清零 → score 回退 → 复位连击
    if _last_player_score >= 0 and player_score < _last_player_score:
        _combo_active = false
        _combo_timer = 0.0
    # 玩家得分: 窗口内再次得分 → 连击成立；首分（0-1 分）→ 不加速但窗口起算
    if player_score > _last_player_score:
        _combo_active = _combo_timer > 0.0
        _combo_timer = combo_window_seconds
    _last_player_score = player_score
```

**`_process()` 修改（PLAYER 分支，移动逻辑之前插入计时衰减 + 移动行改乘 effective_speed）：**

```gdscript
func _process(delta: float) -> void:
    if frozen:
        return                       # 冻结期: 计时不衰减、倍率不生效（裁决 1，边界 5）
    if mode == Mode.AI:
        _ai_process(delta)
        _apply_magnet(delta)
        return
    # ── 连击计时（#504，仅 PLAYER）──
    if _combo_timer > 0.0:
        _combo_timer = max(0.0, _combo_timer - delta)
        if _combo_timer <= 0.0:
            _combo_active = false    # 窗口过期 → 恢复基速

    # 既有输入读取 ...
    var left := Input.is_action_pressed("paddle_left")
    var right := Input.is_action_pressed("paddle_right")
    var move: float = 0.0
    if left and not right:
        move = -1.0
    elif right and not left:
        move = 1.0

    # #504: 连击有效速度（乘性叠加，基值 430 不动）
    var effective_speed: float = paddle_speed
    if _combo_active:
        effective_speed = paddle_speed * (1.0 + combo_speed_bonus)
    position.x += move * effective_speed * delta
    _apply_magnet(delta)
    position.x = clamp(position.x, min_x, max_x)
```

**AI 分支（`_ai_process` / AI 相关 `@export`）：零改动。** `_on_score_changed` 首行 `mode != Mode.PLAYER` 早退保证 AI 板即使收到信号也不改变状态（G6）。

### 3.2 `mini-pong/gdscripts/constants.gd`（文件末尾追加新区，零触碰既有行）

```gdscript

# ── Combo Speed Feedback (#504) ──
# 玩家板连击加速反馈：2s 窗口内玩家再次得分 → 板速 +20%（乘性叠加于 PADDLE_SPEED 基值）。
# 数值按 issue 字面执行（mechanical，#367 taste 域不校准）；窗口过期恢复基速。
const COMBO_WINDOW_SECONDS: float = 2.0
const COMBO_SPEED_BONUS: float = 0.2
```

> `test_constants.gd` TC6 只断言既有常量精确字面值（TC6-1~12），追加新区不触碰 → 保持绿（§9 Scenario C）。

### 3.3 `mini-pong/tests/test_paddle.gd`（追加 Scenario G，沿用 `_make_paddle()` + 直接调 `_process(delta)` 模式）

- `run()` 列表末尾追加 G1~G10 调用（§9 描述，实施阶段写代码）
- 不改动既有 TC-A1~F4 任何断言；`_make_paddle()` 复用
- 新增 `_on_score_changed` 驱动辅助（直接方法调用，不依赖 autoload，裁决 2）
- 对移动距离断言，需注入方向输入：沿用既有 TC-B 模式（headless 下 Input 恒 false）—— 距离断言通过「连击态 vs 基态位移比」而非绝对位移（如 active 帧位移 == 基速帧位移 × 1.2），或临时置 `position.x` 前后差值；**实现细节以「可确定性断言 +20% 位移比」为准**

### 3.4 文件汇总

| 类别 | 文件 | 改动性质 |
|------|------|---------|
| 修改 | `mini-pong/gdscripts/paddle.gd` | PLAYER 分支连击状态机（3.1）；AI 分支零改动 |
| 修改 | `mini-pong/gdscripts/constants.gd` | 文件末尾追加 2 个常量（3.2） |
| 修改 | `mini-pong/tests/test_paddle.gd` | 追加 Scenario G 用例（3.3） |
| 新增 | 无 | — |
| 移除/弃用 | 无 | — |
| 受影响测试 | `mini-pong/tests/test_constants.gd` | 不改动；TC6 保持绿即验证常量追加纪律（回归门） |
| 受影响测试 | `mini-pong/tests/run_tests.gd` | 不改动（test_paddle.gd 已注册，Scenario G 自动纳入） |

**PR 白名单（红线）**：PR files 仅含上述 3 个文件；`scoring_manager.gd` / `game_manager.gd` / `ball.gd` / `*.tscn` / AI 分支 / 雨幕（rain_curtain.gd）零修改。

---

## 4. 数据流

### Flow 1: 正常路径 — 首分（0-1 分，不加速）

```
玩家出界得分 → GameManager.add_score("player", 1, "boundary")
  → score_changed.emit(1, 0) → PlayerPaddle._on_score_changed(1, 0)
    → _last_player_score -1 → 1（增量）: _combo_timer(0) > 0? No → _combo_active = false
    → _combo_timer = 2.0（窗口起算）
  → 移动帧: effective_speed = 430 × 1.0 = 430（基速）
```

### Flow 2: 连击延续 — 2s 窗口内再次得分（+20%）

```
t=0.0  玩家得分 → _combo_timer = 2.0, _combo_active = false
t=1.5  玩家再次得分（拆砖/穿墙任意 kind）→ _on_score_changed(2, 0)
         → _combo_timer(0.5) > 0 → _combo_active = true, _combo_timer = 2.0（刷新）
t=1.516 移动帧: effective_speed = 430 × 1.2 = 516
```

### Flow 3: 窗口过期恢复

```
t=0.0  连击成立（_combo_active = true, _combo_timer = 2.0）
t=2.0  _process 衰减: _combo_timer = max(0, 2.0-2.0) = 0 → _combo_active = false
t=2.016 移动帧: effective_speed = 430（恢复基速，同一 rally 内即时恢复，不等下次得分）
```

### Flow 4: 重开复位（终局 → 新一局）

```
GameManager.reset() → player_score = 0（game_manager.gd:102）
下一局玩家首分 → score_changed.emit(1, 0) → _on_score_changed(1, 0)
  → 重开检测: _last_player_score(≥0 如 5) > 1 → _combo_active = false, _combo_timer = 0.0
  → 玩家增量: _combo_timer(0) > 0? No → 首分语义（不加速，窗口起算）
```

### 失败路径: GameManager autoload 缺失 / 信号未接线

```
_ready(): GameManager == null 或 has_signal 失败 → 跳过连接（零告警刷屏）
  → 连击功能降级为恒基速，游戏可玩（G10 断言不崩、基速位移正常）
```

---

## 5. 边界情况与错误处理

| # | 边界场景 | 处理 |
|---|---------|------|
| 1 | 首分不加速（0-1 分） | `_combo_timer == 0` → `_combo_active = false`；窗口照常起算（裁决 3） |
| 2 | 窗口内连击延续 | 每次玩家得分刷新 `_combo_timer = 2.0`；不因中间 AI 得分中断（裁决 4） |
| 3 | AI 得分不重置计时 | `_on_score_changed` 只对「玩家得分增量」分支触碰计时器；AI 得分分支无操作（时间窗语义） |
| 4 | 窗口过期恢复 | `_combo_timer` 归零 → `_combo_active = false`；下一帧起恢复基速（Flow 3） |
| 5 | 冻结期间（FSM #294） | `frozen` early-return：计时不衰减、倍率不生效；解冻后按剩余窗口继续（裁决 1） |
| 6 | 终局/重开 | `_on_score_changed` 检测 `p < _last_player_score` → 复位计时器 + 活跃标志（Flow 4） |
| 7 | AI 模式板 | 不连接信号；`_on_score_changed` 首行 `mode != Mode.PLAYER` 早退（G6） |
| 8 | headless/测试上下文 autoload 缺失 | null-guard 跳过连接；基速运行不崩不刷屏（G10，失败路径） |
| 9 | delta 尖峰 | `_combo_timer = max(0, ...)` 防负值；大 delta 只可能提前结束连击，不产生负加速 |
| 10 | 多 paddle 实例 | 仅 PLAYER 模式实例连接信号；每个实例独立状态互不干扰（`_last_player_score` 实例级） |
| 11 | 精确窗口边界 | `_combo_timer > 0.0` 判据：t=2.0 恰过期、t=1.999 在窗口内（裁决 5，G5 双断言） |
| 12 | 拆砖连击 | 拆砖分走 `score_changed`（非 `scored`）→ 拆砖后 2s 内出界得分同样连击成立（事件源全 kind） |

---

## 6. 逐组件配置（implement 契约速查）

| 文件 | 位置 | 内容 |
|------|------|------|
| `constants.gd` | 文件末尾（#450 Audio 区之后） | `COMBO_WINDOW_SECONDS: float = 2.0`、`COMBO_SPEED_BONUS: float = 0.2`，注释块标注 #504 |
| `paddle.gd` | 成员区（AI state 之后） | `@export combo_window_seconds` / `@export combo_speed_bonus`（默认 CONSTS）+ `_combo_timer` / `_combo_active` / `_last_player_score`（-1） |
| `paddle.gd` | `_ready()` PLAYER 分支末尾 | `GameManager.score_changed.connect(_on_score_changed)`（null-guard） |
| `paddle.gd` | 新增方法 | `_on_score_changed(player_score: int, _ai_score: int)`（§3.1 伪代码） |
| `paddle.gd` | `_process()` PLAYER 分支 | 计时衰减（frozen 检查后）+ `effective_speed` 乘算移动行（§3.1） |
| `test_paddle.gd` | `run()` 列表 + 新方法区 | Scenario G1~G10（§9） |

**红线复述**：不碰 `scoring_manager.gd` / `game_manager.gd` / `ball.gd` / `*.tscn` / AI 分支 / 雨幕；PR files 白名单仅 3 个文件。

---

## 7. 集成点

> **Status 约定：** ⬜ = pending（资源已创建、未接线）；✅ = connected（implement agent 验证）。implement agent 接线后必须更新本表；review agent 在 merge 前验证所有 ⬜ 已解决或显式延后。

| 集成 | 我方组件 | 目标 Issue | How | Status |
|------|:---:|:---:|-----|:---:|
| 得分事件源 | `paddle.gd._on_score_changed` | #385 | `GameManager.score_changed` 信号连接（PLAYER 分支，null-guard） | ✅ connected |
| FSM 冻结 | `paddle.gd._process` frozen early-return | #294 | 计时衰减置于 frozen 检查之后（冻结期不衰减） | ✅ connected |
| 手感基值 | `constants.gd` 追加区 | #367 | 倍率乘性叠加于 `PADDLE_SPEED=430.0`，基值不动 | ✅ connected |
| 测试注册 | `test_paddle.gd` Scenario G | #504 | `run()` 列表追加 G1~G10；run_tests.gd 自动纳入（零改动） | ✅ connected |
| 验证载体 | playthrough / 截图 E2E | #394 | AC2（run_tests 全绿）/ AC3（e2e_shots 截图断言）只读验证，零修改 | ✅ connected |

---

## 8. 实施阶段

| Phase | 优先级 | 组件 | 估算 |
|:-----:|:------:|------|:----:|
| Phase 1 | P0 | constants.gd 追加 2 常量（§3.2） | 0.1d |
| Phase 2 | P0 | paddle.gd 连击状态机（§3.1：成员 + 连接 + 判定 + 衰减 + 乘算） | 0.3d |
| Phase 3 | P0 | test_paddle.gd Scenario G1~G10 + 验证命令（§9/§10） | 0.4d |

单阶段串行即可（依赖序：常量 → 逻辑 → 测试）；无跨阶段阻塞。验证命令：

```bash
godot --path mini-pong/ --headless --script tests/run_tests.gd   # AC2: 全绿（含既有 17 paddle 用例）
godot --path mini-pong/ --headless --quit                        # 无脚本错误
# CI: opencode-review.yml 视觉 E2E（e2e_shots.json 截图断言）     # AC3
```

---

## 9. 测试用例描述

> 只描述测试场景，不写可运行测试代码（implement agent 依据本节实现 Scenario G）。
> 通用前置：`_make_paddle()`（Area2D.new + paddle.gd 脚本）；`_on_score_changed` 直接方法调用驱动（裁决 2，不依赖 autoload）；`_process(delta)` 快进时间（确定性）。

### Scenario G: 连击阈值 / 速度加成 / 恢复（AC1）

- **G1 — 首分不加速（0-1 分正常速度）：** 新 paddle（`_last_player_score == -1`）→ `_on_score_changed(1, 0)` → 断言 `_combo_active == false` 且 `_combo_timer == 2.0`（窗口起算）；随后 `_process(0.016)` 帧位移 == 基速位移（`paddle_speed × 0.016 × move`，无 +20%）
- **G2 — 窗口内再次得分 → 连击成立 + 速度加成：** `_on_score_changed(1, 0)` → `_process(1.5)`（窗口内）→ `_on_score_changed(2, 0)` → 断言 `_combo_active == true`、`_combo_timer == 2.0`（刷新）；`_process(0.016)` 位移 == `paddle_speed × 1.2 × 0.016 × move`（430→516）
- **G3 — 窗口内连续刷新：** 三次得分间隔均 < 2s（如 1.9s / 1.9s）→ 每次得分后 `_combo_active == true` 且 `_combo_timer` 复位 2.0（连击不因中间 AI 得分中断，见 G7）
- **G4 — 窗口过期恢复：** 连击成立后 `_process(2.1)` 无新得分 → 断言 `_combo_active == false`、`_combo_timer == 0.0`；下一帧位移 == 基速位移（430）
- **G5 — 精确窗口边界（2.0s）：** 得分后 `_process(1.999)` 再得分 → `_combo_active == true`（在窗口内）；对照组：得分后 `_process(2.001)` 再得分 → `_combo_active == false`（恰过期，裁决 5）
- **G6 — AI 模式隔离：** `mode = Mode.AI` 构造 → `_ready()` 不崩；`_on_score_changed(2, 1)` 调用后 `_combo_active` 恒 false、`_combo_timer` 恒 0（首行早退）
- **G7 — AI 得分不重置计时（时间窗语义，TF-2）：** `_on_score_changed(1, 0)` → `_process(1.0)` → `_on_score_changed(1, 1)`（AI 得分，玩家分未变）→ `_process(0.5)` → `_on_score_changed(2, 1)` → 断言 `_combo_active == true`（t=1.5 < 2s 窗口，中间 AI 得分不中断）
- **G8 — 重开复位：** 先构造得分序列到 `_last_player_score = 5`、`_combo_active = true` → `_on_score_changed(1, 0)`（模拟 reset 后新局首分）→ 断言 `_combo_active == false`、`_combo_timer == 2.0`（复位后窗口重新起算，Flow 4）
- **G9 — 冻结期间不衰减：** 连击成立（`_combo_timer = 2.0`）→ `set_frozen(true)` → `_process(2.5)` × 多帧 → 断言 `_combo_timer` 仍 == 2.0（冻结期不衰减）；`set_frozen(false)` → `_process(2.1)` → 断言恢复基速（裁决 1）
- **G10 — 无 autoload 上下文不崩：** 构造 paddle 且不提供 GameManager → `_ready()` 无异常（null-guard 跳过连接）→ `_on_score_changed` 手动调用仍可驱动状态；`_process` 以基速运行

### Scenario C: 常量纪律与既有门（回归）

- **C1 — 常量追加不改既有行：** `test_constants.gd` TC6-1~12 保持绿（既有字面值零触碰）；新增断言 `CONSTS.COMBO_WINDOW_SECONDS == 2.0`、`CONSTS.COMBO_SPEED_BONUS == 0.2`（±0.01）
- **C2 — 既有 paddle 用例回归：** TC-A1~F4 全部保持绿（移动/夹取/实例宽度/实例速度不受影响；`paddle_speed` 语义未变，TC-F3 源码断言仍成立）

### Scenario E: 运行时与视觉（AC2 / AC3）

- **E1 — playthrough 通过：** `run_tests.gd` 全绿（含 e2e_playthrough #394、auto_play #297）—— 连击逻辑不影响 AI vs AI 一局完成
- **E2 — 无脚本错误：** `godot --path mini-pong/ --headless --quit` 退出码 0、无 script error
- **E3 — 视觉 E2E 通过：** e2e_shots.json 截图断言全绿（连击无渲染侧改动 → 纯回归门）

---

## 10. 验收条件映射（AC checklist，源自 Issue #504 body）

| 验收 | 来源 | 落实 |
|------|------|------|
| AC1: 速度逻辑有单元测试（连击阈值/速度加成/恢复） | issue body 验收 1 | §9 Scenario G1~G5（阈值 2s/加成 +20%/恢复）+ G6~G10 边界；PRD §5.1 G1~G5 全部覆盖并扩展 |
| AC2: 运行时 playthrough 通过（游戏可玩，无回归） | issue body 验收 2 | §9 E1/E2；`run_tests.gd` 全绿 + `--headless --quit` 无脚本错误 |
| AC3: 视觉 E2E 通过（截图断言真实渲染） | issue body 验收 3 | §9 E3；CI 视觉 E2E（e2e_shots.json）全绿 |
| 范围: 只改 PlayerPaddle 相关代码 + 测试，不动 AI 板和雨幕 | issue body 范围 | §3.4 PR 白名单 3 文件；AI 分支零改动（G6）；雨幕/记分/球/tscn 零修改（§6 红线复述） |
| 数值字面执行: 2s 窗口 / +20% 倍率 | PRD §1.4 | §3.2 `COMBO_WINDOW_SECONDS=2.0` / `COMBO_SPEED_BONUS=0.2` |
