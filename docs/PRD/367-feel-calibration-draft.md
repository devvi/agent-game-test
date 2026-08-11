# PRD: [Content] Mini Pong 手感校准草稿 — 球速/反弹角/AI强度 (A1)

> **Issue:** #367
> **标签:** enhancement, content, version/mvp, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-11
> **深度:** depth/light（game-to-issues JSON `depth: light` → Sections 1–5 + 8 必填，Section 6 保留、Section 7 跳过）
> **所有权:** `content_ownership: taste-draft`（人机共做 v4 — 草稿达标即 merge，PR 用 `parent #N` 不写 Closes；review agent 打 `status/human-review` + assign 用户定稿）
> **taste 方向来源:** Issue 审美坐标（#289 落地）+ Obsidian 知识库检索 + 项目品味档案（docs/TASTE.md 尚不存在，本 PRD 合成方向，implement 落 TASTE.md 初版）

---

## 1. 问题定义

### 当前状态

Mini Pong 的手感参数全部集中在 `mini-pong/gdscripts/constants.gd`（`class_name GameConstants`，#295 迁移后的单一事实源），但**全是"物理正确"的默认值，没有任何 taste 注入**：没有 `# DRAFT` 标记、没有"该值影响什么"注释、没有候补值、没有情感断言。手感校准的"校准接口三件套"（试玩剧本 + 候补值表 + 情感断言）完全不存在。

| 系统 | 当前状态 | 缺失 |
|------|---------|------|
| `constants.gd` 球速参数 | ✅ `BALL_INITIAL_SPEED=300.0`、`BALL_SPEED_INCREMENT=1.05`、`BALL_MAX_SPEED_MULTIPLIER=2.0`、`BALL_SERVE_ANGLE_RANGE=45.0` | ❌ 无 taste 方向、无 DRAFT 注释、无候补值、无情感断言 |
| `constants.gd` 反弹角参数 | ✅ `BALL_MAX_BOUNCE_ANGLE=60.0` | ❌ 同上 |
| `constants.gd` AI 强度参数 | ✅ `AI_REACTION_DELAY_MIN=0.1`、`AI_REACTION_DELAY_MAX=0.3`、`AI_POSITION_ERROR=20.0`、`AI_SPEED_BOOST=1.2`、`AI_SPEED_SLOW=0.8` | ❌ 同上 |
| `constants.gd` 操控参数 | ✅ `PADDLE_SPEED=400.0` | ❌ 同上（手感相关，建议纳入） |
| 运行时代码消费 | ✅ `ball.gd`/`paddle.gd` 全部经 `@export` 默认值消费 CONSTS；`Main.tscn` **无导出值覆盖**（仅 `mode = 1`）→ 改 constants.gd 即改运行时手感 | — |
| 自动对打 | ✅ `tests/auto_play_test.gd`（#297，100 局 AI vs AI，~5s） | ❌ 无"试玩剧本"文档包装（自动对打 + 手动一局的操作流程） |
| 候补值表 | ❌ 不存在 | 需新建（建议 docs/TASTE.md 初版承载） |
| 情感断言 | ❌ 不存在 | 每条草稿值需附（体验引擎词汇） |
| 品味档案 `docs/TASTE.md` | ❌ 不存在（v4 语义要求项目内品味档案） | 需新建（草稿表 + 试玩剧本 = 校准接口） |
| 测试 | ⚠️ `test_constants.gd` TC6 断言全部参数**精确字面值**（`== 300.0`/`== 1.05`/`== 1.2`…）；`test_ai_paddle.gd` TC-B2/3/4 硬编码 `400.0 * 1.2`/`400.0 * 0.8`/阈值 40 | 改任意草稿值 → 测试红。机械测试需随草稿值更新（无 `# DRAFT` 残留） |

### 预期行为（验收条件，源自 Issue）

