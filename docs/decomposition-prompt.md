你是一个资深游戏开发者 + 系统架构师。请将以下游戏开发命令分解为结构化的 GitHub Issues JSON。

## 项目信息
- 引擎: Godot 4.7.1
- 平台: macOS / Linux / Windows
- 目录: mini-pong/
- 画面风格: 霓虹赛博（暗底 #0a0a12、霓虹蓝 #4a90d9、霓虹红 #ff3355、Godot glow/bloom、GPUParticles2D）

## 用户命令
用 game-to-issues 来做 Mini Pong：经典 Pong 玩法，2D 乒乓球。霓虹赛博视觉风格（暗底+发光线条+辉光粒子+霓虹色块）。玩家挡板 vs AI 对手、球反弹物理、计分系统、三局两胜。全流程验证 game-to-issues skill 和 workflow 管线。

## 分解规则

### 1. 粒度原则
- 每个 Issue 一个独立功能
- 不要拆到单个函数，也不要一个 Issue 涵盖整个游戏
- 合理粒度："实现球物理系统" ✅ / "实现球碰撞检测" ❌ 太细 / "做一个Pong游戏" ❌ 太粗

### 2. 依赖规则
- 用 dependencies 数组表达前置依赖
- DAG（有向无环图），不能有循环依赖
- 基础设施在最前面

### 3. 优先级金字塔: critical < high < medium < low

### 4. 深度: deep / standard / light

### 5. CRPG 专项规则不适用（这是 2D 街机游戏）

### 6. 分层表达不适用（这是街机游戏，不是叙事游戏）

### 7. 引擎专项规范（Godot 4.x）
- CollisionShape2D 必须有 shape 子资源
- InputMap 在代码中绑定，不依赖 project.godot 解析
- 动态创建的节点用 var + _ready() 而非 @onready
- Godot 内置 glow/bloom 通过 WorldEnvironment 配置

### 8. 节奏控制
- 街机游戏节奏由游戏机制本身提供（球速递增、回合制）
- MVP 必须完成完整一局：菜单→对打→计分→结束→重开

### 9. 画面风格
用户已提供明确的画面风格：霓虹赛博。必须包含：
- WorldEnvironment glow/bloom 视觉效果 Issue
- UI 风格（发光字体、霓虹色、暗底）Issue

### 10. 版本切片
- mvp: 最小可玩垂直切片（能完整打一局 Pong）
- v1: 增强（暂停、音效）
- full: 全部

### 11. 集成要求
必须有"胶水代码" Issue 将所有组件连接起来。必须有自动化测试 Issue。

## 输出格式要求
严格 JSON，不要 markdown 包裹。每个 Issue 包含：
- id, title: [类型] 标题
- description: 功能描述
- context: 背景和动机
- depth: light/standard/deep
- priority: critical/high/medium/low
- dependencies: id 数组
- labels: ["enhancement", "workflow/backlog"]
- estimate: small/medium/large
- milestone: mvp/v1/full
- acceptance_criteria: 3-5 条验收条件，包含 "--headless --quit 无脚本错误"
