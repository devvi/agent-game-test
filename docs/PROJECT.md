# Project Overview

## 项目状态

| 指标 | 状态 |
|------|:----:|
| 编译 | ✅ 通过 |
| 可运行 | ✅ 能启动 |
| 可玩 | ✅ PONG://NEON（原 Mini Pong）: 完整状态机(MENU→SERVING→PLAYING⇌PAUSED→SCORED→GAME_OVER)、UI系统、球物理、挡板移动、AI对手、暂停(Escape)、音效合成、L0动态雨幕(GPUParticles2D)、失败屏(win/fail双分支+run数据+软冻结)、球速 HUD 实时显示；🟡 shandong-wolf（当前活跃游戏）: 逻辑地基就绪（WolfConstants 数值集中地 + StateMachineBase 状态机基类 + Game autoload）+ 战斗数值 DRAFT 集中表（#584 只狼基准 14 参数候补值）+ DebugCanvas F1 调参面板（#609，仅 debug build）+ 输入层就绪（Input Map 9 动作 + InputController 意图事件/时间戳缓冲 + PlayerController 加速度移动，#611）+ 战斗实体与状态机就绪（CombatEntity 数据容器/两段血/输入桥 + 11 态战斗状态机 + 战斗时序 DRAFT 分区，#618）+ 火柴人剪影骨架与关键帧动画（Line2D 程序化骨架 7 pivot + 11 态关键帧 + consume_state 契约 + additive 刀光，#612）+ 血条与架势条极简 HUD（两段式血条/双架势条/击杀与处决提示，程序化绘制零贴图，草稿已合并待用户 E2E 截图定稿，#627）+ 拼刀/弹反/架势崩解判定层（CombatJudge 逻辑帧窗口判定 + AttackWindow 窗口契约 + 弹反/拼刀/格挡/受击五结果事件 + 6 判定常量 # DRAFT，#626）+ 雪夜氛围层（#582/#613 四层系统已落地 main：三层视差雪幕 60/60/80 粒子 + 单 CanvasModulate 冷月光 #6e7684 + 水墨晕染 + 血色 vignette 契约；#624/#629 单 moon 层契约：唯一 moon 挂 layer 0 + 雪幕/水墨/血色/UI 禁染 + C3 ==1 守卫；NIGHT_BG_COLOR 等 # DRAFT 定稿归 #582 用户裁决）+ 两条命原地复活系统（ReviveOrchestrator 自动复活编排：died(final=false)→1s 计时→revive()，与 F 键手动路径双路径幂等收敛 + ReviveFX 演出四件套：墨点 burst/瞬态闪屏/慢动作/无敌闪烁，12 演出常量 # DRAFT 归 #584，SW-015 终态契约固化，#637） + 基础日本兵 AI（EnemyAI 行为状态机：巡逻/追击/攻击/被弹反 4 行为态 + 120° 视线 6m 几何感知（无 raycast/Area2D）+ 决策门控 + 弹反抑制窗 0.5s；判定层 3 处 additive 参数化 + AI 分区 18 常量 # DRAFT，AC1-AC5 全过，#638）+ 雪夜山东村战斗舞台（battle_stage.tscn 纯声明式世界层场景：单一连续碰撞面 2400px + 视觉 3 段雪堆高差 60-100px + 草屋×2/枯树×2 墨色剪影 + 山峦远景 + 苍月 Mesh2D 径向渐变 + moon_glow 光晕 shader + PlayerSpawn/EnemySpawnA/B 出生点 + StageCamera limits 2400，零贴图零新增 CanvasModulate（C3 守卫），E2E battle_stage 组截图待用户 AC5 裁决，#646）+ 打击反馈系统（ReactionController 组合触发核心：FEEDBACK_MATRIX 9 事件×6 维分级矩阵（S/A/A-/B/C 六级 + clash/revive/death 补充映射）+ 五效果组件：苍白金 one_shot 火花（#ffd9a0，z_index -1 不盖角色；#675 背景 z=-2 显式化：背景<火花<角色，E2E 截图恢复火花）/ TimeScaleStack 时间缩放栈（D1 min 语义 + 墙钟兜底 + 栈深 3）/ ScreenShake trauma² 屏震（camera_path 解耦）/ FlashEffect 实体+全屏白闪双通道（全屏淡闪仅 A- 级）/ S 级复用 SwordArc 刀光；bind_judge 直连 #577 五结果事件 + subscribe_entity 订阅 #575 6 信号（闭包捕获实体 D2/D4）+ 降级路径；E2E 同帧截图 rig 三档 shot（fb_parry_success/fb_stance_break/fb_execute）冻结效果帧模式供用户 AC6 裁决，28 用例测试套件，反馈分区 12 常量 # DRAFT 归 #584，#654） + 处决系统（ExecutionOrchestrator 处决编排：stance_broken→armed 窗口 3s → 攻击键+距离≤120px 触发处决时序（玩家无敌→execute 转移→execute_kill 杀敌→S 级反馈→淡出）；execute_kill 专用杀敌通道绕过 take_damage execute no-op 无敌红线 + _is_final_dead 停摆守卫；ExecutionFade 墙钟驱动淡出 0.3s 如墨迹消散（慢动作不卡淡出）；recover_from_break 起身疲惫：恢复 50% 架势 + 5s 疲惫期受架势伤害 ×1.2，乘数下沉实体层；「处决演出」分区 7 常量 # DRAFT 归 #584（慢动作三候选并列禁止偷定）；六组测试套件；E2E execution 组 2 shot 待用户 AC5 裁决，#660） + MVP 战斗闭环组装（MainBattle BattleAssembler：13 步程序化装配接线 + 游戏状态机 IDLE→COMBAT→KILL→AFTERGLOW→FAIL（FAIL 终态幂等） + 失败字幕（输入冻结 + AI 停止 + 淡入） + 击杀 5s 余韵 + 教学提示 + 低血氛围单点接线 + Main.tscn 追加挂载 + smoke AC4 闭环自动跑通 —— 组装完成即游戏可玩，#666）+ E2E 剧本验收（e2e_script 组 6 帧情感弧剧本：scene_description/trigger/composition 文字契约 AC1；rig 4→7 态（MOVE/CLASH/EXECUTE + CYCLE_DWELL_FRAMES 定长停留 + move_displacement_px 位移断言）；管线四修复：组级场景键提升/数字 state 直比/分辨率从 project.godot 读取/--size 尺寸断言；headless 三档语义；docs/TEST/586 报告模板，6 帧 1-5 星裁决归用户（AC4），#673） |
| 最近构建 | 2026-08-21（shandong-wolf 背景层级修复 #675：Backdrop/WorldBackdrop z_index 0→-2，E2E 截图恢复火花） |
| 开放 Issues | 1 |

