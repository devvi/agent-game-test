# WolfConstants — 数值集中地（#572/#584）

> 落盘依据：PR #599（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/572-scaffold-main-entry.md` §2.1；
> #584 全量 DRAFT 值表（PR #609，已 merge 2026-08-19）← DESIGN `docs/DESIGN/584-combat-tuning-draft.md` §2.3。
> 本文件为 shandong-wolf 全部数值的**单一事实源**；所有视觉与手感参数必须集中于此，禁止散落硬编码（brief 红线）。

## 1. 设计意图

shandong-wolf 骨架期（#559-#570）`gdscripts/` 为空，后续 #573-#578 的手感参数面临散落硬编码的风险。本文件作为**数值集中地**先行落位：机械常量（非品味参数）骨架期定稿；手感参数全部以 `# DRAFT` 候补值占位。

#584 把占位值升级为**有出处的 DRAFT 表**：每个手感参数带「只狼基准 → 候选集 → 偏离理由」三行注释（只狼体系为 2026-08-19 用户拍板的数值基准），并从 5 分区扩展到 6 分区、新增受击/敌人/处决 7 参数。**定稿仍归 #584**（taste 域，用户实机裁决后替换候补值 + 去 DRAFT 标记；本文件禁止"顺手定稿"）。

## 2. 架构决策

| 方案 | 内容 | 裁决 |
|------|------|:----:|
| A（采纳） | `class_name WolfConstants`，`extends RefCounted`，preload 静态访问 | ✅ 非 Node 不挂场景树，headless 单测可直接引用 |
| B（否决） | 第三方 addon（LimboAI 等） | ❌ 六组件约 40 行自研即满足，不引依赖 |
| C（否决） | autoload 挂 constants（单例化） | ❌ 静态常量无需实例，preload 编译期解析更稳 |

消费方模式：`const C = preload("res://gdscripts/constants.gd")` → `C.PARRY_WINDOW_FRAMES`。
#584 起新消费方（#575/#577）推荐经 `DebugCanvas.get_value("NAME", C.NAME)` 读值（debug 热更新优先，release 回落 const），见 05-DEBUG-CANVAS.md §4。

## 3. 常量定义

文件：`shandong-wolf/gdscripts/constants.gd`（类名 `WolfConstants`，extends RefCounted）。

### 3.1 机械常量（骨架期定稿，非 taste 参数）

| 常量 | 值 | 说明 |
|------|----|------|
| `GAME_VERSION` | `"v0.1.0"` | 与 Main.tscn VersionLabel 一致（#562） |
| `SCREEN_WIDTH` | `1280` | project.godot viewport_width（AC1） |
| `SCREEN_HEIGHT` | `720` | project.godot viewport_height（AC1） |
| `STATE_MACHINE_MAX_TRANSITIONS` | `1` | 状态机单次 update 允许的最大 transition 数（防重入预留，§03） |

### 3.2 手感分区（6 个 `# DRAFT` 分区，14+ 参数，候补值待 #584 用户定稿）

#584 起每个参数带三行注释（只狼基准 / 候选集 / 偏离理由）+ `# # DRAFT` 标记，注释格式：

```gdscript
# PARRY_WINDOW_FRAMES
#   只狼基准: ~12 帧（0.2s @60fps，偏宽松=容错手感来源）
#   候选集: [8, 10, 12, 14]（默认 12 = 只狼基准；8/14 为容错两极备选）
#   偏离理由: 无——只狼基准直接采纳
```

**弹反窗口**（只狼系参考：判定极短，成功即架势重创；生死一瞬的"叮"）

| 常量 | 只狼基准 | 候选集 | DRAFT 默认 | 说明 |
|------|---------|--------|:---:|------|
| `PARRY_WINDOW_FRAMES` | ~12 帧（0.2s @60fps） | [8, 10, 12, 14] | `12` | 弹反判定时间窗（越短越硬核） |
| `PARRY_WINDOW_SECONDS` | = 帧数换算 | — | `0.2` | FRAME_RHYTHM_BASE 派生展示 |

