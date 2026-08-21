# Hud — 极简 HUD 层：两段式血条 + 双架势条 + 击杀/处决提示 + Boss 血条 UI 呈现层（#576/#627/#684）

> 落盘依据：PR #627（implement，taste-draft 草稿已 merge 2026-08-19）← DESIGN `docs/DESIGN/576-hud-stance-bars.md`（#622 合入）。
> 上游：#575 CombatEntity 6 信号契约（hp_changed/stance_changed/stance_broken/state_changed/died/revived）、#584 战斗时序常量（STANCE_BREAK_RECOVERY_SEC=3.0 只读复用）、#562 标题 UI 的 CanvasLayer layer=1 层级约定。
> 下游：#585 组装（bind_player/set_target_enemy 注入 + low_health_changed 接线）、#582 vignette（消费低血信号）、#577/#580（处决/死亡事件源，未合入时 E2E 走 debug API）。
> 所有权：`content_ownership: taste-draft` —— B2 提示文案（5 选 1）+ 全部 HUD 阈值/配色/时长常量标 # DRAFT 待用户 E2E 截图定稿；信号契约/布局锚点/边沿语义等机制结构机械定稿。

## 1. 设计意图

#618 交付 CombatEntity（战斗数据层）后，`gdscripts/` 仍无任何 UI 代码——**本层是战斗读数的「克制」UI 层**：玩家两段式血条、玩家/敌人架势条、击杀与处决提示文字，全部程序化绘制零贴图，并补上低血 vignette 的**信号源缺口**（issue body 明示「HUD 仅发信号」）。

**设计哲学：HUD 是纯消费方——只读信号画条 + 发一个低血信号，零判定、零轮询、零贴图。**

1. **信号驱动、零 `_process` 轮询**（TF-1 静态断言，test_hud T26）：所有更新由 hp_changed / stance_changed / stance_broken / state_changed / died / revived 信号 + Tween/Timer 驱动。
2. **一条线一个信息**：血条 = 两段式单条同轴（段1 全宽 100 + 段2 半宽 50，share 比 2:1），架势条 = 细条（玩家：血条下方 6px；敌人：顶部中央）——信息密度克制，「如果界面被注意到，它就失败了」。
3. **低血是唯一色彩例外**：常态苍白月白 `#e8e6e3` + 墨黑；活性段 <30% 血色点缀 + `low_health_changed` 信号 → #582 vignette。
4. **零贴图零 tscn**：全部 Control 代码创建，`_HudBar` 内部类 `_draw()` 自绘——AC4「无外部 UI 图像资源」字面满足，headless 可实例化可断言。
5. **单例守卫**：Hud 加入 `hud` group，重复实例化时第二实例 `queue_free()`——#585 战斗场景组装幂等安全。

## 2. 类定义

文件：`shandong-wolf/gdscripts/hud.gd`（class_name `Hud`，extends CanvasLayer，layer=1，410 行）。

节点结构（全部代码创建，零 tscn 零贴图）：

```
CanvasLayer (Hud, layer=1)
└── PlayerBarGroup (Control, anchor 左上, position=HUD_PLAYER_MARGIN(16,16))
    ├── PlayerHealthBar (_HudBar, 240×10, 两段: [hp_1, hp_2]/[LIFE_1_MAX, LIFE_2_ABS], active=_active_life)
    └── PlayerStanceBar (_HudBar, 240×6, y = HUD_BAR_HEIGHT+HUD_STANCE_GAP, 单段: stance/stance_max)
EnemyStanceBar (_HudBar, 240×6, 顶部中央 anchor 0.5, top=HUD_ENEMY_BAR_TOP, 默认 hidden)
ExecutePromptLabel (Label, 定宽~220px, TRIM_ELLIPSIS, 墨黑底 + 月白 1px 描边)
KillPromptLabel   (Label, 定宽~120px, TRIM_ELLIPSIS)
```

信号契约（与 #582/#585 下游对齐）：

```gdscript
signal low_health_changed(enabled: bool)   # 边沿触发：活性条占比 < HUD_LOW_HP_RATIO 时恰好一次 true/false
```

关键方法（公有 API 与 PRD §8.3 一致 + DESIGN 补全项）：