## 模块地图

| 模块 | 文件 | 状态 | 设计文档 |
|------|------|:----:|:--------:|
| 3D Scene Layout | `scenes/feature-mini-walker-3d.tscn` | ✅ | GDD |
| 3D Scene Layout (alt) | `scenes/mini_world.tscn` | ✅ | GDD |
| Mini Pong — Paddle | `mini-pong/gdscripts/paddle.gd` | ✅ | GDD |
| Mini Pong — Ball Physics | `mini-pong/gdscripts/ball.gd` | ✅ | GDD |
| Mini Pong — Neon Visual | `mini-pong/gdscripts/ball_trail.gd` | ✅ | GDD |
| Mini Pong — Rain Curtain | `mini-pong/gdscripts/rain_curtain.gd` | ✅ | GDD |
| Mini Pong — Background Pulse | `mini-pong/gdscripts/bg_pulse.gd` | ✅ | GDD |
| Mini Pong — Upgrade Pool | `mini-pong/gdscripts/upgrade_pool.gd` + `upgrade_defs.gd` | ✅ | GDD |
| Mini Pong — Upgrade Pick UI | `mini-pong/gdscripts/upgrade_pick_ui.gd` + `scenes/ui_upgrade_pick.tscn` | ✅ | GDD |
| Mini Pong — Scoring | `mini-pong/gdscripts/scoring_manager.gd` | ✅ | GDD |
| Mini Pong — GameManager | `mini-pong/gdscripts/game_manager.gd` | ✅ | GDD |
| Shandong Wolf — Main Scene | `shandong-wolf/scenes/Main.tscn` | ✅ | GDD |
| Shandong Wolf — Post-Merge Probe | `shandong-wolf/scenes/Main.tscn`（PostMergeProbeLabel） | ✅ | GDD |
| Shandong Wolf — Constants | `shandong-wolf/gdscripts/constants.gd` | ✅ | GDD |
| Shandong Wolf — State Machine | `shandong-wolf/gdscripts/state_machine.gd` | ✅ | GDD |
| Shandong Wolf — Game Autoload | `shandong-wolf/gdscripts/game.gd` | ✅ | GDD |
| Shandong Wolf — DebugCanvas | `shandong-wolf/gdscripts/debug_canvas.gd`（CanvasLayer 调参面板，F1 开关） | ✅ | GDD |
| Shandong Wolf — InputController | `shandong-wolf/gdscripts/input_controller.gd`（autoload 输入意图层：8 信号 + 时间戳缓冲队列） | ✅ | GDD |
| Shandong Wolf — PlayerController | `shandong-wolf/gdscripts/player_controller.gd`（CharacterBody2D 加速度移动，group "player"） | ✅ | GDD |
| Shandong Wolf — CombatEntity | `shandong-wolf/gdscripts/combat_entity.gd`（Node2D 战斗数据容器：两段血/架势/facing + request_transition 唯一转移入口 + 6 信号 + _StateInputBridge 输入桥） | ✅ | GDD |
| Shandong Wolf — CombatStateTable | `shandong-wolf/gdscripts/combat_state_table.gd`（11 态转移合法性表 CANONICAL_STATES/TRANSITIONS/is_legal） | ✅ | GDD |
| Shandong Wolf — CombatStates | `shandong-wolf/gdscripts/combat_states.gd`（CombatStateBase + 11 状态对象 + make_state 工厂，帧/秒常量自动退出） | ✅ | GDD |
| Shandong Wolf — Combat Test Suite | `shandong-wolf/tests/test_combat_entity.gd`（30 用例：121 对转移遍历/受击/架势/两段血复活流/输入桥 mock） | ✅ | GDD |
| Shandong Wolf — StickFigure | `shandong-wolf/gdscripts/stick_figure.gd`（Node2D 程序化骨架：7 pivot + Line2D 肢体 + Polygon2D 头圆 + sprite_slot 原画预留） | ✅ | GDD |
| Shandong Wolf — 动画控制器 | `shandong-wolf/gdscripts/stick_figure_controller.gd`（consume_state 契约 + 11 态→clip 镜像映射 + 过渡 ≤2 帧 + 动画资源运行时动态生成） | ✅ | GDD |
| Shandong Wolf — SwordArc 刀光 | `shandong-wolf/gdscripts/sword_arc.gd`（Polygon2D additive 弧光，无碰撞，判定归 #577） | ✅ | GDD |
| Shandong Wolf — 火柴人场景 | `shandong-wolf/scenes/player_stick_figure.tscn` + `e2e_stick_figure_capture.tscn`（E2E 截图专用 rig） | ✅ | GDD |
| Shandong Wolf — Hud 极简 HUD | `shandong-wolf/gdscripts/hud.gd`（CanvasLayer layer=1：两段式血条/玩家与敌人架势条/击杀与处决提示，纯信号驱动零轮询 + 内部类 _HudBar _draw 自绘 + low_health_changed 边沿信号） | ✅ | GDD |
| Shandong Wolf — HUD E2E 截图 rig | `shandong-wolf/gdscripts/e2e_hud_capture.gd` + `scenes/e2e_hud_capture.tscn`（CaptureRig 模式 4 态，走 Hud 公有 debug API 零战斗场景依赖）+ `e2e_shots.json` hud group（4 shots） | ✅ | GDD |
| Shandong Wolf — HUD 测试套件 | `shandong-wolf/tests/test_hud.gd`（T1-T28：布局锚点/两段结构/低血边沿/敌人条显隐/提示竞争/回生/静态断言/单例守卫/数值防御，run_tests.gd 第 8 套件） | ✅ | GDD |
| Shandong Wolf — CombatJudge 判定器 | `shandong-wolf/gdscripts/combat_judge.gd`（Node 判定协调器：窗口登记 → 弹反/拼刀/格挡/受击裁决（CLASH_PRIORITY 常量）→ 实体接口调用 → 五结果事件 + 防重入） | ✅ | GDD |
| Shandong Wolf — AttackWindow 窗口契约 | `shandong-wolf/gdscripts/combat_attack_window.gd`（RefCounted 纯数据：hit_frame/is_active 闭区间/is_expired，#581 敌AI 与玩家共用） | ✅ | GDD |
| Shandong Wolf — CombatJudge 测试套件 | `shandong-wolf/tests/test_combat_judge.gd`（25 用例：弹反边界 5/拼刀+冲突矩阵 4/格挡受击 5/崩解+事件契约 5/边界失败路径 6，免树 headless tick_frame，95 断言） | ✅ | GDD |
| Shandong Wolf — AtmosphereController 氛围编排 | `shandong-wolf/gdscripts/atmosphere_controller.gd`（Node2D 氛围统一入口：唯一 Moonlight 赋值 + 水墨/雪幕/血色 tunables + 层契约注释 + set_low_health 契约 API） | ✅ | GDD |
| Shandong Wolf — 氛围场景 | `shandong-wolf/scenes/atmosphere/atmosphere_layer.tscn`（Atmosphere 根 + 唯一 Moonlight(layer0) + 雪幕3-5/水墨2/血色10 层零 moon） | ✅ | GDD |
| Shandong Wolf — 夜色世界背景 | `shandong-wolf/scenes/Main.tscn` WorldBackdrop（layer 0 ColorRect，NIGHT_BG_COLOR 单一事实源；#675 z_index -2 背景垫底） | ✅ | GDD |
| Shandong Wolf — 氛围测试套件 | `shandong-wolf/tests/test_atmosphere.gd`（C3-1~C3-5 单 moon 守卫：总数==1/层归属/颜色/Main.tscn 文本无 CanvasModulate/层内无 moon + A-E 场景回归，462 行） | ✅ | GDD |
| Shandong Wolf — EnemyAI 行为层 | `shandong-wolf/gdscripts/enemy_ai.gd`（CharacterBody2D 行为 FSM 持有：patrol/chase/attack/retreat + 120° 视线 6m 几何感知（无 raycast/Area2D）+ 决策门控（实体非 idle/move 不决策）+ 弹反抑制窗 0.5s + decide/_physics_process 分离） | ✅ | GDD |
| Shandong Wolf — EnemyAI 行为状态对象 | `shandong-wolf/gdscripts/enemy_ai_states.gd`（Patrol/Chase/Attack/Retreat 4 态，combat_states.gd 范式派生；绝不直接改 entity.state_name——AI 行为态与战斗 11 态双命名空间） | ✅ | GDD |
| Shandong Wolf — EnemyAI 测试套件 | `shandong-wolf/tests/test_enemy_ai.gd`（36 用例 Scenario A-G：主路径/感知边界/弹反硬直与崩解/5% 回避/常量驱动/边界失败/回归，run_tests.gd 第 10 套件） | ✅ | GDD |
| Shandong Wolf — ReviveOrchestrator 复活编排器 | `shandong-wolf/gdscripts/revive_orchestrator.gd`（Node 信号订阅：died(final=false)→REVIVE_SECONDS 计时→revive() 自动复活，与 F 键手动路径双路径幂等收敛 + is_armed 可观测，headless 确定性 _process 累加） | ✅ | GDD |
| Shandong Wolf — ReviveFX 复活演出 | `shandong-wolf/gdscripts/revive_fx.gd`（Node2D _ready 代码构建零资产：墨点 GPUParticles2D one_shot + 瞬态 CanvasModulate 闪屏 Tween + Engine.time_scale 慢动作 + 父节点 modulate 无敌闪烁，参数全读 constants 复活 FX 分区零字面量） | ✅ | GDD |
| Shandong Wolf — 复活测试套件 | `shandong-wolf/tests/test_revive_orchestrator.gd`（24 用例 7 场景：编排主路径/无敌+架势/终态契约/FX 零字面量/双路径竞争/边界失败/回归，run_tests.gd 第 10 套件） | ✅ | GDD |
| Shandong Wolf — 复活 E2E 截图接线 | `shandong-wolf/scenes/e2e_stick_figure_capture.tscn` + `gdscripts/e2e_stick_figure_capture.gd`（REVIVE 态进入 → fx.trigger() + bind_player_visual，AC5 用户裁决证据路径） | ✅ | GDD |
| Shandong Wolf — 战斗舞台场景 | `shandong-wolf/scenes/battle_stage.tscn`（纯声明式 Node2D 世界层：Ground StaticBody2D 单一碰撞面 + 草屋/枯树/山峦/苍月剪影 + Marker2D×3 + StageCamera，零脚本零贴图零新增 CanvasModulate） | ✅ | GDD |
| Shandong Wolf — 月亮光晕 shader | `shandong-wolf/gdscripts/moon_glow.gdshader`（canvas_item 同心 alpha 衰减冷白光晕，回退双层半透明圆） | ✅ | GDD |
| Shandong Wolf — 战斗舞台测试套件 | `shandong-wolf/tests/test_battle_stage.gd`（14 用例 Scenario A-D：场景结构/碰撞与出生点/视觉色板/相机，run_tests.gd 挂载） | ✅ | GDD |
| Shandong Wolf — ReactionController 反馈编排 | `shandong-wolf/gdscripts/reaction_controller.gd`（Node2D 组合触发核心：trigger_feedback 单入口 + FEEDBACK_MATRIX 9 事件×6 维分级矩阵 + bind_judge 五结果事件直连 + subscribe_entity 6 信号闭包订阅 + _derive_impact_point 刀交点推导 + feedback_played 信号 hook + freeze_time_stack 冻结模式） | ✅ | GDD |
| Shandong Wolf — FeedbackSpark 火花 | `shandong-wolf/gdscripts/feedback_spark.gd`（GPUParticles2D one_shot burst，材质代码创建零 .tres，苍白金 #ffd9a0，z_index -1） | ✅ | GDD |
| Shandong Wolf — TimeScaleStack 时间栈 | `shandong-wolf/gdscripts/time_scale_stack.gd`（RefCounted：push/pop/tick 墙钟兜底，D1 min 语义，Engine.time_scale 唯一写入口，栈深 3） | ✅ | GDD |
| Shandong Wolf — ScreenShake 屏震 | `shandong-wolf/gdscripts/screen_shake.gd`（Node：Camera2D offset trauma² 指数衰减，camera_path 解耦，方向沿攻击向量） | ✅ | GDD |
| Shandong Wolf — FlashEffect 白闪 | `shandong-wolf/gdscripts/flash_effect.gd`（Node：实体 modulate ×5 冲白 + CanvasLayer(layer=0) 全屏淡闪双通道，仅 A- 级可达） | ✅ | GDD |
| Shandong Wolf — 反馈 E2E 截图 rig | `shandong-wolf/gdscripts/e2e_feedback_capture.gd` + `scenes/e2e_feedback_capture.tscn`（CaptureRig 模式：current_state 轮询 + inject_feedback + digit 键 4/6/7/2 + 冻结效果帧；#675 Backdrop z_index -2 恢复火花可见）+ `e2e_shots.json` feedback group（3 shots） | ✅ | GDD |
| Shandong Wolf — 反馈测试套件 | `shandong-wolf/tests/test_reaction_controller.gd`（28 用例 Scenario A-G：矩阵单调/时间栈三路径/火花 burst/屏震衰减/白闪双通道/四要素同帧/碰撞点推导，run_tests.gd 第 13 套件） | ✅ | GDD |
| Shandong Wolf — ExecutionOrchestrator 处决编排器 | `shandong-wolf/gdscripts/execution_orchestrator.gd`（Node 编排器：bind_player/bind_enemy/bind_judge/bind_input/bind_feedback 幂等接线（#578 先例）+ stance_broken→armed 窗口 3s 计时 + attack_pressed 距离/armed/玩家存活校验 → _trigger_execution 时序序列（无敌→转移→杀敌→S 级反馈→淡出）+ armed 到期 recover_from_break，headless _process 手动推进） | ✅ | GDD |
| Shandong Wolf — ExecutionFade 淡出演出 | `shandong-wolf/gdscripts/execution_fade.gd`（Node 墙钟驱动淡出：bind(entity) → modulate alpha 1→0 0.3s → fade_completed → queue_free，is_instance_valid 守卫静默解绑，慢动作期间淡出不卡顿） | ✅ | GDD |
| Shandong Wolf — 处决测试套件 | `shandong-wolf/tests/test_execution_orchestrator.gd`
| Shandong Wolf — MainBattle 组装编排 | `shandong-wolf/gdscripts/main_battle.gd`（Node2D BattleAssembler：13 步程序化装配+bind（玩家/敌人/Judge/HUD/Reaction/Revive/Execution）+ 游戏状态机 IDLE→COMBAT→KILL→AFTERGLOW→FAIL + 失败字幕/教学提示/击杀余韵编排 + 低血氛围单点接线，零改动 17 组件） | ✅ | GDD |
| Shandong Wolf — 组装测试套件 | `shandong-wolf/tests/test_main_assembly.gd`（24 用例 Scenario A-F：挂载完整性/信号链连通/完整闭环/失败路径/余韵 5s/防回归，headless 手动驱动零 await，run_tests.gd 以 MainAssembly 末位挂载） | ✅ | GDD |
| Shandong Wolf — 组装/E2E 剧本截图 rig | `shandong-wolf/gdscripts/e2e_main_assembly_capture.gd` + `scenes/e2e_main_assembly_capture.tscn`（CaptureRig 7 态驱动：SPAWN_COMBAT/PARRY/FAIL_SUBTITLE/AFTERGLOW/MOVE/CLASH/EXECUTE + CYCLE_DWELL_FRAMES 定长停留 + move_displacement_px 位移断言 + digit 1-7）+ `e2e_shots.json` assembly 组（4 shot，match 收窄）+ e2e_script 组（6 帧情感弧剧本，#673） | ✅ | GDD |（六组用例 A-F：触发全链路/触发边界/无敌交互/疲惫数值闭环/淡出清理/失败路径防回归，mock ReactionController 断言 trigger_feedback，run_tests.gd 挂载） | ✅ | GDD |
| Mini Pong — Arena | `mini-pong/scenes/Main.tscn` | ✅ | GDD |
| Mini Pong — Constants | `mini-pong/gdscripts/constants.gd` | ✅ | GDD |
| Mini Pong — ScoreFlash | `mini-pong/gdscripts/score_flash.gd` | ✅ | GDD |
| Mini Pong — StartMenu | `mini-pong/gdscripts/start_menu.gd` | ✅ | GDD |
| Mini Pong — GameHUD | `mini-pong/gdscripts/game_hud.gd` | ✅ | GDD |
| Mini Pong — Neon HUD Style | `mini-pong/gdscripts/ui_neon_style.gd` | ✅ | GDD |
| Mini Pong — GameOverScreen | `mini-pong/gdscripts/game_over_screen.gd` | ✅ | GDD |
| Mini Pong — State Machine | `mini-pong/gdscripts/game_state_machine.gd` | ✅ | GDD |
| Mini Pong — Pause Overlay | `mini-pong/gdscripts/pause_overlay.gd` | ✅ | GDD |
| Mini Pong — Audio Engine | `mini-pong/gdscripts/audio_engine.gd` | ✅ | GDD |
| Mini Pong — Test Suite | `mini-pong/tests/run_tests.gd` | ✅ | GDD |
| Mini Pong — E2E Playthrough 测试 | `mini-pong/tests/e2e_playthrough.gd` + `playthrough_test.tscn` + `playthrough_driver.gd` | ✅ | GDD |
| E2E Review Harness | `scripts/run-e2e-review.sh` + `scripts/e2e/resolve_plan.py` + `scripts/e2e/analyze_bmp.py` + `framework/templates/e2e_capture.gd`（#586 管线修复：组级场景键提升/数字 state 直比/results.json 元数据透传/分辨率从 project.godot 读取/--size 尺寸断言） | ✅ | GDD |