**架势回复**（架势条 = 格挡/弹反资源；崩解 → 处决，brief 核心机制 #5）

| 常量 | 只狼基准 | 候选集 | DRAFT 默认 | 说明 |
|------|---------|--------|:---:|------|
| `POSTURE_RECOVERY_PER_SEC` | 20-35/s（节奏阀） | [20, 25, 30, 35] | `25` | 自然回复速度（#572 占位 0.8/s 与基准差 25-43 倍，#584 全量重写） |
| `POSTURE_RECOVERY_DELAY` | 脱战 1.5s | [1.0, 1.5, 2.0] | `1.5` | 停防后多久开始回复 |
| `POSTURE_BLOCK_COST` | 8-12/次 | [8, 10, 12] | `10` | 长按格挡的架势代价 |
| `POSTURE_BREAK_THRESHOLD` | = 当前 HP 上限（只狼铁律） | 派生（恒等于 LIFE_1_MAX） | `100` | 满则崩解 → 可处决 |

**两条命数值**（只狼式回生，brief 核心机制 #4；#584 新增 LIFE_2_ABS 绝对血量参数）

| 常量 | 只狼基准 | 候选集 | DRAFT 默认 | 说明 |
|------|---------|--------|:---:|------|
| `LIFE_TOTAL` | 回生机制 | [2]（机械语义） | `2` | 两条命结构 |
| `LIFE_1_MAX` | 100%（20 格） | [100, 120] | `100` | 第 1 条满血（容错） |
| `LIFE_2_ABS` | 回生后约半血 | [40, 50, 60] | `50` | 第 2 条绝对血量（#584 新增） |
| `LIFE_2_MAX_RATIO` | 派生展示 | [0.4, 0.5, 0.6] | `0.5` | = LIFE_2_ABS / LIFE_1_MAX（消费方经 get_value 读派生值） |

**刀伤害**（击杀节奏；刀来自尸体，brief 剧情起点）

| 常量 | 只狼基准 | 候选集 | DRAFT 默认 | 说明 |
|------|---------|--------|:---:|------|
| `SWORD_DAMAGE_LIGHT` | 轻击 10-15 | [10, 12, 15] | `12` | 轻击架势伤害 |
| `SWORD_DAMAGE_HEAVY` | 重击 25-40 | [25, 30, 40] | `30` | 重击架势伤害 |
| `SWORD_DAMAGE_EXECUTE` | 忍杀 = 一击必杀 | [999.0]（机械语义） | `999` | 处决，无视架势直接击杀 |

**帧节奏**（攻防"帧感"，只狼系动作核心手感；#584 玩家侧保留、敌人前摇独立参数化）

| 常量 | 只狼基准 | 候选集 | DRAFT 默认 | 说明 |
|------|---------|--------|:---:|------|
| `FRAME_ATTACK_WINDUP` | 玩家前摇可读 | [6, 8, 10] | `8` | 玩家攻击前摇（#572 占位延续） |
| `FRAME_ATTACK_RECOVERY` | 后摇可惩罚 | [12, 14, 16] | `14` | 玩家攻击后摇 |
| `FRAME_RHYTHM_BASE` | 基准帧率参考 | — | `60` | 机械常量语义 |

**受击/敌人/处决**（#584 新增分区，issue body 要求参数）

| 常量 | 只狼基准 | 候选集 | DRAFT 默认 | 说明 |
|------|---------|--------|:---:|------|
| `POSTURE_HIT_COST` | 受击扣架势 30-40/次 | [30, 35, 40] | `35` | 血+架势双重惩罚，逼玩家进攻（只狼核心哲学） |
| `PARRY_COST` | 弹反成功扣 0 | [0, 1, 2] | `1` | 默认 1 防无脑弹反，用户实机裁决 0/1/2 |
| `ENEMY_ATTACK_WINDUP` | 危攻击 14-18 帧 | [12, 15, 18] | `15` | 敌人攻击前摇（可读性） |
| `EXECUTE_RANGE` | 忍杀触发 = 近身 | [1.0, 1.2, 1.5] | `1.2` | 处决触发距离 |
| `SLOWMO_COEFF` | 处决 hit-stop 慢动作 | [0.1, 0.2, 0.3] | `0.2` | 处决慢动作系数（消费方 #577 在 Engine.time_scale 应用，clamp 下限 0.1 防冻结） |