| 方法 | 逻辑要点 |
|------|---------|
| bind_player(entity) | 幂等绑定玩家实体；订阅 hp_changed/stance_changed/state_changed/died/revived（CONNECT_REFERENCE_COUNTED）；null 仅断开 |
| set_target_enemy(entity) | 幂等；换目标先断开旧订阅；null 隐藏 EnemyStanceBar；有效实体 → 订阅 + 立即用当前 stance 值初始化 |
| set_debug_hp / set_debug_stance / show_debug_hint | E2E/单测驱动：走与信号回调同一处理路径（画条 + 低血边沿判定） |
| _on_player_hp_changed | 两段条重绘 + 低血边沿（活性条占比严格小于 0.30，max≤0 防御 → 1.0） |
| _on_enemy_stance_broken | 处决提示：文案 → visible + Tween 淡入 0.15s → Timer 3s（复用 STANCE_BREAK_RECOVERY_SEC）；重复触发重置计时幂等 |
| _on_player_state_changed | to ∈ {attack, heavy_attack, execute} → 立即隐藏处决提示（PRD §4.4 提前打断） |
| _on_enemy_died(entity, final) | final==true → 击杀提示（1.5s）+ 处决提示立即让位（击杀 > 处决）；final==false → 仅隐藏处决 + 清空敌人架势条 |
| _ready / _exit_tree | 加入 hud group + 单例守卫；断开所有实体订阅（双保险防悬垂） |

内部类 `_HudBar`（extends Control，`_draw()` 自绘）：墨黑 60% 背景 + 1px 月白描边（无圆角）+ 逐段填充；`set_segments(values, maxes, active_index)` 注入段数组，`set_low_hp_mode(enabled)` 低血转 HUD_BLOOD_RED；段宽 `clamp(value/max, 0, 1)` 防除零/越界。

## 3. 常量（constants.gd「HUD (#576)」# DRAFT 分区，18 个：13 既有 + 5 新增 #684）

追加式新增分区（不触碰既有 9 分区任何一行），全部标 # DRAFT 待用户定稿；处决窗口复用 `STANCE_BREAK_RECOVERY_SEC=3.0` 不新增常量。

| 常量 | 值（候补） | 影响 |
|------|-----------|------|
| HUD_LOW_HP_RATIO | 0.30 [0.25, 0.30, 0.35] | 低血 vignette 触发阈值（严格小于） |
| HUD_KILL_HINT_SECONDS | 1.5 [1.0, 1.5, 2.0] | 击杀提示停留时长（含淡出） |
| HUD_PLAYER_MARGIN | Vector2(16, 16) | 玩家区块左上角边距 |
| HUD_STANCE_GAP | 6.0 | 血条与玩家架势条间距 |
| HUD_BAR_WIDTH / HUD_BAR_HEIGHT | 240.0 / 10.0 | 血条尺寸 |
| HUD_STANCE_HEIGHT | 6.0 | 架势条高（玩家/敌人） |
| HUD_ENEMY_BAR_WIDTH / HUD_ENEMY_BAR_TOP | 240.0 / 12.0 | 敌人架势条宽 / 顶边距 |
| HUD_MOON_WHITE | Color("#e8e6e3") | 常态描边 / 活性段填充（issue body 指定） |
| HUD_INK_BLACK | Color("#141414") | 背景 / 非活性段填充 |
| HUD_BLOOD_RED | Color("#8c2f2f") | 低血点缀（活性段填充 + 描边） |
| HUD_HINT_FONT_SIZE | 16 | 提示文字字号 |

## 4. 数据流

### Flow 1：玩家受击 → 两段血条更新 + 低血边沿（正常路径）

```
#577 判定 → entity.take_damage → #575 emit hp_changed(88, 50, 1)
  → Hud._on_player_hp_changed → PlayerHealthBar.set_segments([88,50],[100,50],1) → queue_redraw
  → 活性条 0.88 ≥ 0.30 → low=false（_low_health 已 false → 不发射）
  → 持续受击至 25/100=0.25 < 0.30 → low=true 边沿 → emit low_health_changed(true)
      → (#585 接线) #582 set_low_health(true) → vignette 渐显 + 血条活性段转血色
```

### Flow 2：架势涨落 → 双架势条（玩家 / 敌人）

