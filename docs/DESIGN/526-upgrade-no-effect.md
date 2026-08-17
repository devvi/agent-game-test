# DESIGN: [Bug] 三选一升级物品没效果 — 长臂视觉同步 + 桩升级候选池排除

> **Parent Issue:** #526
> **Agent:** game-plan-agent
> **Date:** 2026-08-17
> **Approach:** A + A（PRD §4.1-A 长臂视觉同步 + §4.2-A 候选池排除桩，逐项确认采纳）
> **Reference PRD:** docs/PRD/526-upgrade-no-effect.md（research PR #528 已合并）
> **深度:** 无 `depth/` label → standard（本 DESIGN 单文档，不产 TASKS：文件域 = 3 源文件 + 2 测试文件，单一子系统，不达 skill TASKS 阈值）
> **所有权:** `content_ownership: mechanical` —— 本修复全部为机制/结构改动，无 taste 占位数值

---

## 1. 架构总览

Issue 主诉「选加宽板子升级没效果」经 research 取证（PRD §7 E1）实锤为**表现层未同步**：
`set_paddle_width()` 只同步实例变量与 `CollisionShape2D.shape.size.x`（碰撞即时生效），
而玩家看到的 `ColorRect` offsets 被场景硬编码 `-60..60` 冻结在 120px。次诉「其他升级也没效果」
经审计（PRD §1.4）定位为 3 个设计内**桩升级**（twin/stardust/phantom，#387 §3.1 决策）未被
候选池过滤，玩家选中即无任何反馈。

本设计按 PRD 两个推荐方案修复，**零新文件、零场景改动**：

```
                     ★ Issue #526 修复（2 个独立修复点）
        ┌─────────────────────────────┴─────────────────────────────┐
        │ 修复点 1: 长臂视觉同步（PRD §4.1-A）          修复点 2: 桩升级排除（PRD §4.2-A）
        ▼                                                     ▼
  paddle.gd（修改）                                      upgrade_defs.gd（修改）
  ├─ 新增 _sync_visual()：ColorRect offsets ←            └─ 9 定义增 is_stub: bool
  │   paddle_width/2、paddle_height/2（判空 no-op）          （twin/stardust/phantom = true）
  ├─ _ready() 接入（运行时覆盖场景硬编码）                upgrade_pool.gd（修改）
  └─ set_paddle_width() 末尾调用（效果写入点补表现层）      └─ _ready() 初始化 _available 时
                                                             过滤 is_stub（玩家永远选不到桩卡）
```

### 设计哲学

1. **单一事实源**：`paddle_width`/`paddle_height` 成为碰撞 + 视觉双通道唯一事实源；
   `set_paddle_width` 名字即承诺「板子变宽」，效果写入点补表现层，语义内聚（PRD §4.1 理由 1）。
2. **场景零 diff**：`player_paddle.tscn` ColorRect offset 硬编码保留作初始值（120×20 时
   `_sync_visual()` 计算结果与硬编码逐位一致 → 初始帧零视觉变化，零回归），由 `_ready()`
   运行时覆盖（PRD §3.3 推荐）。
3. **候选池即契约**：`get_candidates()` 的返回值 = 「玩家可选的升级」= 必须全部有效。
   桩定义与 `stub_activated` 标记逻辑**保留**（#387 §3.1 锚点 + 测试可断言），仅从候选池剔除。
4. **测试分层对齐根因**：PRD §2.1 根因链 = 验收只看物理层 + FakePaddle 把断言锁在变量层。
   本设计在**场景级**（`player_paddle.tscn` 实例化）补 ColorRect 断言，测试层穿透到表现层。
5. **不动霓虹材质**：只改 offsets，不碰 `material`/`color`（#392 视觉零回归，PRD 边界 6）。

### PRD 方案确认

| 决策点 | PRD 推荐 | 本设计 | 说明 |
|--------|---------|--------|------|
| 长臂视觉同步 | §4.1-A：`set_paddle_width` 内同步 + `_ready()` 抽 `_sync_visual()` | ✅ 采纳 | 单点修复，1 文件 1 函数 |
| 桩升级处理 | §4.2-A：`is_stub` 标记 + 候选池过滤 | ✅ 采纳 | 桩定义/测试保留，未来实现只改 `is_stub=false` |
| 场景结构重构（方案 B） | 否决 | ✅ 维持否决 | 侵入大、霓虹回归风险，当前收益不成立 |
| 本轮实现 3 桩完整效果（方案 B） | 否决 | ✅ 维持否决 | 超出 bug 修复范围，归独立 feature Issue |

