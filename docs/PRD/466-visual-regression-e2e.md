# PRD: [Test] 视觉回归 E2E — 玩家板可见 + 颜色区分 + 雨幕分布断言

> **Issue:** #466
> **标签:** enhancement, testing, priority/high, version/v1, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #394/#372 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行的像素分析实验补齐）
> **所有权:** `content_ownership: mechanical`（纯测试基建，无品味决策；区域/阈值/分布断言均为机械实现）
> **前置依赖:** #464（CLOSED，PR #469 已 merge）、#465（CLOSED，PR #472 已 merge）
> **上游方案:** `docs/PLAN-e2e-verification-v2.md`（L0-L3 四层模型）、`docs/DESIGN/394-e2e-playability.md`、`docs/DESIGN/464-visual-three-color-layer.md`、`docs/DESIGN/465-rain-curtain-fix.md`
> **参考先例:** `docs/PRD/394-e2e-playability.md`（E2E 可玩性，逻辑层断言）、`docs/PRD/372-e2e-harness-fixes.md`（harness class A 修复）、`tests/pipeline/test_e2e_analyze.py`（analyze_bmp.py 单元测试）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：现有 E2E 视觉层（P5/L3）是"反假证据"防线而非"元素存在"验证。它只证明截图不是黑的/冻结的，无法证明玩家板、砖块、雨幕真的渲染出来了。** 用户实测反馈"看不到 player 板""测试流程竟然没有测出玩家不可操作、player板看不见这样的critical问题"正是这一盲区的直接后果。

#### 预调查结果（bug pre-investigation，Patch 10）

| # | Issue 声明 | 状态 | 证据 |
|---|-----------|------|------|
| 1 | "修复 capture 卡 MENU 问题（ui_accept 模拟或直接 force 状态）" | ✅ **Already fixed** | `e2e_capture.gd` 自 commit `8d0f15e`（#358 Phase 2）起支持 `press: {key: "enter"}` / `{action: "ui_accept"}` 注入，`mini-pong/e2e_shots.json` 的 02_midgame 已带 `press: enter` + `require: player_score >= 1` 门；`docs/e2e-evidence/424/` 与 `447/` 的 `02_midgame.png` 均成功截到 PLAYING 画面（720x1280）→ 无需改动 capture 状态推进机制 |
| 2 | "e2e autoplay 把 PlayerPaddle 设 AI" | ✅ **Still true** | `mini-pong/e2e_shots.json` `autoplay.tweaks` 设 `PlayerPaddle.mode=1`、`AIPaddle.mode=1`、`ai_position_error=200`。AI 模式下挡板仍会渲染，视觉断言不受影响；"玩家不可操作"类回归（输入链路损坏）确实测不出 → 见 §1.2 边界 |
| 3 | "截图只验证非黑/色数/主题色，不验证元素存在" | ✅ **Still true（本 Issue 核心缺口）** | `scripts/e2e/analyze_bmp.py` 仅 4 项全局断言：non-black（黑占比 ≤ 50%）、color count（色桶 ≥ 3）、theme color（`--theme` 容差 32 内存在）、frame diff（Δluma + 变化像素占比）。**无任何区域/元素断言** |
| 4 | `theme_color: "4a90d9"`（e2e_shots.json + 模板） | ⚠️ **Stale** | #464（PR #469）落地后玩家板 = `PADDLE_NEON #00e5ff`、砖块 = `BRICK_NEON #ff9d45`、背景 = `BG_COLOR #0a0a12`；`#4a90d9` 仅存于 BgPulse tint（`BG_PULSE_TINT`）与升级 UI 边框。主题色断言在 post-#464 画面中失去"元素存在"语义 |

#### 实测证据（研究期对真实截图的像素分析）

对 `docs/e2e-evidence/447/02_midgame.png`（pre-#464 证据，720x1280）逐像素分析：

- `#4a90d9` 像素遍布全帧 **x 22-629 / y 30-1279**（采样占比 1.91%）—— 玩家板与 BgPulse 背景同色系，主题色断言在"板不可见"时依然通过 → 证实用户反馈的根因
- 玩家板区域 **y1220-1260** 采样：92% 为近黑背景色桶 (4,4,4)，仅 ~8% 蓝系像素 → 板与背景无对比度，肉眼不可见
- `#00e5ff` / `#ff9d45` 像素数 = 0（该证据早于 #464 merge）→ post-#464 后区域断言才具有判别力

#### post-#464/#465 新基线（源码核实，已 merge 于 origin/main fc090e4）

