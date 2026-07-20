class_name GameUI
extends CanvasLayer
## Touch-first HUD + build bar. Large tap targets, bottom-anchored build
## bar per the doc's Android-front-loaded design; mouse works identically.

signal build_requested(unit_id: String)
signal income_requested
signal installment_requested
signal flagship_fire_requested
signal restart_requested
signal skill_unlock_requested(skill_id: String)

var _gold_label: Label
var _base_label: Label
var _enemy_label: Label
var _phase_label: Label
var _weather_label: Label
var _era_label: Label
var _build_bar: HBoxContainer
var _fire_button: Button
var _result_panel: PanelContainer
var _result_label: Label
var _start_hint: Label
var _skills_button: Button
var _skills_panel: PanelContainer
var _skills_list: VBoxContainer
var _meta_points_label: Label

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
	_era_label = _hud_label()
	status_row.add_child(_phase_label)
	status_row.add_child(_weather_label)
	status_row.add_child(_era_label)
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

	# Shown until the player's first build/upgrade. The match is frozen until
	# then (see LiveMatch), so this tells the player to tap in rather than
	# leaving them staring at a still board thinking it's stuck.
	_start_hint = Label.new()
	_start_hint.text = "Tap a ship below to deploy and begin the battle"
	_start_hint.add_theme_font_size_override("font_size", 22)
	_start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_hint.set_anchors_preset(Control.PRESET_CENTER)
	_start_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_start_hint.position = Vector2(-260, 40)
	_start_hint.custom_minimum_size = Vector2(520, 0)
	root.add_child(_start_hint)

	_skills_button = Button.new()
	_skills_button.text = "Skills"
	_skills_button.custom_minimum_size = Vector2(90, 48)
	_skills_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skills_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skills_button.pressed.connect(func(): _skills_panel.visible = not _skills_panel.visible)
	root.add_child(_skills_button)

	_skills_panel = PanelContainer.new()
	_skills_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skills_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skills_panel.position.y = 52
	_skills_panel.custom_minimum_size = Vector2(240, 0)
	_skills_panel.visible = false
	var skills_vb := VBoxContainer.new()
	_meta_points_label = Label.new()
	_meta_points_label.add_theme_font_size_override("font_size", 16)
	skills_vb.add_child(_meta_points_label)
	_skills_list = VBoxContainer.new()
	skills_vb.add_child(_skills_list)
	_skills_panel.add_child(skills_vb)
	root.add_child(_skills_panel)

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

func refresh_skills(catalog: Catalog, state: Dictionary) -> void:
	_meta_points_label.text = "Meta Points: %d" % int(state.get("meta_points", 0.0))
	for child in _skills_list.get_children():
		child.queue_free()
	var unlocked: Array = state.get("unlocked", [])
	for skill_id in catalog.skills.keys():
		var sdef: Dictionary = catalog.skills[skill_id]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size = Vector2(150, 0)
		label.add_theme_font_size_override("font_size", 13)
		if unlocked.has(skill_id):
			label.text = "%s ✓" % String(sdef["name"])
			row.add_child(label)
		else:
			label.text = "%s (%d)" % [String(sdef["name"]), int(sdef["cost"])]
			row.add_child(label)
			var btn := Button.new()
			btn.text = "Unlock"
			btn.custom_minimum_size = Vector2(70, 36)
			btn.disabled = not SkillProgress.can_unlock(state, catalog, skill_id)
			btn.pressed.connect(func(): skill_unlock_requested.emit(skill_id))
			row.add_child(btn)
		_skills_list.add_child(row)

func sync(live: LiveMatch) -> void:
	_gold_label.text = "Gold: %d" % int(live.gold())
	_base_label.text = "Your Base: %d / %d" % [int(live.base_hp()), int(live.base_hp_max())]
	_enemy_label.text = "Enemy Base: %d / %d" % [int(live.enemy_base_hp()), int(live.enemy_base_hp_max())]
	_phase_label.text = "Phase: %s" % live.phase
	_weather_label.text = "  Weather: %s" % live.weather_id
	_era_label.text = "  Era: %s" % live.era_name()
	_fire_button.visible = live.phase == MatchSim.PHASE_BOSS
	_start_hint.visible = not live.started and not live.is_over()

	if live.is_over():
		_result_panel.visible = true
		_result_label.text = "VICTORY" if live.result == "WIN" else "DEFEAT"
