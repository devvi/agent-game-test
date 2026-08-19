# Startup Guide — 从零开始用 workflow 做游戏

> Godot 4.7 + Agent Workflow 上手指南。仓库: https://github.com/devvi/agent-game-test
> 适用：**已有游戏继续开发** 或 **新建游戏**（一次只做一个）。

---

## 0. 环境清单（首次）

```bash
# 前置依赖
godot --version                          # Godot 4.7.1
gh auth status                           # GitHub CLI 已登录
python3 --version                        # ≥3.10（无 yaml 依赖, manifest 用正则解析）
# workflow 基建（cron + gateway 已部署, 无需手动起）
```

## 1. 当前游戏快速上手（mini-pong）

```bash
# 打开游戏编辑（生成 .godot/ 缓存）
godot --path mini-pong/

# 跑全部测试（L1 逻辑层）
godot --path mini-pong/ --headless --script tests/run_tests.gd

# 手动跑 E2E（review agent 的本地验证流程）
scripts/run-e2e-review.sh <PR_NUM>       # worktree + L0-L3 + 截图 + 证据 comment
```

## 2. 提 Issue 跑 workflow

用 `feature-request.yml` 模板（或直接 `gh issue create` + `workflow/backlog` label）创建 Issue → workflow 自动开始：

```
research agent → PRD → 自动合并 → plan agent → DESIGN → 自动合并
→ implement agent → 代码 + 测试 → CI → review agent（本地 E2E + 截图 + 结论）
→ 脚本层自动 merge → post-merge agent（GDD/PROJECT.md → docs/ PR → 自动合并）→ issue 关闭
```

控制命令：

| 命令 | 效果 |
|------|------|
| `/workflow status` | 状态 + webhook 连通性 |
| `/workflow pause` / `resume` | 暂停（事件累积）/ 恢复 |
| `/workflow hours always` | 全天无限制 |

**版本推进（2026-08-19 起）**：workflow 一次只做一个版本。`~/.hermes/workflow-config.json` 的
`version_target` 字段指定当前版本（`mvp`/`v1`/`v2`）——picker 只拣该版本的 Issue，
该版本全部完成后 **workflow 自动停止**（Feishu 收到"🎉 版本目标完成"通知），
你切换版本（改 `version_target`）才继续下一版本；切换受版本依赖链约束
（v1 需 mvp 全完成，v2 需 v1 全完成）。改完配置下个 tick 自动生效，不用重启。

## 3. 新建游戏（切换 active game）

**架构**：每个游戏 = 一个自包含 Godot 子项目（自己的 `project.godot` + `gdscripts/` + `tests/` + `e2e_shots.json`）。workflow 一次只做一个，`game-env/manifest.yaml` 的 `game.active` 是唯一切换开关。

### Step A: 建目录骨架

```bash
# 以 shandong-wolf 为例（《山东抗日之狼》）— 复制 mini-pong 的成熟结构
mkdir -p shandong-wolf/gdscripts shandong-wolf/tests shandong-wolf/scenes shandong-wolf/assets
# 最小 project.godot（显式 viewport 尺寸 + resizable=false）
cat > shandong-wolf/project.godot << 'EOF'
; Engine configuration file.
[application]
config/name="山东抗日之狼"
run/main_scene=""
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/resizable=false
EOF
# E2E shot plan（游戏自持, runner 自动读 <game>/e2e_shots.json）
echo '{"shots": []}' > shandong-wolf/e2e_shots.json
```

### Step B: manifest 注册 + 切换

```yaml
# game-env/manifest.yaml
game:
  active: shandong-wolf          # ← 从 mini-pong 切过来
  subprojects:
    mini-pong:
      path: mini-pong/
      test_entry: tests/run_tests.gd
      smoke_entry: tests/smoke_test.gd
      compile_check: tests/check_compile.gd
      e2e_plan: mini-pong/e2e_shots.json
    shandong-wolf:               # ← 新增注册
      path: shandong-wolf/
      test_entry: tests/run_tests.gd
      smoke_entry: tests/smoke_test.gd
      compile_check: tests/check_compile.gd
      e2e_plan: shandong-wolf/e2e_shots.json
```

