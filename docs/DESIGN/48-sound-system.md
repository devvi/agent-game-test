# Design: #48 — Sound System（音效系统设计）

> Parent Issue: #48
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

采用 **Hybrid 架构（Approach C）**：一个 `AudioManager` 单例（autoload）管理所有跨场景持续的环境音（雨声、城市嗡嗡声）和状态调制逻辑；每个场景通过 `AudioManager.set_bus_profile(scene_id)` 切换音频总线效果（reverb/low-pass）；脚步声由每个场景独立的 `AudioStreamPlayer2D` 播放，通过 `DialogueRunner` 的 `"play_sound"` 效果类型触发。

**核心设计原则：**
1. **环境音持久化** — 雨声和城市嗡嗡声在场景切换时不应中断，必须由 autoload 持有
2. **声学空间由总线定义** — 每个场景的混响/低通效果通过 Godot AudioBus 切换，而非修改播放器参数
3. **脚步声是事件驱动的** — 不循环播放，由对话选择触发，surface 类型由当前场景决定
4. **状态调制集中管理** — 绝望值 → 音量/音高/失真映射集中在 AudioManager

### Data Flow

```
StateSystem.state_changed(state: Dictionary)
    │
    ▼
AudioManager._on_state_changed(state)
    ├── rain_intensity = clamp((10 - conviction) / 10, 0.0, 1.0)
    ├── rain.volume_db = lerp(-24, -6, rain_intensity * distance_factor)
    ├── rain.pitch_scale = lerp(1.0, 1.3, rain_intensity)
    ├── city_hum.volume_db = lerp(-20, -8, despair_normalized)
    └── master_bus.effect = lerp(0.0, 0.8, despair_normalized)  # distortion

DialogueRunner.choice_made(choice_index, choice_text)
    │
    └── AudioManager.play_footstep(surface_type: String)  [via "play_sound" effect]
            └── footstep_player.stream = preloaded[surface_type]
            └── footstep_player.play()

SceneManager.transition_started(target_scene)
    │
    ▼
AudioManager._on_transition_started(target_scene)
    ├── tween current_ambient.volume_db → -80 over 0.4s
    └── _set_ambient_profile(target_scene) — set new base levels
    └── tween new_ambient.volume_db → target over 0.4s

SceneBase._ready()
    │
    ▼
AudioManager.register_scene(scene_id: String)
    └── set_bus_profile(scene_id)         # reverb/low-pass for underpass
    └── set_distance_factor(distance)     # narrative distance from office
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Ambient audio ownership | `AudioManager` autoload | 环境音需要跨场景持续播放；autoload 不会被场景树释放 |
| Per-scene acoustics | AudioBus profile switching | Godot AudioBus 原生支持 effect stack 切换；比修改每个播放器参数更高效 |
| Footstep playback | Per-scene `AudioStreamPlayer2D` | 脚步声是场景局部的、非持续的；位置音频需要 2D 空间 |
| Asset loading | Preload on `_ready()` | 项目规模小（~7 个音频文件），一次性加载简化错误处理 |
| State → audio mapping | Centralized in `AudioManager` | 避免每个场景重复调制逻辑；单一修改点 |
| Cross-fade | Tween on volume_db | Godot 的 `Tween` API 原生支持属性动画；比 AnimationPlayer 更轻量 |

---

## 2. New Files

### `gdscripts/audio_manager.gd` — AudioManager 自动加载

**角色:** 跨场景单例，管理所有环境音循环、总线效果、状态调制。

**签名:**

```gdscript
extends Node
class_name AudioManager

# ── Signals ──
signal ambient_profile_changed(scene_id: String)   # 场景环境音配置变更
signal footstep_played(surface_type: String)        # 触发脚步声

# ── Public API ──
func register_scene(scene_id: String) -> void
    # 注册当前场景，设置匹配的环境音配置和总线效果

func set_bus_profile(profile: String) -> void
    # 切换音频总线效果链。预定义：
    #   "default"  — 无特效
    #   "indoor"   — 轻微低通 (cutoff_hz: 4000)
    #   "underpass" — 混响 (room_size: 0.8, damping: 0.6) + 低通 (cutoff_hz: 2000)
    #   "outdoor"  — 无特效

func play_footstep(surface_type: String) -> void
    # 播放脚步声。surface_type: "office" / "street" / "underpass"
    # 内置 0.3s 冷却防叠

func get_surface_for_scene(scene_id: String) -> String
    # 返回场景对应的脚步表面类型
    # "office" → "office", "lobby" → "office", "street" → "street",
    # "store" → "street", "bridge" → "street", "underpass" → "underpass",
    # "subway_station" → "street"