---

## 2. 现状核实（plan agent 已对照源码确认，2026-08-17）

| 文件 | 现状 | 对本设计的影响 |
|------|------|---------------|
| `mini-pong/gdscripts/paddle.gd` | `set_paddle_width(w)`（L108–122）：更新 `paddle_width` + `CollisionShape2D.shape.size.x` + `_recalc_bounds()`；**无任何 ColorRect 处理**；`_ready()` 无视觉初始化 | 修改点 1 落点：新增 `_sync_visual()` + 两处接入 |
| `mini-pong/scenes/player_paddle.tscn` | ColorRect `offset_left=-60/offset_right=60/offset_top=-10/offset_bottom=10`（120×20），挂 `neon_glow_material.tres`；CollisionShape2D shape `(120,20)` | **不改**；硬编码保留作初始值，`_ready()` 运行时覆盖 |
| `mini-pong/gdscripts/upgrade_defs.gd` | 9 定义，字段 `id/name/rarity/max_stacks/effect_desc/effect`；**无 `is_stub` 字段**；twin/stardust/phantom 走 `_effect_*_stub` 回调（写 `pool.stub_activated` + push_warning） | 修改点 2 落点：9 定义各增 `is_stub`（3 桩 true） |
| `mini-pong/gdscripts/upgrade_pool.gd` | `_ready()`：`_available = Defs.definitions().duplicate()`（9 条全进池）；`get_candidates()`/`apply()` 均以 `_available` 为准；`_fallback_rarity()` 回退链 [COMMON,RARE,LEGENDARY] | 修改点 2 落点：`_ready()` 过滤 `is_stub`；回退链天然处理传说空池 |
| `mini-pong/gdscripts/constants.gd` | `UPGRADE_POOL_SIZE=9`、`UPGRADE_RARITY_WEIGHTS=[60,30,10]`、`UPGRADE_CANDIDATE_COUNT=3` | **不改**（池大小常量指定义数，定义保留） |
| `mini-pong/tests/test_paddle.gd` | 已有 TC-F1（CollisionShape 同步）/TC-F2（recalc bounds）/TC-F3/F4（实例参数）；**TC-F2 编号已被 `_test_recalc_bounds_f2` 占用** | PRD §8.3 所述「新增 TC-F2」编号冲突 → 新用例用 **TC-F5 起**（见 §8） |
| `mini-pong/tests/test_upgrade_pool.gd` | 29 条 A–I 场景；TC-A3 基于 `Defs.definitions()` 计数（9 条）→ **桩过滤后不受影响**；TC-D1/D4 用 stardust 测「整局不可重复」、TC-E4 断言 3 桩 `apply` 返回 true、TC-B2 统计传说占比 ∈[5,15]% → **4 个用例受桩过滤影响需更新** | 见 §3.3 受影响测试表 + §8 测试描述 |
| `mini-pong/scenes/Main.tscn` | L60/L63：`PlayerPaddle` 与 `AIPaddle` 均为 `player_paddle.tscn` 实例（`mode` 区分） | AC4（AI 挡板同修复）自动成立：同一场景脚本，`_sync_visual()` 对两者一致生效 |
| `mini-pong/assets/neon_glow_material.tres` | 共享材质（#392） | **不改**；offsets 改动不触 material |

### PRD 断言 vs 实际代码库（gap 核查）

