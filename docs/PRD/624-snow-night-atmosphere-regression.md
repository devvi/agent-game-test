# PRD #624 — Fix #613 雪夜氛围回归：雪幕粒子全部不可见 + 血色 vignette 无效果（CanvasModulate×6 破坏渲染）

> **Parent Issue:** #624（bug / priority/high）
> **Blocked PR:** #613（`impl/582-snow-night-atmosphere`，taste-draft 草稿，待修复后裁决）
> **Source:** review conclusion 613.json（已消费删除，本文档证据以本地复现为准）
> **游戏:** shandong-wolf（manifest `game.active`）｜**引擎:** Godot 4.7.1（Compatibility / OpenGL-Metal）
> **深度:** 无 depth label → standard（§1–6 + §8 必写；§7 因已执行实验而保留）
> **日期:** 2026-08-19

---

## 1. 问题定义

### 1.1 预调查结论（bug pre-investigation，Patch 10）

| Issue 声称 | 预调查结果 | 证据 |
|-----------|-----------|------|
| 雪幕粒子全部不可见 | ✅ **Still broken — 已复现** | 官方 E2E 截图 `01_snow_night_atmosphere.png`：luma 15.6、仅 3 色、**0 个白色像素**；blame2 受控实验 bright samples 30→0 |
| 血色 vignette 无效果 | ✅ **Still broken — 已复现** | `verify_blood_before/after.png` 像素几乎一致（mean 17.0/17.2）；blood on 截图**零红色像素**；tween 属性正常（modulate.a 0→1.0）但渲染被压没 |
| 根因「CanvasModulate×6 破坏 GPU 粒子渲染」 | ✅ **确认，机制已实测** | blame2：`no Moonlights → bright samples 恢复 30`；moon_spike 实验：单 moon 只影响自身层、7 moon 全激活时白色内容 255→120 |
| 失败「pre-existing」 | ⚠️ **部分准确** | 失败由 #613 self-correct R1（`7e88741`，2026-08-19 22:05）**引入**——相对该轮 review 是"已存在"，相对 #613 原始实现（`9a87815`）是**新回归**。round 1（单 moon）雪幕可见（ab_as_is：白色 255 像素存在、主题色通过） |

### 1.2 失败清单（实测证据，均来自真实渲染非 headless）

| # | 现象 | Expected | Actual | 证据 |
|---|------|----------|--------|------|
| F1 | 雪幕三层粒子全部不可见 | 白色 α0.7–0.9 粒子可见（PRD #582 §1.5） | 官方截图 291,475 近黑像素 + 125 像素 <127 lum，无白色；blame2 bright samples=0 | `01_snow_night_atmosphere.png`、`verify_full.png`、blame2 实验 |
| F2 | 血色 vignette 无效果 | `debug_trigger_low_health()` 后 0.5s α→0.35 红色边缘可见（AC4） | 触发前后截图 mean 17.0→17.2（无红色像素）；`rect.modulate.a` 实际 0→1.0（属性层正常） | `verify_blood_before/after.png`、`verify_blood2.gd` 输出 |
| F3 | 全场景压暗至近黑 | 冷月色调（#6e7684 蓝灰） | capture 场景整体 luma 15.6–17；`theme #c0c8d0 NOT found`（analyze_bmp 断言失败） | P5-assert.log、全分辨率像素直方图 |
| F4 | Main.tscn 标题 UI 对比度减半 | 白字 255 | 白字 255×0.471≈120（bright>0.5 采样 957→0） | moon_spike `s_all_moons` vs `s_all_white` |

### 1.3 根因机制（已实测确认，非推测）

**CanvasModulate 只调制其所在 CanvasLayer 的内容，且多个 CanvasModulate 逐层累积相乘。**

- **self-correct R1（`7e88741`）为满足 AC2（冷月光作用于全部可见 CanvasLayer）在每个可见层各挂一个 Moonlight CanvasModulate**：layer 0（Atmosphere 根）+ 1（UI）+ 2（水墨）+ 3/4/5（雪幕远/中/近）+ 10（血色）= **7 个**（issue 标题计 atmosphere 内 6 个）。
- 每个 moon 把所在层所有内容乘以 `#6e7684` ≈ (0.431, 0.463, 0.518)：
  - 雪幕白色粒子 255 → ~120，且粒子仅 0.5–1.5px、α0.7–0.9 → 在近黑背景上视觉不可见（F1）
  - 血色 α≤0.35 × 0.471 → α≤0.165，红 (0.55,0.05,0.05) → (0.26,0.02,0.03) → 不可见（F2）
  - capture 场景 Backdrop（layer 0，色 0.1/0.14/0.18）被 root moon ×0.471 → luma ~17 近黑（F3）