# ── State Modulation ──
func set_despair_modulation(despair: float) -> void
    # 调整全局失真强度和音量偏移
    # despair: 0.0 到 1.0（归一化）

# ── Cross-fade ──
func cross_fade_ambient(target_scene: String, duration: float = 0.4) -> void
    # 淡出当前环境音，淡入目标场景环境音
```

**内部状态:**

```gdscript
# ── Audio Players ──
var _rain_player: AudioStreamPlayer2D
var _rain_heavy_player: AudioStreamPlayer2D   # 高强度雨声变体
var _city_hum_player: AudioStreamPlayer2D
var _footstep_player: AudioStreamPlayer2D

# ── State ──
var _current_scene_id: String = ""
var _current_profile: String = "default"
var _rain_intensity: float = 0.0
var _distance_factor: float = 0.0            # 0.0 (office) → 1.0 (subway)
var _last_footstep_time: float = 0.0
const FOOTSTEP_COOLDOWN: float = 0.3

# ── Preloaded Audio Streams ──
var _rain_stream: AudioStream = preload("res://assets/audio/rain_loop.ogg")
var _rain_heavy_stream: AudioStream = preload("res://assets/audio/rain_heavy.ogg")
var _city_hum_stream: AudioStream = preload("res://assets/audio/city_hum.ogg")
var _footstep_office: AudioStream = preload("res://assets/audio/footstep_office.ogg")
var _footstep_street: AudioStream = preload("res://assets/audio/footstep_street.ogg")
var _footstep_underpass: AudioStream = preload("res://assets/audio/footstep_underpass.ogg")
```

### `assets/audio/` — 音频资产

| 文件 | 格式 | 预计长度 | 用途 |
|------|------|----------|------|
| `rain_loop.ogg` | OGG Vorbis, mono, 22050Hz | 10-30s 循环 | 基础雨声循环 |
| `rain_heavy.ogg` | OGG Vorbis, mono, 22050Hz | 10-30s 循环 | 高强度雨声变体（高绝望时叠加） |
| `city_hum.ogg` | OGG Vorbis, mono, 22050Hz | 10-30s 循环 | 城市低频嗡嗡声 |
| `footstep_office.ogg` | OGG Vorbis, mono, 44100Hz | 0.5-1.0s | 硬质地板脚步声 |
| `footstep_street.ogg` | OGG Vorbis, mono, 44100Hz | 0.5-1.0s | 湿漉人行道脚步声 |
| `footstep_underpass.ogg` | OGG Vorbis, mono, 44100Hz | 0.8-1.5s | 带回声的混凝土脚步声 |
| `underpass_ambient.ogg` | OGG Vorbis, mono, 22050Hz | 10-30s 循环 | 地下通道低频环境音 |

> **注意:** 这些是设计规格。实际音频资产需要在实现阶段生成或获取。

---

## 3. Modified Files（按层汇总）

### 3.1 Engine / Autoload Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/audio_manager.gd` | **新文件** — AudioManager autoload | +250 |

### 3.2 State Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/game_state.gd` | 无需修改 — `state_changed` 信号已存在，AudioManager 连接即可 | ±0 |
| `gdscripts/state_system.gd` | 无需修改 — `state_changed` 信号已存在，AudioManager 连接即可 | ±0 |

### 3.3 Scene Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/scene_base.gd` | 新增 `_configure_ambient_audio()` 虚方法，在 `_ready()` 中调用；新增 `scene_id_to_profile()` 辅助方法 | +15 |
| `gdscripts/scene_manager.gd` | 在 `trigger_scene_change()` 中 emit `transition_started` 时附带场景名称；在 `fade_in()` 完成后 emit `transition_completed` — 信号已存在，确认传递场景ID | +5 |
| `gdscripts/underpass.gd` | 重写 `_configure_ambient_audio()`：调用 `AudioManager.set_bus_profile("underpass")`；设置办公室声音距离因子 | +8 |
| `gdscripts/office.gd` | 重写 `_configure_ambient_audio()`：调用 `AudioManager.set_bus_profile("indoor")`；注册场景 | +5 |
| `gdscripts/street.gd` | 继承 `SceneBase`（目前直接 extends Node）；重写 `_configure_ambient_audio()`：调用 `AudioManager.set_bus_profile("outdoor")` | +8 |
| `gdscripts/bridge.gd` | 重写 `_configure_ambient_audio()`：调用 `AudioManager.set_bus_profile("outdoor")`；户外距离因子 | +5 |
| `gdscripts/lobby.gd` | 重写 `_configure_ambient_audio()`：调用 `AudioManager.set_bus_profile("indoor")` | +5 |
| `gdscripts/store.gd` | 重写 `_configure_ambient_audio()`：调用 `AudioManager.set_bus_profile("indoor")` | +5 |
| `gdscripts/subway_station.gd` | 重写 `_configure_ambient_audio()`：调用 `AudioManager.set_bus_profile("indoor")`；最大距离因子 | +5 |

