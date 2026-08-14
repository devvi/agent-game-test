# PRD: [Bug] 修复 main 上既有 L3 视觉回归 — clear_color 双重前缀 + bg-bucket 断言返工

> **Issue:** #476
> **标签:** bug, workflow/available, priority/high
> **Agent:** game-research-agent
> **日期:** 2026-08-14
> **深度:** depth/standard（Issue 无 depth 标签，按 #464/#465/#466 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 以研究期已执行的像素/源码分析实验补齐）
> **所有权:** `content_ownership: mechanical`（配置键名修复 + 断言算法 = 机械可测；雨幕/背景的视觉值已由 #464/#465 定稿，无品味决策）
> **前置依赖:** #464（CLOSED，PR #469 已 merge — 三色常量）、#465（CLOSED，PR #472 已 merge — 雨幕粒子）、#466（OPEN + status/blocked，PR #475 REQUEST_CHANGES — L3 断言实现所在）
> **上游方案:** `docs/DESIGN/466-visual-regression-e2e.md`（L3 区域断言设计）、`docs/PRD/466-visual-regression-e2e.md`
> **来源:** review agent 2026-08-14 04:53 结论（PR #475 REQUEST_CHANGES，issue body 已含根因分析 — 按 bug pre-investigation 边 case 直接验证 + 结构化）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：main 分支存在 2 个既有的 L3 视觉回归失败，且互相叠加：**
1. `mini-pong/project.godot` 的 `[rendering]` 段键名双重前缀 → Godot 静默忽略 → 引擎默认灰 (76,76,76) 取代设计值 (10,10,18)（**真实视觉回归，影响正常游玩，非测试问题**）
2. #466 的 L3 区域断言实现存在 4 个缺陷 → 即使修好 clear_color 仍会失败（bg 桶参与主色竞争、雨签名匹配背景本身、固定板区域不追踪实际板位、单测用近黑背景 ≠ 真实背景）

#### 预调查结果（bug pre-investigation，Patch 10 — issue body 已含根因，逐条验证源码）

| # | Issue 声明 | 状态 | 证据 |
|---|-----------|------|------|
| 1 | `mini-pong/project.godot` `[rendering]` 段 `rendering/environment/defaults/default_clear_color` 双重前缀 → 全路径 `rendering/rendering/...` → Godot 忽略 → 默认灰 (76,76,76) | ✅ **Still broken（确认）** | `mini-pong/project.godot:33` `rendering/environment/defaults/default_clear_color=Color(0.039, 0.039, 0.071, 1)`；同段 line 32 `environment/glow_enabled=true` 为**正确的单前缀格式**（`[rendering]` 段头本身就是前缀，键名不应再带 `rendering/`）。设计值 (0.039,0.039,0.071)=(10,10,18) 与 `constants.gd:147` `BG_COLOR`、`world_environment.tscn:5` `background_color` 一致 |
| 2 | L3-visual-region-dist-0：真实 bg (10,10,18) 桶主导三区 → 两两 RGB dist 0 < 60 | ✅ **Still broken（确认）** | `scripts/e2e/analyze_bmp.py`（impl/466 分支）`dominant_color()` 仅排除近黑桶 (0,0,0)（r<8,g<8,b<8）；真实 bg (10,10,18) → 16 级桶 (0,0,1) **参与竞争** → 每区众数 = bg 桶 → 三区主色相同 → dist 0 |
| 3 | L3-rain-coverage-15pct：rain_signature 匹配暗背景本身 → 假覆盖率 | ✅ **Still broken（确认）** | `rain_signature()` = `b - max(r,g) >= 8 AND luma < 100`。对 bg (10,10,18)：b-max=18-10=8 ✓、luma≈12.7 ✓ → **背景像素本身被判为雨**。深底 (10,10,18) 下覆盖率恒 ≈100%，灰底 (76,76,76) 下 14.6% — 两种情况下都不是在测雨 |
| 4 | AC2 玩家板可见断言失效：`min_nonbg_ratio` 对真实背景恒 100%；固定区域 x240-480 不追踪 AI 板 | ✅ **Still broken（确认）** | `region_stats()` 的 nonblack = `r<8 and g<8 and b<8` 之外；真实 bg (10,10,18) r=10≥8 → 计为前景 → ratio 恒 100% → 板被隐藏仍 PASS。`e2e_shots.json` 视觉配置 paddle 区域 x240-480/y1220-1260，但 review 实测截帧时板在 x15-122 → 与区域重叠 0/1944 px |
| 5 | 单测假绿：合成 PNG 用近黑 bg (4,4,4) ≠ 真实 bg (10,10,18) | ✅ **Still broken（确认）** | `tests/pipeline/test_e2e_analyze.py`（impl/466 分支）`BG_DARK=(4,4,4)`（被众数排除）用于 paddle/三色/雨覆盖正向用例；`BG_REAL=(10,10,18)` 仅用于部分反向用例 → 单测全过但真实运行失败 |
| 6 | **⚠️ 新增发现（issue body 未提及）**：`test_neon.gd` TC4 断言**错误的键名字符串** | ⚠️ **隐藏依赖** | `mini-pong/tests/test_neon.gd:47` `_assert(content.contains("rendering/environment/defaults/default_clear_color"))` — 修复 project.godot 键名后 TC4 将 FAIL（断言的是旧错误键名）。**必须同步更新 TC4 为正确键名 `environment/defaults/default_clear_color`，否则 L1 逻辑层 (run_tests.gd:19 test_neon) 回归** |

