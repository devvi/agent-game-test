# PRD: [Follow-up] pipeline-tests CI 假红 — test fixture 硬编码 macOS 路径（已修复，剩防护断言）

> **Issue:** #521
> **标签:** bug, depth/light, priority/medium, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-17
> **深度:** depth/light（Section 1–5 + 8 必填；Section 6/7 可选）
> **所有权:** `content_ownership: mechanical`（CI 测试基建修复，纯机械，无品味决策）
> **来源:** review #520 实证发现的 follow-up issue（2026-08-17 08:44Z 自动创建）
> **核心结论（bug pre-investigation，Patch 8/10）:** **本 issue 描述的假红在 issue 创建前 7 分钟已被 commit `3c38f7b` 修复**（08:38Z push main），其后两次 pipeline-tests CI 全绿。剩余工作仅为 issue 任务项 3 的可选防护断言。

---

## 1. 问题定义

### 1.1 当前状态

**Issue #521 声明:** CI job `pipeline-tests` 在 main 上连续 5+ 次 push 全红，6 个失败全部在 `tests/pipeline/test_event_processor.py`，根因是 fixture 硬编码本机 macOS 路径 `/Users/devvi/workspace/agent-game-test`（如 test_stalled_scan_gated 的 mock E2E launch），ubuntu runner 上该路径不存在 → `[Errno 2] No such file or directory`。

#### 预调查结果（bug pre-investigation workflow — 逐条对照当前 main 源码 + CI 实证）

| # | Issue 声明 | 状态 | 证据 |
|---|-----------|------|------|
| 1 | test_event_processor.py fixture 硬编码 macOS 路径 → ubuntu runner 必挂 | ✅ **已修复** | commit `3c38f7b`（2026-08-17 16:38:03 +0800，直接 push main）：`scripts/event-processor.py` 的 `E2E_RUNNER` fallback（L1877-1886）与 `e2e_orchestrator` 的 repo root（L2104）从硬编码 `/Users/devvi/workspace/agent-game-test` 改为 `_SCRIPT_DIR` 上一级动态推导 + `E2E_REPO_ROOT_FALLBACK` 环境变量覆盖；`tests/pipeline/test_event_processor.py` L1404 的 cwd 断言改为由 `ep.__file__` 动态推导 |
| 2 | main 上连续 5+ 次 push 全红 | ✅ **已修复（历史事实）** | 08:20Z 之前 5 次 run（01:03Z–08:20Z）确实 failure；08:38:08Z 起（3c38f7b）与 08:46:07Z（7d3efe7 = PR #520 merge）两次 run 均为 **success** |
| 3 | ubuntu CI 上 6 个失败消失 | ✅ **已验证** | `gh run list --workflow pipeline-tests.yml`：32011300779（3c38f7b）= success；32011930155（7d3efe7）= success |
| 4 | 本地 macOS 186 个 pipeline 测试通过 | ⚠️ **数量存疑（结论正确）** | 本地实测 `python3 -m unittest discover -s tests/pipeline` = **174 tests OK**（与 3c38f7b commit message "本地 174 tests OK" 一致）；issue 所述 186 可能是含 #520 新增 12 个的估算，但 #520 diff 实际未触及 tests/pipeline/（只改 mini-pong e2e 与 scripts/e2e/analyze_bmp.py） |
| 5 | （任务项 3）为本地/CI 路径差异加防护断言 | ❌ **未实施（剩余工作）** | 当前 tests/pipeline 内无"禁止硬编码绝对路径"的回归防护；`grep -rn "/Users/" tests/pipeline/` 仅剩 L1405 一处注释 |

**Stale claims:** issue 创建于 2026-08-17 08:44:50Z，而修复 commit `3c38f7b` 于 **08:38:03Z** 已 push、08:38:08Z CI 已转绿 —— 即 issue 创建时 bug 已不存在。issue 标题 "ubuntu runner 必挂" 描述的已是修复前状态（follow-up issue 自动创建机制基于 08:20Z 前的红 CI 快照，存在 ~25 分钟信息滞后）。

### 1.2 预期行为（验收条件，源自 Issue #521）

1. [x] **AC1** 找出 test_event_processor.py 中所有硬编码 `/Users/devvi/workspace/agent-game-test` 的 fixture，改为相对路径/临时目录/环境无关写法 —— **已由 3c38f7b 完成**（实现侧 `_SCRIPT_DIR` 推导 + 测试侧 `ep.__file__` 推导）
2. [x] **AC2** ubuntu CI 上复跑确认 6 个失败消失 —— **已实证**：3c38f7b / 7d3efe7 两次 run 全绿
3. [ ] **AC3**（可选）为本地/CI 路径差异加防护断言 —— **未实施，本 PRD 推荐方案见 §4**

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | pipeline 脚本改动 push main / 开 PR | 每次 scripts/ 改动 | pipeline-tests 在 ubuntu runner 上全绿，不允许出现环境路径类假红 |
| B | 新 fixture 引入本机绝对路径 | 偶发（多 agent 本地开发） | 防护断言应能立即捕获，避免再次出现"本地绿、CI 红"的假红循环 |
| C | 本地 macOS 开发 | 每次本地验证 | 本地 174 tests 保持全绿，无回归 |

