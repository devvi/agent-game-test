# Design: #219 — Sound & Background Music System（音效与背景音乐系统）

> Parent Issue: #219
> Agent: plan-agent
> Date: 2026-07-25

---

## 1. Architecture Overview

### Core Idea

采用 **Approach A（Extend Existing AudioManager）**：在现有 `AudioManager` autoload（346 行，`AudioStreamPlayer2D`）基础上扩展，不创建新的 autoload。新增 `AudioStreamPlayer3D` 用于 3D 空间音频，新增 BGM 播放器层（ambient bed + NPC motif + ending），新增幻觉音频失真总线，新增 NPC→BGM 信号集成。

**核心设计原则：**
1. **单 autoload 保持音频状态一致** — AudioManager 持有所有音频状态，无跨 autoload 协调问题
2. **BGM 使用专用 MusicBus** — 独立于 AmbientBus，支持独立 ducking 和 cross-fade
3. **3D 空间音频与原 2D 播放器共存** — AudioStreamPlayer3D 作为新增 children，2D 播放器保持为 fallback
4. **幻觉音频是叠加层** — 在现有绝望调制之上叠加，通过 Bus effect 开关和 LFO 计时器实现
5. **NPC→BGM 复用现有信号模式** — 与 StateSystem.state_changed → _on_state_changed 相同的连接模式

### Data Flow

#### 3D Spatial Audio Flow
```
SceneBase._ready()
    │
    ├── AudioManager.register_scene(scene_id)
    │     └── set position of AudioStreamPlayer3D children
    │     └── set rain/city spatial parameters per scene profile
    │
    └── AudioManager._sync_3d_listener()
          └── Update AudioStreamPlayer3D positions relative to player
```

#### BGM Playback Flow
```
AudioManager._ready()
    └── _setup_bgm_players()
          ├── _bgm_player (ambient bed, MusicBus)
          ├── _motif_player (NPC overlay, MusicBus)
          └── _ending_player (CinemaBus)
```

#### NPC → BGM Flow
```
NPCNode (approaches player)
    │
    ├── body_entered detected (NPCNode already has _on_body_entered)
    │     → proximity_distance < threshold → emit npc_dialogue_started(npc_id)
    │
    ├── AudioManager._on_npc_dialogue_started(npc_id)
    │     ├── fade_in motif track (2s cross-fade via Tween)
    │     ├── set _active_npc_id = npc_id
    │     └── set _bgm_state = "npc_active"
    │
    ├── Player clicks NPC → dialogue starts
    │     └── AudioManager.set_bgm_ducking(true)
    │           ├── tween _motif_player.volume_db → -8 dB (0.5s)
    │           └── tween _bgm_player.volume_db → -3 dB (0.5s)
    │
    └── Dialogue ends → npc_dialogue_completed(npc_id)
          └── AudioManager._on_npc_dialogue_ended(npc_id)
                ├── tween BGM volume → 0 dB (0.5s)
                └── after 5s timeout: fade_out motif (2s) → set _bgm_state = "ambient"
```

#### Hallucination → Audio Flow
```
NarrativeManager.hallucination_level_changed(level: int)
    │
    ▼
AudioManager._on_hallucination_level_changed(level)
    ├── if level < 5: disable all HallucinationFXBus effects (1s tween)
    ├── if level >= 5:
    │     ├── enable AudioEffectLowPassFilter (cutoff: 3000→500 Hz, proportional to level)
    │     ├── enable AudioEffectReverb (wet mix proportional to level)
    │     └── start _hallucination_lfo_timer (0.5 Hz oscillation)
    ├── if level >= 7:
    │     ├── enable AudioEffectDelay (slapback echo, feedback: 0.3)
    │     └── increase LFO depth (±0.15 pitch oscillation)
    └── if level >= 9:
          ├── enable intermittent audio dropout (Timer: -80 dB for 100ms every 3-5s)
          └── enable phaser/flanger effect on HallucinationFXBus
```