| PRD 断言 | 实际代码库 | 设计处置 |
|---------|-----------|---------|
| 「test_paddle.gd 新增 TC-F2（ColorRect 宽度断言）」（§1.3/§8.3） | TC-F2 已被 `_test_recalc_bounds_f2` 占用（F1–F4 全占用） | 新视觉断言用 **TC-F5 起**，编号不冲突 |
| 「若池过滤改变抽取分布，TC-A3（稀有度计数）同步更新」（§5.3 失败路径 3） | TC-A3 数 `Defs.definitions()`（9 条保留）→ **不会失败**；真正受影响的是 TC-B2（候选统计分布）与 TC-D1/D4/E4 | 受影响测试 = TC-B2/D1/D4/E4（§3.3）；TC-A3 仅新增 `is_stub` 字段断言 |
| 「传说 0 张 → 回退稀有/普通（既有逻辑，需 TC 覆盖确认）」（§5.2 边界 4） | `_fallback_rarity()` 遍历 [COMMON,RARE,LEGENDARY] 取首个非空；`get_candidates()` 内 `eligible.is_empty()` → break 保护 | 逻辑已具备，TC-B2 更新后覆盖确认；`get_candidates` 候选恒 ≥1（池 6 张 ≫ 3） |
| 「`_ready` 前调用 set_paddle_width」（§5.2 边界 3） | `set_paddle_width` 目前无节点就绪依赖（CollisionShape 遍历 fallback 已处理） | `_sync_visual()` 沿用 `get_node_or_null` 判空风格，天然安全 |

---

## 3. 既有组件修改（本设计无新文件）

### 3.1 `mini-pong/gdscripts/paddle.gd` — 视觉同步（修复点 1）

**新增方法**（仿现有 CollisionShape 遍历 fallback 的判空风格）：

```gdscript
## #526: 视觉同步 — ColorRect offsets ← paddle_width/paddle_height（单一事实源）。
## 场景硬编码（-60..60/-10..10）保留作初始值，_ready() 运行时覆盖（零 diff、零回归）。
## 动态/测试构造的 paddle 无 ColorRect → 判空 no-op（与 set_paddle_width 现有 fallback 同风格）。
func _sync_visual() -> void:
	var cr = get_node_or_null("ColorRect") as ColorRect
	if cr == null:
		return
	var half_w := paddle_width / 2.0
	var half_h := paddle_height / 2.0
	cr.offset_left = -half_w
	cr.offset_right = half_w
	cr.offset_top = -half_h
	cr.offset_bottom = half_h
```

**接入点 1 — `_ready()`**：在 `base_paddle_width = paddle_width` 之后、`_recalc_bounds()` 之前插入 `_sync_visual()`。
初始帧 `paddle_width=120/paddle_height=20` → offsets `-60..60/-10..10` 与场景硬编码逐位一致 → 零视觉变化。

**接入点 2 — `set_paddle_width()` 末尾**：在 `_recalc_bounds()` 之后追加 `_sync_visual()`。
调用时序（PRD §3.4 数据流补全）：

```
set_paddle_width(156)
  ├── paddle_width = 156                          ✅ 既有
  ├── CollisionShape2D.shape.size.x = 156         ✅ 既有（球即时感知）
  ├── _recalc_bounds()                            ✅ 既有（clamp）
  └── _sync_visual() → ColorRect offsets ±78      🆕 本设计（玩家下一帧看到变宽）
```

> **不改**：`player_paddle.tscn`（零 diff）、霓虹材质、碰撞逻辑、AI 逻辑。

### 3.2 `mini-pong/gdscripts/upgrade_defs.gd` — `is_stub` 标记（修复点 2）

9 条定义各增一个字段；`effect` 回调、`stub_activated` 标记逻辑、push_warning **全部保留**：

| id | rarity | is_stub | 说明 |
|----|--------|:---:|------|
| `long_arm` / `fireball` / `battering_ram` | COMMON | false | 机械完整实现 |
| `magnet_core` / `slow_time` / `pre_hole` | RARE | false | 机械完整实现 |
| `twin` / `stardust` / `phantom` | RARE/RARE/LEGENDARY | **true** | #387 §3.1 桩，完整实现后改 false 回归候选池 |

```gdscript
{
	"id": "twin",
	"rarity": Rarity.RARE,
	"max_stacks": 1,
	"is_stub": true,          # 🆕 #526：桩升级排除候选池；完整实现后置 false
	"effect": Callable(_SELF, "_effect_twin_stub"),
},
```

文件头注释补一句：#526 桩过滤决策（玩家可选的升级必须全部有可见反馈，PRD §2.2 情感误归因约束）。

### 3.3 `mini-pong/gdscripts/upgrade_pool.gd` — 候选池过滤（修复点 2）

