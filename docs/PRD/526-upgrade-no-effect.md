# PRD #526 — [Bug] 三选一升级物品没效果

> 类型: bug 调查 PRD（bug pre-investigation 流程）
> 引擎/目录约束: Godot 4.7.1 / `mini-pong/`（720x1280 竖屏，resizable=false）
> 深度: 无 `depth/` label → 按 standard（Section 1–6 + 8 必填，Section 7 因已执行取证实验而纳入）
> 前置 Issue: #387 升级池架构、#388 3选1升级UI、#395 升级池文案定稿、#384 砖墙网格（均已落地）

---

## 1. Problem Definition

### 1.1 现象（issue 原文）

> 选了加宽板子的升级，但板子并没有变宽，检查其他升级，看是否也没效果。
> 复现：游戏运行到可以选择升级项 → 选择加宽板子升级项 → 观察。

### 1.2 预调查结论表（bug-pre-investigation 流程）

| Issue 声明 | 预调查结果 |
|-----------|-----------|
| 选"加宽板子"升级后板子没变宽 | ❌ **仍然 broken（本 PRD 主修复目标）** — headless 取证确认：`set_paddle_width(156)` 后 `CollisionShape2D.shape.size.x = 156`（碰撞已同步）但 `ColorRect` offset 仍 `-60..60`（视觉 120px 不动），玩家看到的板子视觉宽度不变 |
| 检查其他升级是否也没效果 | ⚠️ 部分成立 — 9 个升级中 6 个机械生效（可代码级断言），3 个（双生/星尘/幻影）是 #387 §3.1 明示的**桩效果**：玩家选中后无任何可见反馈，体验上等同"没效果" |
| 是否有历史修复 | ✅ 无 — `git log --all` 无 #526 相关提交；当前 main 即 bug 现场 |

### 1.3 受影响系统（当前行为）

| 文件 | 模块 | 当前行为 |
|------|------|---------|
| `mini-pong/gdscripts/paddle.gd` | 挡板实例化参数 | `set_paddle_width(w)`（L108–122）只更新 `paddle_width` 变量 + `CollisionShape2D.shape.size.x` + `_recalc_bounds()`；**不更新视觉 ColorRect** |
| `mini-pong/scenes/player_paddle.tscn` | 挡板场景 | `ColorRect` offset 硬编码 `-60..60`（120px 固定），与 `RectangleShape2D` size `(120,20)` 各自独立 |
| `mini-pong/gdscripts/upgrade_defs.gd` | 升级定义 | `long_arm` 回调正确调用 `paddle.set_paddle_width(...)`（+30% 基数加算）；`twin/stardust/phantom` 为桩回调（只写 `stub_activated` + push_warning） |
| `mini-pong/gdscripts/upgrade_pool.gd` | 升级池 | `_build_ctx()` 经 `paddles` 组惰性解析 paddle（PlayerPaddle 树序在前）；`get_candidates()` 不排除桩升级 → 桩可被抽中 |
| `mini-pong/gdscripts/upgrade_pick_ui.gd` | 3选1 UI | 选中 → `UpgradePool.apply(id)` → 效果回调；UI 本身工作正常（issue 复现步骤 1–2 成立） |
| `mini-pong/tests/test_upgrade_pool.gd` | 测试 | `FakePaddle` 只断言 `paddle_width` 变量与 `set_paddle_width` 调用次数，**不覆盖真实场景的视觉同步** |
| `mini-pong/tests/test_paddle.gd` | 测试 | TC-F1 只断言 `CollisionShape2D.size.x` 同步（DESIGN #387 验收原文），无 ColorRect 断言 |

### 1.4 9 升级效果审计表（issue 要求"检查其他升级"）