```
#577 take_stance_damage → #575 emit stance_changed(stance, max)
  → 玩家：_on_player_stance_changed → PlayerStanceBar.set_segments([stance],[100],0)
  → 敌人（target_enemy 已注入）：_on_enemy_stance_changed → EnemyStanceBar 同轴更新
  → stance ≤ 0 → break_stance → emit stance_broken → Flow 3
```

### Flow 3：架势崩解 → 处决提示（3s 窗口）

```
emit stance_broken(enemy) → _on_enemy_stance_broken
  → ExecutePromptLabel（B2 草稿文案）visible + Tween 淡入 0.15s + Timer(STANCE_BREAK_RECOVERY_SEC=3.0)
  → 分支 A/B：玩家进入 execute/attack/heavy_attack → 立即隐藏（提前打断）
  → 分支 C：3s 超时 → Tween 淡出 0.3s → 隐藏
```

### Flow 4：敌人死亡 → 击杀提示（优先级：击杀 > 处决）

```
emit died(enemy, true) → _on_enemy_died
  → KillPromptLabel visible + Tween 淡入 0.15s + Timer(HUD_KILL_HINT_SECONDS=1.5)
  → ExecutePromptLabel 立即让位（不等其 Timer）+ EnemyStanceBar 隐藏
```

### Flow 5：回生切换（active_life 1→2）— 无跳变无闪烁

```
revived + hp_changed(0, 50, 2) → set_segments([0,50],[100,50],2)
  → 段1 0% 暗显、段2 半管全宽亮起（月白）
  → 活性条 = 50/50 = 1.0 ≥ 0.30 → low=false（若此前 true 则边沿发射 false → vignette 渐隐）
  → 条总视觉长度不变（段2 已在位）——回生瞬间无条长突变
```

## 5. 边界情况

| 情况 | 处理 |
|------|------|
| 无 target_enemy / 敌人已释放 | EnemyStanceBar 默认 hidden；null 隐藏 + 断开订阅；CONNECT_REFERENCE_COUNTED + _exit_tree 双保险，不悬垂不崩溃 |
| 低血阈值边界（恰好 30%） | 严格小于（0.30-0.001 容差语义）：29.9% 发 / 30.0% 不发（T6-T9 锁定） |
| 处决提示重复触发 | Timer 重置幂等，不叠加不闪烁 |
| 击杀与处决竞争 | died(final=true) 时处决提示立即隐藏（击杀 > 处决） |
| 数值异常（负/NaN/越界） | _HudBar 段宽 clamp(value/max, 0, 1)，max≤0 防御返回 1.0，不除零 |
| 多实例（重复实例化） | hud group 单例守卫：第二实例 queue_free() |
| #582 未合入（vignette 消费端缺失） | low_health_changed 无监听者 → 信号安全 no-op，HUD 功能不受影响（#585 接线后闭环） |

## 6. 集成点（#585 组装层）

| 集成 | 方式 | 状态 |
|------|------|:----:|
| bind_player(player) / set_target_enemy(enemy) | #585 战斗场景实例化后注入 | ⬜ 待 #585 |
| low_health_changed → #582 set_low_health() | #585 胶水层接线 | ⬜ 待 #585 |
| stance_broken / died 事件源 | #577/#580 信号订阅（未合入时 debug API 驱动 E2E） | ⬜ 待 #577/#580 |

## 7. B2 提示文案草稿（taste-draft，implement 选 1，候选清单待用户定稿）

| 提示 | implement 选用 | 候选清单 |
|------|--------------|---------|
| 处决提示 | 按攻击键处决 | 按攻击键处决 / 趁势处决 / 了结他 / 就地正法 / 下手吧 |
| 击杀提示 | 击毙 | 击毙 / 斩杀 / 击杀 / 肃清 / 取敌 |

## 8. 测试与 E2E

- **单测**：`shandong-wolf/tests/test_hud.gd`（T1-T28，挂载 run_tests.gd 第 8 套件）——布局锚点（AC1）/两段结构/低血边沿（AC2）/敌人条显隐/提示竞争/回生/零贴图零轮询静态断言（AC4）/单例守卫/数值异常防御。
- **E2E 观感裁决**：`e2e_hud_capture.gd/.tscn`（CaptureRig 模式，current_state 4 态：NORMAL/LOW_HP/EXECUTE_HINT/KILL_HINT）+ `e2e_shots.json` hud group（4 shots：01_hud_normal / 02_hud_low_hp / 03_hud_execute_hint / 04_hud_kill_hint，group 级 main_scene）——走 Hud 公有 debug API，零战斗场景依赖，信号源（#577/#580）未合入也能截全。
- **待用户裁决**：E2E 截图 ≥70% 定稿；<70% 走 # DRAFT 参数迭代（改 constants 候补值，不重写架构）。