- **排除项**（review bisect 已证伪）：Parallax2D、CanvasLayer 结构本身、InkWash/Blood 层、粒子 amount/纹理/动态 vs 静态创建、fixed-fps——均非根因（`reparent_*`/`bisect_*`/`dyn_vs_static`/`fps_*` 实验 mean 均 17.0 无改善；blame2 移除 moons 唯一恢复）。

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家首启（标题场景 = 第一印象） | 每次启动 | 当前启动画面近乎全黑（luma 15.6）——雪夜氛围『第一印象』（PRD #582 brief 审美坐标）直接失败 |
| B | 用户 taste-draft 裁决（#582） | #613 修复后 | 官方 E2E 截图必须能看到雪 + 冷月光 + 水墨质感，否则 ≥70% 裁决无法进行（当前截图连主题色断言都不过） |
| C | 战斗场景（#583）复用氛围层 | #583 实现时 | 若保留"每层一个 moon"结构，战斗场景将继承同样的压暗 bug |
| D | 低血战斗（#575 low_health 发射端） | 未来 | 血色 vignette 是唯一允许打破冷色调的高饱和元素（constants 情感断言）——必须真正可见 |

---

## 2. 设计意图

### 2.1 现状为何存在

| 原因 | 详情 |
|------|------|
| round 1 review 误判「冷月光无效果」为缺陷 | 原实现（`9a87815`）单 CanvasModulate 挂 Atmosphere 根（layer 0），但 Main.tscn 可见内容全在 layer 1–10，layer 0 无内容可染 → A/B 实验 as_is==no_moon「像素级一致」。**这不是 bug**——世界内容（#583 场景几何）尚未存在，layer 0 本就无物可染 |
| self-correct R1 修复方式错误 | `7e88741` 改为「每个可见 CanvasLayer 挂一个 moon」以满足 AC2 → 引入逐层相乘压暗，雪幕/血色（必须保持高亮度的层）被压没 |
| 原设计本意是单节点 | PRD #582 §4.2 方案 B / DESIGN #582：`CanvasModulate 冷月 #6e7684` **单节点**；「亮度 0.6」经色值换算为 #6e7684，无任何"每层一个"的语义 |
| 测试未断言渲染 | test_atmosphere.gd 60 个单测全部为节点存在性/常量值断言（review round 1 明确记录："未断言渲染效果"）；e2e_shots snow_night 单帧无像素断言（analyze_bmp theme 断言失败未被拦截） |

### 2.2 为何现在改

1. **#613 被本 issue 阻塞**（Blocked PR）——不修复无法 merge，taste-draft 裁决（#582 AC5）无法进行。
2. **#583 战斗场景依赖氛围层**（dep edge 11→12）——层契约错误会传染给战斗场景。
3. **『第一印象』红线**：标题场景 = 首启画面，当前近黑（luma 15.6）直接违背 brief 审美坐标（苍白/清冷/大地如墨）。
4. 修复成本低：根因明确、方案收敛，属**回退 + 契约化**而非重构。

### 2.3 之前约束（继承 #582 决策，Patch 19）