#### Ending Music Flow
```
SubwayStationScene._determine_ending()
    │
    ├── NarrativeManager.determine_ending(state) → "keep_walking"/"turn_back"/"stay"
    │
    └── Ending dialogue choice triggers "trigger_event" effect
          │
          ▼
        AudioManager.set_ending_music(ending_id: String)
          ├── cross_fade_to(ending track via _ending_player, 2s)
          ├── fade_out ambient rain (2s)
          ├── fade_out BGM motif (if active)
          └── set _bgm_state = "ending"
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| BGM ownership | AudioManager autoload (not separate BgmManager) | 项目仅 7 场景 4 NPC，分离是过度设计；现有 cross-fade/bus 模式直接复用 |
| 3D spatial audio | AudioStreamPlayer3D children + new 3D-specific players | 2D players 保持为 fallback；3D 提供位置衰减和方向感知 |
| BGM implementation | _bgm_player + _motif_player + _ending_player | 三个独立 AudioStreamPlayer，避免轨道混叠；每个使用独立 bus |
| Hallucination audio | HallucinationFXBus effect chain + LFO timer | GPU 级耦合音频效果通过 Godot AudioBus 原生支持；LFO 用 Timer + _process 驱动 |
| Bus structure | 新 MusicBus, HallucinationFXBus, CinemaBus | 独立控制可用 ducking 和 effect stack |
| NPC→BGM trigger | NPCNode 新信号 npc_dialogue_started + dialogue_completed | 复用现有信号模式（与 StateSystem 相同） |
| BGM ducking | Volume tween on MusicBus | Ducking 是 volume 层；幻觉是 effect 层，两者独立 |
| Audio assets | .ogg 格式（Godot 原生压缩） | OGG Vorbis 比 WAV 小 5-10x，适合循环音频 |
| LFO modulation | Timer at 0.5 Hz + _process pitch_scale update | 比 AudioEffectPitchShift 更轻量，直接在 player 层面调制 |
| Motif overlap guard | _active_npc_id + _queued_motif | 防止两个 NPC 同时触发 motif |

---

## 2. Engine Layer 变更

> AudioManager autoload — 主要改动文件

### AudioManager 新增

#### 新增常量

```gdscript
# ── BGM Constants ──
const BGM_DUCK_DB: float = -8.0
const BGM_AMBIENT_DUCK_DB: float = -3.0
const BGM_CROSSFADE_TIME: float = 2.0
const MOTIF_HOLD_TIME: float = 5.0
const MOTIF_FADE_OUT_TIME: float = 2.0

# ── 3D Audio Constants ──
const RAIN_3D_POSITION: Vector3 = Vector3(0, 15, 0)    # Rain source above player
const CITY_3D_POSITION: Vector3 = Vector3(-50, 5, 0)    # City source from distance
const SUBWAY_3D_POSITION: Vector3 = Vector3(0, -8, 0)   # Subway source below ground

# ── Hallucination Audio Constants ──
const HALLUCINATION_LFO_RATE: float = 0.5               # Hz
const HALLUCINATION_PITCH_DEPTH: float = 0.1            # ±pitch at level 5-6
const HALLUCINATION_PITCH_DEPTH_HIGH: float = 0.15      # ±pitch at level 7+
const HALLUCINATION_DROPOUT_DB: float = -80.0
const HALLUCINATION_DROPOUT_MS: int = 100
const HALLUCINATION_DROPOUT_INTERVAL_MIN: float = 3.0
const HALLUCINATION_DROPOUT_INTERVAL_MAX: float = 5.0
```

#### 新增变量

```gdscript
# ── BGM State ──
var _bgm_player: AudioStreamPlayer                          # Ambient BGM bed
var _motif_player: AudioStreamPlayer                        # NPC encounter motif
var _ending_player: AudioStreamPlayer                       # Ending music
var _bgm_state: String = "ambient"     # "ambient", "npc_active", "ending"
var _active_npc_id: String = ""         # Current active NPC for motif
var _motif_hold_timer: Timer            # 5s hold before motif fade-out

# ── 3D Spatial Players ──
var _rain_3d_player: AudioStreamPlayer3D                    # 3D spatial rain
var _rain_heavy_3d_player: AudioStreamPlayer3D              # 3D spatial heavy rain
var _city_3d_player: AudioStreamPlayer3D                    # 3D spatial city hum
var _traffic_player: AudioStreamPlayer3D                    # Traffic rumble
var _subway_player: AudioStreamPlayer3D                     # Subway rumble
var _subway_close_player: AudioStreamPlayer3D               # Close subway rumble (underpass)

# ── Hallucination Audio State ──
var _hallucination_level: int = 0
var _hallucination_lfo_timer: Timer
var _hallucination_lfo_time: float = 0.0
var _hallucination_dropout_timer: Timer
var _hallucination_effects_active: bool = false

# ── Bus Indices (new) ──
var _music_bus_idx: int = -1
var _hallucination_bus_idx: int = -1
var _cinema_bus_idx: int = -1

# ── Bus Effect Indices (new) ──
var _hallucination_lpf_idx: int = -1
var _hallucination_reverb_idx: int = -1
var _hallucination_delay_idx: int = -1
```

#### BGM 场景配置文件

```gdscript
# Per-scene BGM configuration
const SCENE_BGM_CONFIG: Dictionary = {
    "office":           {"bed_volume": -6, "enabled": true},
    "lobby":            {"bed_volume": -4, "enabled": true},
    "street":           {"bed_volume": -3, "enabled": true},
    "convenience_store": {"bed_volume": -5, "enabled": true},
    "bridge":           {"bed_volume": -3, "enabled": true},
    "underpass":        {"bed_volume": -8, "enabled": true},
    "subway_station":   {"bed_volume": -6, "enabled": true},
}

# NPC motif mapping
const NPC_TO_MOTIF: Dictionary = {
    "Stranger": {"stream": null, "path": "res://assets/audio/npc_stranger_music.ogg"},
    "Guard":    {"stream": null, "path": "res://assets/audio/npc_guard_music.ogg"},
    "Clerk":    {"stream": null, "path": "res://assets/audio/npc_clerk_music.ogg"},
    "Homeless": {"stream": null, "path": "res://assets/audio/npc_homeless_music.ogg"},
}