#### 断言代码所在位置（关键事实）

**L3 区域断言代码（`dominant_color`/`rain_signature`/`region_stats`/`check_visual`/`visual_detail`）当前只存在于被阻塞的 PR 分支 `impl/466-e2e-visual-regression`（PR #475），main 分支没有：**

| 文件 | main 状态 | impl/466 分支状态 |
|------|:---------:|:-----------------:|
| `scripts/e2e/analyze_bmp.py` | ❌ 仅 4 项全局反假断言 | ✅ 含 #466 区域断言 (check_visual) |
| `mini-pong/e2e_shots.json` | ❌ 无 `visual` 字段 | ✅ 含 shot 级 visual 配置（canvas 720x1280、三区、compare_pairs、rain grid 12/min 60%）|
| `tests/pipeline/test_e2e_analyze.py` | ❌ 无区域断言测试 | ✅ 含 #466 区域断言测试（含假绿问题）|
| `scripts/run-e2e-review.sh` | ✅ 存在（P5 调 analyze_bmp.py） | ✅ 同 |

### 1.2 预期行为（验收条件，源自 Issue #476）

1. [ ] **AC1** `mini-pong/project.godot` `[rendering]` 段键名改为 `environment/defaults/default_clear_color`（去双重前缀），值保持 `Color(0.039, 0.039, 0.071, 1)`
2. [ ] **AC2** main 渲染截图 bg avg ≈ (10,10,18)（真实截图验证，非单元测试模拟）
3. [ ] **AC3** `test_neon.gd` TC4 断言更新为正确键名 `environment/defaults/default_clear_color`（**新增，防止 L1 回归**）
4. [ ] **AC4** #466 的 L3 断言在真实画面上通过：三区主色两两 RGB dist ≥ 60（bg 桶被排除）
5. [ ] **AC5** #466 的 L3 雨幕断言在真实画面上通过：雨签名与背景可区分，覆盖率真实反映雨幕分布
6. [ ] **AC6** #466 的 L3 断言单测改用真实背景 (10,10,18) 校准（消除假绿）
7. [ ] **AC7** 板区域断言能追踪真实板位（按节点定位或全宽扫描），隐藏板 → 断言失败

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| 1 | 正常游玩视觉回归 | 每次启动 | 玩家看到的应该是 #464 设计的暗底 (10,10,18) + 电光青板 + 琥珀砖；当前灰底 (76,76,76) 破坏三色分层 |
| 2 | 视觉回归被未来改动破坏 | 每次 impl PR | 未来某 PR 把板改回与背景同色 → L3 断言必须真实拦住（当前假绿拦不住）|
| 3 | #466 PR 解锁 | 一次 | #475 的 REQUEST_CHANGES 依赖本 Issue 的修复范围落地后才能重跑 E2E 通过并 merge |

