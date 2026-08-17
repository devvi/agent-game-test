# DESIGN: [Follow-up] pipeline-tests CI 假红 — 防硬编码绝对路径守护断言

> **Parent Issue:** #521
> **Agent:** game-plan-agent
> **Date:** 2026-08-17
> **Approach:** B — AC3 防护断言（采纳 PRD §4 推荐方案 B；核心修复 commit `3c38f7b` 已合 main 且 CI 双绿，本设计**不**重复修 event-processor 路径逻辑）
> **Reference PRD:** docs/PRD/521-pipeline-tests-ci-portable.md（research PR #522，已合并）
> **所有权:** `content_ownership: mechanical`（CI 测试基建防护 = 纯机械，无品味决策）
> **深度:** light（depth/light 标签）—— 单文件内追加一个守护测试类，无新文件、无迁移、无弃用 → **不产 TASKS 文档**（低于阈值）

---

## 1. 架构概述

### 1.1 设计核心

**在 `tests/pipeline/test_event_processor.py` 内追加守护测试类 `TestNoHardcodedPaths`（PRD §3.2：不新建文件）：扫描 pipeline-tests 执行面（tests/pipeline/*.py 全部 + 被测 6 个 scripts），剔除注释行与 docstring 块后，断言不包含环境特定绝对路径模式（`/Users/`、`/home/`），白名单放行 repo 网络标识（`github.com/devvi`、`devvi/agent-game-test`）与 `~/.hermes` 写法。守护类由 unittest discover 自动拾取，CI（ubuntu）与本地（macOS）跑同一断言，语义天然一致。**

```text
tests/pipeline/*.py ────────┐
                            ├─► TestNoHardcodedPaths.scan()
scripts/event-processor.py ─┘        │  剔除 # 注释 + """docstring""" 块
scripts/event_processor_lib.py       │
scripts/create-issues.py             ├─ 正则 /(?:Users|home)/ 匹配
scripts/e2e/analyze_bmp.py           │        │
scripts/e2e/resolve_plan.py          │        ├─ 命中 → 白名单子串? ── 是 → 放行
scripts/workflow-watchdog.py         ▼        └─ 否 → assertFail(file:line)
                       任一文件缺失 → 显式 raise（不静默通过）
```

设计哲学：

1. **防护的是「复发」而非「现状」** — 假红根因（3c38f7b）已修复且两次 CI run 全绿实证；本守护的价值是让「本地绿、CI 红」的同类假红无法再次静默进入 main（PRD §2.2-2）。
2. **扫描式而非执行式**（PRD §4 方案 B Cons 已声明）— 静态扫描无法捕获运行时动态拼接的绝对路径，接受该残余风险并在 docstring 注明；作为交换，扫描对 CI/本地双环境天然一致、零外部依赖、纯 stdlib（PRD §2.3 约束）。
3. **范围 = 执行面，不越界** — 扫描清单只含 pipeline-tests 实际加载的 scripts（§1.3-1）；`scripts/hermes-verify-*.py` 的硬编码残留（PRD §3.3）不在执行面，属方案 C 范围，本 issue 不碰（保持聚焦）。
4. **白名单是兜底而非主过滤** — 正则本身要求 `/Users/`、`/home/` 前缀，repo 名（`devvi/agent-game-test`）天然不命中；白名单是防御纵深，防 URL/描述性文本误伤。
5. **清单自维护** — `_SCRIPTS_UNDER_TEST` 静态清单 + 同步守护测试 TC9：未来新增被测 scripts 时若未同步清单，测试立即红并提示补录（§8 TC9）。

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实 main 源码）

| PRD 断言 | 实际代码（main @ 5a4e5eb） | 设计裁决 |
|---------|--------------------------|---------|
| 核心修复 3c38f7b 已合 main：`scripts/event-processor.py` E2E_RUNNER fallback 用 `_SCRIPT_DIR` 推导 | ✅ L1875 `_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))`；L1881-1889 E2E_RUNNER 存在性检查 + 上一级 fallback；L2109 `_repo = os.environ.get("E2E_REPO_ROOT_FALLBACK") or os.path.dirname(_SCRIPT_DIR)` | **不重复改动** event-processor.py；守护类仅扫描其源码文本 |
| 测试侧 cwd 断言改为动态推导 | ✅ test_event_processor.py L1404-1408：`_expected_cwd = os.path.dirname(os.path.dirname(os.path.abspath(ep.__file__ or "")))` | 现有断言保留，守护类不触碰 |
| tests/pipeline 内仅剩 L1405 一处注释含 `/Users/` | ✅ `grep -rn "/Users/" tests/pipeline/` 仅命中 L1405 `# 注释` | 守护类必须剔除 `#` 注释行（PRD §5.2-3），否则自伤 |
| 方案 B 建议扫描「tests/pipeline/*.py + scripts/ 被测试文件」 | ✅ 执行面核实：7 个测试文件经 `spec_from_file_location` 共加载 6 个 scripts（event-processor / event_processor_lib / create-issues / e2e/analyze_bmp / e2e/resolve_plan / workflow-watchdog）；test_e2e_runner、test_manifest 不加载 .py 脚本 | 扫描清单 = tests/pipeline/*.py（全部）+ 上述 6 个 scripts；不含未进执行面的 hermes-verify-*.py（方案 C 范围外） |
| 白名单 `github.com/devvi`、`~/.hermes` | ✅ 实际出现：`devvi/agent-game-test`（test_reconcile_check_runs.py:25、test_e2e_runner.py:118 fixture）、`https://github.com/devvi/agent-game-test/...`（test_event_processor.py:1243/1303/1352）、`~/.hermes`（docstring/注释） | 白名单按 PRD 落地；注释/docstring 剔除后 `~/.hermes` 出现面已极少，白名单仍保留作纵深 |
| 修复后 CI 双绿、本地 174 tests OK | ✅ run 32011300779（3c38f7b）/ 32011930155（7d3efe7）均 success | 守护类新增后预期 174+2 全绿（§8 TC10/TC11） |

### 1.3 设计裁决（PRD 缺口闭合 — plan agent 独立裁决）

| # | PRD 未决点 | 裁决 | 理由 |
|---|-----------|------|------|
| 1 | 方案 B「相关 scripts/*.py」范围模糊 | **静态包含清单**：6 个被测 scripts（§1.1），不含 hermes-verify-*.py | 与 PRD §3.3 一致：hermes-verify-* 不在执行面、留作后续 cleanup；排除式（扫全部再豁免）脆弱且隐含维护成本，包含式自文档化 |
| 2 | 注释行处理「实现细节留给 plan」（§5.2-3） | **剔除 `#` 注释行 + 跳过 `"""`/`'''` docstring 块**（行状态机 ~8 行） | L1405 注释即 `/Users/devvi/...`，不剔除则守护自伤；docstring 同步剔除防未来示例文本误报 |
| 3 | Windows `\Users\` 是否纳入（§5.2-6） | **暂不纳入**，docstring 注明未来扩展 | 当前 CI 仅 ubuntu + 本地 macOS，反斜杠路径无出现场景；纳入只会增加误报面 |
| 4 | 静态清单漂移风险 | **新增同步守护测试 TC9**：正则解析 tests/pipeline/*.py 的 `spec_from_file_location(` 模块名 → 断言均在 `_MODULE_TO_SCRIPT` 映射内 | 清单是扫描覆盖率的唯一保证；漂移 = 静默失守，与守护初衷相悖 |
| 5 | 守护类落点 | **追加进 test_event_processor.py**（PRD §3.2 明示不新建文件） | 遵守 PRD 文件面约束；discover 自动拾取，与现有 174 测试同文件同入口 |

## 2. 新组件 — 详细设计

### 2.1 `TestNoHardcodedPaths`（追加到 tests/pipeline/test_event_processor.py 末尾）

- **File:** `tests/pipeline/test_event_processor.py`（追加，不新建文件）
- **类声明:** `class TestNoHardcodedPaths(unittest.TestCase)` — unittest discover 自动拾取
- **常量:**
  - `_ENV_ABS_PATH_RE = re.compile(r"/(?:Users|home)/")` — 环境特定绝对路径模式（macOS `/Users/<user>/`、GHA ubuntu `/home/runner/`、Linux `/home/<user>/`）
  - `_WHITELIST = ("github.com/devvi", "devvi/agent-game-test", "~/.hermes")` — 放行子串（repo 网络标识 + expanduser 写法，PRD §5.1）
  - `_SCRIPTS_UNDER_TEST = ("scripts/event-processor.py", "scripts/event_processor_lib.py", "scripts/create-issues.py", "scripts/e2e/analyze_bmp.py", "scripts/e2e/resolve_plan.py", "scripts/workflow-watchdog.py")`
  - `_MODULE_TO_SCRIPT = {"event_processor": "scripts/event-processor.py", "event_processor_lib": "scripts/event_processor_lib.py", "create_issues": "scripts/create-issues.py", "analyze_bmp": "scripts/e2e/analyze_bmp.py", "resolve_plan": "scripts/e2e/resolve_plan.py", "workflow_watchdog": "scripts/workflow-watchdog.py"}` — 供 TC9 同步校验
- **关键方法:**
  - `_repo_root()` → str：`os.path.dirname(os.path.dirname(os.path.abspath(__file__)))`（与文件头部 `_REPO_ROOT` 同源推导；测试经文件加载，`__file__` 恒非空）
  - `_scanned_files()` → list[str]：`glob(tests/pipeline/*.py)`（排序稳定）+ `_SCRIPTS_UNDER_TEST` 相对 repo root 解析；**任一文件缺失 → 立即 raise FileNotFoundError（不静默跳过）**
  - `_sanitized_lines(path)` → Iterator[(int, str)]：逐行 `strip()`；剔除 `#` 开头注释行；维护 `in_docstring` 状态跳过 `"""`/`'''` 块（含同行开闭）
  - `_violations()` → list[str]：对每个扫描文件每行 sanitize 后，`_ENV_ABS_PATH_RE.search(line)` 且不含任一白名单子串 → 记录 `f"{relpath}:{lineno}: {line.strip()}"`
  - `test_no_hardcoded_env_absolute_paths()`：`self.assertEqual(self._violations(), [], "禁止环境特定绝对路径（/Users/、/home/）: {violations}")`
  - `test_scripts_under_test_covers_all_importlib_loads()`（TC9）：对每个 tests/pipeline/*.py 正则 `spec_from_file_location\(\s*["']([^"']+)` 提取模块名，断言 ∈ `_MODULE_TO_SCRIPT` 键集；否则 fail 提示「新增被测脚本需补录 _SCRIPTS_UNDER_TEST + _MODULE_TO_SCRIPT」

> **实现伪代码（implement agent 按此实现，~45 行；禁止改为执行式/引入 pytest）：**
>
> ```python
> class TestNoHardcodedPaths(unittest.TestCase):
>     _ENV_ABS_PATH_RE = re.compile(r"/(?:Users|home)/")
>     _WHITELIST = ("github.com/devvi", "devvi/agent-game-test", "~/.hermes")
>     _SCRIPTS_UNDER_TEST = (
>         "scripts/event-processor.py",
>         "scripts/event_processor_lib.py",
>         "scripts/create-issues.py",
>         "scripts/e2e/analyze_bmp.py",
>         "scripts/e2e/resolve_plan.py",
>         "scripts/workflow-watchdog.py",
>     )
>     _MODULE_TO_SCRIPT = {
>         "event_processor": "scripts/event-processor.py",
>         "event_processor_lib": "scripts/event_processor_lib.py",
>         "create_issues": "scripts/create-issues.py",
>         "analyze_bmp": "scripts/e2e/analyze_bmp.py",
>         "resolve_plan": "scripts/e2e/resolve_plan.py",
>         "workflow_watchdog": "scripts/workflow-watchdog.py",
>     }
>
>     def _repo_root(self):
>         return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
>
>     def _scanned_files(self):
>         root = self._repo_root()
>         files = sorted(glob.glob(os.path.join(root, "tests", "pipeline", "*.py")))
>         for rel in self._SCRIPTS_UNDER_TEST:
>             p = os.path.join(root, rel)
>             if not os.path.exists(p):
>                 raise FileNotFoundError(f"扫描目标缺失: {rel}")
>             files.append(p)
>         return files
>
>     def _sanitized_lines(self, path):
>         in_doc = False
>         with open(path, encoding="utf-8") as fh:
>             for lineno, raw in enumerate(fh, 1):
>                 line = raw.strip()
>                 if line.startswith(('"""', "'''")) or in_doc:
>                     in_doc = not (line.endswith(('"""', "'''")) and len(line) >= 3)
>                     continue
>                 if line.startswith("#"):
>                     continue
>                 yield lineno, line
>
>     def _violations(self):
>         out = []
>         root = self._repo_root()
>         for p in self._scanned_files():
>             rel = os.path.relpath(p, root)
>             for lineno, line in self._sanitized_lines(p):
>                 if self._ENV_ABS_PATH_RE.search(line) and \
>                    not any(w in line for w in self._WHITELIST):
>                     out.append(f"{rel}:{lineno}: {line}")
>         return out
>
>     def test_no_hardcoded_env_absolute_paths(self):
>         v = self._violations()
>         self.assertEqual(v, [], "禁止环境特定绝对路径（/Users/、/home/）:\n" + "\n".join(v))
>
>     def test_scripts_under_test_covers_all_importlib_loads(self):
>         root = self._repo_root()
>         for tf in sorted(glob.glob(os.path.join(root, "tests", "pipeline", "*.py"))):
>             src = open(tf, encoding="utf-8").read()
>             for m in re.findall(r'spec_from_file_location\(\s*["\']([^"\']+)', src):
>                 self.assertIn(m, self._MODULE_TO_SCRIPT,
>                     f"新增被测脚本 {m} 需补录 _SCRIPTS_UNDER_TEST + _MODULE_TO_SCRIPT")
> ```

## 3. 现有组件修改

| 文件 | 变更 | 原因 |
|------|------|------|
| `tests/pipeline/test_event_processor.py` | **追加** `TestNoHardcodedPaths` 类（~45 行，2 个测试方法）；现有 174 个测试**零改动** | 守护断言落点（PRD §3.2）；discover 自动拾取 |
| `scripts/event-processor.py` | **零改动**（3c38f7b 已修复） | PRD §8 明确「不要重复改动」；本 issue 剩余工作仅 AC3 |

**新增文件:** 无（PRD §3.2 明示）。
**删除/弃用文件:** 无。
**受影响测试文件:** 仅 test_event_processor.py（追加）；其余 8 个 tests/pipeline/*.py 与 mini-pong/ 全部不受影响。

## 4. 数据流

```
Flow 1 — 正常路径（CI ubuntu / 本地 macOS 同一断言）:
unittest discover → TestNoHardcodedPaths.test_no_hardcoded_env_absolute_paths()
  → _scanned_files(): tests/pipeline/*.py(7) + _SCRIPTS_UNDER_TEST(6) = 13 文件
  → _sanitized_lines(): 剔除 # 注释 + docstring 块
  → _ENV_ABS_PATH_RE.search(): 0 命中 → assertEqual([], []) → PASS ✅

Flow 2 — 违规路径（未来 agent 在 fixture 中再次写死 /Users/devvi/...）:
  → 命中行 f"tests/pipeline/test_x.py:NN: <line>" → assertEqual 失败
  → unittest 报告违规 file:line → CI 红 → 提交者立即定位环境路径问题
  → 修复方式: 改相对路径/tempfile/动态推导（同 3c38f7b 模式），而非删除断言

Flow 3 — 覆盖漂移（新增被测脚本未补录清单）:
  → TC9 解析新测试的 spec_from_file_location("new_mod", ...) → "new_mod" ∉ _MODULE_TO_SCRIPT
  → fail 提示「补录 _SCRIPTS_UNDER_TEST + _MODULE_TO_SCRIPT」→ 清单保持自维护
```

## 5. 边界情况与错误处理

| 边界情况 | 缓解 |
|----------|------|
| 扫描目标 scripts 被删除/改名 | `_scanned_files()` 显式 raise FileNotFoundError —— 宁可红，不静默失守 |
| 注释/文档中的路径示例（如 L1405 现状） | `#` 行 + docstring 块剔除；若未来需在 docstring 写路径示例，用 `~`/`<HOME>` 占位写法 |
| repo 名/URL 含 `devvi`（`github.com/devvi/...`、`devvi/agent-game-test`） | 正则要求 `/Users/`、`/home/` 前缀，天然不命中；白名单双重兜底 |
| `~/.hermes` 写法（非字面绝对路径） | 白名单放行；语义为 expanduser 写法，ubuntu/macOS 均合法 |
| 未来 Windows runner（`\Users\` 反斜杠） | 明确暂不纳入（PRD §5.2-6），docstring 注明；CI 现状仅 ubuntu，引入时再扩展模式 |
| 动态拼接的绝对路径（运行时 `os.path.join("/Users", user, ...)`） | 扫描式断言的已知局限（PRD §5.3-2），docstring 注明接受残余风险 |
| 误报（合法路径被当违规） | 白名单误报率应趋零；若误报调整模式/白名单，**不删除断言**（PRD §5.3-1） |
| 编码/换行差异 | `open(..., encoding="utf-8")` + `strip()` 归一化；repo 为 LF，CI checkout 不转换 |
| `ep.__file__` 为空极端场景 | 守护类不依赖 ep；自身 `__file__` 经文件加载恒非空；现有断言已兜底 `or ""` |

## 6. 集成点

> **Status 约定:** ⬜ = 待 implement agent 连接并验证；✅ = implement 已连接。

| 集成 | 我们的组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| CI job `pipeline-tests` | TestNoHardcodedPaths | `.github/workflows/pipeline-tests.yml` | `python3 -m unittest discover -s tests/pipeline` 自动拾取新类，**无需改 workflow** | ⬜ 待 implement 验证 |
| 本地验证入口 | TestNoHardcodedPaths | `tests/pipeline/` 本地 discover | 与现有 174 测试同一入口同一命令 | ⬜ 待 implement 验证 |
| 现有修复 3c38f7b | 守护类（只读） | `scripts/event-processor.py` / 现有 cwd 断言 | 守护类仅扫描源码文本，不改实现 | ⬜ 待 implement 验证 |

## 7. 实施阶段

| 阶段 | 优先级 | 内容 | 估算 |
|:---:|:---:|------|:---:|
| Phase 1（唯一） | P0 | test_event_processor.py 追加 TestNoHardcodedPaths（§2.1 伪代码）→ 本地 `python3 -m unittest discover -s tests/pipeline` 全绿（174+2）→ push 触发 ubuntu CI 全绿 | 0.5 天 |

## 8. 测试用例描述（不写可运行代码）

### Scenario A: 守护类自身行为

- **TC1 现状零违规** — 前置：当前 main（3c38f7b 已合）；对 13 个扫描文件执行扫描；预期：`_violations()` 为空（已核实 6 个 scripts 无 `/Users/`、`/home/` 命中；tests/pipeline 仅 L1405 注释——被剔除）。
- **TC2 捕获代码行硬编码** — 前置：临时 fixture 文件（tempfile 目录内复制一个扫描文件并在**代码行**注入 `x = "/Users/devvi/workspace/agent-game-test/foo"`），monkeypatch 扫描清单指向该文件；预期：assertEqual 失败，报错含 `文件:行号` 与违规行内容。
- **TC3 注释行豁免** — 前置：注入文件仅含 `# 见 /Users/devvi/... 说明`；预期：不命中（`#` 剔除生效），守护通过。
- **TC4 docstring 块豁免** — 前置：注入文件的 `"""..."""` 块内写 `/home/runner/...` 示例文本；预期：不命中（docstring 状态机生效）。
- **TC5 白名单 URL 放行** — 前置：代码行含 `https://github.com/devvi/agent-game-test/issues/1`；预期：不命中。
- **TC6 白名单 repo 名放行** — 前置：代码行含 `"devvi/agent-game-test"`（无 `/Users/` 前缀）；预期：不命中（正则前缀 + 白名单双重保证）。
- **TC7 白名单 `~/.hermes` 放行** — 前置：代码行含 `os.path.expanduser("~/.hermes/e2e-state")`；预期：不命中。
- **TC8 扫描目标缺失显式报错** — 前置：删除/改名 `_SCRIPTS_UNDER_TEST` 中一个文件（或 monkeypatch 指向不存在路径）；预期：FileNotFoundError 抛出（非静默通过），错误信息含缺失文件相对路径。
- **TC9 清单同步（覆盖漂移防护）** — 前置：新增测试文件 `tests/pipeline/test_new_mod.py` 含 `spec_from_file_location("new_mod", ...)` 且未补录映射；预期：同步测试失败，提示补录 `_SCRIPTS_UNDER_TEST`/`_MODULE_TO_SCRIPT`；补录后通过。
- **TC10 现有测试零回归** — 前置：改动前后各跑一次 `python3 -m unittest discover -s tests/pipeline`；预期：改动前 174 OK，改动后 176 OK（174 + TC1 + TC9；TC2-TC8 为负面/辅助用例，计数以 implement 实际组织为准），无既有用例失败。

### Scenario B: 端到端验证

- **TC11 ubuntu CI 全绿** — 前置：push 分支触发 pipeline-tests workflow（ubuntu-latest，`discover -s tests/pipeline`）；预期：job success，全部 pipeline 测试（≥176）通过，无环境路径类失败（对应 issue AC2/验收①）。
- **TC12 本地 macOS 全绿** — 前置：本地执行同一 discover 命令；预期：全绿，与 CI 结果一致（同一断言双环境语义一致，对应 issue 验收②，无回归）。

---

### 附：与 issue #521 验收对照

| Issue 验收 | 满足方式 |
|-----------|---------|
| AC1 无硬编码 macOS 路径 fixture | 已由 3c38f7b 满足（本设计不重复修） |
| AC2 ubuntu CI 上 6 个失败消失 | 已实证（run 32011300779 / 32011930155）；TC11 持续守护 |
| AC3（可选）路径差异防护断言 | **本设计主体**（TestNoHardcodedPaths，TC1-TC12） |