| id | 名称 | 稀有度 | 效果 | 代码审计 | 玩家可感知 |
|----|------|--------|------|---------|-----------|
| `long_arm` | 长臂 | 普通 | 挡板 +30%（基数加算，最多 3 层） | ⚠️ 碰撞生效、**视觉不同步** | ❌ 视觉无变化（本 bug 主诉） |
| `fireball` | 燃烧弹 | 普通 | 球速 +10% + 爆炸碎邻近砖 | ✅ `ball.speed` 封顶乘 + `blast_neighbors` | ✅ 破砖可见 |
| `battering_ram` | 破城锤 | 普通 | 破砖冲击波碎邻近砖 | ✅ `blast_neighbors`（radius 120） | ✅ 破砖可见 |
| `magnet_core` | 磁心 | 稀有 | 挡板磁力吸球 | ✅ `paddle.magnet_enabled = true` | ✅ 球被牵引 |
| `twin` | 双生 | 稀有 | 球分裂为二 | ⚠️ **桩**（#387 §3.1 明示，随 #384 落地后深化） | ❌ 无反馈 |
| `slow_time` | 缓时 | 稀有 | 球速冻结 2s | ✅ `ball.set_speed_scale_timed(0, 2)` | ✅ 球冻结可见 |
| `pre_hole` | 预开洞 | 稀有 | 下波砖墙预开洞 | ✅ `open_hole` 挂起队列（#393 附录 B.3） | ✅ 下波墙有洞 |
| `stardust` | 星尘 | 传说 | 穿墙轨迹伤害 | ⚠️ **桩** | ❌ 无反馈 |
| `phantom` | 幻影 | 传说 | 挡板残影多段判定 | ⚠️ **桩** | ❌ 无反馈 |

**结论：主诉 bug = `long_arm` 视觉不同步；"其他升级没效果" = 3 个设计内桩升级未从候选池剔除，玩家选中即"无效"。**

### 1.5 期望行为

1. 选择长臂后，板子的**视觉宽度**立即（下一帧）与 `paddle_width` 一致（+30% 肉眼可见）。
2. 碰撞/边界行为保持现状（已正确）。
3. 出现在候选池的每个升级，选中后必须有**至少一条可见/可感反馈通道**（视觉/行为/数值）。
4. 未实现的桩升级（双生/星尘/幻影）不再出现在候选池，直到完整实现落地。

### 1.6 用户场景

| 场景 | 频率 | 描述 |
|------|:---:|------|
| A: 玩家选长臂 | 高（普通稀有度 60% 权重） | 期望板子明显变宽，实际无视觉变化 → 困惑、认为游戏坏了 |
| B: 玩家选桩升级 | 中（稀有 30% / 传说 10%） | 选中双生/星尘/幻影 → 无任何反馈 → 信任受损（情感误归因反噬，见 §2） |
| C: 玩家二次堆叠长臂 | 中 | +30% → +60% 视觉应连续放大且 clamp 边界正确 |

---

## 2. Design Intent

### 2.1 为什么当前行为存在

| Issue | 决策 | 缺口 |
|-------|------|------|
| #387 PRD（升级池架构） | 明确"升级改宽度时需同步改 shape（或运行时 set）" | 只提 CollisionShape，**未提视觉 ColorRect** |
| #387 DESIGN | TC-F1 验收 = `set_paddle_width` 后 `CollisionShape2D.size.x` 同步；AC3 验证只写"实例属性变化 + 碰撞 shape 同步" | **视觉同步从未进入验收标准** → 测试自然不覆盖 |
| #387 §3.1 | 桩决策：twin/stardust/phantom 效果回调为"可调用、可断言、不崩溃的桩"，完整实现"随 #384 落地后独立小 PR 深化" | #384 已落地（breakout_grid.gd 存在），**桩回收从未执行**，且候选池不排除桩 |
| #388/#393 | 3选1 UI + Main.tscn 组装完整 | 组装后真实玩家首次触达升级系统，bug 才暴露 |

根因链：**设计验收只看物理层（碰撞 shape），遗漏表现层（视觉节点）**；测试用 FakePaddle 进一步把断言锁定在变量层，两层叠加使"视觉不同步"成为测试盲区。

### 2.2 为什么现在修

1. 玩家可见 bug 实锤（headless 取证 + issue 复现路径一致）。
2. 升级系统是波次成长核心（PLAN-rogue-pong §2.5 情感设计：可预测奖励变无聊 → 3选1+稀有度 = 不可预测性）；"选了没反应"直接摧毁该情感设计前提（情感误归因：玩家把挫败归因于升级系统而非玩法）。
3. 修复面小（paddle.gd 一个函数 + 池过滤一行），风险低。

### 2.3 前序约束（PRD 继承，实施不得破坏）