1. **手感参数集中在 `constants.gd` 单一文件**，agent 填值带 `# DRAFT` 注释 + "该值影响什么" + 2–3 个候补值（朝 TASTE.md 方向）
2. **每条草稿值附情感断言**（体验引擎：它试图触发什么情感——如"利落击打感/逐渐加压的紧张感"）
3. **校准接口三件套齐全**：试玩剧本（自动对打 + 手动一局）+ 候补值表 + 情感断言
4. **机械部分（架构/管线/测试）无 `# DRAFT` 残留**
5. `--headless --quit` 无脚本错误，`tests/run_tests.gd` 全绿

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家试玩 | 每次运行 | 开局有街机速度感；每次击打速度渐进加压；发球/反弹可控可预期，不靠随机坑人 |
| B | 用户定稿（v4 队列） | 每次草稿 merge 后 | GitHub Assigned to me 攒批处理：打开 Issue → 对照候补值表微调 constants.gd → push 定稿 → close |
| C | implement agent 填草稿 | 本管线一次 | 按 taste 方向把草稿值写入 constants.gd（`# DRAFT` + 影响 + 候补 + 情感断言），并建 docs/TASTE.md 初版 |
| D | review agent 定稿就绪检查 | 每次实现 PR | 结构完整（可编译可运行）+ taste 方向对齐（对照审美坐标/TASTE.md 逐项比对）；机械部分无 `# DRAFT` 残留 |
| E | CI/测试 | 每次提交 | `run_tests.gd` 全绿 —— 机械测试断言随草稿值更新，不硬编码旧字面量 |

### 技术约束（继承自 Issue #367）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，只改 `mini-pong/`（自有 `project.godot`） |
| 参数位置 | 手感参数集中在 `mini-pong/gdscripts/constants.gd` 单一文件 |
| 所有权 | taste-draft：PR 用 `parent #N`（小写 p）不写 Closes；草稿达标即 merge，不等人定稿 |
| 反例约束 | 不要让球速在单次 rally 内跳变超过 20%（廉价感）→ 单次击打增量须 ≤ ~1.2× |
| 测试基线 | #346 修复后全绿套件（run_tests.gd 聚合 14 套件 + auto_play_test） |
| 视觉基线 | #289 霓虹赛博（高饱和 + 暗底 #0a0a12）已落地 |

---

## 2. 设计意图

### 为什么现在做

这是 v4 人机共做队列（2026-08-11 拍板）的第一个 A1「数值即表达」内容 Issue：**手感参数不是物理，是表达**。T1/T2/T3 三测全过（两个专家对"弹得爽不爽"答案不同 ✅ / 无法写成 `assert ball.speed == 300` 验证"爽" ✅ / 同样的值换到别的游戏不成立 ✅）→ 人机共做领域。管线语义：agent 生成带 taste 方向的草稿 → **草稿达标即 merge**（结构可用）→ assign 用户定稿（显式队列，不阻塞下游机械 Issue）。本 Issue 的产出物是"草稿 + 校准接口"，不是最终手感。

### 审美坐标与 taste 方向（研究关键发现）

Issue 注入的审美坐标：**手感目标 = 街机爽感**——利落的击打感、逐渐加压的紧张感、可控性优先于随机性。情感断言模板：球速曲线应让玩家感到"**每一次反弹都更紧迫**"，而非"球突然失控"。

Obsidian 知识库检索（`/Volumes/Obsidian/Knowledge Ocean/wiki/`）找到的可迁移设计语言：

