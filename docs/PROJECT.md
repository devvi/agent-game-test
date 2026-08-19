# Project Overview

## 项目状态

| 指标 | 状态 |
|------|:----:|
| 编译 | ✅ 通过 |
| 可运行 | ✅ 能启动 |
| 可玩 | ✅ PONG://NEON（原 Mini Pong）: 完整状态机(MENU→SERVING→PLAYING⇌PAUSED→SCORED→GAME_OVER)、UI系统、球物理、挡板移动、AI对手、暂停(Escape)、音效合成、L0动态雨幕(GPUParticles2D)、失败屏(win/fail双分支+run数据+软冻结)、球速 HUD 实时显示；🟡 shandong-wolf（当前活跃游戏）: 逻辑地基就绪（WolfConstants 数值集中地 + StateMachineBase 状态机基类 + Game autoload）+ 战斗数值 DRAFT 集中表（#584 只狼基准 14 参数候补值）+ DebugCanvas F1 调参面板（#609，仅 debug build）+ 输入层就绪（Input Map 9 动作 + InputController 意图事件/时间戳缓冲 + PlayerController 加速度移动，#611）+ 战斗实体与状态机就绪（CombatEntity 数据容器/两段血/输入桥 + 11 态战斗状态机 + 战斗时序 DRAFT 分区，#618）+ 火柴人剪影骨架与关键帧动画（Line2D 程序化骨架 7 pivot + 11 态关键帧 + consume_state 契约 + additive 刀光，#612） |
| 最近构建 | 2026-08-19（shandong-wolf 火柴人剪影骨架与关键帧动画 #612） |
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
## 已知问题

7项预存测试失败已在 #353 (暂停) 和 #355 (UI字体) 中全部修复并合并。
已知问题：#372（run-e2e-review.sh P6 上传函数定义顺序 bug + frozen 阈值过严）已在 #377 修复并合并（2026-08-11）。
L3 视觉回归（clear_color 双前缀 → 引擎默认灰替代设计暗底 #0a0a12）已在 #476 修复并合并（2026-08-14，PR #479），当前无已知问题。
title 界面混杂游戏世界（#508）已在 #511 修复并合并（2026-08-17）。当前无已知问题。
