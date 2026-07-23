# 09 — 测试系统（Testing）

> 游戏测试架构、头模式运行器、集成测试策略

---

## 1. 测试架构

### 核心理念

测试在 Godot headless 模式下运行（`--headless --script`），无需 3D 渲染管线或 GUI 交互。所有测试脚本通过 `tests/run_tests.gd` 统一编排，这是一个继承 `SceneTree` 的入口脚本，顺序加载各模块的测试文件。

### 测试文件组织

```
tests/
├── run_tests.gd                 # 主运行器 — SceneTree 入口
├── unit/                        # 单元测试（单模块边界测试）
│   ├── test_npc_node.gd
│   ├── test_npc_personality.gd
│   ├── test_player_controller.gd
│   ├── test_scene_base_player.gd
│   ├── test_dialogue_runner_extension.gd
│   ├── test_game_manager_player.gd
│   ├── test_e_key_trigger.gd
│   └── test_input_map_validation.gd
├── integration/                 # 集成测试（多模块协作测试）
│   ├── test_npc_in_scene.gd
│   └── test_player_in_scene.gd
├── test_mvp_integration.gd      # MVP 全流程集成测试（38 用例）
├── test_*.gd                    # 各阶段的独立测试文件
└── test_*.gd.uid                # Godot 资源 UID 文件
```

### 测试模式

所有 GDScript 测试文件使用统一的 `RefCounted` 模式：

```gdscript
extends RefCounted

var passed: int = 0
var failed: int = 0

func run() -> void:
    print("\n=== 测试模块名称 ===")
    _test_group_1()
    _test_group_2()
    print("\n  模块: %d passed, %d failed" % [passed, failed])

func _assert(condition: bool, label: String) -> void:
    if condition:
        passed += 1
        print("    ✅ %s" % label)
    else:
        failed += 1
        print("    ❌ %s" % label)
```

`run_tests.gd` 在每个测试模块结束时汇总 `passed` 和 `failed`：

```gdscript
var _test_script = load("res://tests/...").new()
_test_script.run()
passed += _test_script.passed
failed += _test_script.failed
```

如果 `failed > 0`，运行器以退出码 1 退出。

---

## 2. MVP 集成测试（Issue #158）

### 范围

38 个测试用例覆盖所有 10 个逻辑层集成点，无需 3D 渲染或 GUI：

| 章节 | 测试用例 | 被测系统 |
|------|---------|---------|
| 状态系统集成 | TC-INT-01→06 | StateSystem — 双极滑块、派生值、钳位、阻力、状态 ID、信号发射 |
| 对话-游戏管理器集成 | TC-INT-07→10 | GameManager → StateSystem 委托链 |
| 音频状态调制 | TC-INT-11→13 | AudioManager — 雨强度、音量钳位 |
| 叙事与场景序列 | TC-INT-14→18 | NarrativeManager — 场景顺序、推进、结局判定 |
| 回声系统 | TC-INT-19→20 | 触发的单次抑制、变体计算 |
| NPC 框架 | TC-INT-21→23 | NPCNode 导出、状态机、人格层 |
| 玩家控制器 | TC-INT-24→27 | 节点树构建、摄像机、对话刹车 |
| 场景过渡 | TC-INT-28→29 | 淡入淡出幕布创建、过渡门控 |
| 流程遍历 | TC-INT-30→35 | 走查循环、状态层级、空节点兜底 |
| 结局判定 | TC-INT-36→38 | 三种结局路径全覆盖 |

### 输入验证测试 (Issue #153)

输入验证和错误处理是一个**跨模块**测试主题，分布在三个单元测试文件中：

| 测试文件 | 测试组 | 用例数 | 覆盖内容 |
|----------|--------|--------|----------|
| `test_input_map_validation.gd` | TC-IM-E (Edge) + TC-IM-F (Failure) | 5 | 缺失动作容错、`Input.get_vector()` 安全、已知动作存在性 |
| `test_player_controller.gd` | TC-EX (Export Bounds) | 2 | `@export` 默认值、`clamp()` 边缘行为 |
| `test_npc_node.gd` | TC-IV (Input Validation) | 2 | 空 `dialogue_file`/`dialogue_id` 保护、多态值接受 |
| `test_game_manager_player.gd` | TC-GM-AL (Autoload) | 2 | Autoload 不存在时容错、InputMap 验证不崩溃 |

**验证层测试策略：**

| 层 | 测试方法 | 验证方式 |
|----|----------|----------|
| @export_range | 在 `--script` 中设越界值，验证 `clamp()` 生效 | 值在预期范围内 |
| 启动检查 | 通过 `new()` 实例化后调用带 `_` 前缀的方法 (白盒) | 方法不崩溃 |
| 方法边界保护 | 传空字符串/空字典调用 API 方法 | `push_warning()` 预期的消息，功能不继续 |
| 输入映射缺失 | 删除动作后调用 `_verify_input_map()` | warning 输出，无崩溃 |

### 测试方法

- **无 Autoload 实例化**：脚本直接使用 `load("res://...").new()` 创建模块实例，不依赖 Autoload 注册
- **信号测试**：通过局部信号捕获助手验证信号发射和载荷
- **头模式兼容**：避免依赖 `get_tree()`、`get_node()` 等需要场景树的 API；对需要场景树的系统（PlayerController、SceneManager），仅测试不依赖场景树的逻辑子集（节点树构建、数值运算）
- **可选脚本**：对有解析错误的脚本（如 `underpass.gd`），使用 `has_method()` 和空值检查保证测试不崩溃

### 执行命令

```bash
godot --headless --script tests/run_tests.gd
```

---

## 3. 已知限制

| 限制 | 原因 | 影响 |
|------|------|------|
| 不支持 3D 渲染测试 | Godot 头模式无渲染管线 | 视觉系统、粒子、着色器需要非头模式测试策略 |
| 不支持 GUI 交互测试 | 头模式下 Control 节点无输入处理 | UI 相关的集成需要手动模拟或后续改用 GUT |
| 无覆盖率报告 | Godot 4.7 头模式不暴露覆盖率数据 | 暂无法量化测试覆盖率；建议后续集成 GUT 插件或第三方工具 |
| 部分脚本在头模式有 `get_tree()` 错误 | 旧脚本（`game_state.gd`）假设有活动场景树 | 这些错误被 `assert` 捕获且不影响通过/失败计数，可以安全忽略 |