| 笔记 | 可迁移到本 Issue 的设计语言 |
|------|---------------------------|
| `独立游戏开发与设计思路讨论.md` | "好玩"不是问出来的，是**观察玩家在什么节点产生反应**（犹豫/投入/爽感/调动）；马里奥网球/赛车 = 必杀技**打破运动规则**制造动态变化 → Pong 的对应物 = 速度递增的"加压"是 rally 内的动态变化 |
| `体验引擎-glossary.md` | **Challenge（挑战）** = 对玩家技能的考验，产生**紧张感和精通的潜力** → 逐渐加压的紧张感的理论依据 |
| `体验引擎-patterns.md` | **隐式难度选择**（Implicit Difficulty Selection）：让玩家的选择自然选择难度，显式难度菜单傲慢且校准不良 → AI 强度草稿应"先松后紧"、可被玩家的节奏自然调节，而非一刀切 |
| `体验引擎——游戏设计全景探秘.md` | 价值对：**胜/败 = 竞技满足感**；**技巧/无能 = 精通进程** → 球速/AI 曲线服务于"竞技满足感"与"精通进程" |
| `CUSGA 2026 游戏评选笔记.md` | 反面样本：多款游戏"手感待打磨"被评委点名 → 手感是评审级体验要素，值得人机共做 |

**taste 方向综合（本 PRD 的注入方向，即 TASTE.md 初版的方向）**：

1. **利落击打感**：击打反馈要"干脆"——开局速度不拖沓（300→330 量级）、反弹角度锐利但不失控（50–60°）、每次击打有可感知的加速（+5~8%）。
2. **逐渐加压的紧张感**：速度曲线指数递增 + 上限钳制（cap 1.8–2.0×），让"每一次反弹都更紧迫"；**严禁单次 rally 内跳变 > 20%**（per-hit 增量 ≤ ~1.10 安全）。
3. **可控性优先于随机性**：发球散布收窄（45°→~30°）、反弹角线性映射保留（中心=平直、边缘=锐角）、AI 失误可见可预期（error 20–28px）——随机性只做"调味"不做"主宰"。
4. **挑战但不作弊**：AI 反应延迟下限抬升（0.1→0.15s 量级）、追击速度略增（1.2→1.25 量级）——给玩家"紧咬比分"的压迫感，但保留可战胜窗口。

### 先前约束

| 约束 | 细节 |
|------|------|
| 目录边界 | 只改 `mini-pong/`（manifest 子项目结构） |
| 引擎版本 | Godot 4.7.1，`config/features=PackedStringArray("4.7")` |
| 参数消费链 | `constants.gd` → `ball.gd`/`paddle.gd` 的 `@export` 默认值 → 运行时。**场景无导出覆盖**（已验证 Main.tscn 仅 `mode = 1`），改常量即改手感 |
| 测试基线 | #346 修复后全绿；`test_constants.gd` TC6 断言精确字面量（改值必红，需同步更新） |
| 自动对打 | `tests/auto_play_test.gd`（#297）已存在 = 试玩剧本的"自动对打"载体，直接复用不重建 |
| E2E | `e2e_shots.json` autoplay 用 `ai_position_error=200` 覆盖（仅 E2E 截图用），与草稿值不冲突 |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/gdscripts/constants.gd` | 手感参数单一事实源 | 修改：球速/反弹角/AI/操控参数改为草稿值，每条带 `# DRAFT` 注释（该值影响什么 + 2–3 候补值 + 情感断言） |
| `docs/TASTE.md` | 品味档案（v4 语义） | **新增**：初版 = 候补值表（参数 × 现值 × 草稿 × 候补 × 影响 × 情感断言）+ 试玩剧本（自动对打 + 手动一局操作流程） |
| `mini-pong/tests/test_constants.gd` | 常量测试 | 修改：TC6 字面量断言随草稿值更新（机械部分，无 `# DRAFT` 残留） |
| `mini-pong/tests/test_ai_paddle.gd` | AI 测试 | 修改：TC-B2/3/4 硬编码的 `400.0 * 1.2` / `400.0 * 0.8` / 阈值 40 随草稿值更新（或改为从 CONSTS 读取） |

### 新增文件

| 文件 | 用途 |
|------|------|
| `docs/TASTE.md` | 品味档案初版：候补值表 + 试玩剧本 + 情感断言（校准接口三件套的文档载体；用户定稿差异后续回写此文件） |

### 间接影响

