class_name GameUI
extends CanvasLayer
## Touch-first HUD + build bar. Large tap targets, bottom-anchored build
## bar per the doc's Android-front-loaded design; mouse works identically.

signal build_requested(unit_id: String)
signal income_requested
signal installment_requested
signal flagship_fire_requested
signal restart_requested

var _gold_label: Label
var _base_label: Label
var _enemy_label: Label
var _phase_label: Label
var _weather_label: Label
var _build_bar: HBoxContainer
var _fire_button: Button
var _result_panel: PanelContainer
var _result_label: Label

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("separation", 2)
	root.add_child(top)

	_gold_label = _hud_label()
	_base_label = _hud_label()
	_enemy_label = _hud_label()
	var status_row := HBoxContainer.new()
	_phase_label = _hud_label()
	_weather_label = _hud_label()
	status_row.add_child(_phase_label)
	status_row.add_child(_weather_label)
	top.add_child(_gold_label)
	top.add_child(_base_label)
	top.add_child(_enemy_label)
	top.add_child(status_row)

	_fire_button = Button.new()
	_fire_button.text = "FIRE FLAGSHIP"
	_fire_button.custom_minimum_size = Vector2(0, 64)
	_fire_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_fire_button.position = Vector2(-100, -190)
	_fire_button.custom_minimum_size = Vector2(200, 64)
	_fire_button.visible = false
	_fire_button.pressed.connect(func(): flagship_fire_requested.emit())
	root.add_child(_fire_button)

	_build_bar = HBoxContainer.new()
	_build_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_build_bar.add_theme_constant_override("separation", 4)
	root.add_child(_build_bar)

	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.visible = false
	var vb := VBoxContainer.new()
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 32)
	var restart_btn := Button.new()
	restart_btn.text = "Play Again"
	restart_btn.custom_minimum_size = Vector2(160, 56)
	restart_btn.pressed.connect(func(): restart_requested.emit())
	vb.add_child(_result_label)
	vb.add_child(restart_btn)
	_result_panel.add_child(vb)
	root.add_child(_result_panel)

func _hud_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 18)
	return l

func build_bar_for_roster(roster: Array, catalog: Catalog) -> void:
	for child in _build_bar.get_children():
		child.queue_free()
	for uid in roster:
		var udef: Dictionary = catalog.units[uid]
		var btn := Button.new()
		btn.text = "%s\n%d" % [String(udef["name"]), int(udef["cost"])]
		btn.custom_minimum_size = Vector2(84, 64)
		btn.pressed.connect(func(): build_requested.emit(uid))
		_build_bar.add_child(btn)
	var income_btn := Button.new()
	income_btn.text = "Income\nUpgrade"
	income_btn.custom_minimum_size = Vector2(84, 64)
	income_btn.pressed.connect(func(): income_requested.emit())
	_build_bar.add_child(income_btn)
	var installment_btn := Button.new()
	installment_btn.text = "Cost\nUpgrade"
	installment_btn.custom_minimum_size = Vector2(84, 64)
	installment_btn.pressed.connect(func(): installment_requested.emit())
	_build_bar.add_child(installment_btn)

func sync(live: LiveMatch) -> void:
	_gold_label.text = "Gold: %d" % int(live.gold())
	_base_label.text = "Your Base: %d / %d" % [int(live.base_hp()), int(live.base_hp_max())]
	_enemy_label.text = "Enemy Base: %d / %d" % [int(live.enemy_base_hp()), int(live.enemy_base_hp_max())]
	_phase_label.text = "Phase: %s" % live.phase
	_weather_label.text = "  Weather: %s" % live.weather_id
	_fire_button.visible = live.phase == MatchSim.PHASE_BOSS

	if live.is_over():
		_result_panel.visible = true
		_result_label.text = "VICTORY" if live.result == "WIN" else "DEFEAT"
