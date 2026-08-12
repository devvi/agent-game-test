extends Node
## UpgradePool autoload 单例（#387 §3.2）— 升级池数据枢纽。
## 9 定义（upgrade_defs.gd）+ 稀有度先掷 60/30/10 抽取 + apply 链路 + #395 JSON
## 显示名只读消费（缺失/损坏逐级兜底工作名）。
## 消费方（#386 波次结算 / #388 3 选 1 UI）在本 Issue 不接线——池不主动触发流程。
##
## 概念分层: GameManager(#293)=分数/局/场次；UpgradePool=每波成长决策。
## 所有权: content_ownership: mechanical（数值与文案归 taste 域 #395）。
##
## 目标解析: 惰性 + 可注入（ball_ref/paddle_ref/grid_ref 测试可直接覆盖）；
## #384 未落地 → grid 类效果判空 no-op（DESIGN §6 边界 7）。

signal upgrade_applied(upgrade_id: String)

const CONSTS = preload("res://gdscripts/constants.gd")
const Defs = preload("res://gdscripts/upgrade_defs.gd")

# 可 seed() — 测试/自动对打确定性（TC-I1）
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var stacks: Dictionary = {}          # id → 已拿次数
var stub_activated: Dictionary = {}  # id → true（桩效果标记，可断言）
var _available: Array = []           # 未耗尽定义池（max_stacks 未达上限）
var _display: Dictionary = {}        # id → {name_working, short_phrase, naming_candidates}（#395）
var _display_warn_count: int = 0     # push_warning 至多一次（不 spam）
var ball_ref = null                  # 目标解析缓存；测试可直接注入覆盖（FakeBall 为 RefCounted，故不锁类型）
var paddle_ref = null
var grid_ref = null


func _ready() -> void:
	_available = Defs.definitions().duplicate()
	_load_display_names()


func get_definitions() -> Array:
	return Defs.definitions()


func get_stacks(id: String) -> int:
	return stacks.get(id, 0)


## 抽取 n 张候选卡（AC2/AC5）：每张卡独立走一次稀有度先掷 60/30/10 →
## 稀有度内均匀选 → 候选内 id 去重 → 回退链（DESIGN §5 Flow 3）。
func get_candidates(n: int = CONSTS.UPGRADE_CANDIDATE_COUNT) -> Array:
	var picked_ids: Dictionary = {}
	var result: Array = []
	for i in n:
		if _available.is_empty():
			break
		var rarity: int = _roll_rarity()
		var eligible: Array = _eligible_for(rarity, picked_ids)
		if eligible.is_empty():
			rarity = _fallback_rarity(picked_ids)
			eligible = _eligible_for(rarity, picked_ids)
		if eligible.is_empty():
			break
		var chosen: Dictionary = eligible[rng.randi_range(0, eligible.size() - 1)]
		picked_ids[chosen.id] = true
		result.append(_candidate_item(chosen))
	return result


## 应用升级（AC5）。失败路径（DESIGN §6）: 未知 id / 已耗尽 → false，不计数不 emit。
func apply(upgrade_id: String) -> bool:
	var def: Dictionary = Defs.by_id(upgrade_id)
	if def.is_empty() or not _is_available(upgrade_id):
		return false
	var ctx := _build_ctx()
	ctx["pool"] = self  # 桩效果经 ctx 回调（避免 autoload 名解析，headless 可测）
	def.effect.call(ctx)
	stacks[upgrade_id] = stacks.get(upgrade_id, 0) + 1
	if stacks[upgrade_id] >= def.max_stacks:
		_available_remove(upgrade_id)
	upgrade_applied.emit(upgrade_id)
	return true


## 桩效果标记（§3.1 桩决策）— 由 UpgradeDefs 桩回调经 ctx["pool"] 调用。
func mark_stub_effect(id: String) -> void:
	stub_activated[id] = true
	push_warning("UpgradePool: '%s' 效果为桩实现（#387 §3.1）— 完整实现随 #384 落地后独立小 PR 深化" % id)


func reload_display_names() -> void:
	_load_display_names()


# ── 内部 ──