## 功能

| # | 功能 | 状态 | 文档 |
|:-:|------|:----:|:----:|
| 274 | Mini Walker 3D场景(地板+墙壁) | ✅ 已合并 | DESIGN / GDD |
| 287 | Mini Pong 球物理与碰撞 | ✅ 已合并 | DESIGN / GDD |
| 288 | Mini Pong 玩家挡板 | ✅ 已合并 | DESIGN / GDD |
| 289 | Mini Pong 霓虹视觉效果 | ✅ 已合并 | DESIGN / GDD |
| 290 | Mini Pong AI 对手 | ✅ 已合并 | DESIGN / GDD |
| 291 | Mini Pong 计分系统 | ✅ 已合并 | DESIGN / GDD |
| 292 | Mini Pong UI 系统(菜单/计分/结束) | ✅ 已合并 | DESIGN / GDD |
| 293 | GameManager 全局状态 | ✅ 已合并 | DESIGN / GDD |
| 294 | Game State Machine 状态机 | ✅ 已合并 | DESIGN / GDD |
| 296 | 暂停与音效 (Escape切换 + AudioStreamGenerator合成) | ✅ 已合并 | DESIGN / GDD |
| 295 | 主场景组装 (Main.tscn + constants.gd + ScoreZones + ScoreFlash) | ✅ 已合并 | DESIGN / GDD |
| 297 | 100回合AI自动对打测试 | ✅ 已合并 | DESIGN / GDD |
| 394 | 端到端可玩验证 (AI vs AI 真实物理完整一局 E2E 测试 + L2 全链路 autoplay 驱动) | ✅ 已合并 | DESIGN / GDD |
| 358 | Mini Pong 标题画面版本号 v1.0.0 | ✅ 已合并 | DESIGN / GDD |
| 508 | title 界面隐藏游戏世界（MENU 隐藏 game_world 组，#508 bug 修复） | ✅ 已合并 | DESIGN / GDD |
| 367 | Mini Pong 手感校准草稿 (球速/反弹角/AI 强度) | 🧪 草稿已合并，待用户定稿 | DESIGN / TASTE |
| 378 | Mini Pong 正式命名定稿 — PONG://NEON (B2 命名) | ✅ 已定稿（用户裁决） | DESIGN / TASTE |
| 396 | 波次副句与失败短句候选草稿 (B5 失败表达) | 🧪 草稿已合并，待用户定稿 | DESIGN / GDD |
| 383 | Mini Pong 轴交换+竖屏 (720×1280 竖屏对打) | ✅ 已合并 | DESIGN / GDD |
| 389 | Mini Pong 动态雨幕 (L0 GPUParticles2D 公式驱动雨量) | ✅ 已合并 | DESIGN / GDD |
| 387 | Mini Pong 升级池架构 (9 升级定义 + 60/30/10 抽取 + 实例参数化 + upgrade_hooks 契约) | ✅ 已合并 | DESIGN / GDD |
| 385 | Mini Pong 双得分制 (拆砖 1 分 / 穿墙 3 分 / 21 分终局) | ✅ 已合并 | DESIGN / GDD |
| 392 | Mini Pong 霓虹UI升级 (三区 HUD + 描边/微投影 + 按类信号 + 容错消费 BreakoutGrid) | ✅ 已合并 | DESIGN / GDD |
| 391 | Mini Pong 失败屏 (win/fail 双分支 + 分档选句 + 三项 run 数据 + 终局软冻结) | ✅ 已合并 | DESIGN / GDD |
| 388 | Mini Pong 3选1升级UI (波间三卡霓虹选择层 + 焦点环 + 确认后稀有度 reveal + 暂停/推进接管) | ✅ 已合并 | DESIGN / GDD |
| 448 | Mini Pong 球速 HUD 显示 (GameHUD 实时球速数字, 10Hz Timer 轮询 round(speed) px/s) | ✅ 已合并 | DESIGN / GDD |
| 449 | Mini Pong 背景霓虹呼吸 (L0 背景光晕正弦呼吸, ColorRect + 纯函数公式, BG_PULSE 常量区) | ✅ 已合并 | DESIGN / GDD |
| 465 | Mini Pong 雨幕粒子修复 (全屏均匀雨滴分布 — visibility_rect 剔除修复 + 全屏发射区 + 基值对齐) | ✅ 已合并 | DESIGN / GDD |

