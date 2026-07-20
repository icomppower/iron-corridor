class_name ShipVisuals
extends Node3D
## Reads LiveMatch state and renders it. Never writes back into the sim —
## every position/scale here is a cosmetic derivation of existing sim
## fields (base HP %, stack alive_hp), not new gameplay state.
##
## Each unit type gets a distinct low-poly silhouette + a fixed signature
## accent colour + a billboarded name/count label, so the 12 types read apart
## at a glance. Hull colour stays side-tinted (player blue / enemy red) so
## ownership is always unambiguous; the shape and accent carry the identity.

const LANE_HALF := 22.0
const PLAYER_COLOR := Color(0.28, 0.58, 0.95)
const ENEMY_COLOR := Color(0.88, 0.28, 0.22)
const BOSS_COLOR := Color(0.75, 0.15, 0.65)

# Signature accent colour per unit — same on both sides, so the coloured
# "business end" (turrets, wings, AA barrels, mines...) reads as the unit's ID.
const ACCENT := {
	"gunboat": Color(0.72, 0.74, 0.78),
	"destroyer": Color(0.92, 0.92, 0.95),
	"corvette_asw": Color(0.30, 0.80, 0.42),
	"flak_cruiser": Color(0.96, 0.85, 0.20),
	"minelayer": Color(0.96, 0.55, 0.15),
	"hovercraft": Color(0.30, 0.85, 0.92),
	"battleship_flagship": Color(0.98, 0.80, 0.25),
	"carrier": Color(0.82, 0.72, 0.52),
	"submarine_shallow": Color(0.20, 0.78, 0.72),
	"submarine_deep": Color(0.30, 0.42, 0.82),
	"midget_sub": Color(0.66, 0.42, 0.86),
	"patrol_plane": Color(0.82, 0.84, 0.88),
}

const SHORT_NAME := {
	"gunboat": "Gunboat",
	"destroyer": "Destroyer",
	"corvette_asw": "Corvette",
	"flak_cruiser": "Flak",
	"minelayer": "Minelayer",
	"hovercraft": "Hovercraft",
	"battleship_flagship": "FLAGSHIP",
	"carrier": "Carrier",
	"submarine_shallow": "Sub-Shallow",
	"submarine_deep": "Sub-Deep",
	"midget_sub": "Midget Sub",
	"patrol_plane": "Plane",
}

var _nodes: Dictionary = {}  # key -> {root, body, label}
var _base_player: MeshInstance3D
var _base_enemy: MeshInstance3D
var _boss_mesh: MeshInstance3D
var _boss_label: Label3D

func _ready() -> void:
	_base_player = _make_base_marker(PLAYER_COLOR)
	_base_player.position = Vector3(-LANE_HALF - 3.0, 0.6, 0)
	_base_enemy = _make_base_marker(ENEMY_COLOR)
	_base_enemy.position = Vector3(LANE_HALF + 3.0, 0.6, 0)

	_boss_mesh = MeshInstance3D.new()
	var boss_box := BoxMesh.new()
	boss_box.size = Vector3(3.0, 2.0, 1.4)
	_boss_mesh.mesh = boss_box
	_boss_mesh.material_override = _mat(BOSS_COLOR)
	_boss_mesh.visible = false
	add_child(_boss_mesh)
	_boss_label = _make_label(Color(1, 0.85, 0.98))
	_boss_label.position = Vector3(0, 2.2, 0)
	_boss_mesh.add_child(_boss_label)

func _make_base_marker(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 1.2, 4.0)
	mi.mesh = box
	mi.material_override = _mat(color)
	add_child(mi)
	return mi

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m

func _make_label(color: Color) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# World-space (not fixed_size): perspective shrinks far-lane labels, which
	# separates the two fleets in depth and keeps them from smearing together.
	l.pixel_size = 0.0045
	l.font_size = 40
	l.outline_size = 6
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.no_depth_test = true       # readable, never buried inside a hull
	l.render_priority = 2
	return l

