# PRD: [Bug] 修复 run-e2e-review.sh P6 上传函数定义顺序 + frozen 阈值过严 (class A)

> **Issue:** #372
> **标签:** bug, workflow/available, priority/high, infrastructure
> **Agent:** game-research-agent
> **日期:** 2026-08-11
> **深度:** depth/standard（Issue 无 depth 标签，按 standard 处理：Section 1–6 + 8）
> **来源:** #371 review 的"已知问题"段（review agent 判定 class A 基建问题，非游戏代码缺陷，不阻塞 #371 merge 但需正式修复）
> **约束:** class A 基建 —— 只改 `scripts/`、`framework/templates/`、`mini-pong/e2e_shots.json` 等测试基建文件，**不改游戏代码**（`mini-pong/gdscripts/`、`scenes/`）

---

## 1. 问题定义

### 当前状态

`scripts/run-e2e-review.sh`（#357 引入，commit `864d2df`）是本地 E2E 主 runner，在 #371 review 时暴露 4 个 class A 基建问题，导致 P6 证据上传崩溃、L3 视觉层误报 fail、03_gameover 超时。问题均位于 E2E harness 本身，非游戏缺陷。

### 预调查结果（bug pre-investigation，Patch 8/10）

| # | Issue 声明 | 预调查结果 | 证据 |
|---|-----------|-----------|------|
| 1 | P6 上传函数定义在调用点之后，bash 找不到 | ✅ **确认仍坏** | `upload_via_github`/`upload_via_gist` 定义在第 344/360 行，位于 `exit "$OVERALL"`（第 339 行）**之后** —— P6 在 273/276 行调用时函数从未定义，bash 报 `command not found`，`url` 为空 |
| 1b | `$name_` 未绑定变量 | ✅ **确认仍坏** | 第 283 行 `echo "...shots/$name_"` —— `$name_` 是未绑定变量（应为 `$name`），`set -u` 下 bash 立即退出（实测 rc=127：`bash: name_: unbound variable`）→ P6 在构建 comment 时崩溃，`gh pr comment` 永不执行 |
| 2 | 截图无法嵌入 PR comment（GitHub 端点 + gist fallback 均失败） | ✅ **确认仍坏** | `upload_via_github` 第 349 行用字面量 `Authorization: Bearer ***`（占位符，非真实 token）→ 认证必失败；且 `https://github.com/upload/policies/assets` 是浏览器拖拽上传端点，非 REST comment-attachment API（脚本注释自述 2026-07-31 验证"无 REST 附件 API"）。gist fallback 拼的 URL `https://gist.githubusercontent.com/raw/$id/$fname` 格式错误 —— 真实 raw URL 形如 `https://gist.githubusercontent.com/<user>/<gist_id>/raw/<file>`，缺 username 段 → 404 |
| 3 | frozen 启发式误报：Δluma<5.0 阈值对霓虹暗底过严 | ✅ **确认仍坏** | `analyze_bmp.py::_luma_delta` 计算的是**全帧平均** luma 差（第 232 行 `--min-delta 5.0`）。霓虹暗底（大面积 `#0a0a12` 近黑）使均值几乎不变：#371 实测 Δluma=0.5 < 5.0，但逐像素对比 9301px（1.009%）显著变化，bbox x[16-1239] y[24-701]（HUD/球/挡板），唯一色数 153→209 → L3 误报 fail |
| 4 | 03_gameover 超时：120s 内未捕获 GAME_OVER | ✅ **确认仍坏** | `mini-pong/e2e_shots.json` `max_wall_seconds: 120`；5 分制双 AI 对打（`ai_position_error=200`）在 120s wall-clock 内未打完 → shot 永不 ready → capture exit 1（#371 实测） |
| 5 | `--headless --quit` 无脚本错误 | ⚠️ 待验证 | 属验收条件；需在修复后跑通确认 |

**无 stale claims、无已修复项**：`git log --all -- scripts/run-e2e-review.sh` 只有初始提交 `864d2df`，脚本自 #357 后未改过。

### 预期行为（验收条件，源自 Issue #372）

