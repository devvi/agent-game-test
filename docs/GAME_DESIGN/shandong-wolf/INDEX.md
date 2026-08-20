# GAME DESIGN DOCUMENT — shandong-wolf（山东抗日之狼）

> 本目录为《山东抗日之狼》的 GDD（分游戏目录，2026-08-19 起）。
> 章节由 post-merge agent 在 implement PR merge 后按功能域填充（01-OVERVIEW → 10+），
> 规则见 game-post-merge-agent skill + AGENTS.md「游戏设计文档（GDD）」。
> 章节结构与 mini-pong（docs/GAME_DESIGN/ 根目录）一致：叙事体、层次编号、代码块放定义、表格放参数、段落讲意图。

| File | Description |
|------|-------------|
| [INDEX](INDEX.md) | Table of contents |
| [01-OVERVIEW](01-OVERVIEW.md) | Game overview — 场景骨架（Main.tscn 节点树）、post-merge 探针 Label（#567）+ 探针 C api-close-reopen（#652/#658） |
| [02-CONSTANTS](02-CONSTANTS.md) | WolfConstants 数值集中地 — 机械常量 + 9 个 # DRAFT 手感分区（只狼基准 14 参数三行注释 + #574 动画 20 常量 + #618 战斗时序 5 常量，+ #579 反馈 12 常量，#572/#574/#584/#599/#609/#612/#618/#654） |
| [03-STATE-MACHINE](03-STATE-MACHINE.md) | StateMachineBase 通用状态机基类 — 三接口契约 + 同态/防重入守卫；#575 战斗状态对象派生（#572/#599/#618） |
| [04-GAME-AUTOLOAD](04-GAME-AUTOLOAD.md) | Game autoload 锚点 — 版本号 + constants 预加载，单例注册约定（#572/#599） |
| [05-DEBUG-CANVAS](05-DEBUG-CANVAS.md) | DebugCanvas 战斗数值调参面板 — F1 热更新 + 14 参数 PARAMS 表 + 静态读值链路 + JSON dump（#584/#609） |
| [06-INPUT-CONTROLLER](06-INPUT-CONTROLLER.md) | 输入层 — Input Map 9 动作 + InputController 意图事件/时间戳缓冲 + PlayerController 加速度移动 + 输入层 # DRAFT 分区（#573/#611） |
| [07-STICK-FIGURE-ANIMATION](07-STICK-FIGURE-ANIMATION.md) | 火柴人剪影骨架与关键帧动画 — Line2D 程序化骨架 7 pivot + 11 态→clip 镜像映射 + consume_state 契约 + 过渡 ≤2 帧 + additive 刀光 + E2E 截图像具（#574/#612） |
| [08-COMBAT-ENTITY](08-COMBAT-ENTITY.md) | CombatEntity 战斗实体基类 — 两段血 hp_1/hp_2 + stance/facing 数据容器 + request_transition 唯一转移入口 + 6 信号契约 + _StateInputBridge 输入桥 + 玩家/敌人变体参数（#575/#618） |
| [09-COMBAT-STATE-MACHINE](09-COMBAT-STATE-MACHINE.md) | 11 态战斗状态机 — CANONICAL_STATES 权威集 + TRANSITIONS 转移表 + CombatStateBase/11 状态对象 + 战斗时序 5 常量 + 数据流（#575/#618） |
| [10-HUD-STANCE-BARS](10-HUD-STANCE-BARS.md) | 极简 HUD 层 — CanvasLayer layer=1 纯消费方：两段式血条/玩家与敌人架势条/击杀与处决提示 + low_health_changed 边沿信号 + 13 个 HUD # DRAFT 常量 + 4 帧 E2E 截图剧本（#576/#627） |
| [11-PARRY-CLASH-STANCE-BREAK](11-PARRY-CLASH-STANCE-BREAK.md) | 拼刀/弹反/架势崩解判定层 — CombatJudge 判定协调器（逻辑帧窗口裁决：弹反>拼刀>格挡>受击，CLASH_PRIORITY 常量驱动）+ AttackWindow 窗口契约 + 五结果事件（parry_success/block_held/hit_landed/clash/stance_broken）+ 6 判定 # DRAFT 常量（#577/#626） |
| [12-ATMOSPHERE-SNOW-NIGHT](12-ATMOSPHERE-SNOW-NIGHT.md) | 雪夜氛围层 — 四层系统（三层视差雪幕 60/60/80 粒子 + 单 CanvasModulate 冷月光 #6e7684 + 水墨晕染 shader + 血色 vignette 契约）+ 单 moon 层契约（唯一 moon 挂 layer 0 + 雪幕3-5/水墨2/血色10/UI1 禁染 + C3 ==1 守卫）+ 4 组 24 项氛围常量 # DRAFT（#582/#624/#613，#613 已 merge 2026-08-20 落地 main） |
| [13-REVIVE-SYSTEM](13-REVIVE-SYSTEM.md) | 两条命原地复活系统 — ReviveOrchestrator 编排器（died(final=false)→REVIVE_SECONDS 计时→revive() 自动复活，与 F 键手动路径双路径幂等收敛）+ ReviveFX 演出四件套（墨点 burst/瞬态闪屏/慢动作/无敌闪烁，12 常量 # DRAFT 归 #584）+ SW-015 终态契约（#578/#637） |
| [13-ENEMY-AI](13-ENEMY-AI.md) | 基础日本兵 AI — EnemyAI 行为状态机（第二个 StateMachineBase：patrol/chase/attack/retreat 4 行为态 + 120° 视线 6m 几何感知 + 决策门控 + 弹反抑制窗 0.5s）+ 判定层 3 处 additive 参数化（windup_frames/伤害 @export/judge 读实体参数）+ AI 分区 18 个 # DRAFT 常量 + 36 用例测试套件（#581/#638） |
| [14-SCENE-BATTLE-STAGE](14-SCENE-BATTLE-STAGE.md) | 雪夜山东村战斗舞台 — battle_stage.tscn 纯声明式世界层场景（单一连续碰撞面 2400px + 视觉 3 段雪堆高差 60-100px / 草屋×2 墨色剪影+屋顶压雪线 / 枯树×2 骨架 / 山峦远景 / 苍月 Mesh2D 径向渐变+moon_glow 光晕 shader / PlayerSpawn+EnemySpawnA/B 出生点 / StageCamera limits 2400，零脚本零贴图零新增 CanvasModulate）+ constants 场景参数分区 # DRAFT + E2E battle_stage 组 3 shot（#583/#646，#646 已 merge 2026-08-20） |
| [15-COMBAT-FEEDBACK-SYSTEM](15-COMBAT-FEEDBACK-SYSTEM.md) | 打击反馈系统 — ReactionController 组合触发核心（单入口 trigger_feedback + FEEDBACK_MATRIX 9 事件×6 维分级矩阵）+ 五效果组件（FeedbackSpark 苍白金 one_shot 火花 / TimeScaleStack 时间栈 D1 min+墙钟兜底 / ScreenShake trauma² 屏震 / FlashEffect 实体+全屏白闪双通道 / SwordArc 复用）+ 反馈分区 12 常量 # DRAFT + 28 用例测试套件 + E2E 三档截图 rig（#579/#654，#654 已 merge 2026-08-20） |
| [16-EXECUTION-SYSTEM](16-EXECUTION-SYSTEM.md) | 处决系统 — ExecutionOrchestrator 处决编排器（bind 模式：stance_broken→armed 窗口 3s + 攻击键/距离≤120px 校验 → 触发时序 ①无敌②转移③杀敌④S 级反馈⑤淡出，D1-D6）+ execute_kill 杀敌通道（绕过 take_damage no-op 红线 + _is_final_dead 停摆守卫）+ set_invincible 无敌 + recover_from_break 起身疲惫（50% 架势 + 5s ×1.2 增伤）+ ExecutionFade 墙钟驱动淡出 0.3s + 「处决演出」7 常量 # DRAFT 归 #584 + 六组测试套件 + E2E execution 组 2 shot（#580/#660） |