### 3.3 动画帧节奏 / 骨骼几何配色 / 刀光弧线参数（#574 追加分区，全部 `# DRAFT` 候补值）

#574（PR #612，已 merge 2026-08-19）在 §3.2 帧节奏分区内追加 `FRAME_ANIM_*` 动画帧节奏 7 常量 +
`BODY_*`/`SWORD_*` 骨骼几何配色 9 常量，并新增独立「刀光弧线参数」分区 4 常量——全部 `# DRAFT`
候补值（候补值+影响+情感断言三行注释），**定稿仍归 #584**。⚠️ 双值冲突：
`FRAME_ANIM_ATTACK_RECOVERY=10` 与 `FRAME_ATTACK_RECOVERY=14` 并存互引，禁止实现期二选一偷定。

**动画帧节奏**（《小小系列》式「起势慢→爆发快→收招滞」力度感，消费方 07-STICK-FIGURE-ANIMATION.md）

| 常量 | 值 | 说明 |
|------|----|------|
| `FRAME_ANIM_ATTACK_WINDUP` | `8` | 攻击前摇（与 FRAME_ATTACK_WINDUP=8 对齐互引） |
| `FRAME_ANIM_ATTACK_BURST` | `4` | 挥刀暴发（刀光在此段触发） |
| `FRAME_ANIM_ATTACK_RECOVERY` | `10` | ⚠️ 与 FRAME_ATTACK_RECOVERY=14 冲突，双值共存互引 |
| `FRAME_ANIM_TRANSITION_MAX` | `2` | AC1 过渡上限（2 帧 @60fps = 0.033s） |
| `FRAME_ANIM_MOVE_STEP` | `4` | 步态摆臂循环 4 帧 |
| `FRAME_ANIM_EXECUTE_TOTAL` | `5` | 处决上撩→斩落 5 帧 |
| `FRAME_ANIM_SWORD_ARC_FADE` | `4` | 刀光存在/衰减帧数 |

**骨骼几何与配色**（剪影可读性：角色总高 ≈150px @720p 画布，头:躯干:臂:腿 ≈ 1:2.5:1.9:2.2）

| 常量 | 值 | 说明 |
|------|----|------|
| `BODY_COLOR` | `#2b2b2b` | issue body 指定墨色剪影 |
| `SWORD_COLOR` | `#c0c8d0` | 冷白刀身，雪夜反差点 |
| `BODY_HEAD_RADIUS` | `16.0` | 头圆半径 |
| `BODY_TORSO_LENGTH` | `44.0` | 躯干长 |
| `BODY_ARM_LENGTH` | `34.0` | 臂长 |
| `BODY_LEG_LENGTH` | `40.0` | 腿长 |
| `BODY_LIMB_WIDTH` | `6.0` | Line2D width |
| `SWORD_LENGTH` | `88.0` | 长刀，视觉焦点 |
| `SWORD_WIDTH` | `5.0` | 刀宽 |

**刀光弧线参数**（挥砍轨迹可读性——张角过大刺眼、过小看不清轨迹）

| 常量 | 值 | 说明 |
|------|----|------|
| `SWORD_ARC_SWEEP_DEG` | `120.0` | 张角（PRD 实验 2 预期最佳值） |
| `SWORD_ARC_RADIUS` | `70.0` | 弧半径 |
| `SWORD_ARC_RINGS` | `4` | 径向透明度衰减环数 |
| `SWORD_ARC_ALPHA_START` | `0.6` | 起始 alpha |

> 上述分区均可用 DebugCanvas 运行时 override（仅进程内生效），消费与调参链路见 05-DEBUG-CANVAS.md §4、
> 动画消费契约见 07-STICK-FIGURE-ANIMATION.md。

## 4. # DRAFT 纪律与回归保护