1. [ ] `run-e2e-review.sh` 的 P6 上传函数在调用点**之前**定义，`$name_` 正确绑定（改为 `$name`）
2. [ ] 截图能通过 GitHub 通道嵌入 PR comment（或 gist raw 链接）
3. [ ] frozen 阈值对霓虹暗底游戏不误报（两帧实际差异 > 阈值判定为变化）
4. [ ] 03_gameover 在 deadline 内可捕获（或单独延长该 shot 的 deadline）
5. [ ] `--headless --quit` 无脚本错误

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | review agent 跑 E2E 验证 impl PR | 每次 impl PR | 截图真实上传嵌入 PR comment（Feishu 群 MEDIA: 发图不生效，GitHub raw 链接是唯一证据通道） |
| B | L3 视觉层判定 | 每次含视觉改动的 PR | 霓虹暗底游戏两帧真实变化时不被误判 frozen |
| C | 长对局游戏状态捕获 | GAME_OVER 相关 PR | 5 分制双 AI 对打能在 deadline 内打到 GAME_OVER 并截图 |

### 技术约束（继承自 Issue #372）

| 约束 | 细节 |
|------|------|
| 范围 | class A 基建：`scripts/run-e2e-review.sh`、`scripts/e2e/analyze_bmp.py`、`scripts/e2e/resolve_plan.py`、`framework/templates/e2e_capture.gd`、`mini-pong/e2e_shots.json`、`tests/pipeline/test_e2e_analyze.py`、`test_e2e_runner.py` |
| 不改动 | 游戏代码（`mini-pong/gdscripts/`、`scenes/`、`project.godot`） |
| 语言 | Bash（macOS 13.4 `/usr/bin/env bash`，`set -u` 生效）+ Python3 stdlib |
| 测试基线 | `tests/pipeline/`（104 用例，含 `test_e2e_analyze.py`/`test_e2e_runner.py`），改流水线代码必须过该套件（ARCHITECTURE.md D3） |

---

## 2. 设计意图

### 为什么当前行为存在

| 现象 | 来源 Issue/PR | 原因 |
|------|--------------|------|
| 上传函数定义在文件底部 | #357（`864d2df`） | 初版把 helper 函数放在主流程之后、`exit` 之后 —— bash 函数定义必须在使用前（执行顺序），放在 `exit` 之后等于永不定义 |
| `$name_` 笔误 | #357 | fallback 文案 `$name_` 少写了一个边界（应为 `$name`），`set -u` 下未绑定变量直接终止脚本 |
| `Bearer ***` 占位符 | #357 | 提交时把真实 token 抹成 `***`，从未替换为 env 注入的 `GH_TOKEN` |
| gist raw URL 缺 username 段 | #357 | 初版 URL 拼接错误，未按 `gist.githubusercontent.com/<user>/<id>/raw/<file>` 格式 |
| frozen 用全帧平均 luma | #357 | 平均亮度差对浅色/亮色游戏有效，但霓虹暗底（大面积近黑）使均值稀释局部变化 |
| 全局 120s deadline | #358（`8d0f15e`） | 单一 `max_wall_seconds` 对 loop archetype 三 shot 统一生效；5 分制双 AI 对打耗时不可控 |

### 为什么现在改

#371 review 已用像素级证据证实 L3 红 = harness 误报/超时（class A），不是游戏缺陷。E2E 是 impl PR 的最后一关，P6 崩溃 + 截图无法嵌入 = review agent 只能口头引用本地路径，Feishu 群里证据链断裂。修复后 E2E 证据通道才真正闭环。

### 先前约束（沿用）

| 约束 | 细节 |
|------|------|
| worktree 隔离 | E2E 跑在隔离 git worktree（`/tmp/wt-impl-<N>`），绝不碰主工作树 |
| 4 重反假断言 | 非黑/色数/主题色/帧间差异 —— 防"假截图"的底线，不能整体删除 |
| 纯 stdlib | PNG 解码用 zlib+struct，无 PIL/sips，CI（ubuntu）+ Mac mini 双平台可跑 |
| 游戏自持 shot plan | "框架管机器，游戏管剧本"：`mini-pong/e2e_shots.json` 由游戏侧维护 |

---

## 3. 影响分析

