# GAME DESIGN DOCUMENT — shandong-wolf（山东抗日之狼）

> 本目录为《山东抗日之狼》的 GDD（分游戏目录，2026-08-19 起）。
> 章节由 post-merge agent 在 implement PR merge 后按功能域填充（01-OVERVIEW → 10+），
> 规则见 game-post-merge-agent skill + AGENTS.md「游戏设计文档（GDD）」。
> 章节结构与 mini-pong（docs/GAME_DESIGN/ 根目录）一致：叙事体、层次编号、代码块放定义、表格放参数、段落讲意图。

| File | Description |
|------|-------------|
| [INDEX](INDEX.md) | Table of contents |
| [01-OVERVIEW](01-OVERVIEW.md) | Game overview — 场景骨架（Main.tscn 节点树）、post-merge 探针 Label（#567） |
| [02-CONSTANTS](02-CONSTANTS.md) | WolfConstants 数值集中地 — 机械常量 + 9 个 # DRAFT 手感分区（只狼基准 14 参数三行注释 + #574 动画 20 常量 + #618 战斗时序 5 常量，#572/#574/#584/#599/#609/#612/#618） |
| [03-STATE-MACHINE](03-STATE-MACHINE.md) | StateMachineBase 通用状态机基类 — 三接口契约 + 同态/防重入守卫；#575 战斗状态对象派生（#572/#599/#618） |
| [04-GAME-AUTOLOAD](04-GAME-AUTOLOAD.md) | Game autoload 锚点 — 版本号 + constants 预加载，单例注册约定（#572/#599） |
| [05-DEBUG-CANVAS](05-DEBUG-CANVAS.md) | DebugCanvas 战斗数值调参面板 — F1 热更新 + 14 参数 PARAMS 表 + 静态读值链路 + JSON dump（#584/#609） |
| [06-INPUT-CONTROLLER](06-INPUT-CONTROLLER.md) | 输入层 — Input Map 9 动作 + InputController 意图事件/时间戳缓冲 + PlayerController 加速度移动 + 输入层 # DRAFT 分区（#573/#611） |
| [07-STICK-FIGURE-ANIMATION](07-STICK-FIGURE-ANIMATION.md) | 火柴人剪影骨架与关键帧动画 — Line2D 程序化骨架 7 pivot + 11 态→clip 镜像映射 + consume_state 契约 + 过渡 ≤2 帧 + additive 刀光 + E2E 截图像具（#574/#612） |
| [08-COMBAT-ENTITY](08-COMBAT-ENTITY.md) | CombatEntity 战斗实体基类 — 两段血 hp_1/hp_2 + stance/facing 数据容器 + request_transition 唯一转移入口 + 6 信号契约 + _StateInputBridge 输入桥 + 玩家/敌人变体参数（#575/#618） |
| [09-COMBAT-STATE-MACHINE](09-COMBAT-STATE-MACHINE.md) | 11 态战斗状态机 — CANONICAL_STATES 权威集 + TRANSITIONS 转移表 + CombatStateBase/11 状态对象 + 战斗时序 5 常量 + 数据流（#575/#618） |
| [10-HUD-STANCE-BARS](10-HUD-STANCE-BARS.md) | 极简 HUD 层 — CanvasLayer layer=1 纯消费方：两段式血条/玩家与敌人架势条/击杀与处决提示 + low_health_changed 边沿信号 + 13 个 HUD # DRAFT 常量 + 4 帧 E2E 截图剧本（#576/#627） |
| [11-PARRY-CLASH-STANCE-BREAK](11-PARRY-CLASH-STANCE-BREAK.md) | 拼刀/弹反/架势崩解判定层 — CombatJudge 判定协调器（逻辑帧窗口裁决：弹反>拼刀>格挡>受击，CLASH_PRIORITY 常量驱动）+ AttackWindow 窗口契约 + 五结果事件（parry_success/block_held/hit_landed/clash/stance_broken）+ 6 判定 # DRAFT 常量（#577/#626） |
