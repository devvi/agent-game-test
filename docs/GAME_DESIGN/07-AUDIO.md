# 07. 音频系统（Sound System）

> Issue: #48 — 音频系统
> 状态: ✅ 待合并 (PR #110)
> 实现时间: 2026-07-23

---

## 1. 架构总览

采用**分层音频总线路由 + 场景自适应音量控制**模式。音频管理器（AudioManager）作为 Autoload 运行，管理环境音循环、脚步音效、场景过渡音效及状态调制。

### 核心设计原则

1. **氛围即叙事** — 雨量、城市嗡嗡声、脚步材质映射共同构建场景的情感基调
2. **状态粘合音频** — conviction 影响雨强度，despair 调节失真和音量，音频成为玩家内心状态的外化
3. **场景自适应** — 每个场景注册自己的音效配置文件（室内/室外/地下通道），自动切换总线效果

---

## 2. 音频总线布局

`default_bus_layout.tres` 定义了 5 条总线：

| 总线 | 用途 | 效果 |
|------|------|------|
| Master | 总控 | AudioEffectDistortion（默认关闭，despair > 0.5 时开启） |
| AmbientBus | 环境音（雨声、城市嗡嗡声） | 无 |
| SFXBus | 音效（脚步声） | 无 |
| IndoorBus | 室内场景音效 | AudioEffectLowPassFilter（cutoff=4000Hz） |
| UnderpassBus | 地下通道音效 | AudioEffectReverb（room=0.8）+ AudioEffectLowPassFilter（cutoff=2000Hz） |

### 配置文件切换

- **indoor 配置**：启用 IndoorBus 的低通滤波 → 模拟室内封闭感
- **underpass 配置**：启用 UnderpassBus 的混响+低通滤波 → 模拟隧道回声和闷感
- **outdoor 配置**：不启用任何总线效果 → 保持开放感

---

## 3. AudioManager（音频管理器）

存放位置：`gdscripts/audio_manager.gd`
注册方式：Autoload（`project.godot`）

### 3.1 场景注册表

场景 → 音效配置、脚步表面类型、距离因子映射：

| 场景 | 音效配置文件 | 脚步表面 | 距离因子 |
|------|------------|---------|---------|
| office | indoor | office | 0.0 |
| lobby | indoor | office | 0.2 |
| street | outdoor | street | 0.5 |
| convenience_store | indoor | street | 0.3 |
| bridge | outdoor | street | 0.7 |
| underpass | underpass | underpass | 0.8 |
| subway_station | indoor | street | 1.0 |

### 3.2 环境音层

| 音层 | 资源 | 播放器 | 说明 |
|------|------|--------|------|
| 细雨循环 | rain_loop.wav | RainPlayer | 音量随 rain_intensity * distance_factor 变化 |
| 暴雨循环 | rain_heavy.wav | RainHeavyPlayer | 默认静音（-80dB），despair ≥ 0.5 时渐入 |
| 城市嗡嗡声 | city_hum.wav | CityHumPlayer | 音量随 despair_norm * distance_factor 变化 |

### 3.3 状态调制

通过 `_on_state_changed(state: Dictionary)` 接收 StateSystem 的状态更新：

```
rain_intensity = clamp((10 - conviction) / 10, 0, 1)
despair_norm   = clamp(despair / 10, 0, 1)           # despair ≤ 10
             或 clamp(despair / 100, 0, 1)             # despair > 10
```

| 调制效果 | 公式 | 范围 |
|---------|------|------|
| 雨音量 | lerp(-24dB, -6dB, rain_intensity × distance_factor) | [-24, -6] dB |
| 暴雨音量 | lerp(-30dB, -12dB, despair_norm × distance_factor) | [-30, -12] dB，despair < 0.5 时静音 |
| 雨音高 | lerp(1.0, 1.3, rain_intensity) | [1.0, 1.3] |
| 城市嗡嗡声 | lerp(-20dB, -8dB, despair_norm × distance_factor) | [-20, -8] dB |
| 失真效果 | despair_norm > 0.5 时开启 | 主总线 AudioEffectDistortion |

所有音量通过 `minf(vol, 0.0)` 确保不超过 0dB，防止削波。

### 3.4 场景过渡

`cross_fade_ambient(target_scene_id, duration)` 实现两阶段淡入淡出：

1. **淡出阶段**（duration × 0.5）：所有环境音渐出至 -80dB
2. **配置切换**：更新 distance_factor + 总线配文件
3. **淡入阶段**（duration × 0.5）：雨量和城市嗡嗡声按新场景参数渐入

过渡由 `SceneManager.trigger_scene_change()` 触发。

### 3.5 脚步系统

`play_footstep(surface_type)` 接口：

- 内置 0.3 秒冷却，防止连续触发
- 根据 surface_type 选择对应脚步音资源（office / street / underpass）
- 支持对话效果 `play_sound`：当未指定 surface 时，自动从当前场景推断

#### 3.5.1 移动触发脚步 (#157)

PlayerController 在 `_physics_process()` 中检测 WASD 方向向量非零时，以 `FOOTSTEP_INTERVAL = 0.5s` 为间隔调用 `AudioManager.play_footstep(surface)`。表面类型通过 `AudioManager.get_surface_for_scene(get_tree().current_scene.name)` 自动推断。

| 触发类型 | 调用位置 | 接口 | 间隔 |
|----------|---------|------|------|
| 对话触发 | dialogue_runner.gd | `play_sound` → `play_footstep(surface)` | 对话序列点 |
| 移动触发 (#157) | PlayerController._physics_process() | `_trigger_footstep()` → `play_footstep(surface)` | 0.5s (FOOTSTEP_INTERVAL) |

静止或对话模式时脚步积累器归零，避免停顿时播放多余脚步。无需 AudioManager 修改 — 复用 `FOOTSTEP_COOLDOWN` (0.3s)、`SCENE_TO_SURFACE` 映射等现有机制。

### 3.6 信号

| 信号 | 参数 | 触发时机 |
|------|------|---------|
| ambient_profile_changed | scene_id: String | 总线配置文件切换时 |
| footstep_played | surface_type: String | 脚步音播放时 |

---

## 4. 音频资源清单

存放位置：`assets/audio/`

| 文件 | 格式 | 用途 |
|------|------|------|
| rain_loop.wav | 16-bit 44100 WAV | 细雨环境循环 |
| rain_heavy.wav | 16-bit 44100 WAV | 暴雨环境循环 |
| city_hum.wav | 16-bit 44100 WAV | 城市背景嗡嗡声 |
| footstep_office.wav | 16-bit 44100 WAV | 办公室地面脚步声 |
| footstep_street.wav | 16-bit 44100 WAV | 街道地面脚步声 |
| footstep_underpass.wav | 16-bit 44100 WAV | 地下通道脚步声 |
| underpass_ambient.wav | 16-bit 44100 WAV | 地下通道环境音（预留） |

---

## 5. 测试覆盖

| 测试文件 | 类型 | 测试用例数 |
|---------|------|-----------|
| tests/unit/test_audio_manager.gd | 单元测试 | 7 |
| tests/integration/test_audio_state_modulation.gd | 集成测试 | 3 |
| tests/integration/test_audio_scene_transition.gd | 集成测试 | 2 |
| tests/integration/test_audio_footstep_dialogue.gd | 集成测试 | 3 |

---

## 6. 使用示例

### 场景脚本中注册音频

```gdscript
# scene_base.gd 提供默认实现，子类可覆盖
func _configure_ambient_audio() -> void:
    var am := get_node_or_null("/root/AudioManager")
    if am and am.has_method("register_scene"):
        am.register_scene(scene_id)
```

### 对话效果触发脚步

```json
{
  "type": "play_sound",
  "surface": "street"
}
```

省略 `surface` 时自动从当前场景推断表面类型。

### 场景过渡音效

```gdscript
# SceneManager 自动调用
am.cross_fade_ambient(target_scene_id)
```
