class_name Catalog
extends RefCounted
## Bundles all rules-as-data tables for a sim run. Load once, reuse across many runs.

var units: Dictionary = {}
var economy: Dictionary = {}
var weather: Dictionary = {}
var bosses: Dictionary = {}
var levels: Array = []
var levels_by_id: Dictionary = {}

static func load_from(root: String) -> Catalog:
	var c := Catalog.new()
	c.units = DataLoader.index_by_id(DataLoader.load_json(root.path_join("data/units/units.json")))
	c.economy = DataLoader.load_json(root.path_join("data/economy.json"))
	c.weather = DataLoader.load_json(root.path_join("data/weather.json"))
	c.bosses = DataLoader.index_by_id(DataLoader.load_json(root.path_join("data/bosses/bosses.json")))
	c.levels = DataLoader.load_all_levels(root.path_join("data/levels"))
	for lvl in c.levels:
		c.levels_by_id[lvl["id"]] = lvl
	return c