| 元素 | 常量/场景 | 值 | 区域（720x1280 竖屏） |
|------|-----------|-----|----------------------|
| 玩家板 | `PADDLE_NEON` / player_paddle.tscn | `#00e5ff` 电光青 | 底部 y 1230-1250（Main.tscn position (360,1240)，PADDLE_HEIGHT=20）|
| 砖块 | `BRICK_NEON` / brick.tscn | `#ff9d45` 琥珀橙 | 墙带 y ≈ 586-694（BreakoutGrid @ (0,640)，wall_y=640，4 行 x 24px + gap）|
| 背景 | `BG_COLOR` / BgPulse | `#0a0a12`（BgPulse 呼吸调色） | 全屏；角落可采样 |
| 雨幕 | rain_curtain.tscn | `amount=600`、emission_rect_extents (360,640)、velocity 800-1200、色 (0.72,0.84,1) alpha 0.225 | 全屏 |

### 1.2 预期行为（验收条件，源自 Issue #466）

1. [ ] **AC1** E2E 能截到 midgame（玩家板可见）画面 — 既有 press 注入已满足，无需新增状态推进机制（预调查表 #1）
2. [ ] **AC2** 玩家板可见性断言：底部区域 y1220-1260 内非背景像素占比 ≥ 阈值（板渲染了）
3. [ ] **AC3** 颜色区分断言：玩家板区域主色 ≠ 砖块区域主色 ≠ 背景主色（两两 RGB 欧氏距离 ≥ 60，镜像 #464 AC1 到像素层）
4. [ ] **AC4** 雨幕分布断言：全屏雨像素分布覆盖 ≥ 60% 区域（镜像 #465 AC1）
5. [ ] **AC5** 反向测试：把板/砖改回同色 → 断言失败（防回归有效性）
6. [ ] **AC6** review agent 的 E2E 截图证据包含 midgame 画面（现状已满足，保持）

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| 1 | 视觉回归被未来改动破坏 | 每次 impl PR | 未来某 PR 把板改回与背景同色 → L3 视觉断言必须拦住，不能像 #464 之前那样静默通过 |
| 2 | 雨幕粒子回退成"漏水点" | 每次 impl PR | 未来某 PR 改坏 rain_curtain emission/amount → 覆盖率断言必须拦住 |
| 3 | 截图证据可信度 | 每次 review | review agent 上传的 midgame 截图能直接证明"板可见 + 三色分离 + 全屏雨"，而非仅"非黑非冻结" |

### 1.4 技术约束（继承自 Issue #466 + 项目基线）

- **纯 stdlib 约束**：`analyze_bmp.py` 用 zlib+struct 解码 PNG（无 PIL/sips），CI（ubuntu）与本地 Mac 双跑；`tests/pipeline/test_e2e_analyze.py` 明文约束"no PIL/sips"。扩展必须保持纯 stdlib（本地 python3 虽有 PIL，但 CI 无 → 不可依赖）
- **竖屏 720x1280**：`run-e2e-review.sh` P5 以 `--resolution 720x1280` 跑 capture；区域坐标按此画布定义
- **class A 基建红线**：只改测试基建（`scripts/e2e/`、`mini-pong/e2e_shots.json`、`framework/templates/`、`tests/pipeline/`），**不改游戏代码**（同 #372 约束）
- **文件域**（Issue body）：`mini-pong/e2e_shots.json`（加 midgame 视觉断言配置）、`scripts/e2e/analyze_bmp.py`（扩展区域颜色/对比度/分布断言）、`framework/templates/e2e_capture.gd`（仅若需 — 预调查表明**不需要**改）
- **开源优先**（Issue 要求）：已调研，见 §7 实验 3

## 2. 设计意图

### 2.1 为什么当前行为存在

E2E 视觉层诞生于 #357/#358 的"反假证据"目标（防黑帧/冻结帧/同帧复用），`analyze_bmp.py` 的 4 项断言全部是**全局统计量**，刻意与具体游戏内容解耦（框架模板可复用）。这种设计对"截到了图"有效，但对"游戏元素渲染正确"无效 —— 元素存在性必须靠**区域级**断言，而区域坐标天然是游戏专属的（这正是 Issue 把文件域限定在 mini-pong 的 e2e_shots.json + 扩展 analyze_bmp.py 的原因）。

### 2.2 为什么现在改