```bash
git add game-env/manifest.yaml shandong-wolf/
git commit -m "chore: switch active game → shandong-wolf"
git push
# 下个 tick 起：SPAWN 带 game=shandong-wolf，CI/E2E/worktree 全部跑 shandong-wolf/
```

### Step C: 验证切换生效

```bash
# 确认 event-processor 读到新游戏
python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('ep', 'scripts/event-processor.py')
ep = importlib.util.module_from_spec(spec); sys.argv=['x']; spec.loader.exec_module(ep)
print('ACTIVE_GAME =', ep.ACTIVE_GAME)   # 应输出 snow-blade
"
# 确认 E2E runner 推导
bash scripts/run-e2e-review.sh --help 2>&1 | head -3   # subproject 相关
# 跑 pipeline 测试（SPAWN 断言会跟随 active 变化）
python3 -m unittest discover tests/pipeline/ 2>&1 | tail -1
```

### Step D: 切回旧游戏

```bash
sed -i '' 's/active: snow-blade/active: mini-pong/' game-env/manifest.yaml
git commit -m "chore: switch active game → mini-pong"
# 全链路自动回到 mini-pong
```

## 4. 游戏切换机制速查

| 消费方 | 读取方式 | 改动需求 |
|--------|---------|---------|
| event-processor | `ACTIVE_GAME`（SPAWN 带 `game=`） | 无（已参数化） |
| E2E runner | `default_subproject()` 读 `game.active` | 无 |
| worktree-commit | 编译检查路径从 manifest 读 | 无 |
| CI (opencode-review.yml) | `steps.active-game` → GAME_DIR | 无 |
| Skills (research/review/implement) | ✅ 已参数化（2026-08-19：加"先读 manifest game.active"指令） | 已处理 |

**已知边界**：
- 分支命名不加游戏前缀（`impl/xxx`），issue 号全局唯一，多游戏 issue 不会串
- 一次只做一个游戏（并发两个游戏 = 未支持，需要分支隔离改造）
- GDD 分目录（`docs/GAME_DESIGN/<game>/`）✅ 已落地（2026-08-19），mini-pong 遗留根目录

## 5. 测试与 CI

| 层 | 命令 | 位置 |
|----|------|------|
| Pipeline（Python） | `python3 -m unittest discover tests/pipeline/` | 系统 python3（无 yaml 依赖） |
| L0 编译 | CI `compile` 步骤 | `--path <game>/ --script tests/check_compile.gd` |
| L1 逻辑 | `godot --path <game>/ --headless --script tests/run_tests.gd` | 本地 + CI |
| L2 运行时 | E2E runner `L2-runtime` | playthrough_test.tscn |
| L3 视觉 | E2E runner（默认 skip, deepseek 无多模态） | e2e_shots.json |

## 6. 故障速查

| 症状 | 原因 | 处置 |
|------|------|------|
| SPAWN 不带 `game=` | `_load_manifest` 正则 fallback 失败 | 检查 manifest YAML 缩进（`game:` 顶格, `active:` 两空格） |
| E2E 跑错游戏目录 | manifest `game.active` 与期望不符 | `grep active: game-env/manifest.yaml` |
| CI 的 compile SKIP | 游戏目录缺 `tests/check_compile.gd` | 建目录或提供 check_compile.gd |
| workflow 不推进 | `/workflow status` 看 paused/槽位 | 恢复后等 1-2 tick |
| 忘记切换切回 | 两个游戏目录都在仓库 | `game.active` 决定一切, 切回即恢复 |

---

## 参考

- `framework/ARCHITECTURE.md` — 系统架构（单一事实源）
- `AGENTS.md` — 项目约定 + workflow 总览
- `docs/WORKFLOW_ARCHITECTURE.md` — 运行时架构细节
- `scripts/` — 确定性脚本（event-processor / stage-gate / run-e2e-review / worktree-commit）