### 直接受影响模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `scripts/run-e2e-review.sh` | E2E runner | **修改** —— P6 helper 移到调用点之前；`$name_`→`$name`；`Bearer ***`→env token 注入；gist URL 修正；frozen 阈值策略调整 |
| `scripts/e2e/analyze_bmp.py` | 反假断言 | **修改** —— frame-diff 指标从全帧平均 luma 改为变化像素占比（或均值+占比双条件） |
| `mini-pong/e2e_shots.json` | shot plan | **可能修改** —— 03_gameover 单独延长 deadline（如 `deadline_s` 字段或提升 `max_wall_seconds`） |
| `framework/templates/e2e_capture.gd` | 截图驱动 | **可能修改** —— 支持 per-shot deadline（若走"单独延长"方案） |
| `tests/pipeline/test_e2e_analyze.py` | 流水线测试 | **修改** —— frozen 断言用例适配新指标（现有 `--min-delta 1.0` 用例） |
| `tests/pipeline/test_e2e_runner.py` | 流水线测试 | **可能修改** —— runner 上传/结构变更的断言 |

### 新建文件

无（修复型 PRD，全部为现有文件修改）。

### 间接受影响模块

| 文件 | 影响 |
|------|------|
| `framework/ARCHITECTURE.md` | 第 44-48 行 E2E 组件表描述需同步（frozen 指标、上传通道变更） |
| `framework/templates/e2e_shots.json` | 若模板增加 per-shot deadline 字段，模板同步 |
| 其它游戏 shot plan（未来） | 新字段向后兼容（缺省沿用全局 deadline） |

### 数据流影响

```
run-e2e-review.sh (P5 视觉层)
    │  每张 shot PNG
    ▼
analyze_bmp.py 4 重断言
    ├── 非黑 / 色数 / 主题色   （不变）
    └── frame-diff: 全帧平均Δluma → 【改为】变化像素占比 ≥ 阈值
    │
    ▼
P6 证据层（修复后）
    ├── upload_via_github（真实 GH_TOKEN 注入，或直接弃用该通道）
    └── upload_via_gist（URL 修正为 <user>/<id>/raw/<file>）
            │
            ▼
    gh pr comment --body-file comment.md   ← 修复后能真正执行（此前 P6 崩溃）
```

### 需更新的文档

- [ ] `framework/ARCHITECTURE.md`（第 45 行 analyze_bmp.py 描述：frozen 指标变更）
- [ ] `scripts/run-e2e-review.sh` 头部注释（P6 通道说明）
- [ ] `mini-pong/e2e_shots.json` `_comment` 字段（若 deadline 策略变更）

---

## 4. 解决方案对比

### 4.1 P6 上传函数定义顺序 + `$name_` 绑定（Issue 验收 1）

| 方案 | 描述 | Pros | Cons | Risk | Effort |
|------|------|------|------|------|--------|
| **A: helper 函数移到 P6 调用点之前（推荐）** | 把 `upload_via_github`/`upload_via_gist` 从文件底部（344/360 行）移到 P6 块之前（如 P5 之后、P6 之前），`$name_`→`$name` | 最小改动；bash 语义正确（函数先定义后使用）；不动主流程结构 | 函数体较长（~45 行）使 P6 前段变长；需注意变量作用域（函数内 `local`） | Low | 0.5 天 |
| B: 抽出独立 `scripts/e2e/upload.sh` 并在顶部 source | 上传逻辑独立文件，`source "$SCRIPT_DIR/e2e/upload.sh"` 在脚本顶部 | 关注点分离；未来可复用；P6 块保持精简 | 新增文件；需要处理 SCRIPT_DIR 路径传递 | Low-Med | 1 天 |
| C: 仅把 `exit "$OVERALL"` 移到函数定义之后 | 保持函数在底部，但把 exit 提前 | 最小 diff（1 行移动） | 函数定义仍在 P6 之后 —— **不解决问题**（P6 在 exit 之前执行，调用时函数仍未定义）；且语义混乱 | High | 0 天（无效） |

**推荐 4.1 = A**：直接移动函数定义到 P6 调用点之前，同时修正 `$name_`。理由：(1) bash 要求函数先定义后调用，A 是唯一语义正确的方向；(2) 改动局限单文件，无新增文件；(3) `set -u` 下 `$name_` 必须改为 `$name`，否则 P6 必崩。

### 4.2 截图上传通道（Issue 验收 2）

