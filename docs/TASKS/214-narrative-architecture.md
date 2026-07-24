# Tasks: #214 — 叙事架构 — 博尔赫斯风格约束与三层表达

> Parent Issue: #214
> Agent: plan-agent
> Date: 2026-07-25
> Priority: critical
> Estimated Duration: 3–5 days (Implement Phase)
> Prerequisites: #213 (雨夜普罗摩茨项目骨架 ✅)
> Design Reference: `docs/DESIGN/214-narrative-architecture.md`

---

## Task Breakdown

### Phase 1: 核心引擎扩展 (Core Engine Extension)

**Rationale:** 叙事架构的运行时依赖必须在内容创作之前完成。幻觉等级计算和视觉参数映射是文本创作的基础设施。

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 1.1 | 添加幻觉等级常量 | 在 constants.gd 中添加场景→基础等级映射字典、幻觉等级范围常量、路线 ID 枚举 | `gdscripts/constants.gd` | — | 0.25 h |
| 1.2 | 幻觉等级计算 | 在 NarrativeManager 中添加 get_hallucination_level()，实现 base_level + state_modifier 计算逻辑，发射 hallucination_level_changed 信号 | `gdscripts/narrative_manager.gd` | 1.1 | 0.5 h |
| 1.3 | B1 约束运行时跟踪 | 在 NarrativeManager 中添加不可靠叙述比例跟踪 (节点可靠性标签计数) | `gdscripts/narrative_manager.gd` | 1.2 | 0.25 h |
| 1.4 | 幻觉→视觉参数映射 | 在 WorldviewController 中添加 get_hallucination_params() 和 apply_hallucination_effects()，实现 0–4 级视觉参数 (Vignette, 雨粒子密度, 灯光闪烁) | `gdscripts/worldview_controller.gd` | 1.2 | 1 h |
| 1.5 | 幻觉闪切触发 | 在 NarrativeManager 中添加 trigger_reality_flashback()，幻觉 ≥5 时随机触发 | `gdscripts/narrative_manager.gd` | 1.2 | 0.5 h |
| 1.6 | 验证幻觉引擎 | 运行 `godot --headless --quit`，测试幻觉等级计算和闪切触发 | `gdscripts/narrative_manager.gd`, `gdscripts/worldview_controller.gd` | 1.2–1.5 | 0.25 h |

### Phase 2: 路线选择系统 (Route Selection System)

**Rationale:** 三条路线的分支逻辑依赖于状态系统。必须先实现 C01–C07 的选择点和路线标记。

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 2.1 | 路线状态标记 | 在 StateSystem 中添加 route_flag 属性 (keep_walking / turn_back / stay)，ChoiceEffect 中实现 SET_ROUTE flag | `gdscripts/state_system.gd` | — | 0.5 h |
| 2.2 | C01–C06 选择点 | 为 6 个场景各添加一个关键选择点，使用现有 dialogue_runner 的 choice/effect 系统 | `dialogues/json/*.json` (6 files) | 2.1 | 1.5 h |
| 2.3 | C07 路线分支 | 在地铁站入口添加三分支选择点，触发 route_flag 设置 | `dialogues/json/subway_station.json` | 2.1–2.2 | 0.5 h |
| 2.4 | 路线文本链验证 | 验证三条路线的 6 场景文本链完整，每场景 tone 标记匹配情感曲线 | `dialogues/json/*.json` | 2.2–2.3 | 0.5 h |

### Phase 3: 对话内容创作 (Dialogue Content Creation)

**Rationale:** 最大工作量。根据约束规范 B1–B6 重写 6 场景对话，实现三层表达。

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 3.1 | 场景文本约束标记 | 为 6 场景的 Narrator 台词添加 reliability 标签 | `dialogues/json/*.json` | 1.3 | 1 h |
| 3.2 | L1/L2 文本创作 — Route A | 按约束规范创作 Keep Walking 路线的 6 场景文本链 (>20 节点)，所有节点满足 L1 + L2 | `dialogues/json/*.json` | — | 3 h |
| 3.3 | L3 回声表设计 | 在 constants.gd 中定义 ≥5 处跨场景回声 (回声 ID, 源场景, 目标场景, 触发条件, 文本变体) | `gdscripts/constants.gd` | 1.1 | 0.5 h |
| 3.4 | Route B 差异文本创作 | 从 Route A 拷贝基础对话 JSON，仅修改差异节点 (估计 30% 文本不同) | `dialogues/json/*.json` | 3.2 | 1.5 h |
| 3.5 | Route C 差异文本创作 | 同上，Route C 差异文本 | `dialogues/json/*.json` | 3.2 | 1.5 h |
| 3.6 | L3 回声集成 | 将回声定义接入 EchoManager，验证触发条件和文本变体正确 | `gdscripts/constants.gd`, `gdscripts/narrative_manager.gd` | 3.3, 1.2 | 0.5 h |