### 3.4 Dialogue Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/dialogue_runner.gd` | 在 `_apply_effects()` 的 `match` 中新增 `"play_sound"` case，调用 `AudioManager.play_footstorm(surface_type)` | +10 |

### 3.5 Bus Layout

| File | Change | Est. Lines |
|------|--------|-----------|
| `default_bus_layout.tres` | **新文件** — Godot AudioBus 布局 | +30 |

**Bus 结构:**
- **Master** (0): 输出到设备
  - 插入 `AudioEffectDistortion`（全局状态调制，默认 bypass=true）
- **AmbientBus** (1): 雨声、城市嗡嗡声 → Master
  - 在下面切换effect链
- **SFXBus** (2): 脚步声 → Master
- **IndoorBus** (3): 室内声学 → Master（可选低通）
  - 插入 `AudioEffectLowPassFilter` (cutoff_hz: 4000, bypass=true)
- **UnderpassBus** (4): 地下通道声学 → Master
  - 插入 `AudioEffectReverb` (room_size: 0.8, damping: 0.6)
  - 插入 `AudioEffectLowPassFilter` (cutoff_hz: 2000)

---

## 4. API Contracts

### AudioManager → SceneBase

```gdscript
# SceneBase 调用
AudioManager.register_scene(scene_id)              # _ready() 中调用
AudioManager.set_bus_profile(profile_name)         # _configure_ambient_audio() 中调用
AudioManager.play_footstep(surface_type)            # 由 DialogueRunner 间接调用

# 场景切换时
AudioManager.cross_fade_ambient(target_scene_id)  # 由 SceneManager 调用
```

### DialogueRunner → AudioManager

```gdscript
# 在 dialogue_runner.gd 中新增效果类型
# dialogue JSON 格式:
{
  "type": "play_sound",
  "surface": "street"         # 可选，默认从当前场景推断
}

# _apply_effects() 中:
"play_sound":
    var surface := effect.get("surface", "")
    if surface.is_empty():
        surface = AudioManager.get_surface_for_scene(_current_scene_id)
    AudioManager.play_footstep(surface)
```

### SceneManager → AudioManager

```gdscript
# SceneManager 触发场景切换时:
transition_started.emit(target_scene)
AudioManager.cross_fade_ambient(get_scene_id_from_path(target_scene))
```

---

## 5. Test Plan

### Test Structure

所有测试在 `tests/` 目录下，使用 Godot 4.7.1 headless `--script` 模式（无场景树依赖则用 GDScript 单元测试，有信号/autoload 依赖则用场景测试）。

| 测试文件 | 类型 | 测试目标 |
|----------|------|----------|
| `tests/unit/test_audio_manager.gd` | 单元测试 | AudioManager 核心逻辑 |
| `tests/integration/test_audio_state_modulation.gd` | 集成测试 | 状态变化 → 音频调制 |
| `tests/integration/test_audio_scene_transition.gd` | 集成测试 | 场景切换 → 交叉淡入淡出 |
| `tests/integration/test_audio_footstep_dialogue.gd` | 集成测试 | 对话选择 → 脚步声触发 |

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| AudioManager core | ✅ | ≥ 4 | ✅ |
| State→audio modulation | ✅ | ≥ 3 | ✅ |
| Scene transition cross-fade | ✅ | ≥ 3 | ✅ |
| Dialogue→footstep trigger | ✅ | ≥ 2 | ✅ |
| Audio bus profile switching | ✅ | ≥ 2 | ✅ |

### Concrete Test Cases

#### TC1 — AudioManager: Register Scene Sets Bus Profile
- **Type:** Unit
- **Setup:** Instantiate AudioManager, mock `set_bus_profile`
- **Steps:**
  1. Call `register_scene("underpass")`
  2. Assert bus profile set to `"underpass"`
  3. Call `register_scene("office")`
  4. Assert bus profile set to `"indoor"`