| 约束 | 详情 |
|------|------|
| CanvasModulate 层作用域 | 只影响自身 CanvasLayer（本次实测确认）——设计必须遵守，不能假设全局调制 |
| 雪幕 amount 红线 | `amount` 只在 .tscn 静态声明（60/60/80=200），运行时禁改（rain_curtain 教训） |
| 水墨 edge_alpha ≤ 0.3 硬上限 | AC3，不遮挡战斗读图 |
| 血色 α ≤ 0.35 硬上限 | AC4，0.5s Tween 渐变 |
| 层级约定 | layer 1=UI / 2=水墨 / 3-5=雪幕 / 10=血色（DESIGN #582，全场景统一） |
| 参数单一事实源 | constants.gd「氛围参数」# DRAFT 分区，@export 默认取常量，禁散落硬编码 |
| taste-draft 所有权 | 视觉参数定稿归用户裁决（#582），本 issue 只修结构不擅自改品味参数 |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/scenes/atmosphere/atmosphere_layer.tscn` | 氛围层场景组件 | **改**：移除 6 个 Moonlight CanvasModulate（LayerFar/Mid/Near、InkWashLayer、BloodVignette、Atmosphere 根下 6 个中的 5 个或全部重构），保留单一 moon（位置见 §4 方案 A）；若加世界背景垫底则新增节点 |
| `shandong-wolf/scenes/Main.tscn` | 标题场景 | **改**：移除 UI CanvasLayer 下 Moonlight；按方案 A 增加 layer 0 世界背景（夜色地面/天空），供月光染色 |
| `shandong-wolf/gdscripts/atmosphere_controller.gd` | 氛围编排 | **改**：`_apply_moonlight()` 从 `find_children` 遍历改回单节点直接赋值；补层契约注释 |
| `shandong-wolf/gdscripts/snow_curtain.gd` | 雪幕控制器 | **不改**（粒子本身无缺陷；只受层 moon 影响） |
| `shandong-wolf/gdscripts/blood_vignette.gd/.gdshader` | 血色 vignette | **不改**（tween/属性正常；只受层 moon 影响） |
| `shandong-wolf/tests/test_atmosphere.gd` | 氛围测试 | **改**：新增「CanvasModulate 数量 == 1」守卫断言（防再犯）；如可行加渲染级断言 |
| `shandong-wolf/e2e_shots.json` | E2E shot plan | **改**：snow_night 组补充像素断言配置（theme = 月光色 / 白色粒子存在性）或注释说明由 analyze_bmp 断言 |

### 3.2 新文件

| 文件 | 用途 |
|------|------|
| （可选）`shandong-wolf/scenes/world_backdrop.tscn` 或 Main.tscn 内联 ColorRect | layer 0 夜色世界背景（方案 A 的 AC2 载体）；若 #583 即将提供场景几何可后置 |

### 3.3 间接影响

- **#583 战斗场景**：复用 `atmosphere_layer.tscn`，层契约修正后自动获得正确效果；场景几何放 layer 0（世界层）才能被月光染色。
- **e2e_stick_figure_capture.tscn**：Backdrop 已在 layer 0——修复后自动被月光染色（当前 17 lum 近黑 → 预期 ~36 lum 冷蓝灰夜）。
- **CI/E2E**：analyze_bmp theme 断言（#c0c8d0）当前失败是拦截信号，修复后应恢复通过。

### 3.4 数据流影响（CanvasModulate 乘法链）

```
修复前（7 个 moon，逐层相乘）:
  Backdrop(layer0) ──×#6e7684──► luma 36→17 近黑
  雪幕粒子(layer3-5) ──×#6e7684──► 255→120 不可见
  血色(layer10) ──×#6e7684──► α0.35→0.165 不可见
  UI 文字(layer1) ──×#6e7684──► 255→120 对比度减半

修复后（方案 A：单 moon 挂 layer 0 世界层）:
  Backdrop/世界几何(layer0) ──×#6e7684──► 冷蓝灰夜 ✅ AC2
  雪幕粒子(layer3-5) ──无 moon──► 纯白 α0.7-0.9 ✅ F1
  血色(layer10) ──无 moon──► 饱和红 α≤0.35 ✅ F2
  UI(layer1)/水墨(layer2) ──无 moon──► 原样（水墨自带暗角）
```

### 3.5 文档更新清单

- [ ] `docs/DESIGN/582-snow-night-atmosphere.md`：层契约小节补「CanvasModulate 只影响自身层 + 世界内容放 layer 0」的明确记录（防后续再犯）
- [ ] `docs/GAME_DESIGN/shandong-wolf/`：氛围/渲染章节（如存在）同步层契约
- [ ] GDD/PROJECT.md：post-merge agent 常规更新

---

## 4. 方案对比

### 方案 A：单 CanvasModulate（layer 0 世界层）+ 世界背景垫底（推荐）