# Ending music mapping
const ENDING_MUSIC: Dictionary = {
    "keep_walking": {"stream": null, "path": "res://assets/audio/ending_keep_walking.ogg"},
    "turn_back":    {"stream": null, "path": "res://assets/audio/ending_turn_back.ogg"},
    "stay":         {"stream": null, "path": "res://assets/audio/ending_stay.ogg"},
}

# NPC proximity distance threshold for motif trigger
const NPC_PROXIMITY_TRIGGER_DIST: float = 4.0
```

#### 新增方法签名

```gdscript
# ── Public API ──
func set_ending_music(ending_id: String) -> void
    # 播放结局音乐，cross-fade 退出 ambient/BGM

func set_bgm_ducking(ducking: bool) -> void
    # 对话 ducking：true = -8dB BGM, -3dB ambient；false = 恢复

func trigger_bgm_motif(npc_id: String) -> void
    # 触发 NPC encounter motif（渐变切入）

func clear_bgm_motif() -> void
    # 清除当前 motif（渐变切出）

# ── Internal ──
func _setup_bgm_players() -> void
    # 初始化 BGM AudioStreamPlayer 和 bus 路由

func _setup_3d_players() -> void
    # 初始化 3D AudioStreamPlayer3D

func _setup_hallucination_system() -> void
    # 设置幻觉 LFO timer 和 dropout timer

func _connect_npc_signals() -> void
    # 连接所有 NPCNode 的信号（通过 group "npcs"）

func _connect_hallucination_signals() -> void
    # 连接 NarrativeManager.hallucination_level_changed

func _sync_3d_listener() -> void
    # 在 _process 中同步 3D 音频位置到玩家

func _on_npc_dialogue_started(npc_id: String) -> void
    # NPC 对话开始 → 触发 motif

func _on_npc_dialogue_ended(npc_id: String) -> void
    # NPC 对话结束 → 5s 后淡出 motif

func _on_hallucination_level_changed(level: int) -> void
    # 幻觉等级变化 → 更新 effect chain

func _on_hallucination_lfo_tick() -> void
    # LFO 计时器回调 → 振荡雨声/城市嗡嗡声 pitch

func _on_hallucination_dropout_tick() -> void
    # Dropout 计时器回调 → 短暂静音

func _load_bgm_streams() -> void
    # 预加载 BGM 和 motif 音频流

func _load_3d_audio_streams() -> void
    # 预加载 3D 环境音频流（traffic, subway）

func _update_bgm_bed(scene_id: String) -> void
    # 根据场景更新 ambient BGM bed 音量

func _update_hallucination_effects() -> void
    # 根据当前幻觉等级更新所有 audio effects

func _apply_hallucination_lfo(delta: float) -> void
    # 在 _process 中应用 LFO pitch modulation
```

### Signal 连接变更

#### 新增信号连接

| 发送者 | 信号 | 接收者 | 方法 |
|--------|------|--------|------|
| `NarrativeManager` | `hallucination_level_changed(level)` | `AudioManager` | `_on_hallucination_level_changed` |
| `NPCNode` (group "npcs") | `npc_dialogue_started(npc_id)` | `AudioManager` | `_on_npc_dialogue_started` |
| `NPCNode` (group "npcs") | `dialogue_completed(npc_id)` | `AudioManager` | `_on_npc_dialogue_ended` |

#### NPCNode 新增信号

在 `gdscripts/npc_node.gd` 中添加：

```gdscript
signal npc_dialogue_started(npc_id: String)  # 玩家进入 proximity + NPC 可交互时触发
```

触发时机：当 `_on_body_entered` 且 NPC 处于 IDLE 状态时（靠近但不交互）。

```gdscript
# 在 _on_body_entered() 中新增：
func _on_body_entered(body: Node) -> void:
    # ... existing code ...
    if body.is_in_group("player") and current_state == NPCState.IDLE:
        npc_dialogue_started.emit(name)