func sync(live: LiveMatch, catalog: Catalog) -> void:
	var enemy_dmg_pct: float = 1.0 - (live.enemy_base_hp() / max(1.0, live.enemy_base_hp_max()))
	var player_dmg_pct: float = 1.0 - (live.base_hp() / max(1.0, live.base_hp_max()))
	var player_advance: float = clamp(enemy_dmg_pct, 0.0, 1.0) * LANE_HALF * 0.75
	var enemy_advance: float = clamp(player_dmg_pct, 0.0, 1.0) * LANE_HALF * 0.75

	_sync_side(live.player_stacks(), catalog, -LANE_HALF + player_advance, "player")
	_sync_side(live.enemy_stacks(), catalog, LANE_HALF - enemy_advance, "enemy")

	_base_player.scale = Vector3.ONE * (0.5 + 0.5 * (live.base_hp() / max(1.0, live.base_hp_max())))
	_base_enemy.scale = Vector3.ONE * (0.5 + 0.5 * (live.enemy_base_hp() / max(1.0, live.enemy_base_hp_max())))

	if live.phase == MatchSim.PHASE_BOSS:
		_boss_mesh.visible = true
		_boss_mesh.position = Vector3(LANE_HALF - 1.0, 1.0, 0)
		var hp_pct: float = live.boss_hp_pct()
		_boss_mesh.scale = Vector3.ONE * (0.6 + 0.6 * hp_pct)
		var boss_name: String = String(live.boss.get("id", "boss")).capitalize()
		_boss_label.text = "%s  %d%%" % [boss_name, int(round(hp_pct * 100.0))]
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
				_nodes[key]["root"].visible = false
			continue
		var udef: Dictionary = catalog.units[uid]
		var entry: Dictionary = _get_or_create(key, tag, uid, udef)
		var root: Node3D = entry["root"]
		root.visible = true
		var scale_v: float = 0.32 + sqrt(alive) * 0.045
		entry["body"].scale = Vector3(scale_v, scale_v, scale_v)
		var z: float = (i - roster.size() / 2.0) * 2.0
		var y := 0.4
		match String(udef.get("layer", "surface")):
			"air": y = 3.2
			"periscope": y = 0.05
			"deep": y = -0.7
		root.position = Vector3(base_x, y, z)
		var unit_hp: float = max(1.0, float(udef.get("hp", 1.0)))
		var count: int = max(1, int(ceil(alive / unit_hp)))
		entry["label"].text = "%s ×%d" % [SHORT_NAME.get(uid, uid), count]

func _get_or_create(key: String, tag: String, uid: String, udef: Dictionary) -> Dictionary:
	if _nodes.has(key):
		return _nodes[key]
	var root := Node3D.new()
	add_child(root)

	var body := Node3D.new()      # everything scaled by stack strength lives here
	root.add_child(body)
	var side_color: Color = PLAYER_COLOR if tag == "player" else ENEMY_COLOR
	_build_unit(body, uid, side_color)

	var label := _make_label(Color(1, 1, 1))
	label.position = Vector3(0, 1.7, 0)   # unscaled: constant height above the unit
	root.add_child(label)

	var entry := {"root": root, "body": body, "label": label}
	_nodes[key] = entry
	return entry

## -------------------------------------------------------- low-poly silhouettes
## Each unit builds a small composite mesh in `body` local space, longest axis
## along X (the lane direction). Hull = side colour, accents = ACCENT[uid].

func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot_deg := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)