## 9. 待用户定稿清单（# DRAFT，taste-draft 所有权）

1. B2 提示文案：处决/击杀各 5 选 1（当前「按攻击键处决」「击毙」）
2. HUD_LOW_HP_RATIO / HUD_KILL_HINT_SECONDS / 布局 / 配色 13 常量候补值（#584 调参面板可扩展挂入）
3. E2E 4 帧观感裁决：克制、与雪夜水墨背景融为一体（禁止光效/圆角/饱和堆砌）

## 10. Boss 血条 UI 呈现层增量（#684/#701）

> 落盘依据：PR #701（implement，2026-08-21 merged）← DESIGN `docs/DESIGN/684-boss-hp-bar-ui.md`（plan #699 合入）。
> 上游：#695 EnemyHealthBar 双条组合基底；#576 `_HudBar` 契约/色板。本增量 = **纯呈现层消费端**：零新数据管道、零新信号源（只消费 hp_changed / stance_changed / stance_broken / died 4 信号）、零 tscn 零贴图（#576 红线延续）。
> 所有权：`content_ownership: mechanical`（节点结构/布局锚点/闪白状态机/分档显隐/信号接线全机械可验）；唯一 taste 环节 = 名字文案 + 闪白时长/颜色定值 + 百分比文本去留，全标 `# DRAFT` 只读候选，定稿归 #584/#576 human-review 通道。

**设计意图：** #695 已交付顶部双条主体，本 issue 补呈现层三缺口——① 敌人名字（缺失）② 架势崩解条级闪白（现仅文字提示）③ Boss/杂兵呈现分档（未设计）。四个决策点（名字 Label / 条级闪白 / 分档 API / HP 纯条呈现）共享同一文件与实现窗口，合并实现避免返工。

### 10.1 新组件（hud.gd 内 2 节点/状态 + 1 公有 API，无独立新文件）

**① EnemyNameLabel（敌人名字 Label）**——`_make_hint_label` 同构（零 tscn 零贴图）：锚点 0.5 居中、offset_left/right = ±HUD_ENEMY_NAME_WIDTH/2（±120）、offset_top = HUD_ENEMY_NAME_TOP（2）、font_size 覆写 16（HUD_ENEMY_NAME_FONT_SIZE）、font_color = HUD_MOON_WHITE、**无底框**（克制悬浮，与提示 Label 墨黑底框区分）。超长名 `OVERRUN_TRIM_ELLIPSIS` 省略。显隐 = `_boss_mode and _enemy_display_name != ""`，由 `_apply_enemy_visibility()` 唯一收敛。

```gdscript
var EnemyNameLabel: Label               # tests 直接访问（与 EnemyHealthBar 同模式）
var _enemy_display_name: String = ""    # 当前名字（taste 文案，默认空）

func set_enemy_display_name(name: String) -> void:  # 新 API（PRD §4.1-A）: 空串隐藏；boss 档可见、杂兵档隐藏
```

**② `_HudBar` 崩解闪白状态机（set_break_flash）**——additive 扩展（玩家两条与既有 set_segments 路径零影响）：`_break_flash` / `_break_flash_alpha` / `_flash_tween` 三状态 + Tween 1.0→0.0 淡出（HUD_STANCE_BREAK_FLASH_SECONDS=0.18，零 `_process`）；`_draw` 两处分支（描边/填充）`HUD_STANCE_BREAK_FLASH_COLOR.lerp(原色, _break_flash_alpha)`。竞争语义：flash 期间 set_segments 到达 → `_draw` 读状态变量覆盖填充色，Tween 结束后重绘接管——**无竞态**；died/换目标打断走 `clear_break_flash()`（kill tween + 双状态复位，不留残影）。

