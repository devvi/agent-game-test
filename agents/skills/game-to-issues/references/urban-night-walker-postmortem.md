# Postmortem: urban-night-walker — 一堆资源，没有游戏 (2026-07)

> **失败结论：** game-to-issues 分解出的 18 个组件 Issue **全部实现完成并合入 main**，
> 但整个游戏**无法玩**。原因不是组件质量差，而是**没有任何 Issue 负责组装**。
> 这是"冰箱里的食物"问题的完整实战案例。

## 症状

- 仓库里有：NPCNode、DialogueRunner、SceneBase、dialogue_balloon.tscn、subway_station.tscn、
  StateSystem、Constants（autoload）、多场景 .tscn 文件
- 测试套件有 1000+ 断言（大量 TC 编号），但 **24 个 pre-existing 测试失败**：
  - `dialogue_balloon.tscn` 用了 Godot 4.7 不支持的 `theme_override_*` 语法 → 级联导致 3 个套件无法加载
  - `dialogue_runner` 解析旧格式 dialogue JSON 失败（文件已迁移格式，测试没跟着改）
  - `subway_station.tscn` 路径拼写错误（`subway/` vs `subway_station/`）
  - `Constants` 未注册为 autoload，`ECHO_DEFINITIONS` 字段名变更（echo_id→id, target_scenes→target_scene）
  - `_get_tone` 重命名为 `_get_tone_for_scene`，测试仍调旧名
- 玩家打开游戏：没有主场景入口（main.gd 试图加载不存在的场景树）

## 根因链（三层）

```
L1 分解缺组装：18 个组件 Issue 的 dependencies 互相关联，但没有一个
   [Integration] 主场景组装 Issue 依赖全部组件 → 组件各自为政
L2 pipeline 不验证可玩：CI 只跑"组件级单元测试"，没有"从主场景启动并
   走完一条路径"的端到端测试 → 每个 PR 绿，合起来不可玩
L3 技术债累积：24 个失败测试在 main 上长期存在（pre-existing），
   新功能合入时被旧测试污染，最终无人能分清哪些坏在哪
```

## 对比正例：mini-pong（成功）

```
#10 [mvp] [Integration] 主场景组装   deps=[2,3,4,5,6,7,8,9]  ← 全部组件
    ac: Main.tscn 场景树正确 / 所有信号连接完整 / 全局常量统一配置
#12 [mvp] [Test] 100 回合自动对打    deps=[10]               ← 依赖组装
    ac: 自动对打可跑完 / 计分正确 / 游戏可结束可重开
```

关键差异：
1. mini-pong 的 MVP 有一个 **组装 Issue** 依赖所有组件（组件→组装→验证一条链）
2. mini-pong 的 MVP 有一个 **端到端验证 Issue**（自动对打）依赖组装
3. mini-pong 没有"孤儿组件"——每个组件都出现在组装的 dependencies 里

## 防护措施（已固化进 game-to-issues）

1. **Completeness Gate C5.5 组装闭环**：分解后强制检查
   - 必须有 `[Integration]` 组装 Issue（deps=全部 mvp 组件）
   - 必须有 `[Test]` 端到端验证 Issue（deps=组装）
   - 没有孤儿组件（每个组件都在组装的 deps 里）
2. **依赖顺序即执行顺序**（C6）：pipeline 的 `_has_unresolved_dependencies` 会
   BLOCK 前置未完成的 Issue——分解时确保"先做的"进 dependencies，防止依赖倒置
   （#227 人物移动未合并，#228 交互系统就开始做，被迫猜接口）
3. **重构必改测试**（AGENTS.md 测试纪律）：机制变更（重命名、字段变更、格式迁移）
   必须同步更新测试——urban-night-walker 的 24 个失败大半是"改了代码没改测试"

## 诊断命令（遇到"资源都在但游戏不可玩"时）

```bash
# 1. 主场景入口存在吗？能加载吗？
ls scenes/main.tscn 2>/dev/null || echo "❌ 无主场景"
godot --headless --quit 2>&1 | grep -E "ERROR|SCRIPT ERROR" | head

# 2. 组件级测试 vs 端到端测试的分布
grep -rl "extends SceneTree" tests/ | head
grep -rl "playthrough\|auto.*play\|100 回合\|自动对打" tests/ | head

# 3. pre-existing 失败：main 上跑一遍测试
godot --headless --script tests/run_tests.gd 2>&1 | tail -5

# 4. 依赖倒置检查：有没有"依赖未合并就开始做"的 Issue
gh issue list --state open --json number,title,labels --jq '.[] | select(.labels[].name=="workflow/implement")'
# 对其父依赖的 research/plan PR 状态
```
