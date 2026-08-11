# Project Overview

## 项目状态

| 指标 | 状态 |
|------|:----:|
| 编译 | ✅ 通过 |
| 可运行 | ✅ 能启动 |
| 可玩 | ✅ Mini Pong: 完整状态机(MENU→SERVING→PLAYING⇌PAUSED→SCORED→GAME_OVER)、UI系统、球物理、挡板移动、AI对手、暂停(Escape)、音效合成 |
| 最近构建 | 2026-08-11 |
| 开放 Issues | 1（#367 手感定稿待定） |

## 模块地图

| 模块 | 文件 | 状态 | 设计文档 |
|------|------|:----:|:--------:|
| 3D Scene Layout | `scenes/feature-mini-walker-3d.tscn` | ✅ | GDD |
| 3D Scene Layout (alt) | `scenes/mini_world.tscn` | ✅ | GDD |
| Mini Pong — Paddle | `mini-pong/gdscripts/paddle.gd` | ✅ | GDD |
| Mini Pong — Ball Physics | `mini-pong/gdscripts/ball.gd` | ✅ | GDD |
| Mini Pong — Neon Visual | `mini-pong/gdscripts/ball_trail.gd` | ✅ | GDD |
| Mini Pong — Scoring | `mini-pong/gdscripts/scoring_manager.gd` | ✅ | GDD |
| Mini Pong — GameManager | `mini-pong/gdscripts/game_manager.gd` | ✅ | GDD |
| Mini Pong — Arena | `mini-pong/scenes/Main.tscn` | ✅ | GDD |
| Mini Pong — Constants | `mini-pong/gdscripts/constants.gd` | ✅ | GDD |
| Mini Pong — ScoreFlash | `mini-pong/gdscripts/score_flash.gd` | ✅ | GDD |
| Mini Pong — StartMenu | `mini-pong/gdscripts/start_menu.gd` | ✅ | GDD |
| Mini Pong — GameHUD | `mini-pong/gdscripts/game_hud.gd` | ✅ | GDD |
| Mini Pong — GameOverScreen | `mini-pong/gdscripts/game_over_screen.gd` | ✅ | GDD |
| Mini Pong — State Machine | `mini-pong/gdscripts/game_state_machine.gd` | ✅ | GDD |
| Mini Pong — Pause Overlay | `mini-pong/gdscripts/pause_overlay.gd` | ✅ | GDD |
| Mini Pong — Audio Engine | `mini-pong/gdscripts/audio_engine.gd` | ✅ | GDD |
| Mini Pong — Test Suite | `mini-pong/tests/run_tests.gd` | ✅ | GDD |
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
| 358 | Mini Pong 标题画面版本号 v1.0.0 | ✅ 已合并 | DESIGN / GDD |
| 367 | Mini Pong 手感校准草稿 (球速/反弹角/AI 强度) | 🧪 草稿已合并，待用户定稿 | DESIGN / TASTE |

## 已知问题

7项预存测试失败已在 #353 (暂停) 和 #355 (UI字体) 中全部修复并合并。
已知问题：#372 — run-e2e-review.sh P6 上传函数定义顺序 bug + frozen 阈值过严（class A harness，修复中）。