| 模块 | 影响 |
|------|------|
| `ball.gd` / `paddle.gd` | **零代码改动** —— `@export` 默认值跟随 CONSTS 自动生效 |
| `test_ball.gd` | 本地 `const`（300.0 等）是测试夹具，非断言目标 —— 预期无影响（TC6 才是断言源） |
| `auto_play_test.gd` | 零改动 —— 纯消费者，草稿值变化后自动在新参数下跑 100 局 |
| `e2e_shots.json` | 零改动 —— autoplay tweak 值仅供 E2E 截图，与草稿值正交 |
| `run_tests.gd` | 零改动 —— 套件入口不变 |
| GDD `13-BALL-PHYSICS.md` | 不改（草稿值会变，GDD 记录机制不记录过程值；定稿后由 review agent 按需更新） |

### 数据流

```
GameConstants（constants.gd，# DRAFT 草稿值 + 影响 + 候补 + 情感断言注释）
    │  @export 默认值（ball.gd / paddle.gd，场景无覆盖）
    ▼
运行时手感（球速曲线 / 反弹角 / AI 强度）
    │
    ├──► 玩家试玩：自动对打（auto_play_test.gd 100 局）+ 手动一局（图形模式）
    │
    ▼
docs/TASTE.md（候补值表 + 情感断言 + 试玩剧本）← 校准接口
    │  （用户定稿时对照微调 constants.gd → close）
    ▼
定稿差异回写 docs/TASTE.md（品味档案累积，形成下次草稿的 taste 方向）
```

---

## 4. 方案对比

### 4.1 草稿值承载方式

**Approach A：全部内联 `constants.gd`（推荐）**

草稿值直接写在 constants.gd，每条参数带多行注释：`# DRAFT` 标记 + "该值影响什么" + 2–3 个候补值 + 情感断言。候补值表/试玩剧本等长文本放 docs/TASTE.md。

- Pros：符合 AC1 "手感参数集中在 constants.gd 单一文件，agent 填值带 # DRAFT 注释 + 影响说明 + 候补值"；实现改动最小；review agent 一眼可见全部草稿
- Cons：注释行数会增加 constants.gd 体积（11 个参数 × ~4 行注释 ≈ +45 行）
- Risk: Low ／ Effort: 0.5 天

**Approach B：常量只放草稿值，候补/情感断言全放 TASTE.md**

constants.gd 只写 `# DRAFT 330.0`，候补值与情感断言全部放 TASTE.md 表格。

- Pros：constants.gd 干净
- Cons：**违反 AC1 字面要求**（"带 # DRAFT 注释 + 该值影响什么 + 2-3 个候补值"要求注释内联）；review agent 要跨文件对照，taste 方向散落
- Risk: Med ／ Effort: 0.5 天

**Approach C：独立 JSON 参数表 + 运行时读取器**

新增 `feel_params.json`，运行时加载覆盖 constants。

- Pros：参数可热更新
- Cons：**过度设计** —— 参数已全部 `@export`，编辑器即可调；引入读取器破坏 #295 的单一事实源；机械复杂度上升与 A1 领域（人机共做）背道而驰
- Risk: High ／ Effort: 2 天

### 4.2 校准接口（候补值表 + 试玩剧本）形态

**Approach A：docs/TASTE.md 初版（推荐）**

新建 `docs/TASTE.md`：**候补值表**（参数 × 现值 × 草稿值 × 候补值 × 该值影响什么 × 情感断言）+ **试玩剧本**（① 自动对打：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 中的 Auto-Play 套件跑 100 局，观察无崩溃/无卡死；② 手动一局：`godot --path mini-pong/` 图形模式，按 SPACE 开始，打一局 vs AI，按体验清单逐项打勾）。

- Pros：一次落地 v4 语义要求的品味档案；用户定稿的对照物与反馈记录点同文件；三件套（试玩剧本/候补值表/情感断言）全部有家
- Cons：TASTE.md 初版即承载草稿（严格说是"草稿表"而非"定稿记录"）—— 需在文件头注明初版语义
- Risk: Low ／ Effort: 0.5 天

**Approach B：独立 `docs/CALIBRATION-367.md`**

