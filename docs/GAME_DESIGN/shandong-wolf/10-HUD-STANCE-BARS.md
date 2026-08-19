# Hud — 极简 HUD 层：两段式血条 + 双架势条 + 击杀/处决提示（#576/#627）

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

## 3. 常量（constants.gd「HUD (#576)」# DRAFT 分区，13 个）

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
