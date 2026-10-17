extends CharacterBody3D
## Hero replicated from the pygame implementation (landstalker-py hero.py).
## Two directional sprites (up = seen from the back, down = facing camera)
## plus horizontal flips cover the four isometric orientations; frame sets:
## idle (1 frame), walk (8 frames, advanced on a fixed timer), jump (2 frames,
## ascending/descending). Movement runs along the camera-relative isometric
## diagonals with the pygame key priority: left > right > up > down.

const SPEED := 7.5                 # 2 px/frame * 60 fps / 16 px per tile
const JUMP_VELOCITY = 4.5
const FRAME_STEP_TIME := 0.11      # ~9 frames/s walk cycle as in sprite.py

enum Orientation { NE, NW, SW, SE }

# Sprite files below assets/hero/, mirroring the pygame animation config.
const _ANIM_FILES := {
	"up": {
		"idle": ["up.png"],
		"walk": ["walk_up_0.png", "walk_up_1.png", "walk_up_2.png", "walk_up_3.png",
			"walk_up_4.png", "walk_up_5.png", "walk_up_6.png", "walk_up_7.png"],
		"jump": ["jump_up_0.png", "jump_up_1.png"],
	},
	"down": {
		"idle": ["down.png"],
		"walk": ["walk_down_0.png", "walk_down_1.png", "walk_down_2.png", "walk_down_3.png",
			"walk_down_4.png", "walk_down_5.png", "walk_down_6.png", "walk_down_7.png"],
		"jump": ["jump_down_0.png", "jump_down_1.png"],
	},
}

@onready var _sprite: Sprite3D = $Sprites

var _anims := {}                 # key: "walk_up" etc -> Array[Texture2D]
var _current_anim := ""
var _current_frame := 0
var _frame_timer := 0.0
var _jumping := false


func _ready() -> void:
	_load_animations()
	_apply_sprite("down", "idle")


func _load_animations() -> void:
	for facing in ["up", "down"]:
		for state in ["idle", "walk", "jump"]:
			var textures: Array = []
			for file: String in _ANIM_FILES[facing][state]:
				textures.append(load("res://assets/hero/" + file))
			_anims["%s_%s" % [state, facing]] = textures


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		_jumping = true
	if _jumping and is_on_floor():
		_jumping = false

	# Facing and movement: pygame keeps a single movement axis with key
	# priority left > right > up > down (even when blocked, facing updates).
	var orientation: int = Orientation.SW
	var moving := false
	if Input.is_action_pressed("ui_left"):
		orientation = Orientation.NW
		moving = true
	elif Input.is_action_pressed("ui_right"):
		orientation = Orientation.SE
		moving = true
	elif Input.is_action_pressed("ui_up"):
		orientation = Orientation.NE
		moving = true
	elif Input.is_action_pressed("ui_down"):
		orientation = Orientation.SW
		moving = true
	if moving:
		var axis := _iso_axis(orientation)
		velocity.x = axis.x * SPEED
		velocity.z = axis.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	move_and_slide()

	_update_animation(delta, moving, orientation)


## World direction matching a screen isometric diagonal, so the hero sprite
## cycle and travel direction stay in sync whatever the camera orbit.
func _iso_axis(orientation: int) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	match orientation:
		Orientation.NE:
			return (forward + right).normalized()
		Orientation.NW:
			return (forward - right).normalized()
		Orientation.SW:
			return (-forward - right).normalized()
		Orientation.SE:
			return (right - forward).normalized()
	return Vector3.ZERO


## Replicates hero.update_animation / _update_frame_index in the pygame code.
func _update_animation(delta: float, moving: bool, orientation: int) -> void:
	var facing := "up" if (orientation == Orientation.NE or orientation == Orientation.NW) else "down"
	if not is_on_floor():
		# Jump animation: frame 0 while ascending or jumping, frame 1 when falling.
		_apply_sprite(facing, "jump")
		_sprite.frame = 0 if (_jumping or velocity.y > 0.0) else 1
		return
	var spr_name := "walk" if moving else "idle"
	_set_flip(orientation)
	_apply_sprite(facing, spr_name)
	_sprite.frame = _current_frame
	if not moving:
		_frame_timer = 0.0
		return
	_frame_timer += delta
	if _frame_timer >= FRAME_STEP_TIME:
		_frame_timer = 0.0
		_current_frame = (_current_frame + 1) % _anims[_current_anim].size()
		_sprite.frame = _current_frame


func _apply_sprite(facing: String, spr_name: String) -> void:
	var key := "%s_%s" % [spr_name, facing]
	if key == _current_anim:
		return
	_current_anim = key
	_current_frame = 0
	_frame_timer = 0.0
	_sprite.texture = _anims[key][0]
	_sprite.hframes = _anims[key].size()
	_sprite.frame = 0


func _set_flip(orientation: int) -> void:
	_sprite.flip_h = orientation == Orientation.NW or orientation == Orientation.SE