func _box(sz: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = sz
	return m

func _cyl(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	return m

func _cone(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.02
	m.bottom_radius = radius
	m.height = height
	return m

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	return m

func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	return m

func _build_unit(body: Node3D, uid: String, hull: Color) -> void:
	var accent: Color = ACCENT.get(uid, Color(0.85, 0.85, 0.85))
	match uid:
		"gunboat":
			_part(body, _box(Vector3(1.4, 0.34, 0.5)), Vector3(0, 0, 0), hull)
			_part(body, _cyl(0.12, 0.22), Vector3(0.1, 0.28, 0), accent)  # single turret
		"destroyer":
			_part(body, _box(Vector3(2.2, 0.34, 0.5)), Vector3.ZERO, hull)              # long sleek hull
			_part(body, _box(Vector3(0.5, 0.3, 0.34)), Vector3(0, 0.32, 0), hull.lightened(0.15))  # bridge
			_part(body, _cyl(0.1, 0.18), Vector3(0.7, 0.3, 0), accent)                  # fwd gun
			_part(body, _cyl(0.1, 0.18), Vector3(-0.7, 0.3, 0), accent)                 # aft gun
			_part(body, _cyl(0.08, 0.4), Vector3(-0.15, 0.42, 0), Color(0.2, 0.2, 0.22))  # funnel
		"corvette_asw":
			_part(body, _box(Vector3(1.7, 0.32, 0.48)), Vector3.ZERO, hull)
			_part(body, _box(Vector3(0.4, 0.3, 0.3)), Vector3(0.2, 0.3, 0), hull.lightened(0.15))
			# depth-charge racks (accent boxes) at the stern
			_part(body, _box(Vector3(0.5, 0.16, 0.42)), Vector3(-0.7, 0.22, 0), accent)
			_part(body, _cyl(0.05, 0.5), Vector3(0.35, 0.5, 0), accent)  # sensor mast
		"flak_cruiser":
			_part(body, _box(Vector3(1.9, 0.36, 0.52)), Vector3.ZERO, hull)
			_part(body, _box(Vector3(0.5, 0.34, 0.36)), Vector3(0, 0.34, 0), hull.lightened(0.15))
			# upward AA barrels
			for off in [-0.6, 0.0, 0.6]:
				_part(body, _cyl(0.05, 0.5), Vector3(off, 0.6, 0.12), accent, Vector3(-18, 0, 0))
				_part(body, _cyl(0.05, 0.5), Vector3(off, 0.6, -0.12), accent, Vector3(18, 0, 0))
		"minelayer":
			_part(body, _box(Vector3(1.8, 0.36, 0.56)), Vector3.ZERO, hull)
			_part(body, _box(Vector3(0.4, 0.28, 0.34)), Vector3(0.4, 0.3, 0), hull.lightened(0.15))
			# rack of mines (spheres) on the aft deck
			for mx in [-0.75, -0.5, -0.25]:
				_part(body, _sphere(0.11), Vector3(mx, 0.28, 0.14), accent)
				_part(body, _sphere(0.11), Vector3(mx, 0.28, -0.14), accent)
		"hovercraft":
			# wide low flat skirt + lift fan — sits a touch above the water
			_part(body, _box(Vector3(1.5, 0.22, 0.9)), Vector3(0, 0.12, 0), accent.darkened(0.1))
			_part(body, _box(Vector3(1.0, 0.24, 0.6)), Vector3(0, 0.34, 0), hull)
			_part(body, _cyl(0.28, 0.14), Vector3(-0.45, 0.5, 0), accent)  # fan
		"battleship_flagship":
			_part(body, _box(Vector3(2.8, 0.42, 0.7)), Vector3.ZERO, hull)              # big hull
			_part(body, _box(Vector3(0.7, 0.6, 0.44)), Vector3(0, 0.5, 0), hull.lightened(0.2))  # superstructure
			_part(body, _cone(0.06, 0.7), Vector3(0, 1.0, 0), accent)                   # mast/flag
			for tx in [-0.9, 0.0, 0.9]:                                                 # triple main turrets
				_part(body, _cyl(0.16, 0.24), Vector3(tx, 0.36, 0), accent)
				_part(body, _cyl(0.05, 0.4), Vector3(tx + 0.25, 0.42, 0), accent, Vector3(0, 0, 80))
		"carrier":
			_part(body, _box(Vector3(3.0, 0.3, 0.9)), Vector3(0, 0.1, 0), hull)         # hull
			_part(body, _box(Vector3(3.0, 0.08, 1.0)), Vector3(0, 0.32, 0), accent)     # flat flight deck
			_part(body, _box(Vector3(0.5, 0.5, 0.25)), Vector3(0.4, 0.6, 0.32), hull.lightened(0.2))  # island
			# centreline deck stripe
			_part(body, _box(Vector3(2.6, 0.02, 0.08)), Vector3(0, 0.37, 0), Color(0.95, 0.95, 0.95))
		"submarine_shallow":
			_part(body, _capsule(0.28, 1.8), Vector3.ZERO, hull, Vector3(0, 0, 90))     # cigar hull along X
			_part(body, _box(Vector3(0.4, 0.26, 0.3)), Vector3(0, 0.28, 0), hull.lightened(0.15))  # conning tower
			_part(body, _cyl(0.04, 0.6), Vector3(0.05, 0.6, 0), accent)                 # raised periscope
		"submarine_deep":
			_part(body, _capsule(0.3, 2.0), Vector3.ZERO, hull.darkened(0.15), Vector3(0, 0, 90))
			_part(body, _box(Vector3(0.44, 0.28, 0.32)), Vector3(0, 0.3, 0), accent)    # accent sail, no periscope
		"midget_sub":
			_part(body, _capsule(0.2, 1.0), Vector3.ZERO, hull.darkened(0.1), Vector3(0, 0, 90))
			_part(body, _box(Vector3(0.22, 0.18, 0.2)), Vector3(0, 0.2, 0), accent)
		"patrol_plane":
			_part(body, _box(Vector3(1.5, 0.24, 0.28)), Vector3.ZERO, accent)           # fuselage
			_part(body, _box(Vector3(0.4, 0.06, 2.0)), Vector3(0.1, 0.06, 0), accent.darkened(0.1))  # main wings
			_part(body, _box(Vector3(0.35, 0.06, 0.8)), Vector3(-0.65, 0.06, 0), accent.darkened(0.1))  # tailplane
			_part(body, _box(Vector3(0.3, 0.35, 0.06)), Vector3(-0.65, 0.2, 0), accent.darkened(0.1))   # tail fin
			_part(body, _cone(0.13, 0.3), Vector3(0.85, 0, 0), hull, Vector3(0, 0, -90))  # nose
		_:
			_part(body, _box(Vector3(1.6, 0.34, 0.5)), Vector3.ZERO, hull)
			_part(body, _cyl(0.12, 0.22), Vector3(0, 0.28, 0), accent)
