# PRD: [Bug] run-e2e-review.sh P6 上传函数定义顺序 + frozen 阈值过严 (class A 基建)

> **Issue:** #372
> **标签:** bug, workflow/available, priority/high, infrastructure
> **Agent:** game-research-agent
> **日期:** 2026-08-11
> **深度:** depth/standard（无 depth/ 标签，按 bug 修复标准深度：Sections 1–6 + 8 必填，Section 7 含 4 个实验）

---

## 1. 问题定义

### 当前状态

E2E harness（class A 基建，非游戏代码）存在 4 个问题，由 #371 review 实测发现（PR #371 的"已知问题"段，review agent 判定 class A、不阻塞 merge 但需正式修复）。修复后 E2E 截图应能真实嵌入 PR comment —— Feishu 群 MEDIA 发图不生效，**GitHub raw 链接是唯一证据通道**。

### 预调查结果（bug 前置调查工作流）

| 检查项 | 结果 |
|--------|------|
| 当前源码检查 | 4 个问题全部仍存在于 HEAD（`scripts/run-e2e-review.sh`） |
| 修复 commit 检索 | ❌ 无 — `git log --all \| grep 372` 无结果；`run-e2e-review.sh` 自 864d2df (#357) 创建后未再改动 |
| 既有 PRD/DESIGN 交叉引用 | PLAN-e2e-verification-v2.md（v2 方案）已证实 "GitHub REST API 无评论附件端点" |
| 过时声明 | 无 — Issue 的 4 条问题描述与当前代码完全一致 |

**结论：无已修复项、无过时声明，4 个问题均为真实待修复。**

### 问题 1：P6 上传函数定义顺序 + `$name_` 未绑定变量

证据（`scripts/run-e2e-review.sh`）：

- 第 273/276 行调用 `upload_via_github` / `upload_via_gist`
- 函数定义在第 344/360 行 —— **在 `exit "$OVERALL"`（第 339 行）之后**。bash 逐行执行，`exit` 先执行 → 函数从未被定义 → P6 调用时 "command not found"
- 第 283 行 `echo "_upload failed — see /tmp/e2e-$PR_NUM/shots/$name_"` —— `$name_` 是未绑定变量（循环变量是 `name`，第 270 行定义），`set -u` 下直接 abort（实测 `bash: name_: unbound variable`，exit 127）

实际运行证据：`/tmp/e2e-371/comment.md` 在 `**01_title.png**` 处截断 —— 正是 `$name_` 崩溃点。

### 问题 2：截图无法嵌入 comment

证据（`scripts/run-e2e-review.sh` 第 344–368 行）：

- `upload_via_github`：`Authorization: Bearer ***` 是**字面占位符**（非真实 token）+ `https://github.com/upload/policies/assets` 是 web 上传端点（需浏览器会话/CSRF），不是 REST API —— PLAN-e2e-verification-v2.md 已证实 "GitHub REST API 无评论附件端点"
- `upload_via_gist`：`gh gist create --public` 输出为 `https://gist.github.com/<user>/<id>`，sed 提取 id 后拼接 `https://gist.githubusercontent.com/raw/$id/$fname` —— **URL 格式错误**（正确格式：`https://gist.githubusercontent.com/<user>/<id>/raw/<file>`，缺用户名 + `/raw/` 段）→ 404
- 实际证据：PR #371 上所有截图显示 `_upload failed — see /tmp/e2e-371/shots/01_title.png_`

### 问题 3：frozen 启发式误报（Δluma 阈值过严）

证据（`scripts/e2e/analyze_bmp.py` + `/tmp/e2e-371/P5-assert.log`）：

- `_luma_delta` 计算**全帧平均** |Δluma|（每 3 像素采样）
- P5-assert.log：`02_midgame vs 01_title: Δluma=0.5 < 5.0 — frozen?`
- 但逐像素对比：**9301 px（1.009%）显著变化**，bbox x[16-1239] y[24-701]（HUD/球/挡板均出现），颜色数 14→18/19
- 根因：霓虹暗底风格（大面积 `#0a0a12` 近黑 + 少量发光元素）→ 平均亮度几乎不变 → 全帧平均 Δluma 指标对暗底游戏失效

### 问题 4：03_gameover 超时

证据（`/tmp/e2e-371/results.json`）：

```json
"missed": ["03_gameover"], "reason": "deadline", "elapsed_ms": 120000
```

- shot plan `max_wall_seconds: 120`，5 分制 AI vs AI（`ai_position_error=200`）120s 内未打完 → capture exit 1

### 预期行为（验收条件，源自 Issue）

1. `run-e2e-review.sh` 的 P6 上传函数在调用点之前定义，`$name_` 绑定
2. 截图能通过 GitHub 通道嵌入 PR comment（或 gist raw 链接）
3. frozen 阈值对霓虹暗底游戏不误报（两帧实际差异 > 阈值）
4. 03_gameover 在 deadline 内可捕获（或单独延长）
5. `--headless --quit` 无脚本错误

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | review agent 跑 E2E | 每个 impl PR | 截图真实嵌入 PR comment，作为唯一证据通道 |
| B | 霓虹暗底游戏截图断言 | 每次视觉验证 | frozen 检测不误报，两帧实际差异能通过 |
| C | 完整 loop 剧本验证 | 每次视觉验证 | 03_gameover（终局帧）在 deadline 内捕获 |

### 技术约束（继承自 Issue）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1；修复范围限 `scripts/`、`framework/templates/`、`scripts/e2e/`、shot plans —— **不改游戏代码**（class A 基建边界） |
| 证据通道 | GitHub raw 链接是唯一证据通道（Feishu MEDIA 不生效） |
| bash 语义 | macOS bash 3.2；`set -u` 下未绑定变量致命，函数必须先定义后调用 |
| 测试 | `tests/pipeline/test_e2e_runner.py` / `test_e2e_analyze.py` 须同步更新（P8 原则：pipeline bugs must be caught by tests） |

---

## 2. 设计意图

- E2E 系统是 review agent 的证据通道（PLAN-e2e-verification-v2.md v2 方案），P6 是截图证据上 PR comment 的唯一途径；P6 崩溃 = 证据通道完全失效
- frozen 启发式是"防伪 4 重断言"之一（P6 原则：证据可审计，防伪 4 重断言）；误报使 L3 视觉层对暗底游戏永远 fail，每个 PR 都被误标
- 03_gameover 超时使 loop 剧本的"终局"帧永远缺失，L3 无法闭环验证完整游戏流程
- 修复保持零游戏代码侵入（framework 管机器、游戏管剧本的 P4 原则），截图通道收敛到 gist 官方 REST 这一可靠路径

---

## 3. 影响分析

### 直接受影响的模块

| 文件 | 影响 |
|------|------|
| `scripts/run-e2e-review.sh` | P6 函数定义顺序、`$name_` 绑定、上传通道实现（gist raw URL + 删 web 端点） |
| `scripts/e2e/analyze_bmp.py` | frozen 检测指标（全帧平均 Δluma → 变化像素占比） |
| `framework/templates/e2e_capture.gd` | 如需 per-shot deadline 支持 |
| `mini-pong/e2e_shots.json` | 03_gameover 可能需要延长 deadline 或调整 autoplay tweaks |

### 需新建的文件

- 无（修复为主；测试用例在既有测试文件中新增）

### 间接受影响的模块

- `tests/pipeline/test_e2e_analyze.py`（frozen 指标用例）
- `tests/pipeline/test_e2e_runner.py`（P6 上传路径用例）
- `framework/templates/e2e_shots.json`（模板若加 per-shot deadline 字段则同步 schema）

### 需更新的文档

- `docs/PLAN-e2e-verification-v2.md`（如 frozen 指标语义变更，后续可同步；非阻塞）

---

## 4. 解决方案比较

### 4.1 P6 上传函数定义顺序 + `$name_` 绑定

| 方法 | 描述 | Pros | Cons | 风险 | 工作量 |
|------|------|------|------|------|--------|
| **A: 函数前置 + 修变量名** | 将 `upload_via_github`/`upload_via_gist` 移到 P6 调用点之前（P0/P1 区）；`$name_` → `$name` | 最小改动、直击根因、符合 bash 顺序语义 | 函数位置移动需确认无其他引用 | 低 | S |
| B: 内联上传逻辑 | 把上传逻辑直接写进 P6 循环 | 无函数顺序问题 | 代码重复、可读性差、P6 块膨胀 | 中 | M |
| C: 引入 lib 文件 | 抽到独立 `upload_helpers.sh` 并 source | 复用性好 | 新增文件、source 路径管理 | 低 | M |

**推荐 A**：函数前置 + `$name_` → `$name`，与 4.2 的上传通道修复合并实施。

### 4.2 截图嵌入 comment 通道

| 方法 | 描述 | Pros | Cons | 风险 | 工作量 |
|------|------|------|------|------|--------|
| **A: 修 gist raw URL** | `gh gist create` 后从输出解析 `<user>/<id>`，拼接 `https://gist.githubusercontent.com/<user>/<id>/raw/<file>` | gist 是官方 REST，稳定可靠 | 需解析 `gh gist create` 输出（URL 行） | 低 | S |
| B: 修 web 上传端点 | 修复 `upload/policies/assets` 调用 + 真实 token | 若可用则是 github.com 直链 | web 端点需浏览器会话/CSRF 非 REST；`Bearer ***` 是占位符，无真实 token 可填 | 高 | L |
| **C: 删 web 端点，只留 gist** | 移除 `upload_via_github`，仅用 gist raw | 简化代码、单一可靠通道 | 放弃 github.com 直链的可能性 | 低 | S |

**推荐 A+C 组合**：删除不可行的 web 端点，gist raw URL 修正为正确格式。`gh gist create --public` 输出末行即 gist URL，解析 `<user>/<id>` 后拼接 raw 地址。

### 4.3 frozen 检测指标（霓虹暗底适配）

| 方法 | 描述 | Pros | Cons | 风险 | 工作量 |
|------|------|------|------|------|--------|
| **A: 变化像素占比** | 统计 \|Δluma\|>阈值（如 10）的像素占比，超过 min 占比（如 0.3%）即判定有变化 | 对暗底游戏鲁棒；与 "9301px (1.009%)" 证据直接对应 | 需校准阈值参数 | 低 | S |
| B: 降低 Δluma 阈值 | 5.0 → 0.2 | 改动最小 | 暗底噪声可能误放行真 frozen；治标不治本 | 中 | S |
| C: 区域比较 | 只比较 HUD/球场等 ROI 区域 | 精确 | 需知道游戏布局，破坏框架通用性（P4 原则） | 中 | M |

**推荐 A**：将全帧平均 Δluma 改为"变化像素占比"（\|Δluma\|>10 的像素占比 ≥ 0.5% 判定为变化）。`--min-delta` 参数保留兼容，新增 `--min-change-ratio`。

### 4.4 03_gameover 超时

| 方法 | 描述 | Pros | Cons | 风险 | 工作量 |
|------|------|------|------|------|--------|
| **A: per-shot deadline** | `e2e_capture.gd` 支持 shot 级 `max_wall_seconds` 覆盖，03_gameover 单独延长（如 240s） | 精准，其他 shot 不受影响 | 需 capture.gd + shot plan schema 小改 | 低 | S |
| B: 全局延长 | `max_wall_seconds` 120 → 240/300 | 简单 | 所有运行都变慢，浪费 | 低 | S |
| C: autoplay tweaks 加速 | 提高 `ai_position_error` / 球速，让 5 分更快打完 | 不改 deadline | 改变截图内容节奏（更快），可能与真实手感不一致 | 中 | S |

**推荐 A**：`e2e_capture.gd` 的 deadline 计算支持 per-shot 覆盖（`shot.max_wall_seconds` 优先于全局），`mini-pong/e2e_shots.json` 为 03_gameover 单独延长。

### 推荐方案汇总

| 子系统 | 推荐 | 核心文件 |
|--------|------|---------|
| P6 函数顺序 + `$name_` | A: 函数前置 + 修变量名 | `scripts/run-e2e-review.sh` |
| 截图通道 | A+C: gist raw URL 修正，删 web 端点 | `scripts/run-e2e-review.sh` |
| frozen 指标 | A: 变化像素占比 | `scripts/e2e/analyze_bmp.py` |
| gameover 超时 | A: per-shot deadline | `framework/templates/e2e_capture.gd` + shot plans |

---

## 5. 边界条件与验收标准

### 验收标准（源自 Issue）

- [ ] **AC1** P6 上传函数在调用点之前定义，`$name_` 绑定
- [ ] **AC2** 截图能通过 GitHub 通道嵌入 PR comment（或 gist raw 链接）
- [ ] **AC3** frozen 阈值对霓虹暗底游戏不误报（两帧实际差异 > 阈值）
- [ ] **AC4** 03_gameover 在 deadline 内可捕获（或单独延长）
- [ ] **AC5** `--headless --quit` 无脚本错误
- [ ] **AC6** `tests/pipeline/` 全部通过（含新增用例）

### 边界情况

1. **无截图时**：P6 循环 `[ -f "$png" ] || continue` 已处理空目录
2. **gist 创建失败**：无网络/未认证 → 保留本地路径 fallback 文案
3. **真 frozen 帧**：两帧完全一致 → 变化像素占比 0% → 正确 fail
4. **不同尺寸截图**：`_luma_delta` 返回 inf（不同尺寸 = 不同帧）→ 保持
5. **暗底但有内容变化**：9301px 变化 → 占比 1.009% > 0.5% → pass

### 失败路径

1. gist API 输出格式变化 → 解析失败 → 保留本地路径 fallback
2. 阈值参数选择不当 → 用 `/tmp/e2e-371` 真实截图回归校准

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|------|------|
| #371（E2E 实测来源） | ✅ MERGED | 无 | 4 个问题的实测证据来源 |
| PLAN-e2e-verification-v2.md | ✅ 存在 | 无 | E2E 系统设计文档（v2） |
| gh CLI + GH_TOKEN | ✅ | 低 | gist 创建需要认证 |

**阻塞项：** 无

---

## 7. Spike / 实验

### E1: gist raw URL 格式验证
创建临时 gist，验证 `gh gist create --public` 输出格式与正确 raw URL 拼接；用 `/tmp/e2e-371/shots/01_title.png` 上传后验证 URL 可访问（HTTP 200）。

### E2: frozen 指标回归（真实截图）
用 `/tmp/e2e-371/shots/01_title.png` + `02_midgame.png`（已证实 9301px 变化）验证"变化像素占比"指标通过；用同一张图对比自身验证 fail。

### E3: 03_gameover deadline 实测
在 mini-pong 实测 AI vs AI（`ai_position_error=200`）打完 5 分所需时间，确定 per-shot deadline 合理值（预计 120–240s）。

### E4: bash 函数顺序验证
`bash -n` 语法检查 + `--dry-run` 确认函数定义在调用点之前、`$name_` 已绑定。

---

## 8. 延续上下文

### 系统状态

- E2E harness 4 个 class A 问题已确认存在于当前代码（`run-e2e-review.sh` 自 #357 后未改动）
- 修复不涉及游戏代码（`mini-pong/`），全部在 `scripts/` + `framework/templates/` + shot plans

### 给 plan agent 的关键信息

- 核心文件：`scripts/run-e2e-review.sh`（P6 函数 + 上传通道）、`scripts/e2e/analyze_bmp.py`（frozen 指标）、`framework/templates/e2e_capture.gd`（per-shot deadline）、`mini-pong/e2e_shots.json`（03_gameover 延长）
- 回归证据基线：`/tmp/e2e-371/` 下有真实截图（01_title.png / 02_midgame.png）、P5-assert.log、results.json、comment.md
- 验收以 Issue 的 5 条为准（AC1–AC5）

### 实施顺序

1. `run-e2e-review.sh`：函数前置 + `$name_` → `$name` + gist raw URL 修正 + 删 web 端点
2. `analyze_bmp.py`：frozen 指标改为变化像素占比
3. `e2e_capture.gd`：per-shot deadline 支持
4. shot plans：03_gameover 单独延长
5. 测试：`tests/pipeline/` 更新 + 新增用例

### 验证命令

```bash
bash -n scripts/run-e2e-review.sh
python3 scripts/e2e/analyze_bmp.py /tmp/e2e-371/shots/02_midgame.png --diff-with /tmp/e2e-371/shots/01_title.png
python3 -m pytest tests/pipeline/test_e2e_analyze.py tests/pipeline/test_e2e_runner.py -q
scripts/run-e2e-review.sh <PR_NUM> --dry-run
```

### 风险

- gist 上传依赖网络/认证（低）
- 变化像素占比阈值需用真实截图校准（中）

### 后续问题

- `docs/PLAN-e2e-verification-v2.md` 文档同步（可选）
- 未来暗底 subproject 复用 frozen 指标的经验沉淀
