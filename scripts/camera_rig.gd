extends Node3D
## Camera rig anchored on a target node (the hero).
## The camera orbits around that point:
##   - right mouse button drag, or A/D keys: rotate around the target
##   - W/S keys: lower/raise the camera angle
##   - mouse wheel: zoom in/out (orthographic size)
## Arrows are left to the player script which moves the hero.

const KEY_ROTATE_SPEED := deg_to_rad(120.0)
const KEY_TILT_SPEED := deg_to_rad(75.0)
const MOUSE_ROTATE_SPEED := 0.008
const MOUSE_TILT_SPEED := 0.006
const ZOOM_FACTOR := 1.15
const DEFAULT_ORTHO_SIZE := 16.0
const MIN_ORTHO_SIZE := 8.0
const MAX_ORTHO_SIZE := 60.0
const MIN_ELEVATION := deg_to_rad(10.0)
const MAX_ELEVATION := deg_to_rad(85.0)

@export var target_path: NodePath
@export var distance := 18.0

@onready var _target: Node3D = get_node_or_null(target_path)
@onready var _camera: Camera3D = $Camera3D

var _azimuth := deg_to_rad(45.0)
var _elevation := deg_to_rad(35.264)


func _ready() -> void:
	if _target == null:
		push_warning("CameraRig: target not found, camera stays put.")
		return
	_camera.size = DEFAULT_ORTHO_SIZE
	_follow()
	_apply()


## Orbiting keeps the rig origin on the target; the camera lacks any offset
## except the one derived from the orbit angles and distance.
func _apply() -> void:
	var offset := Vector3(
		sin(_azimuth) * cos(_elevation),
		sin(_elevation),
		cos(_azimuth) * cos(_elevation),
	) * distance
	_camera.position = offset
	_camera.look_at(global_position, Vector3.UP)


func _follow() -> void:
	if _target:
		global_position = _target.global_position


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_A):
		_azimuth -= KEY_ROTATE_SPEED * delta
	if Input.is_key_pressed(KEY_D):
		_azimuth += KEY_ROTATE_SPEED * delta
	if Input.is_key_pressed(KEY_W):
		_elevation = clampf(_elevation + KEY_TILT_SPEED * delta, MIN_ELEVATION, MAX_ELEVATION)
	if Input.is_key_pressed(KEY_S):
		_elevation = clampf(_elevation - KEY_TILT_SPEED * delta, MIN_ELEVATION, MAX_ELEVATION)
	_follow()
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed:
			match mouse.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_camera.size = clampf(_camera.size / ZOOM_FACTOR, MIN_ORTHO_SIZE, MAX_ORTHO_SIZE)
					_apply()
				MOUSE_BUTTON_WHEEL_DOWN:
					_camera.size = clampf(_camera.size * ZOOM_FACTOR, MIN_ORTHO_SIZE, MAX_ORTHO_SIZE)
					_apply()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_azimuth -= motion.relative.x * MOUSE_ROTATE_SPEED
			_elevation = clampf(_elevation + motion.relative.y * MOUSE_TILT_SPEED, MIN_ELEVATION, MAX_ELEVATION)
			_apply()
