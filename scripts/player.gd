extends CharacterBody3D
## Hero replicated from the pygame implementation (landstalker-py hero.py).
## Animation frames are sliced from the game's data sprite sheets
## (data/sprites/SpriteGfx000Anim*.png, 32x48 frames), exactly like
## drawable.extract_frames: two view sets (back for NE/NW, front for SW/SE)
## with a horizontal flip for NW/SE; states: jump/airborne > walk > idle.
## Movement runs along the camera-relative isometric diagonals with the
## pygame key priority: left > right > up > down.

const SPEED := 7.5                 # 2 px/frame * 60 fps / 16 px per tile
const JUMP_VELOCITY = 4.5
const FRAME_STEP_TIME := 0.1111    # 0.15/tick at 60 Hz: one frame per step
const FRAME_WIDTH := 32
const FRAME_HEIGHT := 48

enum Orientation { NE, NW, SW, SE }

const SPRITE_SHEET_DIR := "res://data/sprites/"
# Matches hero.py _load_animations: animation -> [sheet file, frame count]
const _ANIM_SHEETS := {
	"idle_back": ["SpriteGfx000Anim000.png", 1],
	"idle_front": ["SpriteGfx000Anim001.png", 1],
	"walk_back": ["SpriteGfx000Anim002.png", 8],
	"walk_front": ["SpriteGfx000Anim003.png", 8],
	"pickup_back": ["SpriteGfx000Anim004.png", 3],
	"pickup_front": ["SpriteGfx000Anim005.png", 3],
	"carry_walk_back": ["SpriteGfx000Anim006.png", 8],
	"carry_walk_front": ["SpriteGfx000Anim007.png", 8],
	"jump_back": ["SpriteGfx000Anim008.png", 2],
	"jump_front": ["SpriteGfx000Anim009.png", 2],
	"carry_jump_back": ["SpriteGfx000Anim010.png", 2],
	"carry_jump_front": ["SpriteGfx000Anim011.png", 2],
}

@onready var _sprite: Sprite3D = $Sprites

var _anims := {}                 # key: "walk_back" etc -> Array[AtlasTexture]
var _current_frames: Array = []
var _current_anim := ""
var _current_frame := 0
var _frame_timer := 0.0
var _jumping := false
var is_grabbing := false


func _ready() -> void:
	_load_animations()
	_set_animation("idle_front")


func _load_animations() -> void:
	for anim_name: String in _ANIM_SHEETS:
		var cfg: Array = _ANIM_SHEETS[anim_name]
		var sheet: Texture2D = load(SPRITE_SHEET_DIR + cfg[0])
		var frames: Array = []
		for i: int in cfg[1]:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(i * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)
			frames.append(atlas)
		_anims[anim_name] = frames
	# Carry idle shows the first pickup frame, as built in hero.py.
	_anims["carry_idle_back"] = [_anims["pickup_back"][0]]
	_anims["carry_idle_front"] = [_anims["pickup_front"][0]]


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


## Replicates hero.__get_animation_name + _update_frame_index + drawable
## update_animation_frame, with display_rotated handled by flip_h.
func _update_animation(delta: float, moving: bool, orientation: int) -> void:
	var prefix := "carry_" if is_grabbing else ""
	var facing := "back" if (orientation == Orientation.NE or orientation == Orientation.NW) else "front"
	var state: String
	if not is_on_floor():
		# Jump animation: frame 0 while ascending or jumping, frame 1 when falling.
		state = "jump"
	elif moving:
		state = "walk"
	else:
		state = "idle"
	_set_animation(prefix + state + "_" + facing)
	_sprite.flip_h = orientation == Orientation.NW or orientation == Orientation.SE

	if _current_frames.size() <= 1:
		return
	if not is_on_floor():
		_current_frame = 0 if (_jumping or velocity.y > 0.0) else 1
		_frame_timer = 0.0
	elif moving:
		_frame_timer += delta
		while _frame_timer >= FRAME_STEP_TIME:
			_frame_timer -= FRAME_STEP_TIME
			_current_frame = (_current_frame + 1) % _current_frames.size()
	_sprite.texture = _current_frames[_current_frame]


func _set_animation(anim_name: String) -> void:
	if anim_name == _current_anim or not _anims.has(anim_name):
		return
	_current_anim = anim_name
	_current_frame = 0
	_frame_timer = 0.0
	_current_frames = _anims[anim_name]
	_sprite.texture = _current_frames[0]
