# GAME DESIGN DOCUMENT — shandong-wolf（山东抗日之狼）

> 本目录为《山东抗日之狼》的 GDD（分游戏目录，2026-08-19 起）。
> 章节由 post-merge agent 在 implement PR merge 后按功能域填充（01-OVERVIEW → 09+），
> 规则见 game-post-merge-agent skill + AGENTS.md「游戏设计文档（GDD）」。
> 章节结构与 mini-pong（docs/GAME_DESIGN/ 根目录）一致：叙事体、层次编号、代码块放定义、表格放参数、段落讲意图。

| File | Description |
|------|-------------|
| [INDEX](INDEX.md) | Table of contents |
| [01-OVERVIEW](01-OVERVIEW.md) | Game overview — 场景骨架（Main.tscn 节点树）、post-merge 探针 Label（#567） |
| [02-CONSTANTS](02-CONSTANTS.md) | WolfConstants 数值集中地 — 机械常量 + 6 个 # DRAFT 手感分区（只狼基准 14 参数三行注释，#572/#584/#599/#609） |
| [03-STATE-MACHINE](03-STATE-MACHINE.md) | StateMachineBase 通用状态机基类 — 三接口契约 + 同态/防重入守卫（#572/#599） |
| [04-GAME-AUTOLOAD](04-GAME-AUTOLOAD.md) | Game autoload 锚点 — 版本号 + constants 预加载，单例注册约定（#572/#599） |
| [05-DEBUG-CANVAS](05-DEBUG-CANVAS.md) | DebugCanvas 战斗数值调参面板 — F1 热更新 + 14 参数 PARAMS 表 + 静态读值链路 + JSON dump（#584/#609） |
| [06-INPUT-CONTROLLER](06-INPUT-CONTROLLER.md) | 输入层 — Input Map 9 动作 + InputController 意图事件/时间戳缓冲 + PlayerController 加速度移动 + 输入层 # DRAFT 分区（#573/#611） |