| 方案 | 描述 | Pros | Cons | Risk | Effort |
|------|------|------|------|------|--------|
| **A: 修正 gist 通道为主通道（推荐）** | 删除/降级 `upload_via_github`（浏览器端点 + `Bearer ***` 占位符永远不可用），gist 通道 URL 修正为 `https://gist.githubusercontent.com/<user>/<gist_id>/raw/<file>`（`gh gist create` 输出解析出 user+id），`gh pr comment` 的 markdown 用 `![name](gist_raw_url)` | gist 是官方 REST（`gh gist create --public`），永不 404；raw URL 可直接被 GitHub markdown 渲染；无第三方依赖 | gist 公开可见（--public）；`gh gist create` 需要 auth scope（gist）；URL 需从输出解析 user 段 | Low-Med | 1 天 |
| B: 保留 GitHub 端点但注入真实 token | `Bearer ${GH_TOKEN:-$GITHUB_TOKEN}` | 零删除 | 该端点是浏览器拖拽上传端点，非 REST API —— 注入 token 也不可用（脚本注释已自述 2026-07-31 验证无 REST 附件 API） | High | 0.5 天（大概率无效） |
| C: 只留本地路径回退 | 现状：`_upload failed — see /tmp/...` | 零改动 | **不满足验收 2**；Feishu 群证据链断裂 | High | 0 天（无效） |

**推荐 4.2 = A**：gist 是唯一官方 REST 通道。关键修复点：(1) URL 补 `<user>` 段；(2) `Bearer ***` 通道删除或降级为注释说明（避免误导后续维护者）。验收 2 的措辞"GitHub 通道嵌入 PR comment（或 gist raw 链接）"允许 gist raw 链接。

### 4.3 frozen 启发式指标（Issue 验收 3）

| 方案 | 描述 | Pros | Cons | Risk | Effort |
|------|------|------|------|------|--------|
| **A: 变化像素占比（推荐）** | 新增指标：逐像素 |Δluma| > 阈值（如 20）的像素占比 ≥ 阈值（如 0.5%）判定为"变化"。`analyze_bmp.py` 增加 `--diff-ratio` 选项，runner 传 `--min-delta 5.0 --diff-ratio 0.005` 或直接替换 | 对暗底/霓虹风格鲁棒（#371 实测 1.009% 像素显著变化，占比指标必过）；语义直白（"画面确实变了"）；纯 stdlib 可算 | 需确定双阈值（单像素 Δluma 阈值 + 占比阈值）避免过松；像素级遍历已有 `_luma_delta` 基础可复用 | Low-Med | 1 天 |
| B: 降低 `--min-delta`（如 5.0→0.5） | 保持全帧平均 luma，放宽阈值 | 一行改动 | 均值仍被暗底稀释：#371 实测均值 Δluma=0.5，阈值降到 0.5 边缘过；对其它游戏可能引入"假变化"误判 | Med | 0.2 天 |
| C: 均值 OR 占比双条件（任一通过即变化） | 保留均值通道 + 新增占比通道，`--min-delta` 与 `--diff-ratio` 满足其一即 pass | 兼容旧行为；两指标互补（亮色游戏走均值，暗底游戏走占比） | 双条件实现稍复杂；两套阈值参数需文档化 | Low | 1 天 |

**推荐 4.3 = A（或 C 的占比部分）**：#371 像素级证据（1.009% 像素变化、色数 153→209、bbox 覆盖 HUD/球/挡板）明确显示"画面内容已变"，是全帧均值指标失效而非游戏真 frozen。变化像素占比是直接衡量"画面是否变化"的指标，对霓虹暗底鲁棒。若求兼容旧行为可选 C，但 A 更简洁。**注意**：`tests/pipeline/test_e2e_analyze.py` 的 `--min-delta 1.0` 用例（identical 帧 → frozen；全白→全黑 → pass）需同步适配，保证新旧指标都覆盖。

### 4.4 03_gameover 超时（Issue 验收 4）

| 方案 | 描述 | Pros | Cons | Risk | Effort |
|------|------|------|------|------|--------|
| **A: shot 级独立 deadline（推荐）** | `e2e_shots.json` 的 03_gameover shot 增加 `deadline_s` 字段（如 300）；`e2e_capture.gd` 支持 per-shot deadline（缺省用全局 `max_wall_seconds`） | 精准解决单 shot 超时；不动其它 shot；向后兼容（缺省回退全局） | 需改 `e2e_capture.gd` 主循环（deadline 判定改为 per-shot）；`resolve_plan.py` 透传新字段 | Low-Med | 1 天 |
| B: 全局 `max_wall_seconds` 120→300 | 一行改 JSON | 极简 | 所有 shot 共享延长：01_title/02_midgame 本可秒过，白等 3 分钟才轮到超时判定；整体 wall time 拉长 | Low | 0.2 天 |
| C: 降低 AI 误差让对打更快结束 | `ai_position_error` 200→更小（AI 更准）→ 更快分出胜负？ | 不改 deadline | 反而可能让 rally 更长（更准=更不容易失误丢分）；改变对打节奏，影响 02_midgame 证据质量 | Med | 0.5 天（不确定有效） |

