extends Node3D
## v0.2 presentation root: owns a LiveMatch, renders it, and forwards
## touch/mouse UI commands into the sim's player-facing API. This node
## reads sim state every tick and never mutates it directly — all writes
## go through LiveMatch.build()/buy_income()/etc.

const TICKS_PER_SECOND := 8.0
const LEVEL_ID := "level_01"
const PLAYER_STRATEGY_SEED_MIN := 1
const PLAYER_STRATEGY_SEED_MAX := 999999

var catalog: Catalog
var live: LiveMatch
var camera_rig: CameraRig
var ships: ShipVisuals
var ui: GameUI
var _accum := 0.0
var _running := true

func _ready() -> void:
	catalog = Catalog.load_from("res://")
	_setup_world()
	_setup_camera()
	ships = ShipVisuals.new()
	add_child(ships)
	ui = GameUI.new()
	add_child(ui)
	ui.build_requested.connect(_on_build_requested)
	ui.income_requested.connect(_on_income_requested)
	ui.installment_requested.connect(_on_installment_requested)
	ui.flagship_fire_requested.connect(_on_flagship_fire)
	ui.restart_requested.connect(_start_new_match)
	_start_new_match()

func _start_new_match() -> void:
	var level: Dictionary = catalog.levels_by_id[LEVEL_ID]
	var seed_value := randi_range(PLAYER_STRATEGY_SEED_MIN, PLAYER_STRATEGY_SEED_MAX)
	live = LiveMatch.new(level, catalog, seed_value)
	ui.build_bar_for_roster(level["player_roster"], catalog)
	_running = true
	_accum = 0.0

func _process(delta: float) -> void:
	if _running and live != null:
		_accum += delta
		var step_interval := 1.0 / TICKS_PER_SECOND
		while _accum >= step_interval:
			_accum -= step_interval
			live.step()
			if live.is_over():
				_running = false
				break
		ships.sync(live, catalog)
		ui.sync(live)

func _on_build_requested(unit_id: String) -> void:
	if live != null:
		live.build(unit_id)

func _on_income_requested() -> void:
	if live != null:
		live.buy_income()

func _on_installment_requested() -> void:
	if live != null:
		live.buy_installment()

func _on_flagship_fire() -> void:
	if live != null:
		live.aim_flagship_shot()

func _setup_world() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.09, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.48)
	env.ambient_light_energy = 0.6
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	add_child(sun)

	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 60)
	plane.subdivide_width = 60
	plane.subdivide_depth = 30
	ocean.mesh = plane
	var shader := load("res://presentation/ocean.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	ocean.material_override = mat
	add_child(ocean)

func _setup_camera() -> void:
	camera_rig = CameraRig.new()
	add_child(camera_rig)