单独建校准文档，TASTE.md 等定稿后再建。

- Pros：职责分离清晰
- Cons：v4 语义要求品味档案项目内常驻；多一个文件 = 多一处散落；Issue 引用"朝 TASTE.md 方向"，说明 TASTE.md 就是预期载体
- Risk: Med ／ Effort: 0.5 天

**Approach C：只注释不建文档**

候补值/情感断言全部塞在 constants.gd 注释里，不建 TASTE.md。

- Pros：零新增文件
- Cons：**违反 AC3**（校准接口三件套需"候补值表"形态）；试玩剧本无处安放；用户定稿无对照表
- Risk: High ／ Effort: 0 天

### 4.3 研究推荐的草稿值集合（implement 落 `# DRAFT` 的输入）

> 依据：Issue 审美坐标 + Obsidian 设计语言（§2）+ 反例约束（单次 rally 跳变 ≤20%）。**这些是 research 建议，implement 可微调，但必须带齐 影响/候补/情感断言 三要素**。

| 参数 | 现值（物理正确） | 草稿建议 | 候补值 | 该值影响什么 | 情感断言（体验引擎） |
|------|:---:|:---:|:---:|------|------|
| `BALL_INITIAL_SPEED` | 300.0 | **330.0** | 320 / 340 | 开局节奏与横穿时间（1280px：300→4.3s，330→3.9s） | 利落开局——第一拍就有街机速度感 |
| `BALL_SPEED_INCREMENT` | 1.05 | **1.07** | 1.06 / 1.08 | 每次击打加速幅度（指数曲线斜率；1.07^10≈1.97 恰好触顶） | 每一次反弹都更紧迫（单次 +7%，远低于 20% 廉价感红线） |
| `BALL_MAX_SPEED_MULTIPLIER` | 2.0 | **1.9** | 1.8 / 2.0 | 速度上限（330×1.9≈627 px/s ≈ 2.0s 横穿）——上限越高越易"突然失控" | 高压但可控——紧张峰值不越过"失控"阈值 |
| `BALL_MAX_BOUNCE_ANGLE` | 60.0 | **55.0** | 50 / 60 | 边缘击打的锐利度（影响偏移 → 角度线性映射的斜率） | 利落击打感——角度干脆但不刁钻到不可救 |
| `BALL_SERVE_ANGLE_RANGE` | 45.0 | **30.0** | 25 / 35 | 发球散布宽度——随机性对开局的主导权 | 可控性优先——发球不靠随机坑人，胜负交给 rally |
| `PADDLE_SPEED` | 400.0 | **430.0** | 420 / 450 | 玩家操控响应速度（球速加快后必须跟得上） | 跟手——玩家感到"够得着"，挫败来自判断而非操作延迟 |
| `AI_REACTION_DELAY_MIN` | 0.1 | **0.15** | 0.12 / 0.2 | AI 反应下限（0.1s ≈ 人类顶尖反应，显作弊） | 挑战但不作弊——快但可被读 |
| `AI_REACTION_DELAY_MAX` | 0.3 | **0.4** | 0.35 / 0.45 | AI 反应上限 = 玩家喘息窗口 | 给玩家呼吸空间——紧张与放松交替（张力曲线） |
| `AI_POSITION_ERROR` | 20.0 | **24.0** | 20 / 28 | AI 失误幅度（可见可预期的犯错空间） | 人可战胜——失误是"人性"，不是 bug |
| `AI_SPEED_BOOST` | 1.2 | **1.25** | 1.2 / 1.3 | AI 远距离追击速度 | 紧咬比分——压力渐进（隐式难度选择：玩家越快 AI 越咬） |
| `AI_SPEED_SLOW` | 0.8 | **0.75** | 0.7 / 0.8 | AI 接近目标后的缓速（精准度） | 精准但不机械——到位后不抽搐 |

### 推荐与理由

**4.1 选 A（内联 constants.gd）+ 4.2 选 A（docs/TASTE.md 初版）**：

