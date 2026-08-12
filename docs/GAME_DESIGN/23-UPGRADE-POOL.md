# Upgrade Pool — 升级池 (Rogue-lite 成长系统)

> Reference: ../DESIGN/387-upgrade-pool-architecture.md · PRD ../PRD/387-upgrade-pool-architecture.md
> Merged: #423 (2026-08-13) · Issue #387

## Overview

The Upgrade Pool is the **per-wave growth decision system** of PONG://NEON — the
rogue-lite layer that lets each wave run change the paddle/ball/grid. It is the
data hub (autoload `UpgradePool`) between wave settlement (#386, not yet wired) and
the 3-choice UI (#388, not yet wired): the pool does **not** trigger flow itself.

Conceptual layering: `GameManager` (#293) owns score/game/match; `UpgradePool`
owns per-wave growth decisions.

## Architecture

```
UpgradePool (autoload, registered in project.godot)
├── upgrade_defs.gd      # 9 定义 — 单一事实源 (id/稀有度/max_stacks/effect 回调)
├── constants.gd         # 60/30/10 权重 + 候选数 3 + JSON 路径
├── brick_upgrade_hooks.gd  # 砖类效果契约 (open_hole / blast_neighbors)
└── assets/content/upgrade_pool.json  # #395 显示名只读覆盖 (taste 域)
```

- **目标解析**: 惰性 + 可注入 — `ball_ref`/`paddle_ref`/`grid_ref` 从组
  (`balls`/`paddles`/`breakout_grids`) 解析，测试可直接注入假对象覆盖。
- **#384 未落地** → grid 类效果判空 no-op（不崩溃），hook 侧契约先行。
- **rng 可 seed()** — 测试/自动对打确定性。

## 抽取规则 (AC2, 60/30/10)

`get_candidates(n)` — 每张卡独立走一次稀有度先掷 → 稀有度内均匀选 → 候选内 id
去重 → 回退链 `[COMMON → RARE → LEGENDARY]` 取第一个非空稀有度。

| 掷骰 | 稀有度 | 权重 |
|------|--------|:----:|
| 1–60 | COMMON | 60% |
| 61–90 | RARE | 30% |
| 91–100 | LEGENDARY | 10% |

> 研究 spike 已证伪"升级粒度加权无放回"（边际分布漂移到 55.7/37.8/6.5）— 故采用
> 稀有度先掷 + 稀有度内均匀选，精确保持 60/30/10。

## 9 升级定义

| id | 名称 | 稀有度 | max_stacks | 效果 |
|----|------|:------:|:----------:|------|
| long_arm | 长臂 | COMMON | 3 | 挡板宽度 +30%（对基数加算） |
| fireball | 燃烧弹 | COMMON | 3 | 球速 +10%，破砖烧碎相邻砖 |
| battering_ram | 破城锤 | COMMON | 3 | 破砖冲击波，碎邻近砖 |
| magnet_core | 磁心 | RARE | 2 | 挡板磁力吸球 |
| twin | 双生 | RARE | 1 | 球分裂为二（桩） |
| slow_time | 缓时 | RARE | 2 | 球速冻结 2 秒后恢复 |
| pre_hole | 预开洞 | RARE | 1 | 下波砖墙预开洞（经 hooks） |
| stardust | 星尘 | LEGENDARY | 1 | 穿墙轨迹伤害（桩） |
| phantom | 幻影 | LEGENDARY | 1 | 挡板残影多段判定（桩） |

**桩决策 (§3.1)**: twin/stardust/phantom 本期为可调用、可断言、不崩溃的桩 —
写 `stub_activated` 标记 + push_warning，完整实现随 #384 落地后独立小 PR 深化。
机械数值（LONG_ARM_STEP 0.3 / FIREBALL_SPEED_MULT 1.1 / 半径 / 缓时 2s）为占位，
taste 数值归 #395 / PLAN-rogue-pong §2.5。

## apply 链路 (AC5)

```
apply(id) → by_id 查定义 → 可用性检查 (max_stacks 未达上限)
         → _build_ctx() (ball/paddle/grid 惰性解析 + pool 引用)
         → def.effect.call(ctx)   # 效果只写实例属性 → 下一帧 _process 生效
         → stacks[id]++ → 达上限移出池 (整局不可重复) → upgrade_applied 信号
```

失败路径 (DESIGN §6): 未知 id / 已耗尽 → `false`，不计数不 emit。

## 参数实例化 (AC3)

paddle.gd: `const SPEED/PADDLE_WIDTH/PADDLE_HEIGHT` → `@export` 实例属性（默认值仍 =
CONSTS，#367 定稿值不变）+ `set_paddle_width(w)`（同步 CollisionShape2D.size.x +
边界重算 + clamp）+ `base_paddle_width`（长臂加算基准）+ 磁心 `magnet_enabled`/
`magnet_pull_radius`/`magnet_pull_strength`。

ball.gd: `speed_scale` + `set_speed_scale_timed(scale, duration)`（定时恢复，
不依赖 SceneTreeTimer，headless 可测）+ `add_to_group("balls")`。

## upgrade_hooks 契约 (AC4, #384 未落地)

`brick_upgrade_hooks.gd` 向 grid 注册 `open_hole` / `blast_neighbors`。注册时机归
grid 侧（#384 `BreakoutGrid._ready()` 调 `register_all(self)`），分发经
`grid.apply_upgrade_hook(id, ctx)`。不修改 #384 DESIGN 已合并的 API
（generate_wave/clear_wall/brick_destroyed/wall_cleared）。

## 显示名只读消费 (#395)

`upgrade_pool.json`（schema `upgrade-pool-content/v1`）→ FileAccess +
JSON.parse_string + 逐级兜底（缺失/解析失败/schema 不符/缺字段 → 工作名 +
push_warning 至多一次）。display 字段经 `get_candidates()` 候选项透出给 UI。
