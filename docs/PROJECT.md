# Project Overview

## 项目状态

| 指标 | 状态 |
|------|:----:|
| 编译 | ✅ 通过 |
| 可运行 | ✅ 能启动 |
| 可玩 | ✅ PONG://NEON（原 Mini Pong）: 完整状态机(MENU→SERVING→PLAYING⇌PAUSED→SCORED→GAME_OVER)、UI系统、球物理、挡板移动、AI对手、暂停(Escape)、音效合成、L0动态雨幕(GPUParticles2D)、失败屏(win/fail双分支+run数据+软冻结)、球速 HUD 实时显示；🟡 shandong-wolf（当前活跃游戏）: 逻辑地基就绪（WolfConstants 数值集中地 + StateMachineBase 状态机基类 + Game autoload）+ 战斗数值 DRAFT 集中表（#584 只狼基准 14 参数候补值）+ DebugCanvas F1 调参面板（#609，仅 debug build）+ 输入层就绪（Input Map 9 动作 + InputController 意图事件/时间戳缓冲 + PlayerController 加速度移动，#611）+ 战斗实体与状态机就绪（CombatEntity 数据容器/两段血/输入桥 + 11 态战斗状态机 + 战斗时序 DRAFT 分区，#618）+ 火柴人剪影骨架与关键帧动画（Line2D 程序化骨架 7 pivot + 11 态关键帧 + consume_state 契约 + additive 刀光，#612）+ 血条与架势条极简 HUD（两段式血条/双架势条/击杀与处决提示，程序化绘制零贴图，草稿已合并待用户 E2E 截图定稿，#627）+ 拼刀/弹反/架势崩解判定层（CombatJudge 逻辑帧窗口判定 + AttackWindow 窗口契约 + 弹反/拼刀/格挡/受击五结果事件 + 6 判定常量 # DRAFT，#626）+ 雪夜氛围层（#582/#613 四层系统已落地 main：三层视差雪幕 60/60/80 粒子 + 单 CanvasModulate 冷月光 #6e7684 + 水墨晕染 + 血色 vignette 契约；#624/#629 单 moon 层契约：唯一 moon 挂 layer 0 + 雪幕/水墨/血色/UI 禁染 + C3 ==1 守卫；NIGHT_BG_COLOR 等 # DRAFT 定稿归 #582 用户裁决）+ 两条命原地复活系统（ReviveOrchestrator 自动复活编排：died(final=false)→1s 计时→revive()，与 F 键手动路径双路径幂等收敛 + ReviveFX 演出四件套：墨点 burst/瞬态闪屏/慢动作/无敌闪烁，12 演出常量 # DRAFT 归 #584，SW-015 终态契约固化，#637） + 基础日本兵 AI（EnemyAI 行为状态机：巡逻/追击/攻击/被弹反 4 行为态 + 120° 视线 6m 几何感知（无 raycast/Area2D）+ 决策门控 + 弹反抑制窗 0.5s；判定层 3 处 additive 参数化 + AI 分区 18 常量 # DRAFT，AC1-AC5 全过，#638）+ 雪夜山东村战斗舞台（battle_stage.tscn 纯声明式世界层场景：单一连续碰撞面 2400px + 视觉 3 段雪堆高差 60-100px + 草屋×2/枯树×2 墨色剪影 + 山峦远景 + 苍月 Mesh2D 径向渐变 + moon_glow 光晕 shader + PlayerSpawn/EnemySpawnA/B 出生点 + StageCamera limits 2400，零贴图零新增 CanvasModulate（C3 守卫），E2E battle_stage 组截图待用户 AC5 裁决，#646） |
| 最近构建 | 2026-08-20（shandong-wolf 雪夜山东村战斗舞台 #646） |
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
| Shandong Wolf — 夜色世界背景 | `shandong-wolf/scenes/Main.tscn` WorldBackdrop（layer 0 ColorRect，NIGHT_BG_COLOR 单一事实源） | ✅ | GDD |
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
| E2E Review Harness | `scripts/run-e2e-review.sh` + `scripts/e2e/analyze_bmp.py` + `framework/templates/e2e_capture.gd` | ✅ | GDD |

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
## 已知问题

7项预存测试失败已在 #353 (暂停) 和 #355 (UI字体) 中全部修复并合并。
已知问题：#372（run-e2e-review.sh P6 上传函数定义顺序 bug + frozen 阈值过严）已在 #377 修复并合并（2026-08-11）。
L3 视觉回归（clear_color 双前缀 → 引擎默认灰替代设计暗底 #0a0a12）已在 #476 修复并合并（2026-08-14，PR #479），当前无已知问题。
title 界面混杂游戏世界（#508）已在 #511 修复并合并（2026-08-17）。当前无已知问题。
#627 附带框架层注意点：e2e hud group shots 用数字 state（0-3），e2e_capture.gd 驱动以顶层 states 命名 dict 为主——review 截图若报 state 解析问题属框架 gap（resolve_plan.py group 级 main_scene 提升机制已支持）。
#613 雪夜氛围回归（雪幕粒子不可见/血色 vignette 无效果，7 CanvasModulate 乘法链压暗）已由 #629 修复合并（单 CanvasModulate 层契约：7 moon → 1 moon 挂 layer 0 + 四层禁染 + C3 ==1 守卫），修复随 #613 于 2026-08-20 落地 main（含 self-correct 粒子 texture 程序化软白点）；NIGHT_BG_COLOR 候选 #d8dce4 等 taste 值待 #582 用户 E2E 截图定稿。
#578 复活演出参数（constants.gd「复活 FX 分区」12 常量：墨点/闪屏/慢动作/闪烁四件套）为 # DRAFT 候选值，定稿归 #584 调参；AC5 复活瞬间 E2E 截图情绪裁决（「硬汉再起」vs「日式中二觉醒」）待用户定稿 → docs/TASTE.md。
#581/#638 敌人 AI 数值全量 # DRAFT（AI 分区 18 常量 + ENEMY_ATTACK_WINDUP 15→12 实现期 AC1 对齐偏离）定稿归 #584 调参面板；#585 组装前敌人由测试直接装配，场景出生点/巡逻路径 waypoints 待 #583 配置。

#583/#646 战斗舞台参数（constants.gd「场景参数」分区：STAGE_*/PLATFORM_*/色板/MOON_*/物件）为 # DRAFT 候选值（含实现期 self-correct 调亮 STAGE_INK_COLOR #1a1f26→#4a5664 保证 #624 F3 染后 luma ≥30），定稿归 #583 AC5 E2E 截图用户裁决；battle_stage 挂载 Main.tscn 与 EnemyAI.waypoints 配置归 #585 组装。
