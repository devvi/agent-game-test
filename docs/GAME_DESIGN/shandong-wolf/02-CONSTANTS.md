# WolfConstants — 数值集中地（#572）

> 落盘依据：PR #599（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/572-scaffold-main-entry.md` §2.1。
> 本文件为 shandong-wolf 全部数值的**单一事实源**；所有视觉与手感参数必须集中于此，禁止散落硬编码（brief 红线）。

## 1. 设计意图

shandong-wolf 骨架期（#559-#570）`gdscripts/` 为空，后续 #573-#578 的手感参数面临散落硬编码的风险。本文件作为**数值集中地**先行落位：机械常量（非品味参数）骨架期定稿；手感参数全部以 `# DRAFT` 候补值占位，**定稿归 #584**（taste 域，本文件禁止"顺手定稿"）。

## 2. 架构决策

| 方案 | 内容 | 裁决 |
|------|------|:----:|
| A（采纳） | `class_name WolfConstants`，`extends RefCounted`，preload 静态访问 | ✅ 非 Node 不挂场景树，headless 单测可直接引用 |
| B（否决） | 第三方 addon（LimboAI 等） | ❌ 六组件约 40 行自研即满足，不引依赖 |
| C（否决） | autoload 挂 constants（单例化） | ❌ 静态常量无需实例，preload 编译期解析更稳 |

消费方模式：`const C = preload("res://gdscripts/constants.gd")` → `C.PARRY_WINDOW_FRAMES`。

## 3. 常量定义

文件：`shandong-wolf/gdscripts/constants.gd`（类名 `WolfConstants`，extends RefCounted）。

### 3.1 机械常量（骨架期定稿，非 taste 参数）

| 常量 | 值 | 说明 |
|------|----|------|
| `GAME_VERSION` | `"v0.1.0"` | 与 Main.tscn VersionLabel 一致（#562） |
| `SCREEN_WIDTH` | `1280` | project.godot viewport_width（AC1） |
| `SCREEN_HEIGHT` | `720` | project.godot viewport_height（AC1） |
| `STATE_MACHINE_MAX_TRANSITIONS` | `1` | 状态机单次 update 允许的最大 transition 数（防重入预留，§03） |

### 3.2 手感分区（5 个 `# DRAFT` 分区，候补值待 #584 定稿）

每个分区含「候补值 / 该值影响什么 / 情感断言」三行注释（mini-pong constants.gd 注释风格移植）。

**弹反窗口**（只狼系参考：判定极短，成功即架势重创；生死一瞬的"叮"）

| 常量 | 候补值 | 说明 |
|------|--------|------|
| `PARRY_WINDOW_FRAMES` | `12` | 12 帧 @60fps = 0.2s |
| `PARRY_WINDOW_SECONDS` | `0.2` | = FRAME_RHYTHM 的派生展示 |

**架势回复**（架势条 = 格挡/弹反资源；崩解 → 处决，brief 核心机制 #5）

| 常量 | 候补值 | 说明 |
|------|--------|------|
| `POSTURE_RECOVERY_PER_SEC` | `0.8` | 自然回复 0.8 架势/秒 |
| `POSTURE_BLOCK_COST` | `10.0` | 格挡消耗 10 |
| `POSTURE_BREAK_THRESHOLD` | `100.0` | 满则崩解 |

**两条命数值**（只狼式两条命，brief 核心机制 #4）

| 常量 | 候补值 | 说明 |
|------|--------|------|
| `LIFE_TOTAL` | `2` | 机械语义可定稿 |
| `LIFE_1_MAX` | `100.0` | 第 1 条满血 |
| `LIFE_2_MAX_RATIO` | `0.5` | 第 2 条 = 半管血 |

**刀伤害**（击杀节奏；刀来自尸体，brief 剧情起点）

| 常量 | 候补值 | 说明 |
|------|--------|------|
| `SWORD_DAMAGE_LIGHT` | `10.0` | 轻击 |
| `SWORD_DAMAGE_HEAVY` | `25.0` | 重击 |
| `SWORD_DAMAGE_EXECUTE` | `999.0` | 处决，无视架势直接击杀 |

**帧节奏**（攻防"帧感"，只狼系动作核心手感）

| 常量 | 候补值 | 说明 |
|------|--------|------|
| `FRAME_ATTACK_WINDUP` | `8` | 攻击前摇 |
| `FRAME_ATTACK_RECOVERY` | `14` | 攻击后摇 |
| `FRAME_RHYTHM_BASE` | `60` | 基准帧率参考 |

## 4. # DRAFT 纪律与回归保护

- 实现期删除 `# DRAFT` 标记或改值定稿 = `test_constants.gd` FAIL（E2 断言：文件含 ≥5 处 `# DRAFT`、不含「# 定稿」字样）。
- 定稿唯一通道：#584（用户裁决替换候补值 + 去标记）。
- `test_constants.gd` 同时断言 5 分区常量存在（E1）与机械常量值（E3，与 project.godot/Main.tscn 联动）。

## 5. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #572 | 逻辑地基（本文件所属） | 已合并（#599） |
| #584 | 数值定稿（# DRAFT → 定稿） | 待定稿 |