| 约束 | 详情 | 来源 |
|------|------|------|
| 参数实例化 | `const` → `@export`，默认值仍 = CONSTS（`PADDLE_WIDTH=120` / `PADDLE_HEIGHT=20`） | #387 AC3 |
| 碰撞即时感知 | 球读 `CollisionShape2D.shape.size.x` → 长臂后下一帧生效 | #387 DESIGN §4.3 |
| 加算语义 | 长臂对**基数**加算：两次 → +60%（156→192） | #387 DESIGN §5 决策 4 |
| 竖屏尺寸 | 720×1280，挡板横置 120×20 | #383 |
| 霓虹材质 | ColorRect 挂 `neon_glow_material.tres` | #392（改 offsets 不得动 material） |
| 边界 clamp | `_recalc_bounds()` 半宽 clamp，长臂多次堆叠不得越界 | #383/#387 边界 6 |

---

## 3. Impact Analysis

### 3.1 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/gdscripts/paddle.gd` | 挡板 | **修改**：`set_paddle_width()` 增加视觉同步（ColorRect offsets）；`_ready()` 统一走视觉初始化（消除场景硬编码与实例变量的双源） |
| `mini-pong/tests/test_paddle.gd` | 测试 | **修改**：TC-F1 扩展 + 新增 ColorRect 宽度断言（场景级实例化） |
| `mini-pong/gdscripts/upgrade_pool.gd` | 升级池 | **修改**：`get_candidates()`/`_available` 排除桩升级（或 `upgrade_defs.gd` 增加 `is_stub` 标记） |

### 3.2 新文件

| 文件 | 说明 |
|------|------|
| 无（修复全部落在现有文件；如需场景级测试基建，扩展 `test_paddle.gd` 即可） | — |

### 3.3 间接影响

| 文件 | 影响 |
|------|------|
| `mini-pong/scenes/player_paddle.tscn` | 视觉宽度改由运行时派生后，场景内 ColorRect offset 硬编码可保留（作为初始值）或清理；推荐保留不动以最小化场景 diff，由 `_ready()` 运行时覆盖 |
| `mini-pong/tests/test_upgrade_pool.gd` | FakePaddle 不变（变量层断言仍有效）；可在 E 场景补充真实 paddle 集成断言（可选） |
| `mini-pong/assets/content/upgrade_pool.json` | 不改（文案 #395 已定稿；桩升级文案保留，待实现后复用） |
| `docs/GAME_DESIGN/` | 升级章节补充"效果必须有可见反馈通道"约束（review agent post-merge 增量更新） |

### 3.4 数据流影响

```
UpgradePickUI._confirm()
    │  UpgradePool.apply(id)                      ✅ 已接线 (#388/#393)
    ▼
UpgradePool.apply → def.effect.call(ctx)
    │
    ▼
long_arm: paddle.set_paddle_width(w)
    ├── paddle_width = w                          ✅ 已实现
    ├── CollisionShape2D.shape.size.x = w         ✅ 已实现（球即时感知）
    ├── _recalc_bounds()                          ✅ 已实现（clamp）
    └── ColorRect offsets ← w/2                   ❌ 缺失 ← 本 PRD 主修复
                                                    （现为场景硬编码 -60..60）
```

### 3.5 文档更新 checklist

- [x] 本 PRD（docs/PRD/526-upgrade-no-effect.md）
- [ ] GDD 升级章节：效果可见反馈约束（review agent post-merge）
- [ ] （若实施池过滤）#387 DESIGN §3.1 桩决策备注：桩升级排除出候选池

---

## 4. Solution Comparison

### 4.1 长臂视觉同步方案

| 方案 | 描述 | Pros | Cons | Risk | Effort |
|------|------|------|------|:----:|:------:|
| **A: `set_paddle_width` 内同步视觉（推荐）** | `set_paddle_width(w)` 内加 `half = w/2` → `ColorRect.offset_left = -half; offset_right = half`；`_ready()` 抽 `_sync_visual()` 统一初始化（含 `paddle_height` 对称处理 offset_top/bottom）；场景硬编码 offsets 保留作初始值 | 单点修复（paddle.gd 一函数）；paddle_width 成为碰撞+视觉单一事实源；玩家/AI 双挡板同场景同修复；不碰霓虹 material | 需在 `_ready` 前 ColorRect 存在（场景内固定，无风险） | **Low** | 0.5 天 |
| B: 节点结构改造（Container/anchor 自动跟随） | ColorRect 包进 Control/Container，用 anchors 或 `custom_minimum_size` 由 paddle_width 驱动 | 结构上"自动" | 场景结构重构侵入大；霓虹材质/边框样式回归风险（#392）；diff 大，review 成本高 | Med | 1–2 天 |
| C: 只改碰撞、不修视觉（拒绝） | 维持现状 | 零改动 | 玩家可见症状不消除，bug 不成立 | High | — |