### 1.4 技术约束（继承自 Issue #521）

| 约束 | 细节 |
|------|------|
| 测试命令 | `python3 -m unittest discover -s tests/pipeline -v`（pipeline-tests.yml L21-25，无 pytest） |
| CI runner | ubuntu-latest，checkout `fetch-depth: 1`，Python 3.11 |
| 失败容忍度 | **零容忍**：pipeline-tests 是脚本改动的唯一机械门禁，假红会阻塞所有 pipeline 脚本 PR |
| 范围 | 只动 `tests/pipeline/` 与 `scripts/`；不涉及游戏代码（mini-pong/） |

---

## 2. 设计意图

### 2.1 为什么当前状态如此

| # | 现状 | 成因 | 历史 |
|---|------|------|------|
| 1 | 实现曾硬编码 macOS 路径 | `e2e_orchestrator` 2026-08-14 引入（plan ② E2E 前置），开发机即 macOS，写死本机路径最省事；E2E_RUNNER fallback 同样写死（2026-08-14 同步副本 Errno 2 的应急补丁） | 引入 commit 见 `git log --oneline -- scripts/event-processor.py`（2026-08-14 E2E 系列） |
| 2 | issue 创建时 bug 已修复 | 3c38f7b 是开发者（devvi）发现 CI 连续 5 红后直接 push main 的 hotfix（08:38Z）；follow-up issue #521 由 review 流程基于更早的红 CI 快照自动创建（08:44Z），两者相隔 7 分钟 | 08:38Z 修复 → 08:44Z issue 创建 → 08:46Z #520 merge |
| 3 | 无防护断言 | 3c38f7b 只修了已知两处硬编码，未加"禁止绝对路径"的回归防护；issue 任务项 3 是"可选" | — |

### 2.2 为什么现在做

1. **假红成本高**：pipeline-tests 是 scripts/ 改动的唯一机械门禁（零本地测试强化，#517 引入），假红直接阻塞 pipeline 脚本类 PR 的合并。
2. **复发风险真实存在**：本仓库多 agent 并发开发，本地 macOS + CI ubuntu 双环境，任何 agent 新写 fixture 都可能再次引入本机绝对路径；防护断言是防止同类假红复发的低成本保险。
3. **修复已验证**：核心修复已落地且 CI 双绿，本 PRD 的剩余价值在于（a）记录 pre-investigation 结论避免 plan/implement 阶段重复修已修复代码，（b）给出 AC3 防护断言的明确方案。

### 2.3 既有约束

| 约束 | 细节 |
|------|------|
| 测试必须 hermetic | 无网络、无 gh CLI、无 ~/.hermes 依赖（test_event_processor.py 头注释约束） |
| 纯 stdlib | unittest + tempfile + mock，不引入 pytest |
| CI 与本地双绿 | ubuntu runner 与 macOS 本地都必须全绿 |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `tests/pipeline/test_event_processor.py` | E2E orchestrator 测试（TestE2EOrchestrator） | 已改（3c38f7b：cwd 断言动态推导）；若实施 AC3 防护断言，可能新增一个 Guard 测试类 |
| `scripts/event-processor.py` | E2E_RUNNER fallback + e2e_orchestrator repo root | 已改（3c38f7b：_SCRIPT_DIR 推导 + E2E_REPO_ROOT_FALLBACK 覆盖） |

### 3.2 新增文件

无（若实施 AC3，防护断言落在 `tests/pipeline/test_event_processor.py` 内，不新建文件）。

### 3.3 间接影响