---

## 2. 设计意图

### 2.1 为什么当前状态存在

| 事实 | 来源 | 说明 |
|------|------|------|
| clear_color 双重前缀 | commit `2cb4111b`（2026-08-10）| 在 `[rendering]` 段内写键名时误加 `rendering/` 前缀；同段 line 32 `environment/glow_enabled=true` 是正确格式，说明是单行笔误 |
| 断言实现缺陷 | #466 实现（PR #475，68a56cd）| 设计文档 DESIGN 466 明确「阈值首次真实运行校准后回填」，但实现直接提交理论值；`dominant_color` 排除近黑桶的设计假设「背景=近黑」在 post-#464 真实背景 (10,10,18) 下失效 |
| 单测假绿 | #466 实现 | 合成 PNG 用 (4,4,4) 近黑背景，未用真实 BG_COLOR (10,10,18) 验证 |
| L3 持续 fail 未处理 | review 结论 | 自 17:11Z 起 10+ 次 E2E 运行持续 fail 未回填阈值，直至 review agent 定位 |

### 2.2 为什么现在改

- **#466 被阻塞**：PR #475 REQUEST_CHANGES 的根因 1（clear_color）是 main 既有回归，根因 2/3（断言缺陷）是 #466 实现缺陷 — 两者都必须在 #466 merge 前解决
- **真实视觉回归在 main 上存在**：灰底渲染影响所有模式（含正常游玩），违背 #464 三色分层设计
- **测试防线失效**：当前 L3 断言（即使在 #466 分支）在真实画面上假失败/假绿，无法提供回归保护

### 2.3 既有约束

| 约束 | 详情 |
|------|------|
| 引擎 | Godot 4.7.1（game-env/manifest.yaml）|
| 子项目 | `mini-pong/`（独立 project.godot，CI 校验）|
| 平台 | macOS 渲染捕获（`--display-driver macos --rendering-driver opengl3`，720x1280）|
| 设计色值 | #464 定稿：`PADDLE_NEON #00e5ff`、`BRICK_NEON #ff9d45`、`BG_COLOR #0a0a12`（constants.gd:108-109,147）|
| 断言框架 | `scripts/e2e/analyze_bmp.py` 纯 stdlib、无 PIL/网络；测试合成 PNG（tests/pipeline/test_e2e_analyze.py）|
| 工作流 | 本 Issue 的断言返工落在 #466 的 PR 内（issue body 明确 "in #466's PR"）|

---

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/project.godot` | 渲染配置 | 改 1 行：`rendering/environment/defaults/default_clear_color` → `environment/defaults/default_clear_color` |
| `mini-pong/tests/test_neon.gd` | L1 逻辑测试 | 改 1 行（TC4 line 47）：断言键名同步为正确值（**隐藏依赖，新增**）|
| `scripts/e2e/analyze_bmp.py` | E2E 视觉断言（#466 分支）| 返工：`dominant_color()` 排除 bg 桶；`region_stats()`/`min_nonbg_ratio` 改为相对 bg；`rain_signature()` 与 bg 区分；板区域按节点/全宽扫描 |
| `mini-pong/e2e_shots.json` | E2E 视觉配置（#466 分支）| 返工：visual 配置增加 bg 色/排除桶参数；paddle 区域改动态/全宽 |
| `tests/pipeline/test_e2e_analyze.py` | 断言单测（#466 分支）| 返工：合成 PNG 改用真实 bg (10,10,18)；新增 bg-排除/雨-区分/板追踪用例 |

### 3.2 新文件

无（返工现有文件；若采用"板按节点定位"方案，可能需在 `e2e_shots.json` 增加节点路径字段 — 见 §4.2）

### 3.3 间接影响模块

| 文件 | 影响 |
|------|------|
| `scripts/run-e2e-review.sh` | P5 调用 analyze_bmp.py 的接口不变（--visual-config 已透传）→ 无改动，仅行为改善 |
| `framework/templates/e2e_capture.gd` | 板追踪若走节点路径需 capture 侧暴露板位置 → 需评估（§4.2 Approach B）|
| `docs/PRD/466-visual-regression-e2e.md` | 阈值/算法口径变更后需补充说明（可选）|

### 3.4 数据流影响

```
project.godot clear_color 修复
    │
    ▼