```

---

## 3. Bus Layout 变更

> `default_bus_layout.tres` — 新增 3 个 Audio Bus

### 新增 Bus 结构

| Bus ID | 名称 | 效果 | 用途 |
|--------|------|------|------|
| 5 | `MusicBus` | 无 | BGM 层（ambient bed + motif） |
| 6 | `HallucinationFXBus` | 按等级启用效果链 | 幻觉音频失真 |
| 7 | `CinemaBus` | 无 | 结局音乐专用 |

### HallucinationFXBus 效果链

| 效果索引 | 效果类型 | 默认参数 | 启用条件 |
|----------|----------|----------|----------|
| 0 | `AudioEffectLowPassFilter` | cutoff_hz: 3000, bypass: true | 等级 ≥ 5 |
| 1 | `AudioEffectReverb` | room_size: 0.5, damping: 0.4, wet: 0.3, bypass: true | 等级 ≥ 5 |
| 2 | `AudioEffectDelay` | delay: 150ms, feedback: 0.3, bypass: true | 等级 ≥ 7 |
| 3 | `AudioEffectPhaser` | rate_hz: 0.8, depth: 0.6, bypass: true | 等级 ≥ 9 |

### Tres 文件布局新增

```gdscript
# bus/5/name = "MusicBus"
# bus/5/solo = false
# bus/5/mute = false
# bus/5/bypass_fx = false
# bus/5/volume_db = 0.0
#
# bus/6/name = "HallucinationFXBus"
# bus/6/solo = false
# bus/6/mute = false
# bus/6/bypass_fx = false
# bus/6/volume_db = 0.0
# bus/6/effect/0 = AudioEffectLowPassFilter (cutoff_hz: 3000, bypass: true)
# bus/6/effect/1 = AudioEffectReverb (room_size: 0.5, bypass: true)
# bus/6/effect/2 = AudioEffectDelay (delay: 150ms, bypass: true)
# bus/6/effect/3 = AudioEffectPhaser (rate_hz: 0.8, bypass: true)
#
# bus/7/name = "CinemaBus"
# bus/7/solo = false
# bus/7/mute = false
# bus/7/bypass_fx = false
# bus/7/volume_db = 0.0
```

---

## 4. Modified Files（按层汇总）

### 4.1 Engine / Autoload Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/audio_manager.gd` | **主要修改** — 添加 BGM 层、3D 空间音频、幻觉音频、NPC→BGM 信号 | +350 |
| `gdscripts/npc_node.gd` | **修改** — 新增 `npc_dialogue_started` 信号，在 `_on_body_entered` 中触发 | +8 |
| `default_bus_layout.tres` | **修改** — 新增 MusicBus, HallucinationFXBus, CinemaBus | +40 |

### 4.2 Scene Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/scene_base.gd` | 新增 `_configure_bgm()` 虚方法，在 `_ready()` 中调用 | +12 |
| `gdscripts/subway_station.gd` | 在 `_configure_ambient_audio()` 或 ending 触发时调用 `AudioManager.set_ending_music()` | +10 |

### 4.3 Dialogue Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/dialogue_runner.gd` | 新增 `"trigger_event"` effect case → `AudioManager.set_ending_music()` | +8 |

### 4.4 Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/unit/test_audio_manager.gd` | 新增 BGM、3D 空间音频、幻觉音频测试用例 | +100 |
| `tests/integration/test_audio_state_modulation.gd` | 新增幻觉等级→音频效果测试 | +40 |

---

## 5. New Files

### Audio Assets (需创作或获取)

| File | Purpose | Est. Length | Priority |
|------|---------|-------------|----------|
| `assets/audio/ambient_music.ogg` | 持续环境 BGM 床（subtle drone/pad） | 30-60s loop | P0 |
| `assets/audio/npc_stranger_music.ogg` | 陌生人 NPC 遭遇 BGM motif（melancholic piano） | 10-20s loop | P0 |
| `assets/audio/npc_guard_music.ogg` | 警卫 NPC 遭遇 BGM motif（low brass） | 10-20s loop | P0 |
| `assets/audio/npc_clerk_music.ogg` | 店员 NPC 遭遇 BGM motif（warm synth） | 10-20s loop | P0 |
| `assets/audio/npc_homeless_music.ogg` | 流浪汉 NPC 遭遇 BGM motif（lonely guitar） | 10-20s loop | P0 |
| `assets/audio/ending_keep_walking.ogg` | Keep Walking 结局音乐（hopeful orchestral） | 30-60s one-shot | P0 |
| `assets/audio/ending_turn_back.ogg` | Turn Back 结局音乐（melancholy piano） | 30-60s one-shot | P0 |
| `assets/audio/ending_stay.ogg` | Stay 结局音乐（ambiguous ambient） | 30-60s one-shot | P0 |
| `assets/audio/traffic_rumble.ogg` | 远处车流环境音 | 10-30s loop | P1 |
| `assets/audio/subway_rumble.ogg` | 地铁隆隆声（远） | 10-30s loop | P1 |
| `assets/audio/subway_rumble_close.ogg` | 地铁隆隆声（近，地下通道变体） | 10-30s loop | P1 |

---

## 6. API Contracts

### AudioManager → Scene

```gdscript
# SceneBase 调用
AudioManager.register_scene(scene_id)           # _ready() 中调用（已有）
AudioManager.set_bus_profile(profile_name)       # _configure_ambient_audio() 中调用（已有）

# 新增 BGM 配置
AudioManager.set_ending_music(ending_id)         # ending 触发时调用
```

### AudioManager → DialogueRunner

```gdscript
# dialogue JSON 格式新增效果类型:
{"type": "trigger_event", "event": "ending_music"}
# _apply_effects() 中:
"trigger_event":
    if effect.event == "ending_music":
        AudioManager.set_ending_music(ending_id)
```

### AudioManager → NPCNode

```gdscript
# NPCNode 新信号:
signal npc_dialogue_started(npc_id: String)

# AudioManager 连接:
for npc in get_tree().get_nodes_in_group("npcs"):
    if npc.has_signal("npc_dialogue_started"):
        npc.dialogue_started.connect(_on_npc_dialogue_started)
    if npc.has_signal("dialogue_completed"):
        npc.dialogue_completed.connect(_on_npc_dialogue_ended)
```

### AudioManager → NarrativeManager