`_ready()` 初始化 `_available` 时过滤 `is_stub`（在 `_load_display_names()` 之前或之后均可，互不依赖）：

```gdscript
func _ready() -> void:
	_available = []
	for d in Defs.definitions():
		if not d.get("is_stub", false):
			_available.append(d)
	_load_display_names()
```

**行为推论（implement 需知晓）：**
- `get_candidates()`：池 = 6 张非桩（COMMON 3 / RARE 3 / LEGENDARY 0），候选恒 ≥1（6 ≫ 3）。
- `apply("twin"/"stardust"/"phantom")` → `_is_available` 为 false → **返回 false**（不计数不 emit）。
  桩回调本身仍可经 `Defs._effect_*_stub(ctx)` 直接调用断言（`stub_activated` 标记逻辑保留）。
- 传说稀有度 91–100 掷出 → `_eligible_for(LEGENDARY)` 空 → `_fallback_rarity()` 回退 RARE/COMMON（既有逻辑，零新增）。

### 3.4 受影响测试文件（implement 阶段修改清单）

| 文件 | 变更性质 | 内容 |
|------|:---:|------|
| `mini-pong/tests/test_paddle.gd` | 扩展 | 新增 TC-F5 起场景级 ColorRect 断言（§8.1）；既有 TC-F1–F4 不动 |
| `mini-pong/tests/test_upgrade_pool.gd` | 更新 4 用例 + 新增 2 用例 | TC-B2 分布断言、TC-D1/D4 换非桩升级、TC-E4 改断言方向；新增 TC-A5（is_stub 字段）、TC-A6（候选不含桩） |

**新文件：无。删除/废弃文件：无。**

---

## 4. 数据流

### Flow 1 — 正常路径：玩家选长臂（修复点 1 主诉）
```
UpgradePickUI._confirm() → UpgradePool.apply("long_arm")     ✅ 既有接线 (#388/#393)
  → def.effect.call(ctx) → _effect_long_arm
  → new_width = paddle_width + 0.3 × base_paddle_width       (120 → 156)
  → paddle.set_paddle_width(156)
      ├ paddle_width = 156                                   ✅ 既有
      ├ CollisionShape2D.shape.size.x = 156                  ✅ 既有（球下一帧即时感知）
      ├ _recalc_bounds() → min/max 按 78 半宽重算 + clamp     ✅ 既有
      └ _sync_visual() → ColorRect offsets ±78               🆕 玩家下一帧看到 +30% 变宽
  → stacks["long_arm"] += 1, upgrade_applied.emit(id)        ✅ 既有
```
### Flow 2 — 桩升级拦截（修复点 2）：玩家永远看不到桩卡
```
UpgradePickUI.open → UpgradePool.get_candidates(3)
  → _available（_ready 已过滤 is_stub → 6 张非桩）           🆕
  → 候选 = 非桩子集；twin/stardust/phantom 永不出现            🆕 玩家可选的升级 = 全部有效
```
### Flow 3 — 边界：传说空池回退（桩过滤的分布副作用）
```
_roll_rarity() → 91–100 → LEGENDARY
  → _eligible_for(LEGENDARY, picked) 空（池内 0 传说）        🆕 过滤后首次出现
  → _fallback_rarity() → 首个非空稀有度（RARE/COMMON）         ✅ 既有逻辑
  → 候选非空，抽取继续
```

---

## 5. 边界情况与错误处理

