# Project Overview

## 项目状态

| 指标 | 状态 |
|------|:----:|
| 编译 | ✅ 通过 |
| 可运行 | ✅ 能启动 |
| 可玩 | ✅ PONG://NEON（原 Mini Pong）: 完整状态机(MENU→SERVING→PLAYING⇌PAUSED→SCORED→GAME_OVER)、UI系统、球物理、挡板移动、AI对手、暂停(Escape)、音效合成、L0动态雨幕(GPUParticles2D)、失败屏(win/fail双分支+run数据+软冻结)、球速 HUD 实时显示 |
| 最近构建 | 2026-08-13 |
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

## 已知问题

7项预存测试失败已在 #353 (暂停) 和 #355 (UI字体) 中全部修复并合并。
已知问题：#372（run-e2e-review.sh P6 上传函数定义顺序 bug + frozen 阈值过严）已在 #377 修复并合并（2026-08-11），当前无已知问题。