```gdscript
# NarrativeManager 已有信号:
signal hallucination_level_changed(new_level: int)

# AudioManager 连接:
var nm := get_node_or_null("/root/NarrativeManager")
if nm and nm.has_signal("hallucination_level_changed"):
    nm.hallucination_level_changed.connect(_on_hallucination_level_changed)
```

---

## 7. Test Layer

### Test Structure

所有测试使用 Godot 4.7.1 headless `--script` 模式。

| 测试文件 | 类型 | 测试目标 |
|----------|------|----------|
| `tests/unit/test_audio_manager.gd` | 单元测试 | AudioManager 扩展核心逻辑（BGM, 3D, 幻觉, NPC→BGM） |
| `tests/integration/test_audio_state_modulation.gd` | 集成测试 | 幻觉等级→音频效果；状态+BGM 组合 |

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| BGM cross-fade & ducking | ✅ | ≥ 3 | ✅ |
| 3D spatial audio positioning | ✅ | ≥ 2 | ✅ |
| NPC→BGM motif trigger | ✅ | ≥ 3 | ✅ |
| Hallucination audio effects | ✅ | ≥ 4 | ✅ |
| Ending music trigger | ✅ | ≥ 2 | ✅ |
| Motif overlap guard | ✅ | ≥ 2 | — |
| Audio asset graceful degradation | — | — | ✅ |

### Concrete Test Cases

#### TC-BGM-N1 — BGM Ambient Bed Plays on _ready
- **Type:** Unit
- **Setup:** Instantiate AudioManager with BGM setup
- **Steps:**
  1. Call `_ready()` (which calls `_setup_bgm_players()` + `_load_bgm_streams()`)
  2. Assert `_bgm_player` is not null
  3. Assert `_bgm_player.bus == "MusicBus"`
  4. Assert `_bgm_player.stream` is set (or gracefully null if asset missing)
- **Verification:** BGM player exists and is wired to MusicBus

#### TC-BGM-N2 — NPC Motif Trigger Fades In
- **Type:** Unit
- **Setup:** AudioManager with preloaded motif streams
- **Steps:**
  1. Call `trigger_bgm_motif("Stranger")`
  2. Assert `_active_npc_id == "Stranger"`
  3. Assert `_bgm_state == "npc_active"`
  4. Assert `_motif_player.stream` is Stranger motif
  5. Assert `_motif_player.volume_db` is tweening from -80 to 0 dB
- **Verification:** Motif fades in; state updates

#### TC-BGM-N3 — Dialogue Ducking Lowers Volume
- **Type:** Unit
- **Setup:** AudioManager with active BGM motif
- **Steps:**
  1. Call `set_bgm_ducking(true)`
  2. Assert `_motif_player.volume_db` target is `BGM_DUCK_DB` (-8 dB)
  3. Assert `_bgm_player.volume_db` target is `BGM_AMBIENT_DUCK_DB` (-3 dB)
  4. Call `set_bgm_ducking(false)`
  5. Assert volume targets return to 0 dB
- **Verification:** Ducking volume reductions are correct

#### TC-BGM-N4 — Motif Auto-Fades Out After 5 Seconds
- **Type:** Unit
- **Setup:** AudioManager with active motif
- **Steps:**
  1. Call `_on_npc_dialogue_ended("Stranger")`
  2. Assert `_motif_hold_timer` is started with `MOTIF_HOLD_TIME` (5.0)
  3. Simulate timer timeout
  4. Assert `_motif_player.volume_db` is tweening to -80 dB
  5. After tween completes: assert `_bgm_state == "ambient"`, `_active_npc_id == ""`
- **Verification:** Motif holds 5s then fades out; state resets

#### TC-BGM-E1 — Rapid NPC Approach/Leave Cancels Fade
- **Type:** Unit, Edge Case
- **Setup:** AudioManager in ambient state
- **Steps:**
  1. Call `trigger_bgm_motif("Guard")` — fade-in begins
  2. Immediately call `clear_bgm_motif()` (within 0.5s, before fade-in completes)
  3. Assert previous tween is killed
  4. Assert `_bgm_state == "ambient"`
  5. Assert `_motif_player.volume_db` tween targets -80 (fade-out from current level)
- **Verification:** No audio pop; fade-in is reversed cleanly

#### TC-BGM-E2 — Two NPCs in Proximity: Only One Motif
- **Type:** Unit, Edge Case
- **Setup:** AudioManager playing motif for "Guard"
- **Steps:**
  1. Call `trigger_bgm_motif("Clerk")` while Guard motif is active
  2. Assert `_active_npc_id == "Clerk"` (most recent)
  3. Assert Guard motif is faded out, Clerk motif is faded in
  4. Assert no overlap (only _motif_player plays one stream at a time)
- **Verification:** Motif overlap guard prevents simultaneous playback

#### TC-BGM-E3 — Ending Music Overrides Active Motif
- **Type:** Unit, Edge Case
- **Setup:** AudioManager with active Guard motif
- **Steps:**
  1. Call `set_ending_music("keep_walking")`
  2. Assert Guard motif is faded out immediately (hold timer cancelled)
  3. Assert `_bgm_state == "ending"`
  4. Assert `_ending_player.stream` is set to keep_walking track
  5. Assert `_ending_player.volume_db` tween targets 0 dB