| # | 边界/错误场景 | 缓解 |
|---|--------------|------|
| 1 | **宽度越界**：长臂堆满 3 层 → 120×1.9=228 < 720 屏幕宽，不越界；未来超屏时 `_recalc_bounds()` clamp 半宽（#383 语义保持） | `_sync_visual()` 不参与 clamp（纯表现），bounds 逻辑零改动 |
| 2 | **ColorRect 缺失**：动态/测试构造的 paddle 无 ColorRect 子节点 | `_sync_visual()` 判空 no-op（`get_node_or_null` + `is` 类型检查），与 `set_paddle_width` 现有 CollisionShape fallback 同风格 |
| 3 | **`_ready` 前调用**：注入式测试在 `_ready` 前调 `set_paddle_width` | 视觉同步判空跳过；`_ready()` 统一覆盖（`_ready` 末尾状态 = 权威状态） |
| 4 | **传说空池稀有度分布**：池内 0 传说，91–100 掷出后 `_eligible_for` 空 | `_fallback_rarity()` 回退 RARE/COMMON（既有），候选恒 ≥1（6 张 ≫ 3）；TC-B2 更新断言覆盖 |
| 5 | **AI 挡板误升级**：`paddles` 组首节点 = PlayerPaddle（树序），AI 挡板不受玩家升级影响 | 现状不变，不扩大范围（PRD 边界 5）；AC4 只要求 AI 挡板视觉同步机制一致（同场景脚本自动成立） |
| 6 | **霓虹材质回归**：改 ColorRect offsets 误触 material/color | 只改 offsets 四值，不碰 `material`；`test_visual_contrast`（E3-2 文本断言锁定 .tres）零回归 |
| 7 | **玩家对桩升级的 apply 竞态**：`apply(stub_id)` 返回 false | UI 保持打开可重选（#388 边界 2 现状，不回归）；桩回调不触发（`_is_available` 前置拦截） |
| 8 | **目标缺失**：paddle 不在 `paddles` 组 → 长臂/磁心回调 push_warning + no-op | #387 DESIGN §6 失败路径 2 现状正确，不回归 |

---

## 6. 集成点

| 集成 | 本组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 视觉同步 | `paddle.gd _sync_visual()` | `player_paddle.tscn` `ColorRect` | `get_node_or_null("ColorRect")` 节点契约（场景内固定，无风险） | ⬜ pending |
| 桩过滤 | `upgrade_pool.gd _ready()` | `upgrade_defs.gd` 9 定义 `is_stub` | `_available` 初始化过滤 | ⬜ pending |
| 桩回调保留 | `upgrade_defs.gd _effect_*_stub` | `upgrade_pool.gd mark_stub_effect` | `ctx["pool"]` 注入（既有，保留不动） | ✅ 既有 |
| 抽取回退 | `upgrade_pool.gd _fallback_rarity()` | 传说空池 | 既有回退链，零改动 | ✅ 既有 |
| 未来桩实现 | `is_stub=true` 定义 | 独立 feature Issue | 实现完成后 `is_stub=false` 回归候选池 | ⬜ deferred（#387 §3.1 承诺路径） |

---

## 7. 实现阶段

| Phase | 优先级 | 内容 | 涉及文件 | 估计 |
|:-----:|:---:|------|---------|:---:|
| Phase 1 | P0 | 长臂视觉同步：`_sync_visual()` + `_ready`/`set_paddle_width` 接入 | `paddle.gd` | 0.5 天 |
| Phase 2 | P0 | 桩标记 + 池过滤：9 定义增 `is_stub`；`_ready` 过滤 | `upgrade_defs.gd`、`upgrade_pool.gd` | 0.5 天 |
| Phase 3 | P0 | 测试更新：`test_paddle.gd` 新增 TC-F5 起；`test_upgrade_pool.gd` 更新 4 用例 + 新增 2 用例 | 2 个测试文件 | 0.5 天 |

Phase 1/2 相互独立可并行；Phase 3 依赖前两者。全量 headless 套件绿（`godot --path mini-pong/ --headless --script tests/run_tests.gd`）为合入红线。

---

## 8. 测试用例描述（仅描述，不写可运行测试代码）

> 验收映射：AC1–AC6（PRD §5.1）逐条对应；边界 1–8（§5）与失败路径（PRD §5.3）覆盖。
> 测试命名注意：`test_paddle.gd` 的 TC-F2 编号已被 `_test_recalc_bounds_f2` 占用 → 新用例从 **TC-F5** 起。

### 8.1 `test_paddle.gd` — 场景 F 扩展（修复点 1，场景级实例化 `player_paddle.tscn`）

- **TC-F5（AC1 视觉变宽）**：实例化 `player_paddle.tscn` → `_ready()` → `set_paddle_width(156.0)` →
  断言 `ColorRect.offset_right - offset_left == 156.0`（±0.01）且 `paddle_width == 156.0`。
