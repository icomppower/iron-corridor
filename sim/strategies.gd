class_name Strategies
extends RefCounted
## Scripted policies driving a side's spend decisions. Pure functions of
## sim state — no hidden RNG, no Node deps. Called once per decision interval.

## Mono probes must spend at the same throughput as the scripted
## strategies — at 6 buys/decision the mono harness had double the APM
## ceiling and Balance2 was comparing spam-at-2x-speed against
## strategies-at-1x, flagging throughput rather than composition.
const MAX_MONO_BUYS_PER_DECISION := 3
const MAX_WEIGHTED_BUYS_PER_DECISION := 3

static func decide(strategy_id: String, side: Dictionary, catalog: Catalog, level: Dictionary, economy: Dictionary, tick: int) -> void:
	if strategy_id.begins_with("mono:"):
		decide_mono(strategy_id.substr(5), side, catalog, economy, tick)
		return
	match strategy_id:
		"rush":
			_spend_weighted(side, catalog, economy, tick, ["gunboat", "gunboat", "midget_sub", "hovercraft"])
		"eco":
			_eco(side, catalog, level, economy, tick)
		"turtle":
			_spend_weighted(side, catalog, economy, tick, ["corvette_asw", "flak_cruiser"])
		"mixed":
			_spend_weighted(side, catalog, economy, tick, ["corvette_asw", "destroyer", "flak_cruiser", "submarine_shallow", "hovercraft", "minelayer", "INCOME", "battleship_flagship", "carrier"])
		"level_ai":
			# Per-level enemy composition is rules-as-data: levels may ship an
			# "enemy_priority" list to shape what the AI masses (e.g. sub-heavy
			# wall-breaker comps on later levels). Roster still gates buys.
			var default_priority := ["gunboat", "destroyer", "submarine_shallow", "hovercraft", "corvette_asw", "flak_cruiser", "midget_sub", "submarine_deep", "INCOME", "battleship_flagship"]
			_spend_weighted(side, catalog, economy, tick, level.get("enemy_priority", default_priority))
		_:
			push_error("Strategies: unknown strategy_id %s" % strategy_id)

static func mono_strategy_id(unit_id: String) -> String:
	return "mono:%s" % unit_id

static func decide_mono(unit_id: String, side: Dictionary, catalog: Catalog, economy: Dictionary, tick: int) -> void:
	_spend_repeat(side, catalog, economy, tick, [unit_id])

## eco needs early defenders before it dumps gold into upgrades, or it
## dies to the opening rush before its economy ever pays off. The seed
## scales with the enemy's income so eco holds a proportionate wall on
## later, richer levels instead of folding in the opening minutes.
static func _eco(side: Dictionary, catalog: Catalog, level: Dictionary, economy: Dictionary, tick: int) -> void:
	var defender_hp := 0.0
	for uid in side["stacks"].keys():
		defender_hp += float(side["stacks"][uid]["alive_hp"])
	var seed_unit := "corvette_asw" if side["roster"].has("corvette_asw") else "gunboat"
	var udef: Dictionary = catalog.units.get(seed_unit, {})
	var threat_scale: float = max(1.6, float(level.get("enemy_income_base", 12.0)) / 12.0)
	# 2x, not 3x: the thinner opening wall is eco's real cost for the
	# upgrade detour — at 3x eco was strictly better than turtle
	# everywhere (0.99 aggregate, insensitive to level knobs).
	var seed_target: float = float(udef.get("hp", 40.0)) * 2.0 * threat_scale
	if defender_hp < seed_target and side["roster"].has(seed_unit):
		MatchSim.enqueue_build(side, catalog, seed_unit, economy, tick)
		return
	# Payoff phase: eco fields the same corvette/flak military as turtle
	# but detours through INCOME/INSTALLMENT first — a turtle that banks.
	# The upgrade detour is its early-game cost; the compounding economy
	# is what closes matches turtle's flat flow cannot.
	_spend_weighted(side, catalog, economy, tick, ["INCOME", "INSTALLMENT", "corvette_asw", "flak_cruiser"])

## Fair-share purchase scheduler: every priority item accrues "credit" each
## decision call, and we always spend on the most-overdue item. If the
## most-overdue item is not affordable yet, the side holds its gold and
## saves up for it instead of skipping to something cheaper — otherwise
## expensive/rare slots (submarines, flagships) are perpetually crowded
## out by whatever's cheap and never get bought at all.
##
## Upgrades are the exception: they are bought opportunistically (only
## when gold comfortably exceeds the cost) instead of through the credit
## rotation. Their exponentially-growing prices otherwise stall military
## production for dozens of ticks while the side banks gold — the stall,
## not the upgrade, ends up deciding matches.
##
## Saving is also bounded: a side only holds gold for an item already
## within SAVE_REACH of its balance. Unbounded saving froze every list
## containing an expensive unit for its full price, which made cheap-only
## rotations structurally dominant regardless of unit stats.
const UPGRADE_HEADROOM := 1.5
const SAVE_REACH := 150.0