| 567 | Shandong Wolf post-merge 探针 (Main.tscn 右下角 PostMergeProbeLabel, 驱动 post-merge 管线回归) | ✅ 已合并 | DESIGN / GDD |
| 652 | probe-C：api-close-reopen 探针 (marker 文档已随探针清理移除, GitHub API close→reopen→re-close 语义验证, 驱动 post-merge 管线二次回归, #658) | ✅ 已合并 | DESIGN / GDD |
| 572 | Shandong Wolf 逻辑地基 (constants.gd # DRAFT 数值集中地 + StateMachineBase 通用状态机基类 + Game autoload 锚点 + 状态机/常量单测) | ✅ 已合并 | DESIGN / GDD |
| 584 | Shandong Wolf 战斗数值 DRAFT 集中表 (只狼基准 14 参数候补值三行注释 + DebugCanvas F1 调参面板, 草稿已合并) | 🧪 草稿已合并，待用户定稿 | DESIGN / TASTE |
| 573 | Shandong Wolf 输入映射与玩家控制器 (Input Map 9 动作 + InputController 意图事件/时间戳缓冲 + PlayerController 加速度移动, AC1-AC6 全过) | ✅ 已合并 | DESIGN / GDD |
| 575 | Shandong Wolf 战斗实体基类与状态机 (CombatEntity 玩家/敌人变体 + 两段血 + 11 态战斗状态机 + 战斗时序 DRAFT 分区, AC1-AC5 全过) | ✅ 已合并 | DESIGN / GDD |
| 574 | Shandong Wolf 火柴人剪影骨架与关键帧动画 (Line2D 程序化骨架 + 11 态 AnimationPlayer 关键帧 + consume_state 契约 + additive 刀光, 零美术资产 AC5) | ✅ 已合并 | DESIGN / GDD |
| 576 | Shandong Wolf 血条与架势条极简 HUD (两段式血条 + 玩家/敌人架势条 + 击杀/处决提示 + 低血 vignette 信号源, 程序化绘制零贴图 AC4, 草稿已合并待用户 E2E 截图定稿) | 🧪 草稿已合并，待用户定稿 | DESIGN / GDD |
| 577 | Shandong Wolf 拼刀/弹反/架势崩解判定系统 (CombatJudge 判定协调器 + AttackWindow 窗口契约 + 弹反/拼刀/格挡/受击五结果事件, 裁决顺序走 CLASH_PRIORITY 常量零字面量, AC1-AC5 全过) | ✅ 已合并 | DESIGN / GDD |
| 624 | Shandong Wolf 雪夜氛围回归修复 (单 CanvasModulate 层契约: 7 moon → 1 moon 挂 layer 0 + 雪幕/水墨/血色/UI 禁染 + C3 ==1 守卫, 修复 #613 雪幕粒子不可见/血色 vignette 无效果回归; 修复已随 #613 于 2026-08-20 落地 main; 常量 taste 值定稿归 #582) | ✅ 已合并 | DESIGN / GDD |
| 613 | Shandong Wolf 雪夜氛围四层系统 (三层视差雪幕 60/60/80 粒子 + Parallax2D 0.2/0.5/1.0 + 冷月光 #6e7684 + 水墨晕染 ink_wash + 血色 vignette 契约 + 4 组 24 项氛围常量 # DRAFT + test_atmosphere 462 行 C3 守卫, 草稿已合并待用户 E2E 截图定稿) | 🧪 草稿已合并，待用户定稿 | DESIGN / GDD |
| 581 | Shandong Wolf 基础日本兵 AI (EnemyAI 行为状态机: 巡逻→追击→攻击→被弹反, 120° 视线 6m 几何感知 + 决策门控 + 弹反抑制窗 0.5s; 判定层 3 处 additive 参数化 windup_frames/伤害 @export/judge 读实体参数; AI 分区 18 常量 # DRAFT 归 #584, AC1-AC5 全过) | ✅ 已合并 | DESIGN / GDD |
| 578 | Shandong Wolf 两条命原地复活系统 (ReviveOrchestrator 自动复活编排: died(final=false)→1s 计时→revive(), 与 F 键手动路径双路径幂等收敛; ReviveFX 演出四件套: 墨点 burst/瞬态闪屏/慢动作/无敌闪烁, 12 演出常量 # DRAFT 归 #584, SW-015 终态契约固化, AC1-AC5 全过) | ✅ 已合并 | DESIGN / GDD |
| 583 | Shandong Wolf 雪夜山东村战斗场景 (battle_stage.tscn 纯声明式战斗舞台: 单一连续碰撞面 2400px + 视觉 3 段雪堆高差 60-100px + 草屋×2/枯树×2 墨色剪影 + 山峦远景 + 苍月 Mesh2D 径向渐变 + moon_glow 光晕 shader + PlayerSpawn/EnemySpawnA/B 出生点 + StageCamera limits 2400; constants 场景参数分区 # DRAFT; E2E battle_stage 组 3 shot 附 PR, AC1-AC4 过 + AC5 截图待用户裁决, #646) | ✅ 已合并 | DESIGN / GDD |
| 579 | Shandong Wolf 打击反馈系统 (ReactionController 组合触发核心 + FEEDBACK_MATRIX 9 事件×6 维分级矩阵 + 五效果组件: 火花/hit-stop/屏震/白闪/S 级刀光 + TimeScaleStack D1 min 墙钟兜底 + E2E 同帧截图 rig 三档 shot 冻结效果帧, AC1-AC6 全过, 参数 # DRAFT 归 #584, #654) | ✅ 已合并 | DESIGN / GDD |
| 580 | Shandong Wolf 处决系统 (ExecutionOrchestrator 处决编排器（bind 模式 + armed 窗口 + 触发时序）
| 585 | Shandong Wolf MVP 战斗闭环组装 (MainBattle BattleAssembler 13 步装配接线（玩家/敌人/Judge/HUD/Reaction/Revive/Execution 全 bind） + 游戏状态机 IDLE→COMBAT→KILL→AFTERGLOW→FAIL（FAIL 终态幂等，输入冻结 ic.set_process(false) + AI 停用） + 失败字幕淡入（B5 候选 5 选 1 取首项）+ 击杀 5s 余韵 Timer + 教学提示（3 候选取首项）+ 低血氛围单点接线 + Main.tscn 追加挂载（+BattleStage 实例 + MainBattle 节点）; 组装编排 4 常量 # DRAFT 归 #584; test_main_assembly 24 用例 + smoke Scenario II AC4 闭环 + E2E assembly 组 4 shot, AC1-AC5 全过, #666) | ✅ 已合并 | DESIGN / GDD |
| 662 | Shandong Wolf e2e 反馈截图 Backdrop 盖火花修复 (Backdrop/WorldBackdrop z_index 0→-2，背景<火花<角色层级约定固化，E2E 官方截图与真实战斗恢复火花可见, #675) | ✅ 已合并 | DESIGN / GDD |
| 586 | Shandong Wolf 端到端验证（E2E 剧本 + 用户裁决: e2e_script 组 6 帧情感弧剧本（scene_description/trigger/composition 文字契约 AC1）+ rig 4→7 态（MOVE 位移断言/CLASH judge 主路径/EXECUTE 特写, dwell 定长 settle 不跨态）+ 管线四修复（resolve_plan 组级键提升/e2e_capture 数字 state 直比+元数据透传/run-e2e-review 分辨率读取/analyze_bmp --size）+ headless 三档语义 + docs/TEST/586 报告模板, AC1-AC3 管线全过, AC4 用户 6 帧 1-5 星裁决待定稿, #673) | ✅ 已合并 | DESIGN / GDD |+ execute_kill 杀敌通道（绕过 take_damage no-op 红线 + _is_final_dead 停摆）+ set_invincible 玩家无敌 + recover_from_break 起身疲惫（50% 架势 + 5s ×1.2 增伤）+ ExecutionFade 墙钟淡出 + 「处决演出」7 常量 # DRAFT 归 #584 + E2E execution 组 2 shot + 六组测试套件, AC1-AC5 全过, 慢动作/淡出/范围等 DRAFT 值待用户 AC5 裁决, #660) | ✅ 已合并 | DESIGN / GDD |
## 已知问题

7项预存测试失败已在 #353 (暂停) 和 #355 (UI字体) 中全部修复并合并。
已知问题：#372（run-e2e-review.sh P6 上传函数定义顺序 bug + frozen 阈值过严）已在 #377 修复并合并（2026-08-11）。
L3 视觉回归（clear_color 双前缀 → 引擎默认灰替代设计暗底 #0a0a12）已在 #476 修复并合并（2026-08-14，PR #479），当前无已知问题。
title 界面混杂游戏世界（#508）已在 #511 修复并合并（2026-08-17）。当前无已知问题。
#627 附带框架层注意点：e2e hud group shots 用数字 state（0-3），e2e_capture.gd 驱动以顶层 states 命名 dict 为主——review 截图若报 state 解析问题属框架 gap（resolve_plan.py group 级 main_scene 提升机制已支持）。
#613 雪夜氛围回归（雪幕粒子不可见/血色 vignette 无效果，7 CanvasModulate 乘法链压暗）已由 #629 修复合并（单 CanvasModulate 层契约：7 moon → 1 moon 挂 layer 0 + 四层禁染 + C3 ==1 守卫），修复随 #613 于 2026-08-20 落地 main（含 self-correct 粒子 texture 程序化软白点）；NIGHT_BG_COLOR 候选 #d8dce4 等 taste 值待 #582 用户 E2E 截图定稿。
#578 复活演出参数（constants.gd「复活 FX 分区」12 常量：墨点/闪屏/慢动作/闪烁四件套）为 # DRAFT 候选值，定稿归 #584 调参；AC5 复活瞬间 E2E 截图情绪裁决（「硬汉再起」vs「日式中二觉醒」）待用户定稿 → docs/TASTE.md。
#581/#638 敌人 AI 数值全量 # DRAFT（AI 分区 18 常量 + ENEMY_ATTACK_WINDUP 15→12 实现期 AC1 对齐偏离）定稿归 #584 调参面板；#585 组装前敌人由测试直接装配，场景出生点/巡逻路径 waypoints 已由 #585/#666 配置（EnemyAI.waypoints 由 EnemySpawnA/B 坐标派生）。

#583/#646 战斗舞台参数（constants.gd「场景参数」分区：STAGE_*/PLATFORM_*/色板/MOON_*/物件）为 # DRAFT 候选值（含实现期 self-correct 调亮 STAGE_INK_COLOR #1a1f26→#4a5664 保证 #624 F3 染后 luma ≥30），定稿归 #583 AC5 E2E 截图用户裁决；battle_stage 挂载 Main.tscn 与 EnemyAI.waypoints 配置已由 #666 组装完成。

#579/#654 打击反馈强度参数（constants.gd「反馈分区」12 常量：FEEDBACK_SPARK_COUNT/VELOCITY/LIFETIME/HITSTOP_MS/SHAKE_PX/DECAY/SLOWMO/FLASH/ENTITY_FLASH_FACTOR 等）全量 # DRAFT 候补值，定稿归 #584 调参面板/用户裁决；AC6「刀锋相撞」重量感与雪夜水墨宁静基调是否成立待用户 E2E 三档截图（fb_parry_success/fb_stance_break/fb_execute）定稿 → docs/TASTE.md。战斗场景挂载 Camera2D + ReactionController 实例化归 #585 组装；feedback_played 信号消费归 #593 音效。
#585/#666 组装编排参数（constants.gd「组装编排」分区：AFTERGLOW_SECONDS=5.0 / FAIL_SUBTITLE_DELAY=0.5 / FAIL_SUBTITLE_FADE_SECONDS=1.0 / TUTORIAL_HINT_DELAY=3.0）为 # DRAFT 候选值，定稿归 #584 调参；失败字幕文案（B5 失败表达 5 选 1，当前取首项『雪落无声。村口只剩你。』）与教学提示文案（3 候选，当前取首项）为 taste-draft 候选清单，待用户 E2E assembly 组截图（03_fail_subtitle/04_afterglow）定稿 → docs/TASTE.md；敌人重生 / 多敌波次不在 MVP 范围（EnemySpawnB 保留备用，AC3 只要求击杀后空闲 ≥5s）。
#662 e2e_feedback_capture Backdrop（z=0 默认）盖住打击火花（z=-1）缺陷（#654 rig / #666 Main.tscn 引入背景时未设 z_index）已由 #675 修复（两处背景 z_index 0→-2，层级约定「背景<火花<角色」写入 GDD 15 §9）；E2E feedback/assembly 组截图恢复火花可见，真实战斗画面同步修复。当前无新增已知问题。