**推荐 4.4 = A**：per-shot deadline 精确解决"只有 03_gameover 需要更长时间"的问题，且向后兼容。若 implement 阶段发现 `e2e_capture.gd` 改动复杂，退路是 B（全局 120→300，代价是 wall time 变长）。

### 推荐组合表

| 子问题 | 推荐方案 | 核心文件 |
|--------|---------|---------|
| P6 函数顺序 + `$name_` | A: 函数移到调用点前 + `$name_`→`$name` | `scripts/run-e2e-review.sh` |
| 上传通道 | A: gist 为主，URL 补 user 段；删除 `Bearer ***` 通道 | `scripts/run-e2e-review.sh` |
| frozen 指标 | A: 变化像素占比（`--diff-ratio`） | `scripts/e2e/analyze_bmp.py` + `run-e2e-review.sh` |
| 03_gameover 超时 | A: per-shot `deadline_s` | `mini-pong/e2e_shots.json` + `framework/templates/e2e_capture.gd` |
| 流水线测试 | 同步适配 `test_e2e_analyze.py`/`test_e2e_runner.py` | `tests/pipeline/` |

---

## 5. 边界条件与验收标准

### 正常路径（AC 清单，映射 Issue 验收条件）

- [x] **AC1: P6 上传函数在调用点之前定义，`$name_` 绑定** — `upload_via_github`/`upload_via_gist` 定义位于 P6 块之前；`grep -n "upload_via" run-e2e-review.sh` 显示定义行号 < 调用行号；`$name_` 无残留（`grep -n 'name_'` 只匹配 `$name` 后的合法下划线，无 `"$name_"` 模式）
- [x] **AC2: 截图能嵌入 PR comment（或 gist raw 链接）** — 实测 `run-e2e-review.sh <PR>` 后 PR comment 出现 `![name](https://gist.githubusercontent.com/<user>/<id>/raw/<file>)` 图片；或至少 markdown 链接可访问（curl -I 返回 200）
- [x] **AC3: frozen 阈值对霓虹暗底不误报** — 用 #371 的真实两帧（01_title vs 02_midgame，Δluma=0.5 但 1.009% 像素变化）跑 `analyze_bmp.py` 断言 pass；`test_e2e_analyze.py` 新增暗底变化帧用例
- [x] **AC4: 03_gameover 在 deadline 内可捕获** — 实测 E2E 跑通，results.json 显示 03_gameover saved=true（或单独延长后捕获）
- [x] **AC5: `--headless --quit` 无脚本错误** — `godot --path mini-pong/ --headless --quit` exit 0，无 stderr 报错

### 边界情况

1. `gh gist create` 输出解析：`gh gist create --public <png>` 输出可能含多行（创建进度/URL）—— 解析需取 URL 行并提取 `<user>/<gist_id>`，不能假设 `tail -1` 就是 URL
2. gist raw URL 中的文件名含空格/中文 → URL 需 percent-encode；建议 fallback 用 shot name（`01_title.png` 等，已安全）
3. 无 `GH_TOKEN`/`GITHUB_TOKEN` 时：`upload_via_github` 条件分支跳过（现状），但 gist 通道依赖 `gh` auth —— 未登录时需回退本地路径并**不崩溃**（`set -u` 安全：所有变量先绑定）
4. `--no-comment`/`--dry-run` 模式：P6 跳过，上传函数定义位置移动不影响这些模式
5. 多张截图循环：第一张上传失败不应中断后续（`|| return 1` 已隔离，但要确保函数内 `set -u` 安全）
6. `analyze_bmp.py` 新指标对纯黑→纯黑帧：占比 0% → 判定 frozen（正确）；纯黑→全白：占比 100% → 变化（正确）
7. 双 AI 对打 5 分制耗时波动：per-shot deadline 需留裕量（120→300s），但不能无限（防死锁卡死 CI）
8. shot plan 缺省兼容：旧 plan 无 `deadline_s` 字段 → 用全局 `max_wall_seconds`（向后兼容）

### 失败路径