**描述：** 回退 self-correct R1 的多 moon 结构，恢复 PRD #582 §4.2 方案 B 原设计——**唯一一个 Moonlight CanvasModulate 挂在 layer 0**（Atmosphere 根或世界根）；其余 6 个全部删除。layer 0 内容（世界背景/场景几何/角色）被染成冷蓝灰（AC2）；雪幕（3-5）/水墨（2）/血色（10）/UI（1）不放 moon，保持原始亮度与饱和度。为让 AC2 在标题场景即有物可染，Main.tscn 增加 layer 0 夜色世界背景（深蓝灰 ColorRect，或渐变；色值进 constants.gd 氛围分区 # DRAFT）。

| 维度 | 评估 |
|------|------|
| Pros | 恢复原设计意图；雪/血/UI 完全不受影响；单节点零累积；层契约清晰可注释可测试；与 #583（世界几何放 layer 0）天然兼容 |
| Cons | Main.tscn 需补 layer 0 世界背景（新增 1 个节点 + 1-2 个常量）；capture 场景当前 Backdrop 会被染暗（正是期望的夜色）；若未来想染雪幕需另想办法（当前审美不需要——雪必须白） |
| Risk | **Low**——机制已被 spike 验证（单 moon 只影响自身层），回退面小 |
| Effort | 0.5–1 天（场景改 2 个、controller 改 1 个、测试补守卫 + E2E 验证） |

### 方案 B：保留 per-layer moon，但雪/血/UI 层 moon 改白（去效果）

**描述：** 保留「每层一个 moon」结构，但只让世界层（layer 0）的 moon 为 #6e7684，其余层 moon 设为白色（#ffffff = 无操作）。

| 维度 | 评估 |
|------|------|
| Pros | 改动最小（只改 tscn 颜色值） |
| Cons | **白 moon 节点毫无意义却保留 6 个**——结构欺骗性强，任何后续 agent 都会困惑；重新引入风险高（把白 moon 改回 #6e7684 即复发）；与「单一事实源」原则冲突；无法表达「世界层」契约 |
| Risk | **Med-High**——治标不治本，架构债 |
| Effort | 0.25 天 |

### 方案 C：弃用 CanvasModulate，冷月光并入全屏 shader（screen texture）

**描述：** 删除全部 CanvasModulate，扩展 ink_wash.gdshader（或新建 moon.gdshader）用 BackBufferCopy/screen texture 对已渲染画面做整体色温调制。

| 维度 | 评估 |
|------|------|
| Pros | 单一 shader 控制色温+暗角；不依赖层语义 |
| Cons | Compatibility 渲染器对 screen texture 支持有限（需 spike 验证）；性能成本（全屏二次采样）；与水墨层耦合或需新增一整个渲染层；`#583` 场景几何变化时画面内容需重采样；改动面远大于根因 |
| Risk | **High**——引擎兼容性 + 性能 + 复杂度三重不确定 |
| Effort | 2–3 天 |

### 推荐：**方案 A**

1. 根因是「多 moon 逐层相乘」，方案 A 直接消除乘法链（7→1），机制已被实测验证（moon_spike：单 moon 无跨层影响）。
2. 恢复 PRD/DESIGN #582 的原设计意图（§4.2 方案 B 单节点），零架构漂移。
3. 与 #583 的场景规划一致：世界内容放 layer 0 是 Godot 默认层，战斗场景自然落位。
4. AC2 的「无物可染」问题由「layer 0 世界背景」补齐——这是 round 1 误判的根源，一并解决。
5. 附带修复测试缺口：CanvasModulate 数量守卫 + 像素级断言（详见 §5/§8）。

---

## 5. 边界条件与验收标准

### 5.1 验收条件（映射 issue body）