- **Verification:** Ending music takes priority; motif is cancelled

#### TC-BGM-F1 — Missing BGM Asset Graceful Degradation
- **Type:** Unit, Failure Path
- **Setup:** AudioManager with null motif stream
- **Steps:**
  1. Null the `_motif_player.stream` reference
  2. Call `trigger_bgm_motif("Stranger")`
  3. Assert no crash (push_warning logged)
  4. Assert game continues with ambient audio only
- **Verification:** Graceful null-guard; no crash

#### TC-BGM-F2 — Missing NPC Signal Graceful Degradation
- **Type:** Unit, Failure Path
- **Setup:** NPCNode without `npc_dialogue_started` signal
- **Steps:**
  1. In `_connect_npc_signals()`, NPC node has no signal
  2. Assert `has_signal()` returns false → no connection made
  3. Assert no error logged (graceful skip)
- **Verification:** Missing signal doesn't break _connect_npc_signals()

#### TC-3D-N1 — 3D Rain Player Positioning
- **Type:** Unit
- **Setup:** AudioManager with 3D players
- **Steps:**
  1. Call `_setup_3d_players()`
  2. Assert `_rain_3d_player` is not null
  3. Assert `_rain_3d_player.position == RAIN_3D_POSITION`
  4. Assert `_rain_3d_player.max_db_distance > 0` (finite attenuation model)
- **Verification:** 3D rain player exists and is positioned correctly

#### TC-3D-N2 — Per-Scene 3D Profile Switching
- **Type:** Unit
- **Setup:** AudioManager with 3D players
- **Steps:**
  1. Call `register_scene("office")` — indoor profile
  2. Assert `_rain_3d_player.volume_db` is lower than outdoor
  3. Call `register_scene("street")` — outdoor profile
  4. Assert `_rain_3d_player.volume_db` is full
- **Verification:** 3D rain volume varies by scene profile

#### TC-HALL-N1 — Hallucination Level <5: No Effects
- **Type:** Unit
- **Setup:** AudioManager with hallucination system
- **Steps:**
  1. Set `_hallucination_level = 0`
  2. Call `_update_hallucination_effects()`
  3. Assert HallucinationFXBus all effects are bypassed (disabled)
  4. Assert `_hallucination_effects_active == false`
- **Verification:** Below threshold, no audio distorition

#### TC-HALL-N2 — Hallucination Level 5: LowPass + Reverb Enabled
- **Type:** Unit
- **Setup:** AudioManager with hallucination system
- **Steps:**
  1. Call `_on_hallucination_level_changed(5)`
  2. Assert HallucinationFXBus effect 0 (LowPass) is enabled
  3. Assert HallucinationFXBus effect 1 (Reverb) is enabled
  4. Assert effect 2 (Delay) is bypassed (level < 7)
  5. Assert `_hallucination_effects_active == true`
- **Verification:** Level 5 enables LPF + reverb

#### TC-HALL-N3 — Hallucination Level 7: Delay Added
- **Type:** Unit
- **Setup:** AudioManager at level 5
- **Steps:**
  1. Call `_on_hallucination_level_changed(7)`
  2. Assert effect 2 (Delay) is now enabled
  3. Assert pitch oscillation depth increased to `HALLUCINATION_PITCH_DEPTH_HIGH`
- **Verification:** Level 7 adds delay + stronger LFO

#### TC-HALL-N4 — Hallucination Level 9: Dropout Active
- **Type:** Unit
- **Setup:** AudioManager at level 7
- **Steps:**
  1. Call `_on_hallucination_level_changed(9)`
  2. Assert `_hallucination_dropout_timer` is started (repeating)
  3. Assert effect 3 (Phaser) is enabled
  4. On dropout timer trigger: assert volume drops to -80 dB for ~100ms
- **Verification:** Level 9 adds intermittent dropout + phaser

#### TC-HALL-E1 — Hallucination Level Drops Below Threshold: Effects Fade Out
- **Type:** Unit, Edge Case
- **Setup:** AudioManager at level 7 with active effects
- **Steps:**
  1. Call `_on_hallucination_level_changed(4)` — below 5
  2. Assert effects are tweening to disabled (1s smooth transition)
  3. After tween: assert all HallucinationFXBus effects are bypassed
  4. Assert `_hallucination_lfo_timer` is stopped
- **Verification:** Smooth transition out when level drops below 5

#### TC-HALL-E2 — LFO Pitch Oscillation on Rain
- **Type:** Unit, Edge Case
- **Setup:** AudioManager at level 5 with 3D rain player
- **Steps:**
  1. Record `_rain_3d_player.pitch_scale` at t=0
  2. Advance `_hallucination_lfo_time` by 0.5s (quarter cycle at 0.5 Hz)
  3. Call `_apply_hallucination_lfo(0.5)`
  4. Assert `_rain_3d_player.pitch_scale` changes (±0.1 at 0.5 Hz)
  5. Advance another 0.5s: assert pitch returns toward original
- **Verification:** LFO modulates rain pitch smoothly