**推荐 A，理由：**
1. 根因是"表现层未同步"，A 直接在效果写入点补表现层，语义内聚（`set_paddle_width` 名字即承诺"板子变宽"）。
2. 变更面 = 1 个文件 1 个函数，与 #387 既有实现风格一致（实例属性即时生效，无新机制）。
3. 测试可精确断言：场景级实例化 → `set_paddle_width(156)` → `offset_right - offset_left == 156`。
4. B 的场景重构收益（结构性自动跟随）在当前需求（仅长臂一个升级改宽度）下不成立，纯增风险。

### 4.2 桩升级（双生/星尘/幻影）处理方案

| 方案 | 描述 | Pros | Cons | Risk | Effort |
|------|------|------|------|:----:|:------:|
| **A: 候选池排除桩（推荐）** | `upgrade_defs.gd` 每条定义加 `is_stub: bool`（3 桩 = true）；`upgrade_pool.gd` 初始化 `_available` / `get_candidates()` 过滤 `is_stub`；桩定义保留（文档/未来实现锚点），`stub_activated` 标记逻辑保留供测试 | 立即可做；玩家永远选不到"无效"卡；稀有度回退链（`_fallback_rarity`）天然处理池变小（传说 0 张 → 回退稀有/普通） | 传说稀有度暂不可抽（池内 0 传说）；需确认 60/30/10 抽取在传说空池时行为（已有回退链，TC 覆盖） | **Low** | 0.5 天 |
| B: 本轮实现 3 桩完整效果 | twin 球分裂 / stardust 轨迹伤害 / phantom 残影判定全部实现 | 内容最完整 | 超出 bug 修复范围，等于 3 个功能 Issue 的量；twin 涉及球实例管理、stardust 涉及轨迹伤害判定，风险高 | High | 3–5 天 |
| C: 维持现状（桩留在池中） | 不处理 | 零改动 | 玩家继续抽到"无效"卡，本 issue 的"其他升级也没效果"部分不闭环 | Med | — |

**推荐 A，理由：**
1. 本 issue 是 bug 修复，不是功能开发；B 的正确归宿是独立 feature Issue（随 #384 深化路径已在 #387 §3.1 声明）。
2. A 用一行过滤 + 一个标记即可让"玩家可选的升级 = 全部有效"，与 AC 语义（每个可选升级有可见反馈）一致。
3. 桩定义与测试保留，未来实现时只改 `is_stub=false` 即可回归。

---

## 5. Boundary Conditions and Acceptance Criteria

### 5.1 正常路径 AC（对应 issue body）

- [x] **AC1: 长臂视觉变宽** — 场景级实例化 `player_paddle.tscn`，`set_paddle_width(156)` 后 `ColorRect.offset_right - offset_left == 156`（±0.01），且 `paddle_width == 156`。
  - 验证：headless 场景级测试断言（TC-F1 扩展）；视觉上 120→156 肉眼可辨（+30%）
- [x] **AC2: 碰撞同步不回退** — `set_paddle_width(156)` 后 `CollisionShape2D.shape.size.x == 156`（保持 TC-F1 既有断言）。
- [x] **AC3: 堆叠语义连续正确** — 连续 `apply("long_arm")` 两次：视觉宽度 156 → 192（基数加算 ×1.6），每次视觉与碰撞同步。
- [x] **AC4: AI 挡板同修复** — AIPaddle 与 PlayerPaddle 同场景实例，`set_paddle_width` 对两者视觉一致生效。
- [x] **AC5: 桩升级排除候选池** — `get_candidates(3)` 返回结果不含 `twin/stardust/phantom`；`Defs.by_id` 仍可查（定义保留）。
- [x] **AC6: 其他机械升级可断言生效** — fireball（球速×1.1 封顶）/ battering_ram（blast 调用）/ magnet_core（magnet_enabled）/ slow_time（speed_scale 冻结）/ pre_hole（open_hole 挂起）经现有 TC-E1–E5 全绿 + 场景级抽查。