- **TC-F6（AC2 碰撞不回退）**：同前置 → 断言 `CollisionShape2D.shape.size.x == 156.0`（TC-F1 既有断言在场景级复验）且 ColorRect 宽度 == 156（双通道同步）。
- **TC-F7（AC3 堆叠语义）**：连续两次 `set_paddle_width(156)` → `set_paddle_width(192)`（或经 `apply("long_arm")` 两次）→ 每次断言视觉 == 碰撞 == 实例变量（156 → 192 基数加算）。
- **TC-F8（AC4 AI 挡板）**：`mode = Mode.AI` 实例化 → `set_paddle_width(156)` → ColorRect 同步（同场景脚本自动成立，显式断言防回归）。
- **TC-F9（边界 2 判空 no-op）**：动态构造 paddle（无 ColorRect 子节点）→ `set_paddle_width(156)` → 不崩溃、`paddle_width` 仍更新（视觉判空跳过）。
- **TC-F10（边界 3 _ready 前调用）**：实例化后 `_ready()` 前调 `set_paddle_width(156)` → 不崩溃；`_ready()` 后 ColorRect == 当前 paddle_width（`_ready` 统一覆盖）。
- **TC-F11（初始帧零回归）**：场景实例化 `_ready()` 后（未调 setter）→ ColorRect 宽度 == 120 == 场景硬编码（`_sync_visual` 初始值与硬编码逐位一致，防初始帧漂移）。

### 8.2 `test_upgrade_pool.gd` — 更新 + 新增（修复点 2）

**更新（4 个既有用例，桩过滤后语义变化）：**

- **TC-B2（分布统计）**：桩过滤后传说占比恒 0%，原断言 `l_pct ∈ [5,15]%` 失效 → 改为：`c_pct + r_pct == 100`、`l_pct == 0`、`r_pct ∈ [30,45]`（回退链吸收传说份额后的合理区间，implement 以实测校准），并断言全程候选非空（边界 4）。
- **TC-D1（整局不可重复）**：原用 `stardust`（桩，`apply` 将返回 false）→ 改用非桩 max_stacks=1 升级 **`pre_hole`**：首次 apply true、二次 false、后续候选无 `pre_hole`（语义等价，桩无关）。
- **TC-D4（候选 vs 整局正交）**：原断言 `stardust` 先出现于候选 → 改用 **`pre_hole`** 复现「取前可见 → 取后全局消失」。
- **TC-E4（桩效果）**：原断言 `apply(stub_id)` 返回 true + `stub_activated` 标记 → 改为：`apply("twin"/"stardust"/"phantom")` **均返回 false**（不在候选池）；桩回调保留性另测——直接调用 `Defs._effect_twin_stub({"pool": pool})` → `stub_activated["twin"] == true`（标记逻辑保留供未来实现回归）。

**新增（2 个）：**

- **TC-A5（AC5 标记完整性）**：9 定义均有 `is_stub` 字段（bool）；`twin/stardust/phantom` == true、其余 6 个 == false；`Defs.by_id("stardust")` 仍可查（定义保留）。
- **TC-A6（AC5 候选池排除）**：`_ready()` 后多轮 `get_candidates(3)`（≥50 轮，种子固定）→ 结果永不含 `twin/stardust/phantom`；候选恒为 3 张非桩；`get_candidates(30)` 全量返回 ≤ 6 张且不含桩。

### 8.3 既有用例回归确认（AC6 — 其他机械升级仍可断言生效）

- `fireball`（球速 ×1.1 封顶 + blast_neighbors）、`battering_ram`（blast radius 120）、
  `magnet_core`（magnet_enabled）、`slow_time`（set_speed_scale_timed(0,2)）、`pre_hole`（open_hole 挂起）
  —— 分别由既有 TC-E1/E2/E3、TC-H1/H2 覆盖，**零改动**，实施后全绿即 AC6 达成。
- `test_paddle.gd` 既有 TC-F1（CollisionShape）与 TC-F2（bounds）零改动；全量套件绿为合入红线。

### 8.4 手动/视觉验证（非自动化）

- 真机（非 headless）游玩：波次结算 → 三选一 → 选「长臂」→ 挡板视觉立即 +30% 变宽（120→156 肉眼可辨）。
- 连选两次长臂 → 156→192 连续放大，边界 clamp 正常。
- 多局观察三选一候选：双生/星尘/幻影不再出现；稀有/普通升级全部生效有反馈。