#### TC2 — AudioManager: Rain Intensity From State
- **Type:** Unit
- **Setup:** AudioManager with mock state
- **Steps:**
  1. Call `_on_state_changed({conviction: 10})` — max hope
  2. Assert `_rain_intensity == 0.0` (silent rain)
  3. Call `_on_state_changed({conviction: 0})` — max despair
  4. Assert `_rain_intensity == 1.0` (max rain)
  5. Call `_on_state_changed({conviction: 5})` — neutral
  6. Assert `_rain_intensity == 0.5`

#### TC3 — AudioManager: State Modulation Applies Volume/Pitch
- **Type:** Unit
- **Setup:** AudioManager with AudioStreamPlayer2D instances
- **Steps:**
  1. Set despairs to 0.0
  2. Assert `_rain_player.volume_db` near -24 dB
  3. Set despairs to 1.0
  4. Assert `_rain_player.volume_db` near -6 dB
  5. Assert `_rain_player.pitch_scale` near 1.3

#### TC4 — AudioManager: Footstep Cooldown
- **Type:** Unit
- **Setup:** AudioManager with mock time
- **Steps:**
  1. `play_footstep("office")` — first call, plays immediately
  2. Immediately call `play_footstep("street")` — within 0.3s cooldown, ignored
  3. Assert `footstep_played` emitted only once

#### TC5 — AudioManager: Footstep Surface Mapping
- **Type:** Unit
- **Setup:** AudioManager
- **Steps:**
  1. `get_surface_for_scene("office")` → `"office"`
  2. `get_surface_for_scene("street")` → `"street"`
  3. `get_surface_for_scene("underpass")` → `"underpass"`
  4. `get_surface_for_scene("subway_station")` → `"street"` (fallback to outdoor)

#### TC6 — AudioManager: Missing Audio Assets Degrade Gracefully
- **Type:** Unit, Failure Path
- **Setup:** AudioManager with invalid preload paths simulation
- **Steps:**
  1. Simulate failed preload
  2. Call `_ready()`
  3. Assert no crash (push_warning logged)
  4. Assert the game continues silently

#### TC7 — SceneManager: Cross-Fade During Scene Transition
- **Type:** Integration
- **Setup:** SceneManager with AudioManager connected
- **Steps:**
  1. Trigger scene change from "office" to "street"
  2. Assert `AudioManager.cross_fade_ambient("street", 0.4)` is called
  3. Assert current ambient volume starts tweening to -80 dB
  4. Assert new ambient volume starts tweening to target level

#### TC8 — SceneManager: Rapid Scene Transition Aborts Current Fade
- **Type:** Integration, Edge Case
- **Setup:** SceneManager + AudioManager
- **Steps:**
  1. Start scene transition → office to street
  2. Immediately (within 0.2s) trigger another transition → street to underpass
  3. Assert first tween is killed
  4. Assert second tween starts from current volume

#### TC9 — DialogueRunner: "play_sound" Effect Triggers Footstep
- **Type:** Integration
- **Setup:** DialogueRunner with AudioManager mock
- **Steps:**
  1. Create dialogue choice with `effects: [{type: "play_sound", surface: "street"}]`
  2. Call `select_choice(0)`
  3. Assert `AudioManager.play_footstep("street")` is called

#### TC10 — DialogueRunner: "play_sound" Without Surface Infers From Scene
- **Type:** Integration, Edge Case
- **Setup:** DialogueRunner with AudioManager mock
- **Steps:**
  1. Create dialogue choice with `effects: [{type: "play_sound"}]` (no surface)
  2. Set current scene to "office" in AudioManager mock
  3. Call `select_choice(0)`
  4. Assert `AudioManager.play_footstep("office")` is called

#### TC11 — DialogueRunner: Non-Footstep Choices Don't Trigger Sound
- **Type:** Integration, Edge Case
- **Setup:** DialogueRunner with AudioManager mock
- **Steps:**
  1. Create dialogue choice with no effects
  2. Call `select_choice(0)`
  3. Assert `AudioManager.play_footstep` NOT called

#### TC12 — Underpass: Audio Bus Profile Applies Effects
- **Type:** Integration
- **Setup:** UnderpassScene with AudioManager
- **Steps:**
  1. Set `register_scene("underpass")`
  2. Assert bus profile is `"underpass"`
  3. Assert Reverb effect is enabled with room_size=0.8, damping=0.6
  4. Assert LowPassFilter effect is enabled with cutoff_hz=2000

#### TC13 — State Change During Scene Transition Updates Target
- **Type:** Integration, Edge Case
- **Setup:** AudioManager with tween in progress
- **Steps:**
  1. Start cross-fade from office to street
  2. Mid-fade, call `_on_state_changed({conviction: 2})` — despair rises
  3. Assert the active tween's target volume has been updated (less loud for despair)
  4. Assert no audio glitch (volume spike or sudden jump)

