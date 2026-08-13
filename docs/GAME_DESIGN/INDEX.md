# GAME DESIGN DOCUMENT INDEX

| File | Description |
|------|-------------|
| [09-TESTING](09-TESTING.md) | Testing system — headless test runner, E2E Playthrough (真实物理完整一局), auto-play test, local E2E review harness (L0-L3), coverage map |
| [INDEX](INDEX.md) | Table of contents |
| [10-SCENE-LAYOUT](10-SCENE-LAYOUT.md) | 3D scene layout — floor, walls, collision |
| [11-PLAYER-PADDLE](11-PLAYER-PADDLE.md) | Player paddle & AI opponent — InputMap, movement, clamp, AI mode |
| [12-NEON-VISUAL](12-NEON-VISUAL.md) | Neon cyber visuals — glow, trail, flash, colors |
| [13-BALL-PHYSICS](13-BALL-PHYSICS.md) | Ball physics — wall/paddle collision, speed escalation, scoring, serve |
| [14-SCORING-SYSTEM](14-SCORING-SYSTEM.md) | Scoring system — brick 1pt / pierce 3pt / 21-point run, signal chain |
| [15-GAME-MANAGER](15-GAME-MANAGER.md) | GameManager autoload — global state singleton, reset APIs, get_winner() |
| [16-UI-SYSTEM](16-UI-SYSTEM.md) | UI system — StartMenu, GameHUD (三区霓虹 + 球速实时显示 #448), GameOverScreen with CanvasLayer architecture |
| [17-GAME-STATE-MACHINE](17-GAME-STATE-MACHINE.md) | Game state machine — 5-state FSM, input routing, paddle freeze, UI orchestration |
| [18-PAUSE-SYSTEM](18-PAUSE-SYSTEM.md) | Pause system — Escape toggle, PAUSED state, PauseOverlay CanvasLayer |
| [19-AUDIO-ENGINE](19-AUDIO-ENGINE.md) | Audio engine — AudioStreamGenerator synthesis, 4 sound effects |
| [20-NAMING](20-NAMING.md) | Naming — constraints (红线), NAMING.md draft flow, finalization handoff to TASTE.md |
| [21-WAVE-FAILURE-TEXT](21-WAVE-FAILURE-TEXT.md) | Wave failure text — 波次副句/失败短句红线, content JSON schema (wave-failure-text/v1), #390/#391 消费数据流, TASTE.md 定稿回写 |
| [22-RAIN-CURTAIN](22-RAIN-CURTAIN.md) | L0 rain curtain — GPUParticles2D atmosphere layer, formula-driven rain intensity, contract API |
| [23-UPGRADE-POOL](23-UPGRADE-POOL.md) | Upgrade pool — rogue-lite per-wave growth, 9 upgrades, 60/30/10 rarity draw, instance parameterization, upgrade_hooks contract |
| [24-WAVE-CYCLE](24-WAVE-CYCLE.md) | Wave cycle — wave state machine, wall_cleared orchestration, dual-lever difficulty, 21-pt stop |
| [25-UPGRADE-UI](25-UPGRADE-UI.md) | Upgrade Pick UI — 波间 3 选 1 升级选择层, wave_settled 挂点, 焦点环/确认, 稀有度 reveal, 暂停与推进接管 |
| [26-BG-NEON-BREATH](26-BG-NEON-BREATH.md) | Background neon breath — L0 背景光晕正弦呼吸 (ColorRect + 纯函数公式 + BG_PULSE 常量区, FSM-independent) |
