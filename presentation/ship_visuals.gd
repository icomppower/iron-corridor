class_name ShipVisuals
extends Node3D
## Reads LiveMatch state and renders it. Never writes back into the sim —
## every position/scale here is a cosmetic derivation of existing sim
## fields (base HP %, stack alive_hp), not new gameplay state.

const LANE_HALF := 22.0
const PLAYER_COLOR := Color(0.28, 0.58, 0.95)
const ENEMY_COLOR := Color(0.88, 0.28, 0.22)
const BOSS_COLOR := Color(0.75, 0.15, 0.65)

var _nodes: Dictionary = {}
var _base_player: MeshInstance3D
var _base_enemy: MeshInstance3D
var _boss_mesh: MeshInstance3D

func _ready() -> void:
	_base_player = _make_base_marker(PLAYER_COLOR)
	_base_player.position = Vector3(-LANE_HALF - 3.0, 0.6, 0)
	_base_enemy = _make_base_marker(ENEMY_COLOR)
	_base_enemy.position = Vector3(LANE_HALF + 3.0, 0.6, 0)

	_boss_mesh = MeshInstance3D.new()
	_boss_mesh.mesh = BoxMesh.new()
	_boss_mesh.mesh.size = Vector3(3.0, 2.0, 1.4)
	var boss_mat := StandardMaterial3D.new()
	boss_mat.albedo_color = BOSS_COLOR
	_boss_mesh.material_override = boss_mat
	_boss_mesh.visible = false
	add_child(_boss_mesh)

func _make_base_marker(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.mesh.size = Vector3(1.6, 1.2, 4.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	add_child(mi)
	return mi

func sync(live: LiveMatch, catalog: Catalog) -> void:
	var enemy_dmg_pct: float = 1.0 - (live.enemy_base_hp() / max(1.0, live.enemy_base_hp_max()))
	var player_dmg_pct: float = 1.0 - (live.base_hp() / max(1.0, live.base_hp_max()))
	var player_advance: float = clamp(enemy_dmg_pct, 0.0, 1.0) * LANE_HALF * 0.75
	var enemy_advance: float = clamp(player_dmg_pct, 0.0, 1.0) * LANE_HALF * 0.75

	_sync_side(live.player_stacks(), catalog, -LANE_HALF + player_advance, "player")
	_sync_side(live.enemy_stacks(), catalog, LANE_HALF - enemy_advance, "enemy")

	_base_player.scale = Vector3.ONE * (0.5 + 0.5 * (live.base_hp() / max(1.0, live.base_hp_max())))
	_base_enemy.scale = Vector3.ONE * (0.5 + 0.5 * (live.enemy_base_hp() / max(1.0, live.enemy_base_hp_max())))

	if live.phase == MatchSim.PHASE_BOSS or (live.phase == MatchSim.PHASE_FINISH and live.boss_killed and live.boss.size() > 0):
		_boss_mesh.visible = live.phase == MatchSim.PHASE_BOSS
		if live.phase == MatchSim.PHASE_BOSS:
			_boss_mesh.position = Vector3(LANE_HALF - 1.0, 1.0, 0)
			var hp_pct: float = live.boss_hp_pct()
			_boss_mesh.scale = Vector3.ONE * (0.6 + 0.6 * hp_pct)
	else:
		_boss_mesh.visible = false

func _sync_side(stacks: Dictionary, catalog: Catalog, base_x: float, tag: String) -> void:
	var roster: Array = catalog.units.keys()
	for i in range(roster.size()):
		var uid: String = roster[i]
		var key := "%s:%s" % [tag, uid]
		var alive := 0.0
		if stacks.has(uid):
			alive = float(stacks[uid]["alive_hp"])
		if alive <= 0.0:
			if _nodes.has(key):
				_nodes[key].visible = false
			continue
		var mesh := _get_or_create(key, tag, catalog.units[uid])
		mesh.visible = true
		var scale_v: float = 0.3 + sqrt(alive) * 0.045
		mesh.scale = Vector3(scale_v, scale_v, scale_v)
		var z: float = (i - roster.size() / 2.0) * 2.0
		var y: float = 0.4
		match String(catalog.units[uid].get("layer", "surface")):
			"air":
				y = 3.0
			"periscope":
				y = 0.1
			"deep":
				y = -0.6
		mesh.position = Vector3(base_x, y, z)

func _get_or_create(key: String, tag: String, udef: Dictionary) -> MeshInstance3D:
	if _nodes.has(key):
		return _nodes[key]
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLAYER_COLOR if tag == "player" else ENEMY_COLOR
	if udef.get("flagship", false):
		mat.albedo_color = mat.albedo_color.lightened(0.35)
	mi.material_override = mat
	add_child(mi)
	_nodes[key] = mi
	return mi