- 实现期删除 `# DRAFT` 标记或改值定稿 = `test_constants.gd` FAIL（E2 断言：文件含 ≥5 处 `# DRAFT`、不含「# 定稿」字样；#584 扩展为 14 参数存在性 + 三行注释格式 + 候选集断言）。
- 定稿唯一通道：#584（用户实机裁决替换候补值 + 去标记；裁决后回填 `docs/TASTE.md` shandong-wolf §③ 定稿差异记录）。
- `test_constants.gd` 同时断言 5 分区常量存在（E1）与机械常量值（E3，与 project.godot/Main.tscn 联动）。
- 运行中调参不破坏 DRAFT 纪律：override 仅进程内生效（DebugCanvas），代码值保持候补，见 05-DEBUG-CANVAS.md。

## 5. 战斗时序分区（#575/#618 追加）

> 追加式新增分区（PR #618，已 merge 2026-08-19），不触碰既有 8 分区任何一行；全部 `# DRAFT` 只读，
> 定稿归 #584（调参面板）。注释遵循 #572 规范：候补值 + 影响什么 + 情感断言。
> 消费方：combat_states.gd 定时状态自动退出（帧/秒计数）+ CombatEntity 复活无敌期计时。

| 常量 | 候补值 | 候选集 | 说明 | 消费方 |
|------|--------|--------|------|--------|
| `STAGGER_FRAMES` | `12` | [8, 12, 16] | 受击硬直时长——太短无受击感，太长卡操作 | StaggerState |
| `PARRY_SUCCESS_FRAMES` | `10` | [8, 10, 12] | 弹反成功瞬间帧（硬直窗口，#577 驱动进入） | ParrySuccessState |
| `STANCE_BREAK_RECOVERY_SEC` | `3.0` | —（#580 同值互引） | 崩解后敌人起身恢复时间 | StanceBreakState |
| `REVIVE_SECONDS` | `1.0` | —（#578 同值互引） | 倒地→复活的演出时长 | ReviveState |
| `INVINCIBLE_SECONDS` | `1.0` | —（#578 同值互引） | 复活后无敌时长 | CombatEntity |

## 6. 判定分区（#577/#626 追加）

> 追加式新增分区（PR #626，已 merge 2026-08-19），不触碰既有分区任何一行；全部 `# DRAFT` 只读，
> 定稿归 #584（调参面板）。注释遵循 #572 规范：候补值 + 影响什么 + 情感断言。
> 消费方：combat_judge.gd（裁决）+ combat_attack_window.gd（窗口契约），详见 11-PARRY-CLASH-STANCE-BREAK.md。

| 常量 | 候补值 | 候选集 | 说明 | 消费方 |
|------|--------|--------|------|--------|
| `PARRY_STANCE_DAMAGE` | `25.0` | [20, 25, 30] | 弹反成功涨敌架势（AC1 ≥20 硬约束） | CombatJudge 弹反路径 |
| `CLASH_STANCE_COST` | `10.0` | [8, 10, 12] | 拼刀双方各扣小架势 | CombatJudge 拼刀路径 |
| `CLASH_PRIORITY` | `0` | [0=弹反优先, 1=拼刀优先] | 同帧三重叠裁决顺序开关 | resolve_attack 顺序 |
| `HITBOX_ACTIVE_FRAMES` | `4` | [4, 6, 8] | 攻击暴发判定持续帧（与 #574 暴发帧对齐） | AttackWindow.is_active |
| `HITBOX_RANGE` | `80.0` | [60, 80, 100] | 横板一维命中距离阈值 px | resolve_attack 距离校验 |
| `PARRY_DIRECTION_TOLERANCE` | `1` | [1=仅同侧, 2=宽容] | 弹反必须面向攻击 | resolve_attack facing 校验 |

## 7. 氛围分区指针（#582/#624，载体 impl/582 分支）

> 雪幕/冷月光/夜色背景/水墨/血色 五分区常量（MOONLIGHT_*/NIGHT_BG_COLOR/INK_*/BLOOD_*）随
> #582 氛围实现落地于 **impl/582-snow-night-atmosphere 分支**（main 上无氛围代码），常量表、
> 层契约与 C3 守卫详见 [12-ATMOSPHERE-SNOW-NIGHT](12-ATMOSPHERE-SNOW-NIGHT.md)。
> 全部 `# DRAFT` 候补值，定稿归 #582 用户裁决（#624 修复只定约束不定值）。

