# 复盘：都市夜行人 集成测试失败全记录

> **时间：** 2026-07-24
> **引擎：** Godot 4.7.1
> **场景：** 实现 agent 生成完整场景链后的首次实机游玩测试

## 问题清单

### 1. 碰撞系统（Critical — 玩家无法在任何场景行走）

| # | 问题 | 场景 | 根因 | 修复 |
|---|------|------|------|------|
| 1 | 按空格下坠 | `office.tscn` | 5 个 CollisionShape3D 节点的 `shape` 字段为空（`shape = null`） | 为每个 CollisionShape3D 添加对应 sub_resource 引用 |
| 2 | 墙壁可穿过 | `office.tscn` | 只有一面后墙（BackWall），左右两侧和前墙（门两侧）完全无碰撞体 | 添加 LeftWall、RightWall、FrontWallLeft、FrontWallRight |
| 3 | 跳转后下坠 | `lobby.tscn` | 场景中 **0 个 StaticBody3D**，只有 Area3D 触发器，无地板 | 添加 Floor (StaticBody3D + CollisionShape3D + BoxShape) |
| 4 | 跳转后下坠 | `subway_station.tscn` | 同上，0 个 StaticBody | 添加地板 |
| 5 | 视觉可见但无碰撞 | `bridge.tscn` | BridgeDeck/Railing/CanalSurface 的 CSGBox3D 子节点缺少 `use_collision = true` | 为 5 个 CSGBox3D/CSGCylinder3D 添加 use_collision |
| 6 | 视觉可见但无碰撞 | `street.tscn` | StreetSurface/BuildingLeft/Right/StoreFront 的 CSGBox3D 缺少 use_collision | 加 use_collision |
| 7 | 视觉可见但无碰撞 | `underpass.tscn` | 5 个 CSGBox3D 缺少 use_collision | 加 use_collision |
| 8 | 视觉可见但无碰撞 | `convenience_store.tscn` | 4 个 CSGBox3D 缺少 use_collision（Floor、Counter、Shelving） | 加 use_collision |

**根因模式：** 场景的视觉资产（CSGBox3D）被用作几何体，但 collision 开关没有打开；或者直接缺失 StaticBody3D + CollisionShape3D。

### 2. 输入系统（Critical — WASD 完全无效）

| # | 问题 | 文件 | 根因 | 修复 |
|---|------|------|------|------|
| 9 | `move_forward` 按键没绑定 | `project.godot` | `[input]` 节中 `move_forward` 前有一条 `#` 注释行，Godot 4.7 的 INI 解析器跳过此条目 | 移除注释行，去 tab 缩进，与其他 entry 格式一致 |
| 10 | InputMap events 解析为空 | `project.godot` | 即使去掉注释后，`InputMap.has_action()` 返回 true 但 `InputMap.action_get_events()` 返回空数组。Godot 4.7 的 INI 解析器在 `[input]` 节有 **持久化 bug**：键绑定事件不加载 | 在 PlayerController._ready() 中用代码手动绑定 InputMap：`InputMap.action_add_event()` |
| 11 | 门上写着 (E) 但按 E 没反应 | `office.tscn` | OfficeDoorTrigger 只监听了鼠标点击 (`input_event`)，没有挂 EKeyTrigger | 添加 EKeyTrigger 子节点 + 连接信号 |
| 12 | EKeyTrigger 无法检测玩家 | `office.tscn` | EKeyTrigger 是 Area3D 但没有 CollisionShape3D 子节点，无法触发 `body_entered` | 添加 CollisionShape3D + BoxShape |

### 3. Player Controller 初始化（Severe — 玩家角色不生成）

| # | 问题 | 文件 | 根因 | 修复 |
|---|------|------|------|------|
| 13 | PlayerController 报错后被移除 | `player_controller.gd` | `@onready var head: Node3D = $Head` 在 `_build_node_tree()` 执行之前运行，找不到节点 → Godot 4.7 将此视为运行时错误 → PlayerController 被移出场景树 | 将 `@onready var` 改为普通 `var`，在 `_ready()` 中建完节点后手动赋值 |

### 4. 场景过渡系统（Medium — 过渡体验不完整）

| # | 问题 | 文件 | 根因 | 状态 |
|---|------|------|------|------|
| 14 | 对话到场景过渡 | `scene_manager.gd` | 通过 `choice_made` 信号 + 读 choice 的 `"scene"` 字段触发场景切换 | ✅ 逻辑正确，无需修复 |
| 15 | SceneManager 在每个场景中存在 | 各 .tscn | 每个场景都有 SceneManager + FadeCurtain | ✅ 正确 |
| 16 | main.gd → office 跳转用 change_scene_to_file | `main.gd` | 标题画面→办公室使用 `change_scene_to_file()`，这会摧毁整个场景树 | ⚠️ 工作正常但架构上需注意 |

---

## 归纳：Checklist 模板

### 对所有含 3D 场景的 Issue

```markdown
## 技术验证清单

### Collision
- [ ] 每个 StaticBody3D 是否有 CollisionShape3D 子节点且 shape != null？
- [ ] 每个 CSGBox3D/CSGCombiner3D 是否需要 `use_collision = true`？
- [ ] 场景是否有至少一个地板/站立面？
- [ ] 玩家 SpawnPoint 下方是否有碰撞体？
- [ ] 场景边界是否有墙壁/围栏防止玩家走出世界？

### Input
- [ ] InputMap actions 是否在 `_ready()` 中用代码绑定？
- [ ] E-key 交互：EKeyTrigger 是否有 CollisionShape3D？
- [ ] @onready 变量是否只引用 .tscn 中静态存在的节点？

### Player Controller 集成
- [ ] 场景继承 SceneBase？→ 自动创建 PlayerController
- [ ] 场景是否有自己的 Camera3D？→ 是否与 PlayerController 的相机冲突？
- [ ] 是否有 SpawnPoint Marker3D？→ 玩家初始位置

### 场景过渡
- [ ] 场景是否有 SceneManager 子节点？
- [ ] 对话 "scene" 字段路径正确？
- [ ] 目标场景是否有地板？
- [ ] 目标场景会触发 `_instantiate_player()`（继承 SceneBase）？
```

---

## 场景碰撞完整性自动化检查

```python
# 在每个场景 Issue 的验收条件中包含：
# 所有 3D 游戏场景的碰撞完整性验证
# 运行：python3 scripts/check_collision.py

import os, re

minimal_scenes = ['office', 'lobby', 'street', 'store', 
                  'bridge', 'underpass', 'subway_station']

for scene_name in minimal_scenes:
    path = f'scenes/{scene_name}/{scene_name}.tscn'
    if not os.path.exists(path):
        # 尝试直接搜索
        pass
    with open(path) as f:
        content = f.read()
    
    sb = len(re.findall(r'type="StaticBody3D"', content))  # 物理体
    cs = len(re.findall(r'type="CollisionShape3D"', content))  # 碰撞形状
    csg_col = len(re.findall(r'use_collision = true', content))  # CSG碰撞
    
    has_floor = (sb > 0 and cs > 0) or csg_col > 0
    print(f"{scene_name}: SB={sb} CS={cs} CSGcol={csg_col} Floor={'✅' if has_floor else '❌'}")
```