#464/#465 刚刚（2026-08-13，PR #469/#472）落地三色分层与全屏雨幕，颜色/分布基线第一次具有判别力（板=青、砖=橙、底=暗、雨=全屏淡蓝）。用户明确要求"确保修复不被未来改动破坏" —— 若现在不做视觉回归断言，下一次同色回归会再次静默通过。时机即窗口：断言阈值可直接以 #464/#465 的机械常量（RGB 距离 ≥ 60、覆盖率 ≥ 60%）为准，无需品味博弈。

### 2.3 先前约束（沿用）

- 4-fold anti-fake 断言（non-black / color count / theme / frame diff）**保留** —— 新区域断言是叠加层，不是替代
- 截图捕获仍走 `run-e2e-review.sh` P5（worktree 隔离 + 真实渲染 + gist 证据上传），不改 capture 状态推进（预调查表 #1）
- 断言全部由 `analyze_bmp.py`（或扩展）执行，capture.gd 只负责截图 —— 职责边界不变

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 改动 | 影响 |
|------|------|------|
| `scripts/e2e/analyze_bmp.py` | 新增区域断言 CLI 参数与实现（region 颜色主色、非背景像素占比、RGB 距离、网格分布覆盖率） | 核心扩展点；向后兼容（无新参数时行为不变） |
| `mini-pong/e2e_shots.json` | midgame shot 增加 `visual` 断言配置（区域定义 + 阈值）；`theme_color` 更新或移除 | 视觉层从"全局统计"升级为"元素存在" |
| `tests/pipeline/test_e2e_analyze.py` | 新增区域断言单元测试（合成 PNG，无网络/无 Godot） | 保证 CI 可测 |
| `scripts/run-e2e-review.sh` | P5 断言循环透传新参数（或读取 shot 级 visual 配置） | 管线接线 |
| `framework/templates/e2e_capture.gd` | **不改**（预调查结论：状态推进已可用） | — |

### 3.2 新建文件

无新脚本文件（区域断言并入 `analyze_bmp.py`，见 §4.1）。如 plan agent 判定拆脚本更优，备选 §4.2。

### 3.3 间接影响

- `docs/DESIGN/394-e2e-playability.md` 的 L3 章节描述需补一句"区域断言"（文档同步，非代码）
- 模板 `framework/templates/e2e_shots.json` 的 `theme_color: "4a90d9"` 属历史值，模板层面不动（其他游戏自有主题色），仅 mini-pong 实例更新
- review agent 的 P6 证据评论将自然包含"断言通过明细"（analyze_bmp 的 ✅/❌ 行已入 P5-assert.log 与 comment 上下文）

### 3.4 数据流（断言管线）

```
run-e2e-review.sh P5
  ├─ godot --resolution 720x1280 --script capture.gd -- plan.json
  │     └─ shots/01_title.png, 02_midgame.png, 03_gameover.png
  ├─ 既有 4-fold anti-fake（每张图）: non-black / colors / theme / diff
  └─ 新增 midgame 区域断言（仅 02_midgame，读取 shot 级 visual 配置）:
        ├─ R_paddle(y1220-1260): 非背景像素占比 ≥ 阈值 → AC2
        ├─ 三区主色: R_paddle vs R_brick(y560-720) vs R_bg(角落)
        │     └─ 两两 RGB 欧氏距离 ≥ 60 → AC3
        └─ 全屏雨像素: 蓝色主导 + 低亮度 签名, 网格覆盖 ≥ 60% → AC4
```

### 3.5 文档更新

- `docs/DESIGN/394-e2e-playability.md`：L3 章节补充区域断言说明（一行级）
- 本 PRD merge 后由 plan agent 产出 DESIGN/TASKS（§8）

## 4. 方案对比（区域断言实现策略）

### 4.1 Approach A：扩展 analyze_bmp.py，shot 级 visual 配置驱动（推荐）

`analyze_bmp.py` 增加区域断言参数（如 `--region-paddle y0:y1 --min-nonbg-ratio 0.05`、`--region-brick ...`、`--region-bg ...`、`--rgb-min-dist 60`、`--rain-coverage 0.6`），由 `run-e2e-review.sh` 从 resolved plan 的 shot 级 `visual` 字段读取并透传。

- ✅ 单一分析入口，4-fold 与新断言同进程，`test_e2e_analyze.py` 合成 PNG 可直接覆盖
- ✅ 纯 stdlib、CI 可跑；参数化后模板级复用（其他游戏传自己的区域）
- ✅ 区域坐标在 e2e_shots.json（游戏专属配置），框架逻辑与游戏内容解耦
- ❌ analyze_bmp.py 从 340 行增长（~+150 行）；CLI 参数变多需小心向后兼容（缺省即关闭）