- [x] **AC1: 雪幕粒子可见** — 修复后 E2E 截图雪幕区域存在白色（≥200 lum）像素；blame2 式受控实验 bright samples ≥ 基线（无 moon 时）的 50%
- [x] **AC2: 冷月光色调成立** — 单 CanvasModulate 挂 layer 0；layer 0 世界背景被染成 #6e7684 系冷蓝灰；E2E 截图存在 #6e7684 邻近色像素（analyze_bmp theme 断言用 `6e7684` 而非 `c0c8d0`）
- [x] **AC3: 血色 vignette 可见** — `debug_trigger_low_health()` 后 0.5s 截图边缘存在红色（r>g 且 r-b ≥ 0.15）像素；`get_visual_alpha()` 契约不变
- [x] **AC4: CanvasModulate 数量守卫** — test_atmosphere 新增断言：atmosphere_layer.tscn 实例内 CanvasModulate 总数 == 1（防再犯）
- [x] **AC5: 非氛围层不受影响** — UI 文字（layer 1）亮度恢复（≥200 lum 白字）；水墨 edge_alpha ≤0.3 不变；粒子 amount 未改（60/60/80）
- [x] **AC6: 回归验证** — 原失败实验全绿：官方 snow_night 截图 theme 断言通过、verify_blood before/after 有像素差异、blame2 bright samples 恢复

### 5.2 边界情况

1. **layer 0 无内容时**（#583 前 Main.tscn）：月光无可染对象——由「世界背景垫底」保证 AC2 成立；若用户裁决去掉背景，AC2 判定改为「capture 场景（有 Backdrop）成立」。
2. **#583 战斗场景落地后**：世界几何放 layer 0 自动被染；若战斗场景把世界放别的层，需遵循层契约（契约注释 + 单测守卫只在 atmosphere_layer 内有效，跨场景靠文档）。
3. **雪幕层被误加 moon**（未来调参）：若有人给雪幕层加 #6e7684 moon，白色雪变灰——`CanvasModulate == 1` 守卫测试会拦截。
4. **血色触发时机**：`set_low_health(true)` 幂等（已测）；修复后重复触发不应叠加（tween kill 已有）。
5. **Compatibility vs Forward+ 渲染器**：本项目 CI/E2E 用 Compatibility（OpenGL/Metal）；若未来切 Forward+，CanvasModulate 层作用域语义需重新验证（spike S3 顺带验证两驱动）。
6. **capture 场景与 Main.tscn 的 moon 归属**：capture 场景实例化同一 atmosphere_layer.tscn——守卫断言按场景组件算（1 个/组件），Main.tscn 的 UI 层 moon 一并删除（修复后全场景合计 1 个）。

### 5.3 失败路径

1. **删 moon 后冷月光完全消失**（方案 A 执行偏差：把唯一的 moon 也删了）→ AC2 截图无 #6e7684 像素 → 守卫断言（==1）失败拦截。
2. **世界背景垫底颜色过亮/过暗** → 与水墨暗角叠加后读图受影响 → edge_alpha ≤0.3 硬上限 + 用户裁决（taste-draft）。
3. **E2E theme 断言仍失败**（雪/血/月光像素不足）→ 先查渲染驱动/窗口分辨率（720x405 异常已在 22:57 run 出现），再查层契约；禁止用「加大粒子」掩盖（amount 红线）。

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|------|
| #613（本 PRD 对应的实现 PR） | OPEN，被本 issue 阻塞 | 修复后需重新 review + taste-draft 裁决 |
| #582（氛围总 issue，taste-draft） | OPEN（workflow/implement + status/blocked） | 修复后 E2E 截图重新提交用户 ≥70% 裁决 |
| #583（战斗场景） | 依赖 #582/#613 | 层契约修正后复用 atmosphere_layer.tscn |
| #575（玩家实体 low_health 发射端） | OPEN backlog | 血色消费端已就绪，不受影响 |
| #586（E2E 剧本） | 未来 | 完整剧本可纳入"月光/雪/血"像素断言 |

```
#582 (氛围, taste-draft) ──► #613 (实现 PR, 被 #624 阻塞)
                                ▲
#624 (本 bug 修复) ─────────────┘
#583 (战斗场景) ──► 依赖 #613 修复后的氛围层契约
```

---

## 7. Spike / 实验

> 深度 standard 下 §7 可选；因**关键实验已在调研阶段实际执行**（真实渲染），此处记录结果并补 1 个修复验证实验，供 plan/implement agent 直接复用方法。

### S1（已执行）：单 CanvasModulate 的层作用域 — moon_spike.gd