static func _spend_weighted(side: Dictionary, catalog: Catalog, economy: Dictionary, tick: int, priority: Array) -> void:
	for item in ["INCOME", "INSTALLMENT"]:
		if item in priority and _purchasable(side, catalog, item) and side["gold"] >= _upgrade_cost(side, economy, item) * UPGRADE_HEADROOM:
			_execute_buy(side, catalog, economy, tick, item)
	var credit: Dictionary = side.get("_credit", {})
	var units: Array = priority.filter(func(i): return i != "INCOME" and i != "INSTALLMENT")
	for item in units:
		credit[item] = float(credit.get(item, 0.0)) + 1.0
	var attempts := 0
	while attempts < MAX_WEIGHTED_BUYS_PER_DECISION:
		attempts += 1
		var ranked := units.filter(func(i): return _purchasable(side, catalog, i))
		ranked.sort_custom(func(a, b): return float(credit.get(a, 0.0)) > float(credit.get(b, 0.0)))
		if ranked.is_empty():
			break
		var top: String = ranked[0]
		if _affordable(side, catalog, economy, top):
			_execute_buy(side, catalog, economy, tick, top)
			credit[top] = 0.0
			continue
		if MatchSim.spawn_cost(side, catalog, top, economy) <= float(side["gold"]) + SAVE_REACH:
			break # close enough — hold gold and save for it
		# Top item is far out of reach: keep the economy flowing with the
		# next-most-overdue affordable item instead of freezing.
		var bought := false
		for item in ranked.slice(1):
			if _affordable(side, catalog, economy, item):
				_execute_buy(side, catalog, economy, tick, item)
				credit[item] = 0.0
				bought = true
				break
		if not bought:
			break
	side["_credit"] = credit

static func _upgrade_cost(side: Dictionary, economy: Dictionary, item: String) -> float:
	var cfg: Dictionary = economy["income_upgrade"] if item == "INCOME" else economy["installment_upgrade"]
	var level: int = int(side["income_level"]) if item == "INCOME" else int(side["installment_level"])
	return float(cfg["cost_base"]) * pow(float(cfg["cost_growth"]), level)

## Whether the item is a valid purchase target at all (in roster / upgrade
## not maxed) — independent of current gold, so the scheduler can decide
## to save up for it.
static func _purchasable(side: Dictionary, catalog: Catalog, item: String) -> bool:
	if item == "INCOME":
		return int(side["income_level"]) < int(catalog.economy["income_upgrade"]["max_level"])
	elif item == "INSTALLMENT":
		return int(side["installment_level"]) < int(catalog.economy["installment_upgrade"]["max_level"])
	return side["roster"].has(item) and catalog.units.has(item)

static func _affordable(side: Dictionary, catalog: Catalog, economy: Dictionary, item: String) -> bool:
	if item == "INCOME":
		var cfg: Dictionary = economy["income_upgrade"]
		if int(side["income_level"]) >= int(cfg["max_level"]):
			return false
		var cost: float = float(cfg["cost_base"]) * pow(float(cfg["cost_growth"]), int(side["income_level"]))
		return side["gold"] >= cost
	elif item == "INSTALLMENT":
		var cfg: Dictionary = economy["installment_upgrade"]
		if int(side["installment_level"]) >= int(cfg["max_level"]):
			return false
		var cost: float = float(cfg["cost_base"]) * pow(float(cfg["cost_growth"]), int(side["installment_level"]))
		return side["gold"] >= cost
	if not side["roster"].has(item) or not catalog.units.has(item):
		return false
	return side["gold"] >= MatchSim.spawn_cost(side, catalog, item, economy)

static func _execute_buy(side: Dictionary, catalog: Catalog, economy: Dictionary, tick: int, item: String) -> void:
	if item == "INCOME":
		MatchSim.buy_income_upgrade(side, economy)
	elif item == "INSTALLMENT":
		MatchSim.buy_installment_upgrade(side, economy)
	else:
		MatchSim.enqueue_build(side, catalog, item, economy, tick)

## Buys the first affordable item repeatedly — used for mono-composition
## balance testing where we deliberately want an all-in spam pattern.
static func _spend_repeat(side: Dictionary, catalog: Catalog, economy: Dictionary, tick: int, priority: Array) -> void:
	var roster: Array = side["roster"]
	var buys := 0
	while buys < MAX_MONO_BUYS_PER_DECISION:
		var bought := false
		for item in priority:
			if item == "INCOME":
				if MatchSim.buy_income_upgrade(side, economy):
					bought = true
					break
			elif item == "INSTALLMENT":
				if MatchSim.buy_installment_upgrade(side, economy):
					bought = true
					break
			else:
				if not roster.has(item) or not catalog.units.has(item):
					continue
				if MatchSim.enqueue_build(side, catalog, item, economy, tick):
					bought = true
					break
		if not bought:
			break
		buys += 1