#### TC-HALL-E3 — Hallucination Change During Dialogue
- **Type:** Unit, Edge Case
- **Setup:** AudioManager in dialogue (ducking active) + hallucination level change
- **Steps:**
  1. Set BGM ducking active
  2. Call `_on_hallucination_level_changed(7)` — effect enable
  3. Assert volume ducking still active (not overridden by hallucination effects)
  4. Assert hallucination effects are added alongside ducking (not replacing)
- **Verification:** Ducking and hallucination effects are independent layers

#### TC-HALL-F1 — No NarrativeManager Autoload
- **Type:** Unit, Failure Path
- **Setup:** AudioManager without NarrativeManager in scene tree
- **Steps:**
  1. Call `_connect_hallucination_signals()`
  2. Assert `get_node_or_null("/root/NarrativeManager")` returns null
  3. Assert no signal connection made
  4. Assert no crash — game continues without hallucination audio
- **Verification:** Graceful null-guard

#### TC-ENDING-N1 — Ending Music Cross-Fades Ambient
- **Type:** Unit
- **Setup:** AudioManager playing ambient BGM + rain
- **Steps:**
  1. Call `set_ending_music("keep_walking")`
  2. Assert `_ending_player.stream` is keep_walking audio
  3. Assert `_ending_player.volume_db` is tweening from -80 to 0 dB (fade-in)
  4. Assert `_bgm_player.volume_db` is tweening to -80 dB (fade-out)
  5. Assert `_rain_player.volume_db` is tweening to -80 dB
- **Verification:** Ending music cross-fades; ambient fades out

#### TC-ENDING-E1 — Ending Triggers While NPC Motif Active
- **Type:** Unit, Edge Case
- **Setup:** AudioManager with active Guard motif
- **Steps:**
  1. Call `set_ending_music("turn_back")`
  2. Assert `_motif_player.volume_db` tween targets -80 (immediate fade-out)
  3. Assert `_motif_hold_timer` is stopped (cancelled)
  4. Assert `_bgm_state == "ending"`
- **Verification:** Ending music cancels active motif

#### TC-ENDING-F1 — Missing Ending Asset
- **Type:** Unit, Failure Path
- **Setup:** AudioManager with null ending stream
- **Steps:**
  1. Null the `_ending_player.stream` reference
  2. Call `set_ending_music("keep_walking")`
  3. Assert push_warning logged: "Ending music asset not found"
  4. Assert ambient audio still plays normally
- **Verification:** Missing ending asset doesn't crash

---

## 8. Implementation Priority Order

| # | Step | Description | Dependencies |
|---|------|-------------|-------------|
| 1 | **AudioManager 扩展骨架** | 添加 BGM players、3D players、新 bus 索引、新常量/变量 | 无 |
| 2 | **Bus Layout 更新** | 添加 MusicBus、HallucinationFXBus、CinemaBus | Step 1 |
| 3 | **3D 空间环境音** | 转换雨声/城市嗡嗡声到 AudioStreamPlayer3D；添加 scene profile 3D 配置 | Step 1-2 |
| 4 | **车流+地铁隆隆声** | 资源 + player + per-scene 激活 | Step 1-3 |
| 5 | **幻觉音频系统** | 连接 signal、effect chain、LFO、dropout | Step 1-2 |
| 6 | **BGM 系统** | ambient bed + per-scene 音量配置 | Step 1-2 |
| 7 | **NPC→BGM 集成** | NPC 新信号 + motif 触发 + ducking + auto-fade-out | Step 1-2, 6 |
| 8 | **结局音乐** | 3 个 ending track + trigger 集成 | Step 1-2, 6 |
| 9 | **NPC node 修改** | 新增 `npc_dialogue_started` 信号 | Step 7 |
| 10 | **SceneBase 扩展** | 新增 `_configure_bgm()` 虚方法 | Step 6 |
| 11 | **测试** | 所有测试用例 | Step 1-10 |

### 依赖图

```
Step 1 (Skeleton) ─┬─ Step 2 (Bus) ─┬─ Step 5 (Hallucination)
                   │                ├─ Step 6 (BGM) ─┬─ Step 7 (NPC→BGM) ── Step 9 (NPC signal)
                   │                │                └─ Step 8 (Ending)
                   │                └─ Step 3 (3D) ── Step 4 (Traffic/Subway)
                   └─ Step 10 (SceneBase)
                                                      └─ Step 11 (Tests)
```

---

## 9. Files Changed（汇总）