### 5.2 边界情况（≥5）

1. **宽度越界**：长臂堆满 3 层 → 120×1.9=228 < 720 屏幕，不越界；未来若超屏，`_recalc_bounds()` clamp 半宽（保持 #383 语义）。
2. **ColorRect 缺失**：动态/测试构造的 paddle 无 ColorRect → `_sync_visual()` 判空 no-op（与 `set_paddle_width` 现有 CollisionShape 遍历 fallback 同风格）。
3. **`_ready` 前调用**：`set_paddle_width` 在 `_ready` 前被调（如注入式测试）→ 节点未就绪时视觉同步判空跳过，`_ready` 统一覆盖。
4. **候选池空桩后稀有度分布**：传说 0 张 → `_roll_rarity` 掷出 91–100 时 `_eligible_for` 空 → `_fallback_rarity` 回退稀有/普通（既有逻辑，需 TC 覆盖确认）。
5. **AI 挡板也被升级**：`paddles` 组首节点 = PlayerPaddle（树序），AI 挡板不受玩家升级影响（现状不变，不扩大范围）。
6. **霓虹材质**：改 ColorRect offsets 不影响 `material` 属性与边框色（#392 视觉不回归）。

### 5.3 失败路径（≥3）

1. **`apply` 返回 false**（未知 id / max_stacks 竞态）→ UI 保持打开可重选（#388 边界 2，现状正确，不回归）。
2. **目标缺失**：paddle 不在 `paddles` 组 → 长臂/磁心回调 push_warning + no-op（#387 DESIGN §6 失败路径 2，现状正确）。
3. **测试回归**：`test_paddle.gd` / `test_upgrade_pool.gd` 全绿（CI `--headless --script tests/run_tests.gd`）；若池过滤改变抽取分布，`test_upgrade_pool.gd` TC-A3（稀有度计数）同步更新。

---

## 6. Dependencies and Blockers

### 6.1 Depends on

| 依赖 | 状态 | 风险 |
|------|:---:|:---:|
| #387 升级池架构（9 定义 + apply 链路 + 桩决策） | ✅ merged | 低（本 PRD 在其上打补丁） |
| #388 3选1升级UI（apply 调用点） | ✅ merged | 低 |
| #395 升级池文案（JSON 显示名） | ✅ merged | 低 |
| #384 砖墙网格（桩深化前提，已落地） | ✅ merged | 低（桩回收走独立 Issue，不阻塞本修复） |
| #393 Main.tscn 组装（升级窗口实例化） | ✅ merged | 低 |

### 6.2 Blocks

| 未来工作 | 优先级 | 说明 |
|---------|:---:|------|
| 桩升级完整实现（twin/stardust/phantom） | P1 | #387 §3.1 承诺路径；实现后 `is_stub=false` 回归候选池 |
| 升级效果可见反馈的 taste 深化 | P2 | 若反馈通道需更强表达（如板子变宽动画），走 taste 域 |

### 6.3 依赖链

```
#387 升级池架构 ──► #388 3选1UI ──► #393 Main.tscn 组装 ──► #526 本修复
     │                                                    ▲
     └── #395 文案 ────────────────────────────────────────┘
#384 砖墙网格（桩深化前提，独立路径）──► 未来桩实现 Issue
```

### 6.4 准备清单

- [ ] 实施前跑全量 headless 测试基线（`/usr/local/bin/godot --path mini-pong/ --headless --script tests/run_tests.gd`）
- [ ] 确认 `get_candidates` 桩过滤后的抽取分布测试用例（TC-A3 更新）

---

## 7. Spike / Experiment

> standard 深度下 Section 7 可选；本 PRD 的取证实验已在研究阶段实际执行，记录如下。

### E1: 长臂视觉同步取证（已执行，2026-08-17）

- **问题**: `set_paddle_width` 是否同步视觉节点？
- **方法**: headless 实例化 `player_paddle.tscn`，调用 `set_paddle_width(156.0)`，打印 ColorRect offsets 与 CollisionShape size。
- **结果**:
  ```
  BEFORE : paddle_width=120  ColorRect width=120  CollisionShape size.x=120
  AFTER  : paddle_width=156  ColorRect width=120  CollisionShape size.x=156
  VERDICT: BUG_CONFIRMED (visual frozen at 120, collision 156)
  ```
