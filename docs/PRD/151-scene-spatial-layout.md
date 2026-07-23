# Research: Scene Spatial Layout — 为所有 3D 文本对象分配正确坐标

> Parent Issue: [#151](https://github.com/devvi/agent-game-test/issues/151)
> Agent: research-agent
> Date: 2026-07-24
> Label: `workflow/research`
> Dependency: #149 (Player Controller — PR #176, 已合并)

---

## 1. 概述 (Title & Overview)

本文档为 Issue #151 ("Scene Spatial Layout — Place all 3D text objects at correct coordinates") 的 PRD，研究如何为当前全部堆积在原点 (0,0,0) 的 3D 环境文本对象分配正确的空间坐标，使其沿玩家行走路径合理排布。

### 受影响的文本对象

| 对象名 | 类型 | 定义位置 | 当前坐标 | 继承轴 |
|--------|------|----------|----------|--------|
| `WorldLabel` | Label3D | `scenes/main.tscn` | (0, 0, -5) | — |
| `RainText` | RainText (extends TextComponentBase) | `scenes/components/rain_text.tscn` + `gdscripts/rain_text.gd` | (0, 0, 0) | hope |
| `LamppostText` | LamppostText (extends TextComponentBase) | `scenes/components/lamppost_text.tscn` + `gdscripts/lamppost_text.gd` | (0, 0, 0) | will |
| `PuddleText` | PuddleText (extends TextComponentBase) | `scenes/components/puddle_text.tscn` + `gdscripts/puddle_text.gd` | (0, 0, 0) | hope |
| `NeonSign` | NeonSign (extends TextComponentBase) | `scenes/components/neon_sign.tscn` + `gdscripts/neon_sign.gd` | (0, 0, 0) | conviction |

### 当前场景结构 — 文本对象的实际使用情况

| 场景文件 | 使用的 Label3D | 来源 |
|---------|---------------|------|
| `main.tscn` | `WorldLabel` (visible=false, debug) | 直接定义 |
| `street.tscn` | NeonSign, Graffiti, StreetSign (直接 Label3D) | 直接定义 |
| `lobby.tscn` | EntranceText, StrangerSpotlight (直接 Label3D) | 直接定义 |
| `bridge.tscn` | TrafficText, HomelessText, RainBridgeText (直接 Label3D) | 直接定义 |
| `underpass.tscn` | GraffitiText, EchoText, UnderpassLightText (直接 Label3D) | 直接定义 |
| `convenience_store.tscn` | OpenSign, ShelfLabels (直接 Label3D) | 直接定义 |

**关键发现：** 组件化的 `.tscn` 场景文件 (`rain_text.tscn` 等) 已创建但**未被任何场景实例化**。现有场景使用内联的 Label3D 节点，不继承 TextComponentBase 的 5 态变体能力。

---

## 2. 现状 (Current State / Motivation)

### 问题

1. **所有组件化文本对象在原点堆积** — `rain_text.tscn`, `lamppost_text.tscn`, `puddle_text.tscn`, `neon_sign.tscn` 四个组件场景的位置均为 `(0, 0, 0)`，且未被任何场景引用。

2. **WorldLabel 位置固定** — `main.tscn` 中的 WorldLabel 位置为 `(0, 0, -5)`，但 `visible = false`（已被 StatusBar 取代），作为 debug 文字保留。

3. **现有场景使用内联 Label3D** — street.tscn 等场景直接定义了 Label3D 节点，不使用 component .tscn 文件。这些 Label3D 使用普通 Label3D 类型，**没有** TextComponentBase 的 5 态变体切换能力。

4. **缺少统一的空间规划** — 没有文档说明文本对象应该放置在场景的何处、何高度、面向何方向。

### 为什么现在要改

- Issue #154（5 态环境文本系统）已创建组件化文本场景（rain_text.tscn 等）和变体资源（.tres 文件），但**放置阶段**被跳过
- 玩家控制器 (#149, PR #176) 已合并 — 玩家现在可以沿行走路径通过场景
- 场景序列完整（office → lobby → store → bridge → underpass → subway_station），但环境文本组件的空间布局尚未定义
- 组件化文本对象的 5 态变体能力比内联 Label3D 更强大（自动色调转换、淡出动画）

---

## 3. 设计上下文 (Design Context)

### 3.1 行走路径定义

根据 GDD 06-NARRATIVE.md，叙事路径为：

```
办公室 (office)
  │
  ▼
大厅 (lobby)
  │
  ▼
便利店 (convenience_store)
  │
  ▼
天桥 (bridge)
  │
  ▼
地下通道 (underpass)
  │
  ▼
地铁站 (subway_station) → 结局
```

### 3.2 玩家控制器参数

从 `player_controller.gd`：
- `walk_speed = 2.5 m/s` — 叙事步行速度
- `camera_height = 1.6m` — 视线高度
- 玩家为 CharacterBody3D，碰撞体 CapsuleShape3D: radius=0.3, height=1.4

### 3.3 场景尺寸参考

| 场景 | 地面尺寸 | 关键区域坐标 |
|------|---------|-------------|
| `street.tscn` | CSGBox3D: (12, 0.2, 10) | SpawnPoint: (0, 0, -3), StoreFront: (4, 1, 2), Streetlamp: (3, 0, -3) |
| `convenience_store.tscn` | CSGBox3D: (10, 0.2, 8) | Counter: (0, 0.5, -2), ExitTrigger: (0, 0.5, 5) |
| `lobby.tscn` | 暂无地面几何体 | 仅有 Area3D triggers |

### 3.4 文本组件系统架构

TextComponentBase 继承关系：
```
Label3D
  └── LoFiText3D (gdscripts/lo_fi_text_3d.gd)
        └── TextComponentBase (gdscripts/text_component_base.gd)
              ├── RainText (gdscripts/rain_text.gd) — hope 轴
              ├── LamppostText (gdscripts/lamppost_text.gd) — will 轴
              ├── PuddleText (gdscripts/puddle_text.gd) — hope 轴
              └── NeonSign (gdscripts/neon_sign.gd) — conviction 轴
```

### 3.5 现有内联 Label3D 位置参考

| 场景 | 内联 Label3D 节点 | 位置 |
|------|------------------|------|
| street.tscn | Environments/NeonSign | (4.5, 2.5, 3) |
| street.tscn | Environments/Graffiti | (-4.5, 0.5, 3) |
| street.tscn | Environments/StreetSign | (2, 2, -3) |
| store.tscn | Environments/OpenSign | (0, 2.5, -3) |
| store.tscn | Environments/ShelfLabels | (-3, 1.5, 2) |

---

## 4. 需求 (Requirements)

### R1: 组件化文本对象位置定义

为每个组件化文本对象定义在**目标场景**中的 `position` 和（如需要）`rotation`。

| 对象 | 推荐放置场景 | 推荐位置 | 高度理由 | 语义 |
|------|------------|---------|---------|------|
| `WorldLabel` | `main.tscn` | (0, 0, -5) — 保持现有位置 | 相机正前方 5m | Debug HUD，visible=false |
| `RainText` | `street.tscn` → 室外 | (3, 2.5, 0) | 视线高度 (1.6m) + 微抬头 | 雨水文字在街道中央上方的雨幕中 |
| `LamppostText` | `street.tscn` → 路灯旁 | (3, 1.5, -3) | 路灯杆高度一半 (Pole 高 3m) | 路灯杆上的文字标识 |
| `PuddleText` | `street.tscn` → 地面 | (0, 0.1, 2) | 地面略高 (+0.1m 避免 z-fighting) | 地面水坑倒影文字 |
| `NeonSign` | `street.tscn` → 店门口 | (4.5, 2.5, 3) | 参照现有内联 Label3D 位置 | 便利店霓虹招牌 |

### R2: 场景实例化

将所有组件化文本对象作为 `PackedScene` 实例化到目标场景中，替换或补充现有的内联 Label3D。

### R3: 向后兼容

- 现有内联 Label3D 节点保留（Graffiti, StreetSign, OpenSign 等）
- WorldLabel 保持 `visible = false`（debug 模式）
- 不改变场景脚本（street.gd 等）的 node path 引用

### R4: 坐标单位规范

所有坐标使用 Godot 单位（米），以场景原点 (0,0,0) 为基准：
- Y+ 向上，Z+ 指向玩家前进方向
- 文本对象 Y 坐标 = 视线高度（~1.6m）适用阅读文本；地面文本 Y = 0.1m

---

## 5. 验收标准 (Acceptance Criteria)

### AC1: 组件文本对象在场景中可见且位置正确
- [ ] `RainText` 实例出现在 street.tscn 的 (3, 2.5, 0)，Billboard 面向玩家
- [ ] `LamppostText` 实例出现在 street.tscn 的 (3, 1.5, -3)，靠近 Streetlamp 几何体
- [ ] `PuddleText` 实例出现在 street.tscn 的 (0, 0.1, 2)，在地面高度
- [ ] `NeonSign` 实例出现在 street.tscn 的 (4.5, 2.5, 3)，与霓虹内联 Label3D 同位置
- [ ] `WorldLabel` 在 main.tscn 的 (0, 0, -5)，visible=false

### AC2: 5 态变体功能正常
- [ ] 每个组件化文本对象连接了 StateSystem / NarrativeManager 信号
- [ ] 状态变化时文本内容和视觉效果（发光、颜色）按变体 .tres 文件切换
- [ ] Tween 淡转动画正常（0.3s 淡出→切换→淡入）

### AC3: 不破坏现有场景
- [ ] 现有内联 Label3D（Graffiti, StreetSign, OpenSign 等）位置和功能不变
- [ ] 场景脚本的 node path 引用未被破坏
- [ ] 玩家行走路径不受影响（文本对象是 Label3D，无碰撞体）

### AC4: 多场景一致性
- [ ] 如果有文本对象需要在多个场景出现（如 RainText 在 street 和 bridge 都有），每个实例获得独立坐标

---

## 6. 开放式问题 (Open Questions)

### Q1: 内联 Label3D vs 组件实例化策略
现有场景（street.tscn、lobby.tscn 等）使用内联 Label3D。应该用组件场景替换它们，还是只在新位置添加组件实例？

**可能方案：**
- **方案 A（替换）：** 将内联 Neonsign/Graffiti 替换为 NeonSign/RainText 组件实例，保留现有位置 — 获得 5 态变体能力，但有破坏现有场景脚本 node path 的风险
- **方案 B（并排）：** 保持内联 Label3D 原样，仅在需要 5 态变体的位置添加组件实例 — 零风险但引入冗余
- **方案 C（脚本接管）：** 不修改 .tscn，让场景脚本在 `_ready()` 中创建组件实例并放置 — 最灵活但偏离现有模式

**初步建议：** 方案 A 或 B，取决于 Plan 阶段的具体技术评估。

### Q2: 哪些场景需要 RainText 实例？
Rain 是贯穿多个场景的意象。雨文字应该只在 street 出现，还是在 street + bridge（以及未实现的 office lobby 等）都有？

**建议：** street 作为首次室外场景安装 RainText 组件。其他场景的 RainText 由后续 Issue 处理。

### Q3: LamppostText 在 street 的精确位置？
Streetlamp 几何体位于 (3, 0, -3)，Pole 高 3m。LamppostText 应挂在 Pole 上还是独立站立？

**建议：** 放置在 Pole 侧面，位置 (3, 1.5, -3)，面向玩家路径。Billboard 模式确保可读性。

### Q4: WorldLabel 的未来？
WorldLabel 已被 StatusBar (#53) 取代。是否应为不影响调试而保留，还是可以移除？

**建议：** 保持 `visible = false`，保留为 debug 调试用。移除不属于本 Issue 范围。

### Q5: PuddleText 在 street 的精确地面位置？
Puddle 是地面反射文字。是否应放在 spawn point 附近让玩家立即看到，还是放在路径中途？

**建议：** 放在玩家从 SpawnPoint (0, 0, -3) 向前走到 (0, 0, 2) 时的地面 — 玩家接近商店入口前看到。

---

## 7. 实现笔记 (Implementation Notes)

### 7.1 场景修改范围

**`scenes/street.tscn`** 修改：
1. 添加新节点，实例化 `rain_text.tscn` → 位置 (3, 2.5, 0)
2. 添加新节点，实例化 `lamppost_text.tscn` → 位置 (3, 1.5, -3)
3. 添加新节点，实例化 `puddle_text.tscn` → 位置 (0, 0.1, 2)
4. 添加新节点，实例化 `neon_sign.tscn` → 位置 (4.5, 2.5, 3)

**`scenes/main.tscn`** 修改：
- WorldLabel 已就位，`visible=false` — 无需修改

组件实例化语法：
```gdscript
[ext_resource type="PackedScene" path="res://scenes/components/rain_text.tscn" id="n_rain_text"]
[node name="RainText" parent="Environments" instance=ExtResource("n_rain_text")]
position = Vector3(3, 2.5, 0)
```

### 7.2 依赖关系

| 依赖 | 状态 | 说明 |
|------|------|------|
| #149 (Player Controller) | ✅ 已合并 (PR #176) | 玩家行走路径已定义 |
| #154 (5-State Environmental Text) | ✅ 已合并 | 组件化文本系统 + 变体文件已就绪 |
| #142 (Player Controller PRD) | ✅ 已合并 | 玩家控制架构设计 |
| #45 (Narrative Architecture) | ✅ 已合并 | 场景序列定义 |

### 7.3 风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 场景脚本引用了被替换的 Label3D node path | 运行时错误 | 使用方案 B（并排）或根据 node path 确认替换安全 |
| 组件文本的 5 态变体行为与内联文本冲突 | 视觉双影或重叠 | 使用方案 A（替换）确保唯一性 |
| pixel_size 冲突 | 视觉破碎 | 组件 `rain_text.tscn` 的 `pixel_factor=0.5`，内联 Label3D 的 `pixel_size` 不同；叠加可能导致不可预读 |

### 7.4 测试覆盖

| 测试 | 覆盖场景 |
|------|---------|
| 位置正确性 | 每个组件实例在场景树中的 global_position 断言 |
| 可见性 | WorldLabel visible=false 保持 |
| 5 态变体 | 状态变化后文本内容和 emissive 属性按预期更新 |
| 无异常 | 场景加载时不产生 `null reference` 错误 |

### 7.5 输出产物

| 文件 | 动作 | 说明 |
|------|------|------|
| `docs/PRD/151-scene-spatial-layout.md` | ✅ 新建（本文档） | PRD |
| `scenes/street.tscn` | **修改** — 添加 rain/lamppost/puddle/neon 组件实例 | 组件放置 |
| `scenes/main.tscn` | 确认 WorldLabel 已有 | 无修改 |
| `docs/DESIGN/151-scene-spatial-layout.md` | Plan 阶段输出 | Design doc |

---

*本期 Research 阶段完成。下一阶段: Plan → `workflow/plan` 标签。*