func _candidate_item(def: Dictionary) -> Dictionary:
	return {
		"id": def.id,
		"name": def.name,
		"rarity": def.rarity,
		"max_stacks": def.max_stacks,
		"effect_desc": def.effect_desc,
		"display": _display.get(def.id, {}),
	}


func _roll_rarity() -> int:
	return rarity_from_roll(rng.randi_range(1, 100))


## 60/30/10 权重映射（AC2）: 1–60 → COMMON, 61–90 → RARE, 91–100 → LEGENDARY。
## 静态纯函数便于单测边界（TC-B1）。
static func rarity_from_roll(roll: int) -> int:
	if roll <= CONSTS.UPGRADE_RARITY_WEIGHTS[0]:
		return Defs.Rarity.COMMON
	if roll <= CONSTS.UPGRADE_RARITY_WEIGHTS[0] + CONSTS.UPGRADE_RARITY_WEIGHTS[1]:
		return Defs.Rarity.RARE
	return Defs.Rarity.LEGENDARY


func _eligible_for(rarity: int, picked_ids: Dictionary) -> Array:
	var out: Array = []
	for d in _available:
		if d.rarity == rarity and not picked_ids.has(d.id):
			out.append(d)
	return out


## 回退链 [COMMON, RARE, LEGENDARY] 取第一个非空稀有度（DESIGN §5 Flow 3）。
func _fallback_rarity(picked_ids: Dictionary) -> int:
	for r in [Defs.Rarity.COMMON, Defs.Rarity.RARE, Defs.Rarity.LEGENDARY]:
		if not _eligible_for(r, picked_ids).is_empty():
			return r
	return Defs.Rarity.COMMON


func _is_available(id: String) -> bool:
	for d in _available:
		if d.id == id:
			return true
	return false


func _available_remove(id: String) -> void:
	# 按 id 删除（Dictionary 为值语义，按内容 erase 有误删风险 → 显式按 id）
	for i in range(_available.size() - 1, -1, -1):
		if _available[i].id == id:
			_available.remove_at(i)
			return


## 惰性 + 可注入目标解析（DESIGN §3.2）:
## ball_ref = balls 组（ball.gd _ready 加组）；paddle_ref = paddles 组（已有）；
## grid_ref = breakout_grids 组（#384 落地时加组 — 契约）。
func _build_ctx() -> Dictionary:
	if ball_ref == null and is_inside_tree():
		ball_ref = get_tree().get_first_node_in_group("balls")
	if paddle_ref == null and is_inside_tree():
		paddle_ref = get_tree().get_first_node_in_group("paddles")
	if grid_ref == null and is_inside_tree():
		grid_ref = get_tree().get_first_node_in_group("breakout_grids")
	return {"ball": ball_ref, "paddle": paddle_ref, "grid": grid_ref, "params": {}}


## #395 JSON 只读消费（DESIGN §4.4）: FileAccess + JSON.parse_string + 逐级兜底。
## 可选 path 参数便于测试注入缺失/损坏文件（默认生产路径）。
func _load_display_names(path: String = CONSTS.UPGRADE_JSON_PATH) -> void:
	_display = {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		_warn_display_once("UpgradePool: %s 缺失或为空 — 显示名回退工作名" % path)
		return
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_warn_display_once("UpgradePool: %s JSON 解析失败 — 显示名回退工作名" % path)
		return
	if parsed.get("schema", "") != "upgrade-pool-content/v1":
		_warn_display_once("UpgradePool: %s schema 不符 — 显示名回退工作名" % path)
		return
	var ups = parsed.get("upgrades", [])
	if typeof(ups) != TYPE_ARRAY:
		_warn_display_once("UpgradePool: %s upgrades 非数组 — 显示名回退工作名" % path)
		return
	for u in ups:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var uid = u.get("id", "")
		if uid == "":
			continue
		_display[uid] = {
			"name_working": u.get("name_working", ""),
			"short_phrase": u.get("short_phrase", ""),
			"naming_candidates": u.get("naming_candidates", []),
		}


func _warn_display_once(msg: String) -> void:
	if _display_warn_count > 0:
		return
	_display_warn_count += 1
	push_warning(msg)