### 4.2 Approach B：新建独立 `scripts/e2e/visual_assert.py`

新脚本专职区域断言，analyze_bmp.py 不动。

- ✅ 职责单一、旧脚本零风险
- ❌ 重复 PNG 解码逻辑（或需抽公共库，改动面反而更大）；run-e2e-review.sh 需串两个分析器，P6 输出要合并；与 test_e2e_analyze.py 的测试设施重复

### 4.3 Approach C：capture.gd 内做像素断言（Godot 侧）

在 `e2e_capture.gd` 截帧后用 `Image.get_pixel()` 直接断言，结果随 results.json 输出。

- ✅ 免去 PNG 解码，可精确按节点坐标断言（无需猜区域）
- ❌ **违反既有职责边界**（capture 只截图不分析，模板注释明文）；模板被游戏逻辑污染；headless/CI 与本地渲染差异影响像素值；`--headless` 下视口为 0（#394 §1.4 已知），区域像素不可得
- ❌ 与"断言证据可独立复核"目标冲突 —— 像素证据应留在可审计的 Python 层

### 4.4 推荐组合

**Approach A**（扩展 analyze_bmp.py + e2e_shots.json shot 级 visual 配置 + test_e2e_analyze.py 合成 PNG 单测 + run-e2e-review.sh 接线）。

关键设计决策（供 plan agent 定稿）：

| 决策点 | 建议 | 理由 |
|--------|------|------|
| 区域坐标放哪 | e2e_shots.json 的 shot 级 `visual` 字段 | 游戏专属配置，框架逻辑解耦；resolve_plan.py 已透传 shot 对象 |
| 板区域 R_paddle | y1220-1260，x 240-480（板道窄带） | 覆盖板 span（y1230-1250）+ 余量；x 窄带提高非背景占比信噪比（板 120px 宽 vs 全宽 720px 会被背景稀释，实测 92% 背景即此因） |
| 砖区域 R_brick | y560-720 全宽 | 墙带 wall_y=640 ± 砖阵半高；含拆砖中/波次间隙两种状态（见 §5.2） |
| 背景区域 R_bg | 四角 60x60（如 (0,0)-(60,60)、(660,0)-(720,60)、(0,1220)-(60,1280)、(660,1220)-(720,1280)） | 角落无板/砖/HUD；BgPulse 呼吸取瞬时值即可（三区同帧比较） |
| 主色提取 | 区域内颜色桶（16 级）众数，排除近黑背景桶 | 与现有 color_buckets 同粒度，抗噪声 |
| 雨签名 | `b - max(r,g) ≥ 8 且 luma < 100` | 雨滴混合色 ≈ (49,56,71)（alpha 0.225 叠暗底，luma≈56）；BgPulse 亮相 luma≈149 被排除；暗相 r≈g≈b 非蓝主导被排除 |
| 覆盖率网格 | 12x12 网格（60x107 每格），含 ≥1 雨像素的格数占比 ≥ 60% | 镜像 #465 AC1；网格化抗"单点密集"假阳性 |
| theme_color | mini-pong 实例改为 `00e5ff`（玩家板电光青）或移除 | 4a90d9 已无元素语义（预调查表 #4）；板色存在性由 AC2 区域断言覆盖，theme 可作为廉价兜底 |
| 反向测试 | test_e2e_analyze.py 合成"同色"PNG 断言必失败 | AC5 以合成 PNG 实现，无需真机改色 |

## 5. 边界条件与验收

### 5.1 正常路径（AC 检查清单，映射 Issue body）

- [ ] AC1：`run-e2e-review.sh` P5 截图 02_midgame 成功（既有 press 注入，回归验证）
- [ ] AC2：`analyze_bmp.py --region-paddle` 对 post-#464 midgame 截图：非背景像素占比 ≥ 5%（板 120x20=2400px / 区域 240x40=9600px ≈ 25%，阈值 5% 留 5 倍余量）
- [ ] AC3：三区主色两两 RGB 距离 ≥ 60（#00e5ff vs #ff9d45 vs 暗底 —— 常量级距离已由 test_visual_contrast.gd 保证 ≥ 60，像素级需验证渲染后仍成立）
- [ ] AC4：雨覆盖率 ≥ 60%（12x12 网格）
- [ ] AC5：合成同色 PNG → 断言 exit 1（单测）
- [ ] AC6：P6 评论含 02_midgame 截图（既有）