1. AC1 字面要求草稿值 + 影响 + 候补值内联在 constants.gd —— 只有 4.1-A 满足；
2. AC3 要求"候补值表 + 试玩剧本 + 情感断言"三件套成体系 —— 4.2-A 用 TASTE.md 一次承载，同时落地 v4 的品味档案语义（用户定稿差异回写同一文件）；
3. 参数消费链已验证无场景覆盖（§3），改 constants.gd 即改手感，无需任何运行时机制 —— C 方案（JSON 读取器）是纯浪费。

---

## 5. 边界条件与验收标准

### 验收标准（映射 Issue 5 条 AC）

- [x] **AC1: 草稿值集中在 constants.gd 单一文件** — 11 个参数（§4.3）带 `# DRAFT` 注释；每条注释含"该值影响什么" + 2–3 候补值
  - 验证：`grep -c "# DRAFT" mini-pong/gdscripts/constants.gd` ≥ 11；抽查 3 条注释三要素齐全
- [x] **AC2: 每条草稿值附情感断言** — 注释含"情感断言"字段（体验引擎词汇：利落击打感/逐渐加压的紧张感/可控性/挑战但不作弊…）
  - 验证：`grep -c "情感断言" mini-pong/gdscripts/constants.gd` ≥ 11；TASTE.md 表中同字段齐全
- [x] **AC3: 校准接口三件套齐全** — docs/TASTE.md 含：试玩剧本（自动对打复用 auto_play_test.gd + 手动一局步骤清单）+ 候补值表 + 情感断言列
  - 验证：TASTE.md 三节齐全；自动对打步骤可复现（`godot --path mini-pong/ --headless --script tests/run_tests.gd` 含 Auto-Play 套件）
- [x] **AC4: 机械部分无 `# DRAFT` 残留** — 除 constants.gd（草稿层）与 TASTE.md（文档）外，无任何 `# DRAFT`
  - 验证：`grep -rn "# DRAFT" mini-pong/ --include="*.gd" | grep -v constants.gd` 为空
- [x] **AC5: headless 无脚本错误 + 测试全绿** — `godot --path mini-pong/ --headless --quit` 退出码 0 无 push_error；`tests/run_tests.gd` 全绿（含更新后的 TC6 / TC-B2/3/4）
  - 验证：本机跑两命令；CI 同款命令通过

### 边界条件

1. **单次 rally 速度跳变 ≤20%（反例红线）**：per-hit 增量（`BALL_SPEED_INCREMENT`）须 ≤ ~1.20；§4.3 建议 1.07 安全。任何候选值超出红线即视为违反 Issue 情感断言。
2. **测试字面量同步**：`test_constants.gd` TC6 与 `test_ai_paddle.gd` TC-B2/3/4 的硬编码字面量必须随草稿值更新（机械部分，无 `# DRAFT` 标记）；漏改 = 全红。
3. **headless vs 图形**：手动一局试玩需要图形环境；headless 下只有自动对打可跑 —— 试玩剧本须区分两种模式，且 headless 步骤不得依赖图形输入。
4. **`test_ball.gd` 本地 const 是夹具**：其 300.0/1.05 等为测试场景构造值，非断言目标 —— 不需要改，也不要误当草稿值改。
5. **E2E autoplay 覆盖**：`e2e_shots.json` 的 `ai_position_error=200` 仅用于 E2E 截图（故意放水 AI 让球能得分），与草稿值正交 —— 不要为了 E2E 改草稿值，也不要删 E2E tweak。
6. **TASTE.md 初版语义**：初版是"草稿表 + 试玩剧本"（记录 agent 草稿），不是"定稿差异记录"；文件头注明，避免与 v4 的"定稿差异回写"语义混淆。
7. **`SERVE_DELAY=0.5` 与 `BOUNCE_COOLDOWN_FRAMES` 等非手感参数**：不在本 Issue 三组范围（球速/反弹角/AI强度），保持现值，不标 DRAFT。

### 失败路径