**③ `set_boss_mode(bool)` 分档 API + `_apply_enemy_visibility()` 三态显隐**——幂等（同值早退）；true = 名字+血条+架势条全显；false = 血条+名字隐藏、仅保留小架势条（现状位置）；null 目标 = 三态全隐。`set_target_enemy` / `_on_enemy_died` 的显隐逻辑收敛进 `_apply_enemy_visibility()`（签名零改动，先数据后显隐保证杂兵档小条有初始值）；`final=false` 防御分支 → 名字清空 + 双条清 0 + clear_break_flash()。

### 10.2 新常量（constants.gd「Boss 血条 UI」分区，5 项 # DRAFT 归 #584）

| 常量 | 值（候补） | 影响 |
|------|-----------|------|
| HUD_ENEMY_NAME_WIDTH | 240.0 [200, 240, 280] | 名字 Label 宽（= 血条同宽对齐，超长省略号） |
| HUD_ENEMY_NAME_FONT_SIZE | 16 [14, 16, 18] | 名字字号（= HUD_HINT_FONT_SIZE 同级，克制） |
| HUD_ENEMY_NAME_TOP | 2.0 [0.0, 2.0, 4.0] | 名字与血条上边距（血条 offset_top=12 → 名字 2..30） |
| HUD_STANCE_BREAK_FLASH_SECONDS | 0.18 [0.12, 0.18, 0.25] | 崩解白闪淡出时长（sekiro「崩解白闪」惩罚清晰） |
| HUD_STANCE_BREAK_FLASH_COLOR | HUD_MOON_WHITE [HUD_MOON_WHITE, HUD_BLOOD_RED.lightened(0.5)] | 闪白色（默认月白零新色相；「血染白」变体 taste 裁决） |

> 全 `# DRAFT` 只读：实现期选默认值，候选集随 PR 提交，定稿归 #584/taste 通道。碎裂提示（PRD 4.2-B）与 HP 百分比数字文本（PRD 4.4-B）留 taste 候选，implement 未实现。

### 10.3 数据流（全为既有信号消费端）

```
main_battle._build_hud: set_target_enemy(enemy) → set_boss_mode(true) → set_enemy_display_name("雪夜刀客")（# DRAFT 占位文案）
  hp_changed      → EnemyHealthBar.set_segments                 ✅ 既有（#695）
  stance_changed  → EnemyStanceBar.set_segments                 ✅ 既有（#695）
  stance_broken   → EnemyStanceBar.set_break_flash() + 处决文字   ← 新增条级闪白（正交互不遮挡）
  died(final)     → 名字隐藏 + 双条隐藏 + 击杀提示                ← 名字联动新增
```

### 10.4 E2E 截图扩展（3 新态）

`e2e_hud_capture.gd` enum 0-6 向后兼容扩展（NORMAL=0/LOW_HP=1/EXECUTE_HINT=2/KILL_HINT=3 + BOSS_BAR=4/STANCE_BREAK_FLASH=5/MINION_MODE=6），CYCLE_SEQUENCE 7 态；debug API `set_debug_stance_break()` 直置 flash 态绕开真实 Tween 时序。`e2e_shots.json` hud group +3 shots：`05_hud_boss_bar`（名字+血条+架势条全显）/ `06_hud_stance_break_flash`（debug 置位闪白帧，与常态帧比色数/主题色）/ `07_hud_minion_mode`（仅小架势条）。

### 10.5 装配与测试

- **装配（main_battle.gd `_build_hud` +2 行）**：MVP 唯一敌人 = 精英 → Boss 档 `set_boss_mode(true)` + `set_enemy_display_name("雪夜刀客")`（# DRAFT 占位文案，taste 候选进 PR 待用户定稿）。
- **单测（test_hud.gd additive）**：场景 A（名字布局/显隐 A1-A6）+ B（闪白状态机 B1-B6）+ C（分档三态 C1-C5）+ D（信号回归）+ E（E2E 态）+ F（装配断言）；既有 T1-T28/B1-B5 零改动全绿。
- **静态契约延续**：零贴图零 tscn + 零 `_process` 轮询（TF-1 断言延续）——新代码全部信号 + Tween 驱动。

### 10.6 待用户定稿清单（# DRAFT，taste 通道 #584/#576）

1. 敌人名字文案（当前占位「雪夜刀客」）+ 名字字号/上边距候选
2. 崩解闪白时长（0.12/0.18/0.25）与颜色（月白 vs 血染白）
3. 碎裂提示（PRD 4.2-B）与 HP 百分比数字文本（4.4-B）去留