### Phase 4: 视觉与后 MVP 扩展 (Visual & Post-MVP Expansion)

**Rationale:** 幻觉级别 5+ 需要额外的 shader 和粒子扩展，非 MVP 必要但需要基础设施。

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 4.1 | 雨方向随机化 | 在 RainController 中添加 rain_direction_noise 参数，连接 worldview 幻觉映射 | `gdscripts/rain_controller.gd` | 1.4 | 0.5 h |
| 4.2 | 文字抖动 shader | 为 Label3D 创建文字抖动/漂移 shader，通过 worldview 参数控制 | `scenes/components/`, materials | 1.4 | 1 h |
| 4.3 | SubViewport 叠加 (后 MVP) | 为幻觉 9–10 级实现场景叠加系统 | `scenes/`, `gdscripts/` | 1.4 | 2 h |
| 4.4 | 全场景幻觉参数调优 | 遍历 6 场景，为各幻觉等级调优视觉参数值 | 所有场景 + worldview | 4.1–4.2 | 1 h |

### Phase 5: 约束合规性验证 (Constraint Compliance Validation)

**Rationale:** 所有内容创作完成后，运行完整验证。

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 5.1 | B1–B6 约束扫描 | 编写 GDScript 脚本扫描对话 JSON，验证 6 条约束的合规性 | `tests/` (新文件) | 3.1–3.5 | 0.5 h |
| 5.2 | Hemingway 合规检查 | 确保所有文本节点满足 25 字符/句、3 句/节点 | `tests/` (新文件) | 3.1–3.5 | 0.25 h |
| 5.3 | 三层表达完整性检查 | 验证每场景至少 1 处 L1/L2 示例节点，回声表 ≥5 处 | `tests/` (新文件) | 3.2, 3.3, 3.6 | 0.25 h |
| 5.4 | Godot 编译验证 | `godot --path rainy-night-prometheus/ --headless --quit` | 全部 | 1–4 全部 | 0.1 h |

---

## Dependency Graph

```ascii
Phase 1: Core Engine
  1.1 (constants)
    └─ 1.2 (hallucination level)
         ├─ 1.3 (B1 tracking)
         ├─ 1.4 (visual mapping)
         │    ├─ 4.1 (rain direction)    ── Phase 4 (post-MVP visual)
         │    ├─ 4.2 (text drift shader)
         │    └─ 4.3 (SubViewport)
         └─ 1.5 (flashback)
              └─ 1.6 (verify)
                    │
Phase 2: Route System
  2.1 (state route flag)
    ├─ 2.2 (C01–C06 choices)
    │    └─ 2.3 (C07 branch)
    │         └─ 2.4 (chain verify)
    │
Phase 3: Content Creation ── (parallel with Phase 1/2 for text planning)
  3.1 (reliability tags)
  3.2 (Route A text) ───────── 3.4 (Route B diff) ─┐
                              ├─ 3.5 (Route C diff) ─┤
  3.3 (echo table) ───────── 3.6 (echo integration) ─┤
                                                     │
Phase 5: Validation ◄────────────────────────────────┘
  5.1 (B1–B6 scan)
  5.2 (Hemingway check)
  5.3 (three-layer check)
  5.4 (Godot compile)
```

---

## Summary — File Changes

| File | Type | Change | Est. Lines |
|------|------|--------|:----------:|
| `gdscripts/constants.gd` | Modify | 幻觉等级常量、路线 ID、回声定义 | +20 |
| `gdscripts/narrative_manager.gd` | Modify | 幻觉等级计算、B1 跟踪、闪切触发 | +50 |
| `gdscripts/worldview_controller.gd` | Modify | 幻觉→视觉参数映射 | +40 |
| `gdscripts/rain_controller.gd` | Modify | 雨方向随机化参数 (后 MVP) | +15 |
| `gdscripts/state_system.gd` | Modify | route_flag 属性、SET_ROUTE effect | +10 |
| `dialogues/json/*.json` | Modify | 6 场景对话按约束重写 (Route A + B + C) | ~800 |
| `scenes/components/text_drift_shader.gdshader` | New | 文字抖动 shader (后 MVP) | ~30 |
| `tests/test_narrative_constraints.gd` | New | 约束合规性验证 | ~100 |
| **Total** | | | **~1065** |
