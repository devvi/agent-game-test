# Wave Cycle — 波次循环 (核心循环骨架)

> Reference: ../DESIGN/386-wave-cycle.md · PRD ../PRD/386-wave-cycle.md
> Merged: #428 (2026-08-12) · Issue #386 · 所有权: mechanical（数值曲线归 taste-draft）

## Overview

波次循环是 PONG://NEON 从「单局对打」走向 rogue-pong 核心循环的骨架（PLAN-rogue-pong
§2.1）：砖墙打空（#384 契约 `wall_cleared`）＝一局结束 → 结算（短暂状态，为 #388 升级 UI /
#390 转场提供挂点）→ 自动生成更厚新墙 → 下一波。分工延续 #385 模式：**autoload 持状态 +
信号，场景节点消费编排**。

- `GameManager`（autoload）只做波次**状态持有**：`wave_index` / `wave_state` / 信号 / 查询 API，零场景引用
- `WaveController`（场景节点，与 ScoringManager 同构）消费 `wall_cleared`，驱动状态机、算难度、调 `generate_wave`
- FSM **零改动**：终局仍走既有 `match_over → GAME_OVER` 路径

## 状态机

`GameManager.WaveState` 三态，宿主在 autoload：

```
IDLE ──begin_wave()──► RUNNING ──settle_wave()──► SETTLED ──(WAVE_SETTLE_DELAY 延时)──► begin_wave()…（下一波）
  ▲                                                                                        │
  └──────────────────────end_wave_cycle()（21 分终局停止；wave_index 保留供 run 统计）◄──────┘
```

| 状态 | 语义 | 进入方式 |
|------|------|---------|
| IDLE | 无波次（局前/终局后） | 初始 / `end_wave_cycle()` / `reset_match()` |
| RUNNING | 一波进行中 | `begin_wave()` |
| SETTLED | 墙已清空，结算窗口 | `settle_wave()` |

## 信号契约（#388/#390/#393 消费挂点）

| 信号 | 负载 | 消费方 |
|------|------|--------|
| `wave_started(wave_index)` | 当前波次号 | #390 转场「第 N 道墙」/ #393 HUD |
| `wave_settled(wave_index)` | 当前波次号 | #388 升级 UI 触发时机 |

## API（GameManager）

```gdscript
begin_wave()            # wave_index += 1 → RUNNING → wave_started.emit
settle_wave()           # IDLE 时 no-op；→ SETTLED → wave_settled.emit
end_wave_cycle()        # → IDLE；wave_index 保留（#391 读取 run 波次数）
is_wave_cycle_active()  # wave_state != IDLE
reset_match()           # 追加重置 wave_index=0 / wave_state=IDLE（首波从 1 起）
```

## 常量（constants.gd，WAVE_* 组）

| 常量 | 值 | 意图 |
|------|:--:|------|
| WAVE_START_THICKNESS | 1 | 首波厚度（行数）——机械占位，taste-draft 可调 |
| WAVE_THICKNESS_STEP | 1 | 每波厚度增量（AC2 厚度杠杆） |
| WAVE_MAX_INDEX | 99 | 波次上限防御（21 分制下 AC5 实际远早触发） |
| WAVE_SETTLE_DELAY | 1.0s | 结算 → 下一波自动延时（#388 接线后由其接管推进时机） |
| AI_DIFFICULTY_FACTOR | 0.9 | 每波 AI 参数收紧系数（<1 = 更难；taste-draft 占位） |
| AI_REACTION_DELAY_MIN/MAX_FLOOR | 0.05 / 0.12 | AI 收紧 clamp 下限 |
| AI_POSITION_ERROR_FLOOR | 8.0 | AI 位置误差 clamp 下限 |

## 数据流

### 墙清空 → 结算 → 下一波（AC1/AC3）

```
BreakoutGrid 最后一砖销毁 → wall_cleared()          [#384 契约，整墙只发一次]
  → WaveController._on_wall_cleared()（get_node_or_null 容错连接）
     ├─ guard: _settling / GameManager.is_run_over() → return
     → settle_wave() → SETTLED → wave_settled.emit   [#388/#390 挂点]
     → await WAVE_SETTLE_DELAY
     → begin_wave() → wave_index+1 → wave_started.emit  [#390/#393 挂点]
     → _apply_difficulty() → generate_wave(厚度, GAPS, -1)  [内部先 clear_wall → 单实例]
```

### 难度递增（AC2，双杠杆）

- **厚度杠杆**：`thickness = WAVE_START_THICKNESS + (wave_index-1) * WAVE_THICKNESS_STEP`（线性严格递增）
- **AI 杠杆**：`ai_reaction_delay_min/max`、`ai_position_error` 每波 × `AI_DIFFICULTY_FACTOR`，
  clamp 到 FLOOR 下限（触底后持平，厚度杠杆仍严格递增 → AC2 确定性满足）

AI 参数是 paddle.gd 的实例级 `@export`（#387 落地），运行时改实例属性即生效。

### 21 分终局停止（AC5）

最后一砖使一方到 21：`match_over` 先发（brick_destroyed → add_score → _check_run_end）→ FSM
`_on_match_over` → GAME_OVER；`wall_cleared` 后到 → 入口 `is_run_over()` 守卫 return；若已
settle 则 `end_wave_cycle()` → IDLE。**不生成新墙**。

## 容错与边界

- **#384 未接线期**：`get_node_or_null("../BreakoutGrid")` 为 null → `push_warning` + 跳过连接，
  状态机保持 IDLE；直调 `_advance_wave` 时无 `generate_wave` 则跳过生成但 `wave_index` 仍 +1（不卡死）
- **`_settling` 布尔守卫**：结算延时期间忽略重复 `wall_cleared`（配合 #384 的 `_wall_cleared_emitted`）
- **WAVE_MAX_INDEX 防御**：99 波后停止递增与生成（21 分制下正常流程不会到达）
- **AIPaddle 未接线**：跳过 AI 缩放 + push_warning，厚度杠杆仍满足 AC2
- **layout 参数**：字面量 `0`（= BrickLayout.GAPS，注释对齐 #414 契约；不 preload 未落地脚本）

## 集成点状态（merged 时）

| 集成 | 状态 |
|------|:----:|
| BreakoutGrid.wall_cleared → WaveController | ✅ 已接线（容错） |
| wave_started → #390/#393 消费 | ⬜ 下游（#390 转场 / #393 HUD 接线） |
| wave_settled → #388 升级 UI 触发 | ⬜ 下游（#388 接线后接管推进时机） |
| match_over → FSM GAME_OVER | ✅ 既有路径复用 |
| RainCurtain.set_wave_factor(wave_index) | ✅ 已接线（#389 契约，容错） |
| reset_match() → 波次重置 | ✅ 已实现 |

> 数值曲线（厚度增速 / AI 收紧幅度 / 首波厚度）全部为机械占位，调优归 taste-draft Issue。