### 5.2 边界情况（Edge Cases）

| 边界 | 风险 | 缓解 |
|------|------|------|
| 波次间隙砖块清空 | 02_midgame 截帧时 R_brick 无砖 → AC3 砖主色退化为背景色 → 误报 | 方案 a：shot `require` 增加"砖块存在"门（capture 模板扩展 `children_in_group` 计数，小改）；方案 b：`require player_score >= 1` 保持 + 砖区非背景占比 < 阈值时重试截帧（settle 重试）；方案 c：接受概率性（autoplay AI 下 player_score≥1 时墙通常未清空）→ 推荐 a，plan agent 定夺 |
| BgPulse 呼吸相位 | R_bg 主色随呼吸变化 | 三区同帧比较（AC3 是"区际"距离，非绝对色）；呼吸 tint 是蓝系，与板青/砖橙距离仍 ≥ 60 |
| 雨幕 alpha 低（0.225） | 雨像素与暗底接近 | 签名用"蓝主导 + 低亮度"双条件（§4.4），暗底 r≈g≈b 不满足蓝主导 |
| 粒子瞬时分布不均 | 单帧雨覆盖 < 60% | 网格化统计 + 阈值 60% 与 #465 AC1 对齐（#465 验收已按此通过） |
| HUD/计分文本干扰 | R_brick/R_paddle 区域混入 HUD 像素 | 区域坐标避开 HUD（HUD 顶部/中上，R_brick y560-720 与其不重叠；板区域 x 窄带） |
| 分辨率变化 | 区域坐标写死 720x1280 | e2e_shots.json 声明 `visual.canvas: "720x1280"`，analyzer 校验截图尺寸，不匹配则 fail 而非错位 |

### 5.3 失败路径（Failure Paths）

- 任一区域断言 fail → P5 层 fail → run-e2e-review.sh exit 1 → PR 评论呈现 ❌ 明细（既有机制）
- 截图缺 midgame（capture 超时）→ 既有 missed 机制报错，区域断言跳过并显式标注"未执行"
- analyze_bmp.py 解析新参数失败 → 旧断言仍跑（参数缺省即关闭），新增 CLI 解析必须向后兼容

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 说明 |
|------|------|------|
| #464 三色分层（PR #469） | ✅ merged（c09d900） | AC2/AC3 的颜色基线（PADDLE_NEON/BRICK_NEON/BG_COLOR） |
| #465 雨幕修复（PR #472） | ✅ merged（865b32e） | AC4 的分布基线（amount=600 全屏） |
| #394 E2E 基建（playthrough + shot plan） | ✅ merged | 本 Issue 的载体（e2e_shots.json / run-e2e-review.sh） |
| #372 harness 修复 | ✅ merged（93766f8） | per-shot deadline / frozen 阈值，保证 midgame 截图可达 |

### 6.2 依赖链

#464/#465（视觉修复）→ #466（视觉回归断言）→ （plan agent）DESIGN/TASKS → （impl agent）analyze_bmp 扩展 + shot plan 接线 → review agent 用 run-e2e-review.sh 出具含 midgame 区域断言的证据

### 6.3 阻塞

无。两个前置 Issue 均已 merge 且最新 main（fc090e4）包含全部依赖。

## 7. Spike / 实验（研究期已执行）

### 实验 1：pre-#464 截图像素分析（证明问题真实存在）

对 `docs/e2e-evidence/447/02_midgame.png` 全帧分析：`#4a90d9` 像素 bbox x22-629/y30-1279（1.91% 采样占比），板区 y1220-1260 92% 背景色 → **主题色断言无法证明板可见**，与用户反馈一致。实验脚本：纯 stdlib 读 PNG + 区域统计（本 PRD 研究期已跑通，证明纯 stdlib 分析可行）。

### 实验 2：post-#464 颜色基线核算

`PADDLE_NEON (0,229,255)` vs `BRICK_NEON (255,157,69)` vs `BG_COLOR (10,10,18)`：RGB 欧氏距离板-砖 ≈ 347、板-底 ≈ 300、砖-底 ≈ 278，均 ≥ 60（常量级由 test_visual_contrast.gd 验证，像素级同源）。雨滴混合色核算：`(0.72,0.84,1)*0.225 + 背景*0.775 ≈ (49,56,71)`，luma ≈ 56，满足"蓝主导 + 低亮度"签名（BgPulse 亮相 luma ≈ 149 被排除）。**待 plan/impl 阶段用真实 post-#464 截图复核（建议首次运行记录实际值回填阈值）**。