## 8. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #572 | 逻辑地基（本文件所属，5 分区骨架） | 已合并（#599） |
| #584 | 数值 DRAFT 集中表（只狼基准 14 参数 + 三行注释 + 新增分区） | 草稿已合并（#609），待用户定稿 |
| #575 | 战斗实体基类与状态机（追加「战斗时序」5 常量分区） | 已合并（#618） |
| #577 | 判定层（追加「判定」6 常量分区：弹反/拼刀/格挡/受击裁决 + 窗口契约，#626） | 已合并（#626） |
| #574 | 动画帧节奏/骨骼几何/刀光弧线参数 # DRAFT 分区追加（7+9+4 常量，双值冲突 10vs14） | 已合并（#612） |
| #578 | 两条命原地复活系统（追加「复活 FX」12 常量分区：墨点/闪屏/慢动作/闪烁四件套参数） | 已合并（#637） |
| #583 | 雪夜山东村战斗场景（追加「场景参数」分区：舞台尺寸/平台/色板/月亮/物件，STAGE_*/PLATFORM_*/MOON_*/HOUSE_* 等） | 已合并（#646） |
| #579 | 打击反馈系统（追加「反馈分区」12 常量：FEEDBACK_SPARK_*/HITSTOP/SHAKE_PX/SLOWMO/FLASH/TIME_MAX_STACK/ENTITY_FLASH_FACTOR 等） | 已合并（#654） |

## 9. 复活 FX 分区指针（#578/#637）

> 复活演出 12 常量（INK_BURST_*/FLASH_*/SLOWMO_HOLD_SECONDS/INVINCIBLE_FLICKER_*）随 #637 落地于
> constants.gd「复活 FX 分区」：墨点 burst / 瞬态闪屏 / 慢动作 / 无敌闪烁四件套参数，全 `# DRAFT`
> 候选值，定稿归 #584（复用 SLOWMO_COEFF=0.2 节奏语言、HUD 色值互引零新色相）。
> 完整组件/数据流/契约见 [13-REVIVE-SYSTEM](13-REVIVE-SYSTEM.md)。

## 10. 场景分区指针（#583/#646）

> 战斗舞台场景参数随 #646 落地于 constants.gd「场景参数」分区（文件尾部）：舞台尺寸
> STAGE_*（机械定稿）+ 平台 PLATFORM_* / 色板 / 月亮 MOON_* / 物件 HOUSE_*（# DRAFT 候补值）。
> 定稿归 #583 AC5 用户 E2E 截图裁决（构图/配色归用户，机械部分已定稿）。实现期 self-correct
> R1：STAGE_INK_COLOR #1a1f26 → #4a5664（染后 luma 0.055 < 30 违反 #624 F3，调亮后 ≈ 39/255 ≥ 30）。
> 完整组件/数据流/契约见 [14-SCENE-BATTLE-STAGE](14-SCENE-BATTLE-STAGE.md)。

## 11. 反馈分区指针（#579/#654）

> 打击反馈 12 常量随 #654 落地于 constants.gd「反馈分区」（文件尾部）：火花
> FEEDBACK_SPARK_COUNT/COLOR/VELOCITY/LIFETIME/Z_INDEX + 顿帧 FEEDBACK_HITSTOP_MS +
> 屏震 FEEDBACK_SHAKE_PX/DECAY + 慢动作 FEEDBACK_SLOWMO + 白闪 FEEDBACK_FLASH/
> ENTITY_FLASH_FACTOR + 时间栈 FEEDBACK_TIME_MAX_STACK，全 `# DRAFT` 候补值，
> 定稿归 #584（taste 域；实现期禁止「顺手定稿」）。
> 完整组件/矩阵/数据流/红线见 [15-COMBAT-FEEDBACK-SYSTEM](15-COMBAT-FEEDBACK-SYSTEM.md)。