| 模块 | 影响 |
|------|------|
| `scripts/hermes-verify-dialogue-schema.py` L7 | 仍有硬编码 `DIALOGUES_DIR = "/Users/devvi/..."`，但**不在 pipeline-tests 执行面**（该 job 只跑 `discover -s tests/pipeline`），不影响本 issue 验收；可留作后续 cleanup 项 |
| 其他 tests/pipeline/*.py | `test_reconcile_check_runs.py:25`、`test_e2e_runner.py` 等使用 `devvi/agent-game-test` 字符串均为 **repo 名（网络标识）而非文件路径**，ubuntu 上无碍，不需要改 |
| 后续 plan/implement | 若 AC3 被采纳，implement 阶段只需在 tests/pipeline 加一个守护测试类 + 跑本地 174+ 测试确认无回归 |

### 3.4 数据流影响

```
修复前（假红路径）:
ubuntu CI checkout (如 /home/runner/work/agent-game-test/...)
    │
    ▼
test_event_processor.py fixture 断言 cwd == "/Users/devvi/workspace/agent-game-test"
    │  (实现侧 Popen cwd 硬编码同一 macOS 路径)
    ▼
ubuntu 上路径不存在 → [Errno 2] No such file or directory → 6 tests FAIL

修复后（3c38f7b）:
_SCRIPT_DIR = dirname(abspath(__file__))  # CI checkout 下即 repo/scripts/
    │
    ├── E2E_RUNNER = _SCRIPT_DIR/run-e2e-review.sh（存在即用）
    │       └── fallback: dirname(_SCRIPT_DIR)/scripts/run-e2e-review.sh（repo 根推导）
    │
    └── e2e_orchestrator: _repo = E2E_REPO_ROOT_FALLBACK or dirname(_SCRIPT_DIR)
            └── 测试断言 cwd == dirname(dirname(abspath(ep.__file__)))  ← 与实现同源推导
```

---

## 4. 方案对比

### 方案 A：仅记录已修复状态，AC3 防护断言不做（最小改动，零代码）

| 维度 | 内容 |
|------|------|
| 描述 | 本 PRD 只输出 pre-investigation 结论（已修复 + CI 双绿证据），plan 阶段不排任何实现任务，issue 直接收尾 |
| Pros | 零回归风险；issue 描述的核心 bug 确实已死 |
| Cons | 复发防护缺失——任何 agent 再写本机绝对路径 fixture，假红会原样复发，且无自动捕获 |
| Risk | 低（当前），中（复发场景） |
| Effort | 0 天 |

### 方案 B：实施 AC3 防护断言（推荐）

| 维度 | 内容 |
|------|------|
| 描述 | 在 `tests/pipeline/` 新增一个守护测试类（如 `TestNoHardcodedPaths`），扫描本测试目录全部测试源码 + `scripts/` 被测试文件，断言不包含本机绝对路径模式（`/Users/<user>/`、`/home/runner/` 等环境特定路径）；路径白名单允许 `github.com/devvi`（repo 名，非文件路径） |
| Pros | 单次实现永久防复发；CI ubuntu + 本地 macOS 双环境跑同一断言，语义天然一致；纯 stdlib，~30 行 |
| Cons | 需维护路径模式白名单（误报风险低但存在）；防护是"扫描式"而非"执行式"，无法捕获动态拼接的绝对路径 |
| Risk | 低 |
| Effort | 0.5-1 天 |

### 方案 C：防护断言 + 顺带清理 `scripts/hermes-verify-dialogue-schema.py` L7 硬编码

| 维度 | 内容 |
|------|------|
| 描述 | 在方案 B 基础上，把 dialogue-schema 脚本的 `DIALOGUES_DIR` 也改为相对 repo 根推导（虽然不在 pipeline-tests 执行面） |
| Pros | 消除仓库内最后一个本机绝对路径残留；未来该脚本若被纳入 CI 不会踩坑 |
| Cons | 超出本 issue 验收范围（issue 只要求 pipeline-tests 相关 fixture）；扩大改动面 |
| Risk | 低 |
| Effort | 1 天 |

### 推荐

**方案 B。** 理由：
1. issue 任务项 3 明确列出"（可选）为本地/CI 路径差异加防护断言"，方案 B 是该任务的直接落地，价值/成本比最高。
2. 方案 A 放弃防护，假红复发概率在多 agent 并发开发模式下不可忽视（本次 5 连红就是实证）。
3. 方案 C 的 dialogue-schema 清理与 pipeline-tests 无执行关系，应作为独立 cleanup issue 而非混入本 issue——保持本 issue 范围聚焦（pipeline-tests 假红）。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单）

- [x] **AC1（已满足）** 无硬编码 macOS 路径 fixture —— `grep -rn "/Users/" tests/pipeline/` 仅剩注释；`scripts/event-processor.py` 用 `_SCRIPT_DIR` 推导
- [x] **AC2（已满足）** ubuntu CI 全绿 —— run 32011300779 / 32011930155 均 success；本地 174 tests OK
- [ ] **AC3（待 implement，方案 B）** 新增防护断言：
  - 扫描 `tests/pipeline/*.py` + 相关 `scripts/*.py`，无 `/Users/<user>/`、`/home/runner/` 等环境特定绝对路径
  - 白名单：`github.com/devvi/...`（repo 标识）、`~/.hermes/...`（expanduser 写法，非字面绝对路径）
  - 本地 174+ 测试全绿、ubuntu CI 全绿

### 5.2 边界情况

1. `ep.__file__` 为空（极端加载场景）——现有断言 `ep.__file__ or ""` 已兜底为 `""`，dirname 推导退化安全
2. 防护断言扫描到 `devvi/agent-game-test` 字样——必须白名单（repo 名是网络标识，ubuntu 上合法）
3. 防护断言扫描到注释里的路径——应默认放行注释？不：注释里的路径同样会误导后续维护者，建议扫描时排除 `#` 注释行但保留代码行（实现细节留给 plan）
4. CI checkout 深度 1——`_SCRIPT_DIR` 推导不依赖 git 历史，深度 1 无影响
5. `E2E_REPO_ROOT_FALLBACK` 环境变量注入——测试可通过该变量模拟跨平台场景，防护断言设计时应覆盖该注入路径
6. Windows runner（未来若引入）——`\Users\` 反斜杠路径模式是否纳入扫描，留给 plan 阶段决策（当前 CI 仅 ubuntu）

### 5.3 失败路径

1. **防护断言误报**（把合法 repo 名当路径）→ 白名单机制误报率应趋零；若误报，调整模式而非删除断言
2. **防护断言遗漏**（动态拼接路径）→ 扫描式断言的已知局限，接受残余风险，文档注明
3. **CI 再次假红**（其他环境特定假设）→ 本 PRD 的 pre-investigation 表是排查起点；任何新假红应优先怀疑 fixture 环境假设

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|------|
| commit `3c38f7b`（已合 main） | ✅ 已满足 | 无——修复已生效，本 issue 不依赖任何未合并代码 |
| PR #520（已合 main，7d3efe7） | ✅ 已满足 | 无——#520 的 e2e_shots 改动与 pipeline-tests 无冲突（两次 CI 已实证） |

**阻塞:** 无。本 issue 不阻塞其他工作（假红已消除）。

**依赖链:**
```
review #520 实证 ──► #521 (本 issue) ──► [可选] AC3 防护断言 ──► plan/implement
```

## 7. Spike / 实验

Skipped per depth/light label（Section 7 对 depth/light 可选；且修复已实证——两次 ubuntu CI 全绿 + 本地 174 tests OK 即为实验证据）。

---

## 8. 延续上下文（给 plan agent）

### 系统状态

- **核心修复已合 main**：commit `3c38f7b`（2026-08-17 08:38Z）同时改了 `scripts/event-processor.py`（E2E_RUNNER fallback L1877-1886、e2e_orchestrator repo root L2104：`_SCRIPT_DIR` 上一级推导 + `E2E_REPO_ROOT_FALLBACK` 覆盖）与 `tests/pipeline/test_event_processor.py`（L1404 cwd 断言动态推导）。
- **CI 已双绿**：pipeline-tests run 32011300779（3c38f7b）与 32011930155（7d3efe7，#520 merge）均 success；本地实测 174 tests OK。
- **issue #521 创建晚于修复 7 分钟**，其"5+ 次全红/ubuntu 必挂"描述是修复前快照，plan/implement 阶段**不要重复修 event-processor 路径逻辑**。

### 主要风险

1. **复发**：多 agent 并发开发下，新 fixture 可能再次硬编码本机绝对路径 → 建议 implement 采纳方案 B 防护断言（AC3）。
2. **范围蔓延**：`scripts/hermes-verify-dialogue-schema.py` L7 的硬编码 DIALOGUES_DIR 不在 pipeline-tests 执行面，不要混入本 issue（如需清理应开独立 issue）。

### 下一步（若 AC3 被采纳）

1. 在 `tests/pipeline/` 新增守护测试类（方案 B），扫描 tests/pipeline/*.py + 相关 scripts/*.py 中环境特定绝对路径模式（`/Users/<user>/`、`/home/runner/`），白名单 `github.com/devvi`、`~/.hermes`。
2. 本地跑 `python3 -m unittest discover -s tests/pipeline` 全绿（预期 174 + 新增 ≥1）。
3. push 触发 pipeline-tests CI（ubuntu）全绿。
4. 若 issue 无后续实现任务（方案 A 被选），则本 PRD merge 后 issue 由 workflow-chain 推进到 workflow/plan，plan agent 依据本 PRD 决定是否排 AC3。

### 关键文件清单

| 文件 | 角色 |
|------|------|
| `tests/pipeline/test_event_processor.py` | 已修复的测试；AC3 防护断言的落点 |
| `scripts/event-processor.py` | 已修复的实现（_SCRIPT_DIR 推导）；不要重复改动 |
| `.github/workflows/pipeline-tests.yml` | CI 定义（ubuntu-latest + discover -s tests/pipeline） |