| File | Type | Change | Est. Lines |
|------|------|--------|-----------|
| `gdscripts/audio_manager.gd` | **Modify** | 扩展：BGM players、3D players、hallucination system、NPC→BGM signals | +350 |
| `gdscripts/npc_node.gd` | **Modify** | 新增 `npc_dialogue_started` signal + `_on_body_entered` 触发 | +8 |
| `gdscripts/scene_base.gd` | **Modify** | 新增 `_configure_bgm()` 虚方法 | +12 |
| `default_bus_layout.tres` | **Modify** | 新增 MusicBus, HallucinationFXBus, CinemaBus | +40 |
| `gdscripts/dialogue_runner.gd` | **Modify** | 新增 `"trigger_event"` case for ending music | +8 |
| `gdscripts/subway_station.gd` | **Modify** | 在 ending 触发时调用 `set_ending_music()` | +10 |
| `assets/audio/ambient_music.ogg` | **New** | 环境 BGM bed | N/A |
| `assets/audio/npc_stranger_music.ogg` | **New** | 陌生人 NPC motif | N/A |
| `assets/audio/npc_guard_music.ogg` | **New** | 警卫 NPC motif | N/A |
| `assets/audio/npc_clerk_music.ogg` | **New** | 店员 NPC motif | N/A |
| `assets/audio/npc_homeless_music.ogg` | **New** | 流浪汉 NPC motif | N/A |
| `assets/audio/ending_keep_walking.ogg` | **New** | Keep Walking 结局音乐 | N/A |
| `assets/audio/ending_turn_back.ogg` | **New** | Turn Back 结局音乐 | N/A |
| `assets/audio/ending_stay.ogg` | **New** | Stay 结局音乐 | N/A |
| `assets/audio/traffic_rumble.ogg` | **New** | 远处车流环境音 | N/A |
| `assets/audio/subway_rumble.ogg` | **New** | 地铁隆隆声（远） | N/A |
| `assets/audio/subway_rumble_close.ogg` | **New** | 地铁隆隆声（近） | N/A |
| `tests/unit/test_audio_manager.gd` | **Modify** | 新增 BGM/3D/幻觉/ending 测试 | +100 |
| `tests/integration/test_audio_state_modulation.gd` | **Modify** | 新增幻觉等级→音频效果测试 | +40 |

### 总计

| Category | New | Modify | Est. Lines |
|----------|-----|--------|-----------|
| GDScript | 0 | 5 | +388 |
| Bus Layout | 0 | 1 | +40 |
| Audio Assets | 11 | 0 | N/A |
| Tests | 0 | 2 | +140 |
| **Total** | **11** | **8** | **+568** (code) |

---

## 10. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Music assets unavailable (creative bottleneck) | High | High | 使用 placeholder tones（纯正弦波）用于开发测试；尽早开始资产创作 |
| 3D spatial audio 与 2D transform 冲突 | Low | Medium | AudioManager 将 3D players 附加到场景根节点；在 `_process` 中同步位置 |
| Hallucination effect stack 超载音频硬件 | Low | Low | 限制并发效果；使用 bus-level wet/dry mix（非 per-player 效果） |
| NPC→BGM motif 重叠（两个 NPC 靠近） | Medium | Medium | `_active_npc_id` 守卫 + `_queued_motif` 队列 |
| Dialogue ducking 与 hallucination effects 冲突 | Low | Low | Ducking 是 volume 层；hallucination 是 effect 层，完全独立 |
| BGM cross-fade pop（tween retargeting） | Low | Low | 使用 `tween.kill()` + `create_tween()` pattern（已验证于 `cross_fade_ambient`） |
| NPC node 没有 `npc_dialogue_started` signal | Low | Medium | `has_signal()` 检查 + 无 signal 跳过（兼容旧版 NPC） |

---

## 11. Verification Checklist

- [ ] TC-BGM-N1 to TC-BGM-N4: BGM system tests pass (ambient bed, motif, ducking, auto-fade)
- [ ] TC-BGM-E1 to TC-BGM-E3: Edge cases pass (rapid approach, NPC overlap, ending override)
- [ ] TC-BGM-F1 to TC-BGM-F2: Failure paths pass (missing asset, missing signal)
- [ ] TC-3D-N1 to TC-3D-N2: 3D spatial audio tests pass
- [ ] TC-HALL-N1 to TC-HALL-N4: Hallucination effect tests pass (level 5, 7, 9)
- [ ] TC-HALL-E1 to TC-HALL-E3: Hallucination edge cases pass (level drop, LFO, dialogue)
- [ ] TC-HALL-F1: Hallucination failure path passes (no NarrativeManager)
- [ ] TC-ENDING-N1: Ending music cross-fade test passes
- [ ] TC-ENDING-E1: Ending over NPC motif test passes
- [ ] TC-ENDING-F1: Missing ending asset test passes
- [ ] Walk through all 7 scenes: 3D rain spatial presence correct per scene
- [ ] 3D rain directionality: rain from above-front on bridge, from entrance in underpass
- [ ] City ambience: traffic on street, subway rumble in underpass/subway
- [ ] 4 NPC encounters: unique motifs play for each
- [ ] Dialogue ducking: BGM volume drops -8 dB during dialogue
- [ ] Post-dialogue: motif holds 5s then cross-fades back to ambient
- [ ] Hallucination level 5: rain muffled + reverby
- [ ] Hallucination level 7: pitch wobble + delay echoes
- [ ] Hallucination level 9: audio dropouts
- [ ] 3 endings → unique music plays over credits
- [ ] Ending music fades gracefully on menu return
- [ ] Missing NPC signal: graceful degradation, no crash
- [ ] Missing BGM assets: game continues with ambient-only audio
- [ ] No regression on existing features (rain, city hum, footsteps, state modulation, scene transitions)
- [ ] All pre-existing tests still pass