1. gist 创建失败（网络/auth scope 缺 gist）→ 回退本地路径文案（不崩溃），comment 仍发布（含本地路径提示）
2. `analyze_bmp.py` 新指标参数缺失 → 默认走旧均值逻辑或报参数错误（exit 2），不静默 pass
3. `e2e_capture.gd` per-shot deadline 解析失败（字段类型非 int）→ 回退全局 deadline，不 crash
4. P6 comment 构建中途出错 → `gh pr comment` 不应执行半成品（构建完再发布，或失败时明确 log）

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #357（E2E runner 初版，`864d2df`） | ✅ 已 merge | 本 PRD 修复的对象 |
| #358（金丝雀，`8d0f15e` 修正） | ✅ 已 merge | shot plan/deadline 现状来源 |
| #371（手感校准草稿） | ✅ 已 merge | 提供了像素级证据（9301px/1.009%、Δluma=0.5） |
| `tests/pipeline/`（104 用例） | ✅ 存在 | 改流水线代码必须过该套件（ARCHITECTURE.md D3） |

### 依赖链

```
#357 (runner 初版) → #358 (金丝雀修正, deadline/assert_text) → 本 Issue #372 (4 项 harness 修复)
                                                                    ↓
                                              #371 review 实测证据 (9301px/1.009%, Δluma=0.5)
```

### 阻塞

| 未来工作 | 优先级 | 说明 |
|---------|--------|------|
| 后续所有 impl PR 的 E2E 视觉验证 | 高 | 不修复则每次霓虹暗底改动都可能 L3 误报 fail |
| Feishu 群证据链 | 中 | 截图嵌入 PR comment 后，review agent 可在 Feishu 引用链接 |

### 准备

- [ ] implement 前本地跑一次 `python3 -m pytest tests/pipeline/` 确认基线全绿
- [ ] 准备 #371 的两张真实截图（01_title/02_midgame）作为 frozen 指标回归样本

---

## 7. Spike / 实验

Skipped per depth/standard label（Issue #372 无 depth 标签，按 standard 处理：Section 7 可选）。

若 implement 阶段对 4.3 的占比阈值（单像素 Δluma 阈值 20 + 占比 0.5%）不确定，建议用 #371 真实两帧做一次快速实验：跑 `analyze_bmp.py --diff-ratio 0.005 --diff-with 02.png 01.png` 验证 pass，再跑 identical 帧验证 fail。

---

## 8. 延续上下文

### 系统状态

- E2E runner `scripts/run-e2e-review.sh`（368 行）4 项 class A 缺陷已定位并给出修复方向，全部在测试基建层，**不涉及游戏代码**
- `scripts/e2e/analyze_bmp.py` 的 `_luma_delta`（全帧平均）是 frozen 误报根因；`tests/pipeline/test_e2e_analyze.py` 现有 2 个 diff 用例（identical→frozen、全白→全黑→变化）需适配新指标
- `mini-pong/e2e_shots.json`：loop archetype 3 shot，`max_wall_seconds: 120`，03_gameover 超时
- `framework/templates/e2e_capture.gd`：主循环单一全局 deadline（`_deadline_ms`），per-shot deadline 需新增字段支持

### 关键风险

1. 4.3 占比阈值需用真实数据校准（#371 两张截图已在 `/tmp/e2e-371/shots/`，若已清理可用 `docs/e2e-evidence/358/` 的 01_title/02_midgame.png 替代 —— 同款霓虹暗底风格）
2. gist 通道依赖 `gh` auth 的 gist scope；无 gist scope 时需降级路径
3. `set -u` 是全局开关 —— 所有新增变量必须在使用前绑定，避免再次踩 `$name_` 类坑

### 下一步（plan agent）

1. 按 §4 推荐组合出 DESIGN：`run-e2e-review.sh`（函数上移 + `$name_` 修正 + gist URL 修复 + `--diff-ratio` 传参）、`analyze_bmp.py`（新增占比指标 + CLI 选项）、`e2e_shots.json` + `e2e_capture.gd`（per-shot deadline）
2. 更新 `tests/pipeline/test_e2e_analyze.py`（新指标用例 + 暗底变化帧用例）、必要时 `test_e2e_runner.py`
3. 更新 `framework/ARCHITECTURE.md` 第 45 行（analyze_bmp 描述）
4. 验收时实测跑通一次完整 `run-e2e-review.sh`（可用 --dry-run 验证 P6 构建 + 真实 run 验证上传）