1. **漏改测试断言**：TC6/TC-B2/3/4 仍断言旧字面量 → 套件红。缓解：implement 在改 constants.gd 的同一次提交更新测试；review agent 用 AC5 全绿卡口。
2. **DRAFT 注释格式不统一**（缺候补值/缺情感断言）→ review agent 定稿就绪检查打回重写。缓解：PRD §4.3 给出每参数的完整三要素模板。
3. **TASTE.md 表结构不齐** → 用户无法对照定稿。缓解：review agent 按 AC3 三节齐全检查。
4. **草稿值违反 20% 红线**（如 increment 1.25）→ 直接违反 Issue 情感断言。缓解：review agent 对照 §5 边界 1 逐参数校验。
5. **并发 agent 同时改 constants.gd**（多 agent 工作流）→ 冲突。缓解：本 PR 只改 mini-pong/ 内文件 + docs/TASTE.md；merge 前 `git pull origin main` 复查。

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|------|
| #287 球物理（ball.gd 参数消费链） | ✅ CLOSED | 无 |
| #290 AI 对手（paddle.gd AI 模式） | ✅ CLOSED | 无 |
| #289 霓虹赛博视觉（审美坐标来源） | ✅ CLOSED | 无 |
| #295 constants 迁移（单一事实源） | ✅ CLOSED | 无 |
| #297 AI 自动对打测试（试玩剧本自动对打载体） | ✅ CLOSED | 无 |
| #346 测试基线修复（全绿基线） | ✅ CLOSED | 无 |

```
#287 → #295 → #289 ─┐
#290 ───────────────┼──► #367（本 Issue，草稿 + 校准接口）
#297 ───────────────┘        │
                             ▼
                    docs/TASTE.md（品味档案初版）──► 用户定稿（Assigned to me 队列）
```

**无阻塞。** v4 语义：本 Issue 是 human Issue（taste-draft），**不进依赖链** —— 草稿 merge 即满足下游依赖，下游机械 Issue 不等用户定稿。

---

## 7. Spike / 实验

Skipped per `depth/light`（game-to-issues JSON `depth: light`；Section 7 仅 `depth/deep` 必填）。手感参数的可调性已由 `@export` + 场景无覆盖验证（§3），无需 spike。

---

## 8. 延续上下文（Continuation Context）

**给 plan agent 的手递**（plan agent 产出 DESIGN 时直接采用，无需重扫源码）：

**系统状态**：`constants.gd` 为手感参数单一事实源，11 个可草稿参数（球速 4 + 反弹角 1 + AI 5 + 操控 1，见 §4.3）；消费链 `CONSTS → ball.gd/paddle.gd @export 默认值`，场景无导出覆盖；`auto_play_test.gd` 可复用为自动对打；`docs/TASTE.md` 尚不存在（需新建）；`test_constants.gd` TC6 与 `test_ai_paddle.gd` TC-B2/3/4 断言精确字面量（改值必红）。

**主风险**：
1. 测试字面量漏改 → 全红（§5 失败路径 1）
2. 草稿值超 20% 红线 → 违反情感断言（§5 边界 1）
3. TASTE.md 初版语义混淆（草稿表 ≠ 定稿记录）（§5 边界 6）

**下一步（plan → implement）**：
1. DESIGN 引用本 PRD §4.3 草稿值集合（含候补/影响/情感断言），逐参数列为常量修改清单
2. DESIGN 明确 docs/TASTE.md 初版结构（候补值表 + 试玩剧本 + 情感断言三节）
3. implement 一次性提交：constants.gd 草稿值 + 注释 → test_constants.gd/test_ai_paddle.gd 字面量同步 → docs/TASTE.md 初版
4. review agent：定稿就绪检查（结构完整 + taste 方向对齐 + 机械无 DRAFT 残留）→ merge（PR 用 `parent #367`）→ 打 `status/human-review` + assign 用户
5. 用户定稿差异回写 docs/TASTE.md —— 下次同类草稿的方向来源