#### TC14 — Volume Clipping Protection at Max Despair
- **Type:** Unit, Edge Case
- **Setup:** AudioManager
- **Steps:**
  1. Set despair to 1.0, distance_factor to 1.0
  2. Assert rain volume_db ≤ 0 dB (never clipping)
  3. Assert city hum volume_db ≤ 0 dB

#### TC15 — Audio File Not Found Graceful Degradation
- **Type:** Unit, Failure Path
- **Setup:** AudioManager with missing stream reference
- **Steps:**
  1. Null the `_rain_stream` reference
  2. Call `_ready()`
  3. Assert push_warning logged: "Audio file not found: res://assets/audio/rain_loop.ogg"
  4. Assert game continues without crash

#### TC16 — Bus Not Found Fallback to Master
- **Type:** Unit, Failure Path
- **Setup:** AudioManager with invalid bus name
- **Steps:**
  1. Call `set_bus_profile("nonexistent")`
  2. Assert fallback to "Master" bus
  3. Assert push_warning logged: "Audio bus 'nonexistent' not found, using 'Master'"

#### TC17 — Scene With No Profile Uses Default
- **Type:** Unit, Failure Path
- **Setup:** AudioManager
- **Steps:**
  1. Call `register_scene("unknown_scene")`
  2. Assert profile set to "default"
  3. Assert push_warning logged: "No ambient profile for scene 'unknown_scene'"

---

## 6. Files Changed（汇总）

| File | Type | Change | Est. Lines |
|------|------|--------|-----------|
| `gdscripts/audio_manager.gd` | **New** | Central autoload for ambient sound management | +250 |
| `default_bus_layout.tres` | **New** | Audio bus layout (Master, Ambient, SFX, Indoor, Underpass) | +30 |
| `assets/audio/rain_loop.ogg` | **New** | Rain audio loop asset | N/A |
| `assets/audio/rain_heavy.ogg` | **New** | Heavy rain variant | N/A |
| `assets/audio/city_hum.ogg` | **New** | City ambient drone | N/A |
| `assets/audio/footstep_office.ogg` | **New** | Footstep on hard floor | N/A |
| `assets/audio/footstep_street.ogg` | **New** | Footstep on wet pavement | N/A |
| `assets/audio/footstep_underpass.ogg` | **New** | Footstep with echo | N/A |
| `assets/audio/underpass_ambient.ogg` | **New** | Underpass-specific ambient | N/A |
| `gdscripts/scene_base.gd` | Modify | Add `_configure_ambient_audio()` virtual method | +15 |
| `gdscripts/scene_manager.gd` | Modify | Ensure transition signals carry scene info for AudioManager | +5 |
| `gdscripts/dialogue_runner.gd` | Modify | Add `"play_sound"` effect type in `_apply_effects()` | +10 |
| `gdscripts/underpass.gd` | Modify | Override `_configure_ambient_audio()` — underpass bus profile | +8 |
| `gdscripts/office.gd` | Modify | Override `_configure_ambient_audio()` — indoor profile | +5 |
| `gdscripts/street.gd` | Modify | Extend SceneBase; override `_configure_ambient_audio()` — outdoor profile | +8 |
| `gdscripts/bridge.gd` | Modify | Override `_configure_ambient_audio()` — outdoor profile | +5 |
| `gdscripts/lobby.gd` | Modify | Override `_configure_ambient_audio()` — indoor profile | +5 |
| `gdscripts/store.gd` | Modify | Override `_configure_ambient_audio()` — indoor profile | +5 |
| `gdscripts/subway_station.gd` | Modify | Override `_configure_ambient_audio()` — indoor, max distance | +5 |
| `gdscripts/rain_controller.gd` | Modify | No change needed — AudioManager connects to StateSystem directly | ±0 |

---

## 7. Verification Checklist

- [ ] TC1-TC5: AudioManager unit tests pass
- [ ] TC6: Missing audio asset graceful degradation verified
- [ ] TC7-TC8: Scene transition cross-fade works correctly
- [ ] TC9-TC11: Dialogue footstep triggers work correctly
- [ ] TC12: Underpass bus profile applies reverb + low-pass
- [ ] TC13: State change during transition doesn't glitch
- [ ] TC14: Volume never clips at max despair
- [ ] TC15-TC17: All failure paths handled gracefully
- [ ] No regression on existing dialogue system
- [ ] No regression on existing scene transitions
- [ ] All pre-existing tests still pass