Godot 渲染清屏色 = (10,10,18)（真实截图）
    │
    ▼
e2e_capture.gd 截帧 → shots/*.png
    │
    ▼
analyze_bmp.py --visual-config e2e_shots.json 的 visual 字段
    ├── region_stats(排除 bg 桶后) → 板/砖/背景主色
    ├── compare_pairs → 两两 RGB dist ≥ 60
    ├── rain_grid_coverage(雨签名 vs bg 区分) → ≥ 60%
    └── 板区域追踪（节点定位/全宽扫描）→ 隐藏板 → fail
    │
    ▼
summary.json L3_visual = pass/fail → PR 证据 comment
```

### 3.5 需更新的文档

- [ ] `docs/PRD/466-visual-regression-e2e.md`（阈值回填口径补充，可选）
- [ ] `docs/DESIGN/466-visual-regression-e2e.md`（若板追踪方案改变区域定义）
- [ ] `docs/e2e-evidence/`（重跑后的新证据截图）

---

## 4. 方案比较

### 4.1 子系统 1：project.godot clear_color 键名修复

**Approach A：去掉双重前缀（推荐）**

把 `[rendering]` 段内 `rendering/environment/defaults/default_clear_color` 改为 `environment/defaults/default_clear_color`。Godot 4.x 中该设置完整路径是 `rendering/environment/defaults/default_clear_color`，但在 `[rendering]` 段内书写时**段头即前缀**（同段 `environment/glow_enabled=true` 验证）。

- Pros：1 行改动；与同段既有键格式一致；设计值已正确（0.039,0.039,0.071）；Godot 4.x 官方格式
- Cons：需同步更新 test_neon.gd TC4（否则 L1 回归）
- Risk：Low
- Effort：<0.5 天

**Approach B：删除该键，仅依赖 world_environment.tscn 的 background_color**

- Pros：单一来源
- Cons：clear_color 用于渲染清屏阶段，与场景 WorldEnvironment 的 background 语义不同；删除后非场景阶段（如 MENU 前）仍可能灰底；world_environment.tscn:5 已有相同值 → 冗余但无害
- Risk：Med（清屏色与场景背景分离语义易引入新回归）
- Effort：<0.5 天

**Approach C：不改键名，在测试里容忍灰底**

- Pros：零配置改动
- Cons：真实视觉回归继续存在（玩家看到灰底）；L3 断言在灰底下仍无法区分元素
- Risk：High（问题不解决）
- Effort：0

**推荐：Approach A**。理由：(1) 1 行修复根治 main 既有回归；(2) 键名格式与同段 line 32 一致，验证充分；(3) 配套 TC4 更新成本 1 行。

### 4.2 子系统 2：L3 断言返工（在 #466 的 PR 内）

**Approach A：bg 相对化断言（推荐）**

把断言从"绝对近黑"改为"相对背景"：
1. `dominant_color()`：接受 `exclude_buckets` 参数（来自 visual 配置的 bg 色桶 (0,0,1)），排除 bg 桶后取众数 → 三区主色 = 板青/砖橙/背景各自桶
2. `min_nonbg_ratio`：nonbg 判定从 `r<8,g<8,b<8` 改为 `与 bg 色 RGB 距离 ≥ 阈值`（如 ≥ 24）→ 真实 bg (10,10,18) 不再恒 100%
3. `rain_signature()`：增加"与 bg 区分"条件（如 `rgb_distance(c, bg) ≥ 阈值` 或收紧 `b-max(r,g) ≥ 16`）→ 背景不再被判为雨
4. 板区域：由固定 x240-480 改为**全宽扫描 y1220-1260 底部条带**（板必在底部），或由 capture 侧按节点路径注入板实际位置（`e2e_shots.json` 加 `paddle_node` 字段）
5. 单测：合成 PNG 背景统一用 `BG_REAL=(10,10,18)`；新增 bg-排除、雨-区分、板-追踪反例

- Pros：直接消除 review 定位的 4 个缺陷；配置驱动（游戏专属参数在 e2e_shots.json）；符合 DESIGN 466 的"阈值真实运行校准后回填"要求
- Cons：改动面较大（analyze_bmp.py + e2e_shots.json + 单测 3 文件）；全宽扫描需验证砖块不落入底部条带
- Risk：Med（板/砖/背景三区坐标需在真实截图上复核）
- Effort：1-2 天

**Approach B：元素色存在性断言（presence check）**

放弃主色比较，直接检查区域内是否存在 PADDLE_NEON #00e5ff / BRICK_NEON #ff9d45 容差内的像素（配置驱动容差）：
1. 每个区域断言"目标元素色像素占比 ≥ 阈值"
2. 雨断言保留网格覆盖率但签名与 bg 区分
3. 板区域同样需全宽/节点追踪

- Pros：语义最直接（"板渲染了吗"= "区域内有青色"）；天然避开 bg 桶竞争；实现更简单
- Cons：对 glow/混合后的实际像素色依赖容差（BgPulse 呼吸 tint、neon glow 混合可能偏移色值）；与 #464 的"颜色区分"AC 语义（三色两两分离）脱钩，需保留 compare_pairs 才满足 AC3
- Risk：Med（glow 混合色偏移 → 容差难定；可能需真实截图标定）
- Effort：1-2 天

**Approach C：混合方案（bg 相对化 + 元素色辅助）**

主色比较保留（bg 桶排除），同时为板/砖增加元素色 presence 辅助断言作为双保险；雨签名 bg 区分。

- Pros：主断言验证"颜色区分"（AC3），辅助断言验证"元素存在"（AC2）— 两全
- Cons：实现量最大；两套断言口径需维护
- Risk：Low-Med
- Effort：2-3 天

**推荐：Approach A（bg 相对化断言）**，理由：(1) 直接修复 review 定位的全部 4 个缺陷；(2) 保留 #466 AC2/AC3/AC4 的原始语义（区域主色比较 + 雨网格），与 DESIGN 466 一致；(3) 配置驱动，游戏专属参数（bg 色、排除桶、阈值）放 e2e_shots.json；(4) 板追踪优先全宽扫描（零 capture 改动），若底部条带误报再升级节点定位。若实现期发现 glow 混合导致元素色无法与 bg 区分，回退到 Approach C 的元素色辅助。

### 4.3 推荐组合

| 子系统 | 推荐 | 核心文件 |
|--------|------|---------|
| clear_color 键名 | A: 去双重前缀 + TC4 同步 | `mini-pong/project.godot`、`mini-pong/tests/test_neon.gd` |
| L3 断言返工 | A: bg 相对化断言（+全宽板扫描） | `scripts/e2e/analyze_bmp.py`、`mini-pong/e2e_shots.json`、`tests/pipeline/test_e2e_analyze.py` |

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 检查表）

- [x] **AC1: project.godot 键名修复** — `[rendering]` 段内为 `environment/defaults/default_clear_color=Color(0.039, 0.039, 0.071, 1)`
  - 验证：`grep -n "default_clear_color" mini-pong/project.godot` → 无 `rendering/rendering` 前缀；`grep -c "rendering/environment/defaults" mini-pong/project.godot` = 0
- [x] **AC2: 真实截图 bg avg ≈ (10,10,18)** — 重跑 `run-e2e-review.sh`（或空场景截图），分析 bg 区域均值
  - 验证：像素分析 bg avg ≈ (10,10,18)，非 (76,76,76)
- [x] **AC3: test_neon.gd TC4 同步**（新增）— TC4 断言 `environment/defaults/default_clear_color`
  - 验证：`tests/run_tests.gd` L1 通过（含 test_neon）
- [x] **AC4: 三区主色分离（bg 桶排除）** — #466 断言在真实画面 pass
  - 验证：paddle vs brick vs bg 两两 RGB dist ≥ 60；`analyze_bmp.py --json` 输出 dominants 非 bg 桶
- [x] **AC5: 雨幕分布真实** — rain coverage ≥ 60% 且雨签名 ≠ bg
  - 验证：bg 区域无雨签名像素；雨覆盖率来自真实雨滴
- [x] **AC6: 单测真实背景校准** — test_e2e_analyze.py 合成 PNG 用 (10,10,18)
  - 验证：`python3 -m pytest tests/pipeline/test_e2e_analyze.py` 全过；新增反例（bg=真实色时断言仍区分）
- [x] **AC7: 板追踪** — 板被隐藏 → 断言 fail
  - 验证：反向用例（无板）rc=1；真实截图中板位置任意（x 任意）均被捕获

### 5.2 边界情况

1. BgPulse 呼吸相位 → bg 主色轻微偏移（tint 蓝系）→ bg 桶排除需容差（桶粒度 16 级天然覆盖；若超出需按 bg 色距离排除而非固定桶）
2. 雨滴与 bg 混合后的中间色（如 (49,56,71)）→ 雨签名需与 bg 距离阈值兼容（设计值 (49,56,71) vs bg (10,10,18) 距离 ≈ 63，安全）
3. 砖块行 y560-720 与底部板条带 y1220-1260 无重叠（720x1280 布局）→ 全宽扫描安全；需在真实截图复核
4. glow bloom 混合 → 板青色可能被 glow 提亮/偏移 → 元素色断言（如用 Approach C）需容差；主色比较不受影响（桶众数）
5. 深色模式下 capture 的 display-driver 差异 → 截图色彩空间一致（sRGB）→ 断言阈值稳定
6. AI 板 autoplay 模式位置随机（ai_position_error=200）→ 板区域必须动态/全宽，固定区域必然漏检（review 实测 x15-122 vs 区域 x240-480）

### 5.3 失败路径

1. 修改 project.godot 后 L1 测试失败（TC4 未同步）→ 必须同 PR 更新 test_neon.gd:47（AC3 防）
2. 真实截图 bg 仍非 (10,10,18) → 检查键名是否仍带前缀、值是否被覆盖（world_environment 优先于 clear_color 的场景需验证）
3. 板全宽扫描与砖块误报 → 收窄 y 范围或加元素色辅助（Approach C 兜底）
4. rain_signature 与 bg 距离阈值过紧 → 真雨漏检（覆盖率假低）→ 阈值按真实截图回填（DESIGN 466 校准要求）

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|------|
| #464 三色常量（PADDLE_NEON/BRICK_NEON/BG_COLOR）| CLOSED（PR #469 已 merge）| 无 |
| #465 雨幕粒子（amount=600, emission_rect）| CLOSED（PR #472 已 merge）| 无 |
| #466 L3 断言实现（analyze_bmp.py + e2e_shots.json + 单测）| OPEN + status/blocked（PR #475 REQUEST_CHANGES）| **关键**：断言返工在此 PR 内进行 |
| PR #475 的 review 结论 | 2026-08-14 04:53 已出 | 返工完成后需重跑 E2E 再 review |
| Godot 4.7.1 渲染捕获链路（run-e2e-review.sh P5）| 可用 | 低 |

**依赖链：**
```
#464 (三色, merged) ──► #465 (雨幕, merged) ──► #466 (L3 断言, blocked #475)
                                                      ▲
                                                      │ 断言返工
#476 (本 Issue: clear_color 修复 + 断言返工) ─────────┘
```

**阻塞：** 无（本 Issue 自身不阻塞其他；#466/#475 被本 Issue 解锁）

**准备清单：**
- [ ] 在 impl/466-e2e-visual-regression 分支（或基于它的新分支）上做断言返工
- [ ] main 分支修复 project.godot + test_neon.gd（可独立 PR 或随 #466 一并）
- [ ] 重跑 `scripts/run-e2e-review.sh <PR_NUM>` 验证 L3 在真实画面 pass
- [ ] review agent 复检 PR #475

---

## 7. Spike / 实验

按 depth/standard 惯例 + 研究期已执行的分析，记录以下实验（非新增 spike）：

| # | 问题 | 方法 | 结果 | 对方案的影响 |
|---|------|------|------|-------------|
| 1 | clear_color 双重前缀是否真被忽略？ | 源码核实 project.godot:33 vs :32 格式；review agent 实测渲染（空场景 + 场景模式 + main 仓库）| 双前缀 → (76,76,76)；修正后 → (10,10,18)（review 04:53 复现）| 确认 Approach A |
| 2 | 真实 bg (10,10,18) 的 16 级桶是什么？| 计算 (10>>4, 10>>4, 18>>4) = (0,0,1) | 桶 (0,0,1) ≠ 近黑桶 (0,0,0) → 参与主色竞争 | 确认需排除 bg 桶（Approach A 第 1 点）|
| 3 | rain_signature 对 bg 是否成立？| 代入 (10,10,18)：b-max=8 ✓, luma≈12.7 ✓ | 背景本身被判为雨 → 覆盖率假 100%/14.6% | 确认签名需与 bg 区分（Approach A 第 3 点）|
| 4 | 板实际位置 vs 固定区域 | review 实测截帧：板 x15-122 | 与区域 x240-480 重叠 0/1944 px | 确认板区域需动态/全宽（Approach A 第 4 点）|
| 5 | 单测背景 vs 真实背景 | 源码核对 test_e2e_analyze.py BG_DARK=(4,4,4) vs BG_REAL=(10,10,18) | 正向用例全用近黑 → 假绿 | 确认单测需真实背景（Approach A 第 5 点）|

---

## 8. 延续上下文（plan agent 交接）

### 系统状态

- **main**：project.godot:33 双重前缀（灰底回归真实存在）；test_neon.gd:47 TC4 断言错误键名；**无** L3 区域断言代码
- **impl/466-e2e-visual-regression（PR #475，被阻塞）**：L3 区域断言代码 + visual 配置 + 单测全在此分支，含 4 个已定位缺陷
- **相关常量**：`constants.gd:108-109,147`（PADDLE_NEON/BRICK_NEON/BG_COLOR）、`world_environment.tscn:5`（background_color 同值）

### 主要风险

1. **TC4 隐藏依赖**（最高优先级）：不更新 test_neon.gd:47 直接改 project.godot → L1 逻辑层回归（run_tests.gd:19 含 test_neon）
2. **断言返工位置**：必须在 #466 的 PR 分支进行（issue body 明确），plan agent 需先确认 PR #475 的 checkout/分支策略
3. **真实截图校准**：所有阈值（bg 距离、雨签名、板条带 y 范围）必须按真实渲染截图回填，不得提交理论值（DESIGN 466 §8 要求，review 根因 3）
4. **glow 混合**：neon glow 可能偏移元素色，若 Approach A 主色比较在真实截图上仍不稳定 → 回退 Approach C 元素色辅助

### 下一步（plan agent）

1. 在 `impl/466-e2e-visual-regression` 分支基础上做断言返工（analyze_bmp.py + e2e_shots.json + test_e2e_analyze.py），按 §4.2 Approach A
2. 独立（或随 #466）修复 `mini-pong/project.godot` + `mini-pong/tests/test_neon.gd`（§4.1 Approach A + AC3）
3. 重跑 `scripts/run-e2e-review.sh`，用真实截图回填阈值，验证 L3 pass
4. 更新 `tests/pipeline/test_e2e_analyze.py` 用 BG_REAL=(10,10,18) 校准
5. 重开 PR #475 的 review 流程

### Obsidian 知识库检索记录

- 检索路径：`~/Documents/Obsidian Vault/wiki/` + `raw/`（注：`/Volumes/Obsidian/Knowledge Ocean/` 挂载为空，实际 vault 在 `~/Documents/Obsidian Vault`）
- 命中笔记：`赛博增殖：网球与绒毛.md`（项目起源 — mini-pong 即该 ASCII 网球游戏，确认暗底霓虹审美方向）、`体验引擎-patterns.md`（"抽象留白"设计模式 — 支持 #464 暗底 + 高饱和元素的视觉语言）、`独立游戏开发讨论.md`、`技术笔记.md`
- 检索词：雨幕/rain/霓虹/neon/视觉回归/clear color/背景色/Pong/网球 — **无直接覆盖 clear_color 渲染配置或 L3 断言的笔记**（该缺陷为纯机械/技术问题，Obsidian 无品味决策输入）；本 Issue 的视觉目标值全部来自 #464/#465 已定稿常量
