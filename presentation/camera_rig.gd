class_name CameraRig
extends Node3D
## Free 3D camera over the lane: drag-pan (mouse or single-finger touch)
## and pinch-zoom (two-finger touch) or mouse-wheel zoom on desktop.
## Mouse input maps onto the same pan/zoom the touch path uses, per the
## design doc's "mouse maps onto this for free."

@export var pan_bounds := Vector2(60.0, 20.0)
@export var zoom_min := 8.0
@export var zoom_max := 45.0
@export var pan_speed := 0.05

var _camera: Camera3D
var _distance := 19.0
var _dragging := false
var _drag_touch_index := -1
var _pinch_start_distance := -1.0
var _touch_positions: Dictionary = {}

func _ready() -> void:
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, 0)
	add_child(_camera)
	_apply_distance()

func _apply_distance() -> void:
	_camera.transform = Transform3D.IDENTITY
	_camera.position = Vector3(0, _distance * 0.62, _distance)
	_camera.look_at(Vector3(position.x, 0, 0), Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-2.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(2.0)
	elif event is InputEventMouseMotion and _dragging:
		_pan(event.relative)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_positions[st.index] = st.position
		else:
			_touch_positions.erase(st.index)
			_pinch_start_distance = -1.0
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touch_positions[sd.index] = sd.position
		if _touch_positions.size() == 1:
			_pan(sd.relative)
		elif _touch_positions.size() == 2:
			_handle_pinch()

func _handle_pinch() -> void:
	var positions := _touch_positions.values()
	var dist: float = positions[0].distance_to(positions[1])
	if _pinch_start_distance < 0.0:
		_pinch_start_distance = dist
		return
	var delta := _pinch_start_distance - dist
	_zoom(delta * 0.05)
	_pinch_start_distance = dist

func _pan(rel: Vector2) -> void:
	position.x = clamp(position.x - rel.x * pan_speed, -pan_bounds.x, pan_bounds.x)
	position.z = clamp(position.z + rel.y * pan_speed, -pan_bounds.y, pan_bounds.y)
	_apply_distance()

func _zoom(delta: float) -> void:
	_distance = clamp(_distance + delta, zoom_min, zoom_max)
	_apply_distance()