- **影响**: 主诉 bug 实锤；修复方案 A 的目标状态 = ColorRect width 156。

### E2: 测试盲区取证（已执行）

- **问题**: 现有测试为何没拦住？
- **方法**: 读 `test_upgrade_pool.gd`（FakePaddle 仅变量断言）+ `test_paddle.gd` TC-F1（仅 CollisionShape 断言）。
- **结果**: 两层断言都不到表现层 → 视觉不同步是测试盲区。
- **影响**: 方案 A 必须配套场景级 ColorRect 断言（AC1），否则回归无门。

### E3: 桩过滤后的抽取分布验证（建议 implement 阶段执行）

- **问题**: `_available` 排除 3 桩后，`get_candidates(3)` 在传说空池时回退链是否稳定、候选恒 ≥1？
- **方法**: 修改后跑 `test_upgrade_pool.gd` TC-A3/TC-B1/TC-D3 + 新增"桩不出现在候选"断言。
- **预期**: 回退链（`_fallback_rarity`）保证候选非空；稀有度计数更新（COMMON=3/RARE=4/LEGENDARY=0）。
- **影响**: 若回退链异常 → 方案 A 需在 `get_candidates` 加空池保护（现状已有 break，风险低）。

---

## 8. Continuation Context

### 8.1 系统状态（交接给 plan agent）

- 升级全链路已组装且工作：`GameManager.wave_settled` → `UpgradePickUI.open` → `UpgradePool.get_candidates(3)` → `apply(id)` → 效果回调（Main.tscn L161 UpgradePickUI 实例、project.godot L22 UpgradePool autoload）。
- 主 bug 定位：`paddle.gd set_paddle_width()` 缺视觉同步；`player_paddle.tscn` ColorRect offset 硬编码 -60..60。
- 次 bug 定位：3 桩升级（twin/stardust/phantom）留在候选池，玩家选中无反馈。
- 取证脚本位置：研究阶段临时脚本（`/tmp/verify_526.gd`），不入库；实施阶段以正式测试替代。

### 8.2 主要风险

| 风险 | 等级 | 缓解 |
|------|:---:|------|
| 霓虹材质视觉回归（改 offsets 动 material） | 低 | 只改 offsets，不碰 material/color；视觉对比测试（test_visual_contrast）回归 |
| 桩过滤改变抽取分布引发 TC 失败 | 低 | 同步更新 TC-A3 稀有度计数；回退链已有 TC-B1 覆盖 |
| AI 挡板被误升级 | 低 | `paddles` 组首节点语义不变；不扩大范围 |

### 8.3 下一步（plan agent 输入）

1. **DESIGN 范围**: ① `paddle.gd` 新增 `_sync_visual()`（offsets ← paddle_width/2 与 paddle_height/2，判空 no-op），`_ready()` 与 `set_paddle_width()` 复用；② `upgrade_defs.gd` 9 定义加 `is_stub` 字段（3 桩 true）；③ `upgrade_pool.gd` `_ready()` 初始化 `_available` 时过滤 `is_stub`（或 `get_candidates` 内过滤）；④ `test_paddle.gd` 新增 TC-F2（ColorRect 宽度断言）+ `test_upgrade_pool.gd` 更新 TC-A3/新增桩过滤断言。
2. **验收红线**: AC1–AC6（§5.1）逐条对应测试；全量 headless 套件绿。
3. **不做**: 桩升级完整实现（独立 Issue）；升级动画/反馈增强（taste 域）；场景结构重构（方案 B 否决）。
4. **Obsidian 知识搜索结论**: vault（/Volumes/Obsidian，Knowledge Ocean）无升级池专篇笔记；相关设计原则——选项反馈分量（"选择了之后，可以靠选项的视觉停留或者全屏效果加强选项的分量"，来自 完美的一天/选项设计类型）、物理随机性=乐趣来源、情感误归因（体验引擎）——已由 PLAN-rogue-pong.md §2.5 引用并在本 PRD §2.2 落地为"效果必须有可见反馈"约束；本次研究未发现需要新增知识库条目。