### 实验 3：开源优先调研（Issue 硬性要求）

| 候选 | 结论 |
|------|------|
| GitHub 搜索 "godot visual regression" | 无成熟专项工具；`tuomas-maenpaa/gdsentry`（1★）为综合测试框架非视觉回归专用 |
| gdUnit4 screenshot 比较 | 需插件集成 + Godot 内跑，与"真实渲染 + Python 可审计证据"管线不合 |
| pixelmatch / Percy / Applitools（JS/SaaS） | 引入 node 依赖或 SaaS，违反纯 stdlib/CI 约束，mini-pong 场景过重 |
| **结论** | **无成熟可复用方案 → 扩展项目自有纯 stdlib analyze_bmp.py（Approach A）**，与 #372/#394 技术路线一致 |

## 8. 延续上下文（交给 plan agent）

### 系统状态

- 最新 main `fc090e4` 已含 #464（c09d900）/ #465（865b32e）全部改动
- `analyze_bmp.py`（340 行）4 项全局断言可用；`test_e2e_analyze.py` 合成 PNG 设施完备（`make_png` + `run_cli`）
- `mini-pong/e2e_shots.json`：3 shots，autoplay AI，`theme_color: 4a90d9`（stale）
- `e2e_capture.gd`：press 注入/require/assert_text/settle/per-shot deadline 全部可用，**无需改动**
- 真实 post-#464 截图**尚不存在**（最近证据 447 为 pre-#464）→ 阈值需在 impl 后首次真实运行校准

### 关键文件清单（plan agent 需要产出 DESIGN/TASKS 的文件）

| 文件 | 动作 | 内容 |
|------|------|------|
| `scripts/e2e/analyze_bmp.py` | 修改 | 区域断言：`--region-*` 参数、主色提取、非背景占比、RGB 距离、雨签名、网格覆盖率 |
| `mini-pong/e2e_shots.json` | 修改 | 02_midgame 增 `visual` 配置（区域坐标 + 阈值 + 雨网格）；`theme_color` → `00e5ff` 或移除 |
| `tests/pipeline/test_e2e_analyze.py` | 修改 | 区域断言单测：合成"正常三色 PNG"（通过）与"同色 PNG"（AC5 必失败）；雨分布合成图 |
| `scripts/run-e2e-review.sh` | 修改 | P5 循环读取 resolved plan shot 级 visual 配置并透传 analyzer 参数；尺寸校验 |
| `framework/templates/e2e_capture.gd` | ❌ 不改 | 预调查结论（§1.1 表 #1） |
| `docs/DESIGN/394-e2e-playability.md` | 修改（一行） | L3 章节补区域断言说明 |

### 实施顺序（推荐）

1. `analyze_bmp.py` 区域断言核心（纯函数：主色/占比/距离/覆盖）→ 单测先行（合成 PNG）
2. `test_e2e_analyze.py` 增补用例（含 AC5 反向用例）
3. `e2e_shots.json` 02_midgame 加 `visual` 配置
4. `run-e2e-review.sh` P5 接线（透传 + 尺寸校验）
5. 真机跑 `run-e2e-review.sh` 于一个含视觉改动的 PR 或 --baseline，记录实际像素值回填阈值（实验 2 的待复核项）
6. 文档一行同步（DESIGN 394）

### 主要风险与缓解

- **砖区波次间隙空窗**（§5.2）：capture 模板加 `children_in_group` 计数 require（推荐）或截帧重试
- **阈值校准**：post-#464 首帧未验证 → 首次运行用保守阈值（板非背景 ≥ 5%、RGB ≥ 60、雨覆盖 ≥ 60%），记录实测值后按需收紧
- **向后兼容**：新 CLI 参数缺省即关闭，旧调用（无 visual 配置的 PR diff）行为不变

### 交给 plan agent 的硬性要求

1. 不修改任何 `mini-pong/gdscripts/`、`scenes/`、`project.godot` 游戏代码（class A 红线）
2. `e2e_capture.gd` 保持零改动（除非 §5.2 选择方案 a —— 若选，改动仅限 `require` 增加 `children_in_group` 计数，且需模板级兼容）
3. 全部新断言在 `tests/pipeline/test_e2e_analyze.py` 有合成 PNG 单测（CI 可跑，无网络/无 Godot）
4. `visual.canvas` 声明 720x1280 并做尺寸校验，防止区域错位
5. 真实截图阈值校准结果回写本 PRD/DESIGN（记录实测值 vs 理论值偏差）
