# Game Overview — 山东抗日之狼（shandong-wolf）

> 本目录 GDD 首个章节（2026-08-19，post-merge agent 依据 #567 探针 PR 落盘）。
> 当前阶段：骨架期 —— 引擎 Godot 4.7.1，项目 `shandong-wolf/`，主场景 `scenes/Main.tscn`。

## 1. 游戏总览

《山东抗日之狼》是 agent-game-test 仓库当前活跃游戏（`game-env/manifest.yaml`
的 `game.active` 切换，2026-08-18 起一次只做一个游戏）。与 mini-pong（历史单游戏
时期遗留，GDD 在 `docs/GAME_DESIGN/` 根目录）不同，本游戏的 GDD 独立成目录
`docs/GAME_DESIGN/shandong-wolf/`，章节编号从 01 起（01-OVERVIEW → 09+ 按功能域）。

截至 #570（2026-08-19）项目处于最小冒烟骨架期：主场景承载标题/副标题/版本号/
探针标签，无游戏逻辑脚本、无资源资产。骨架链路（CI 编译 / headless 启动 / E2E
截图）经 #559/#562/#563 打通，本次 #567 在场景侧追加一枚探针标签以驱动
post-merge 管线全链路回归（GDD 落盘 + docs PR 自动合并）。

## 2. 场景结构：`shandong-wolf/scenes/Main.tscn`

主场景为纯声明式 CanvasLayer UI 骨架（零脚本、零资源），启动首帧即可见全部元素。
启动链：`project.godot` 的 `run/main_scene` 指向本场景（#562 落地）。

| 节点 | 类型 | 层级/锚点 | 内容 | 来源 |
|------|------|-----------|------|------|
| Main | Node2D | root | 场景根 | #562 |
| CanvasLayer | CanvasLayer | layer=1 | UI 层容器 | #562 |
| CenterContainer | CenterContainer | 全屏 anchors_preset=15 | 居中布局 | #562 |
| VBoxContainer | VBoxContainer | alignment=1 | 标题组垂直排列 | #562 |
| TitleLabel | Label | 居中 | 「山东抗日之狼」 font_size=64 | #562 |
| SubtitleLabel | Label | 居中 | 「雪夜 · 大刀 · 山东村」 font_size=28, α0.8 | #563 |
| VersionLabel | Label | 左下 anchors_preset=2 | 「v0.1.0」 font_size=16, α0.6 | #562 |
| PostMergeProbeLabel | Label | 右下 anchors_preset=3 | 「post-merge probe」 font_size=16, α0.6 | #570 |

布局要点：VersionLabel（左下）与 PostMergeProbeLabel（右下）严格镜像
（offset_left=16 ↔ offset_right=-16、offset_right=400 ↔ offset_left=-400），
1280x720 下互不重叠；探针锚在右下角向左上生长（grow_horizontal=0 / grow_vertical=0），
与标题区无遮挡。

## 3. 探针 Label（#567，post-merge probe）

### 3.1 设计意图

探针是管线冒烟验证物而非游戏功能（`content_ownership: mechanical`，无品味裁决
空间）：文案由 issue 指定（「post-merge probe」，含空格无引号，E2E 断言按
node path `CanvasLayer/PostMergeProbeLabel` 精确匹配），视觉「可见但克制」
（font_size 16、α0.6，与 VersionLabel 同规格）。它驱动一条完整
research→plan→implement→CI→E2E→review→merge→post-merge 管线回归
（#562/#566 曾暴露 GDD 更新成无主责任的结构性缺口，2026-08-19 方案 X 修复后
由本探针实证全链路）。

### 3.2 节点定义（tscn 节选）

```text
[node name="PostMergeProbeLabel" type="Label" parent="CanvasLayer"]
anchors_preset = 3
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -400.0
offset_top = -36.0
offset_right = -16.0
offset_bottom = -12.0
grow_horizontal = 0
grow_vertical = 0
text = "post-merge probe"
theme_override_font_sizes/font_size = 16
modulate = Color(1, 1, 1, 0.6)
```

### 3.3 参数

| 属性 | 值 | 说明 |
|------|-----|------|
| 挂载层级 | CanvasLayer 直属（VersionLabel 之后） | 不进 CenterContainer/VBox，避免自动排列连锁 diff |
| anchors_preset | 3（右下角） | 镜像 VersionLabel 的左下 anchors_preset=2 |
| 文本 | `post-merge probe` | issue 指定，精确匹配硬约束 |
| 可见性 | font_size=16, α0.6 | 与 VersionLabel 一致，视觉克制 |

### 3.4 设计决策

- **方案 A（纯 tscn 声明式 Label）**：采纳（#567 DESIGN §2.1）。零脚本、零信号、
  零方法，CI 编译风险趋零，diff 极小（~10 行 tscn）。
- **方案 B（探针 .gd 脚本）/ C（自定义 Theme/字体）**：否决。冒烟验证物不需要
  逻辑；ASCII 文本 + Godot 内置默认字体零压力，新增资产违反「零资产骨架期」。

## 4. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #559 | shandong-wolf 管线冒烟（Main.tscn 骨架，2026-08-18） | 已合并 |
| #562 | Main.tscn 场景结构落地 + post-merge 机制（merge 事件绑定 GDD） | 已合并 |
| #563 | 结论骨架回归（SubtitleLabel，静态 Label + 管线全链路回归） | 已合并 |
| #567 | post-merge 阶段回归探针（PostMergeProbeLabel） | 已合并（#570） |
| #652 | probe-C：api-close-reopen 探针（marker 文档已随探针清理移除，#658 已合并） | 已合并（#658） |

## 5. 探针 C：api-close-reopen（#652/#658，2026-08-20）

### 5.1 设计意图

探针 C 是 GitHub API 语义实验（issue 正文「实验3: API close 后 reopen 是否
re-close」，`content_ownership: mechanical`，无品味裁决空间），marker 文档
`docs/probe-c.md`（单行文本「probe C: api close reopen test 1787223373」，
时间戳为探针发射时刻）经完整 PR 流程（impl/652 分支 → PR #658 → squash
merge）落地 main。与 #567 探针同族：驱动
research→plan→implement→CI→E2E→review→merge→post-merge 管线二次回归，
并验证「Closes #N」关键字 + API close/reopen 语义下 issue 终态收敛
（#652 终态 CLOSED + status/done）。

### 5.2 Marker 文档定义（docs/probe-c.md）

```text
probe C: api close reopen test 1787223373
```

### 5.3 参数

| 属性 | 值 | 说明 |
|------|-----|------|
| 探针编号 | C（#650 A / #651 B / #652 C） | 系列第三枚，探针名 = issue 标题前缀 probe-C |
| marker 文件 | docs/probe-c.md | 单行文本，1787223373 = 探针发射时间戳 |
| 实验内容 | API close 后 reopen 是否 re-close | issue 正文「实验3」，终态 CLOSED + status/done |
| 合并路径 | impl/652-api-close-reopen → PR #658 squash merge | 2026-08-20T12:50:30Z |

### 5.4 设计决策

- **方案 A（纯 marker 文档 PR）**：采纳。探针只测管线与 API 语义，不需要游戏
  代码/场景改动，`docs/probe-c.md` 单行文本 diff 最小。
- **post-merge 联动**：PR #658 merge 事件 → `_ensure_post_merge_state` →
  SPAWN: post-merge（one-shot）→ 本 GDD 章节即由该流程写入 —— 与 #567 同款
  闭环回归，2026-08-20 二次实证 post-merge 管线无回归。