- **问题**：单个 moon 挂不同 CanvasLayer 影响哪些层？是否全局调制？
- **方法**：Main.tscn 全 moon 改白后逐个激活（layer 0/2/3/10），截图采样 bright>0.5 像素数与 max 亮度。
- **结果**：`s_moon_root/layer2/layer3/layer10` 均与全白基线一致（bright 955-960，max 255）→ **单 moon 只影响自身层，零跨层影响**（连最顶层 layer 10 也不能全局调制）。
- **对方案的影响**：排除「顶层 moon 全局染」的幻想；确认方案 A（moon 必须与目标内容同层）是唯一正确结构。

### S2（已执行）：多 moon 累积相乘量化 — 全分辨率像素分析

- **问题**：7 个 moon 全激活时各层内容被压到什么程度？
- **方法**：全分辨率（每像素）亮度直方图 + 主色统计，对照全白基线。
- **结果**：Main.tscn 白色内容 255→~120（#606080 系）；capture 场景 Backdrop 36→17（近黑）；官方截图 0 白像素、0 红像素；`s_all_moons` bright>0.5 采样 957→0。
- **对方案的影响**：量化确认 F1/F2/F3；修复目标阈值（雪 ≥200 lum、血 r-g≥0.15、月光 #6e7684 邻近色）由此定标。

### S3（待 implement 执行）：修复验证 — 单 moon + layer 0 世界背景

- **问题**：方案 A 落地后，雪/血/月光三项像素断言是否同时成立？
- **方法**：复刻 S1 脚本（moon_spike.gd 改 3 行：只激活 root moon + 加 layer 0 背景 ColorRect），对 Main.tscn 与 capture 场景各截图 1 张，跑 analyze_bmp.py：`--theme 6e7684`（月光）、白色粒子存在性（自定义计数）、红色像素计数。
- **预期结果**：背景呈冷蓝灰（≈#2f333c = 78×0.471 附近）、雪白像素存在、血触发后红像素存在；全部断言通过。
- **对方案的影响**：通过 → 方案 A 定稿；失败 → 检查 moon 是否落在正确层 / 背景是否在 layer 0。

---

## 8. 交接上下文（Continuation Context）

### 给 plan agent 的系统状态

- **当前 main 无氛围代码**（#613 未 merge）；修复基于 `impl/582-snow-night-atmosphere` 分支（head `51d3083`）。
- **修复范围（方案 A）**：
  1. `atmosphere_layer.tscn`：删除 6 个 Moonlight（LayerFar/Mid/Near/InkWashLayer/BloodVignette 下各 1 + Atmosphere 根 1，保留**唯一一个**——建议保留 Atmosphere 根下 layer 0 那个）；`Main.tscn`：删除 UI CanvasLayer 下 Moonlight。
  2. `atmosphere_controller.gd`：`_apply_moonlight()` 改为直接 `_moonlight.color = moonlight_color`（去掉 find_children 遍历）；头部注释写明层契约（moon 只在 layer 0 世界层，雪/墨/血/UI 层不放 moon 的原因 = 本 PRD §1.3）。
  3. `Main.tscn`（或 capture 场景）：layer 0 增加夜色世界背景（建议 ColorRect 色 `#0d1520` 附近，**值进 constants.gd 氛围分区** # DRAFT，如 `NIGHT_BG_COLOR`）。
  4. `test_atmosphere.gd`：新增守卫——实例内 `find_children("*", "CanvasModulate")` 数量 == 1（在 `_test_c3_moonlight_covers_visible_layers` 附近，需改写该测试的语义：从「每可见层都有 moon」反转为「全组件仅 1 个 moon」）。
  5. `e2e_shots.json` snow_night 组：注明像素断言口径（theme `6e7684`；雪白像素；血触发红像素由 review 手动 A/B）。
- **红线**：不改 amount（60/60/80）；不改水墨/血色 shader 的 α 上限；不改 constants 既有氛围值（taste 域归用户）；不动 `mini-pong/`、manifest、workflows、scripts。
- **验证方法**：L0 编译 + L1 测试（守卫断言）+ 本地真实渲染截图（S3 脚本，Compatibility 驱动）→ analyze_bmp 三项断言 → review agent 按 E2E 协议出证据。
- **已知风险**：E2E runner 曾以 720x405 窗口截图（22:57 run）——像素断言需按实际分辨率适配；官方截图需重新产出（旧图 luma 15.6 作废）。
