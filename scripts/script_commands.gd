extends RefCounted
class_name ScriptCommands
## Entity behaviour scripts, a faithful port of landstalker-py
## script_commands.py: every behaviour YAML is a list of commands; the
## interpreter calls one command every physics tick, re-entering multi-tick
## commands each frame via `current_command_state` until they return true.
## Commands drive the entity through ScriptCommands.entity (an EntityActor)
## and read the room through ScriptCommands.level (level.gd tiles).
## Several py commands are stubs; they are stubbed here too so missing
## features are visible in logs instead of derailing the script.

const VERBOSE := false

var entity: EntityActor
var level: Node

var is_running := false
var script_commands: Array = []      # [[name, params], ...]
var current_command_index := 0
var current_command_state = null     # per-command persistent state between ticks
var should_loop := true
var waiting_for_condition := false
var wait_condition_type := 0

var _handlers := {
	# Movement
	"MoveRelative": cmd_move_relative,
	"MoveAbsolute": cmd_move_absolute,
	"MoveTimed": cmd_move_timed,
	"MoveRandomTimed": cmd_move_random_timed,
	"MoveNoClip": cmd_move_no_clip,
	"MoveUntilCollision": cmd_move_until_collision,
	"MoveUpRelative": cmd_move_up_relative,
	"MoveUpAbsolute": cmd_move_up_absolute,
	"MoveUpTimed": cmd_move_up_timed,
	"MoveUpToInitPos": cmd_move_up_to_init_pos,
	"MoveDownRelative": cmd_move_down_relative,
	"MoveDownAbsolute": cmd_move_down_absolute,
	"MoveDownTimed": cmd_move_down_timed,
	"MoveDownUntilCollision": cmd_move_down_until_collision,
	"MoveToXYPosImmedite": cmd_move_to_xy_pos_immediate,
	"MoveToZPosImmediate": cmd_move_to_z_pos_immediate,
	"SetTargetPosition": cmd_set_target_position,
	"MoveToTargetPosition": cmd_move_to_target_position,
	"NudgeUp": cmd_nudge_up,
	"ResetToInitialPos": cmd_reset_to_initial_pos,
	"Jump": cmd_jump,

	# Rotation
	"TurnCW": cmd_turn_cw,
	"TurnCWImmediate": cmd_turn_cw,
	"TurnCWNoUpdate": cmd_turn_cw_no_update,
	"TurnCCW": cmd_turn_ccw,
	"TurnCCWImmedate": cmd_turn_ccw,
	"TurnCCWNoUpdate": cmd_turn_ccw_no_update,
	"Turn180": cmd_turn_180,
	"Turn180Immediate": cmd_turn_180,
	"Turn180NoUpdate": cmd_turn_180_no_update,
	"TurnNE": cmd_turn_ne,
	"TurnNEImmediate": cmd_turn_ne,
	"TurnNENoUpdate": cmd_turn_ne_no_update,
	"TurnNW": cmd_turn_nw,
	"TurnNWImmediate": cmd_turn_nw,
	"TurnNWNoUpdate": cmd_turn_nw_no_update,
	"TurnSE": cmd_turn_se,
	"TurnSEImmediate": cmd_turn_se,
	"TurnSENoUpdate": cmd_turn_se_no_update,
	"TurnSW": cmd_turn_sw,
	"TurnSWImmediate": cmd_turn_sw,
	"TurnSWNoUpdate": cmd_turn_sw_no_update,
	"TurnRandom": cmd_turn_random,
	"TurnRandomImmediate": cmd_turn_random,
	"TurnToFace": cmd_turn_to_face,
	"RotatePlayer": cmd_rotate_player,
	"UpdateSpriteOrientation": cmd_update_sprite_orientation,

	# Timing
	"Pause": cmd_pause,
	"Pause4s": cmd_pause_4s,
	"Freeze": cmd_freeze,

	# Speed
	"SlowSpeed": cmd_slow_speed,
	"NormalSpeed": cmd_normal_speed,
	"FastSpeed": cmd_fast_speed,
	"XFastSpeed": cmd_xfast_speed,
	"SetObjectSpeed": cmd_set_object_speed,

	# Visibility / physics toggles
	"SetVisible": cmd_set_visible,
	"SetSolid": cmd_set_solid,
	"MakeVisible": cmd_make_visible,
	"MakeInvisible": cmd_make_invisible,
	"Hide": cmd_hide,
	"RemoveSprite": cmd_remove_sprite,
	"ShowWhenCollisionClear": cmd_show_when_collision_clear,
	"EnableGravity": cmd_enable_gravity,
	"DisableGravity": cmd_disable_gravity,
	"EnableBackwardsMovement": cmd_enable_backwards_movement,
	"DisableBackwardsMovement": cmd_disable_backwards_movement,
	"EnableFrameUpdate": cmd_enable_frame_update,
	"DisableFrameUpdate": cmd_disable_frame_update,
	"FlashSpinAppear": cmd_flash_spin_appear,
	"FlashSpinDisappear": cmd_flash_spin_disappear,
	"DecayFlash": cmd_decay_flash,

	# Sound / dialog / items
	"PlaySound": cmd_play_sound,
	"ShowDialog": cmd_show_dialog,
	"PrintText": cmd_print_text,
	"GiveItem": cmd_give_item,
	"TakeItem": cmd_take_item,

	# Conditions / flags
	"IfHasItem": cmd_if_has_item,
	"IfFlagSet": cmd_if_flag_set,
	"WaitForFlagSet": cmd_wait_for_flag_set,
	"WaitForFlagClear": cmd_wait_for_flag_clear,
	"SetFlag": cmd_set_flag,
	"ClearFlag": cmd_clear_flag,
	"WaitForCondition": cmd_wait_for_condition,

	# Switches / flow
	"ActivateSwitch": cmd_activate_switch,
	"ResetSwitch": cmd_reset_switch,
	"StartCutscene": cmd_start_cutscene,
	"StartHiCutscene": cmd_start_hi_cutscene,
	"TriggerTileSwap": cmd_trigger_tile_swap,
	"FollowPlayerNoJump": cmd_follow_player_no_jump,
	"FollowPlayerWithJump": cmd_follow_player_with_jump,
	"PlaybackInput": cmd_playback_input,
	"ResetPlayback": cmd_reset_playback,
	"GotoCommand": cmd_goto_command,
	"RepeatBegin": cmd_repeat_begin,
	"RepeatEnd": cmd_repeat_end,
	"Loop": cmd_loop,
	"End": cmd_end,

	# Unknown opcodes
	"Unknown5A": cmd_unknown,
	"UnknownB33": cmd_unknown,
	"UnknownB47": cmd_unknown,
	"UnknownB63": cmd_unknown,
	"UnknownB65": cmd_unknown,
	"UnknownB66": cmd_unknown,
	"UnknownB67": cmd_unknown,
}


func _init(target_entity: EntityActor, target_level: Node) -> void:
	entity = target_entity
	level = target_level


func start_script(commands: Array, loop := true) -> void:
	if is_running:
		return
	is_running = true
	script_commands = commands
	current_command_index = 0
	current_command_state = null
	should_loop = loop
	waiting_for_condition = false
	wait_condition_type = 0


func update() -> void:
	if not is_running or script_commands.is_empty():
		return
	if waiting_for_condition:
		return
	if current_command_index >= script_commands.size():
		if should_loop:
			current_command_index = 0
			current_command_state = null
		else:
			is_running = false
		return
	var command: Array = script_commands[current_command_index]
	var name := str(command[0])
	var params = command[1]
	if params == null:
		params = {}
	if not _handlers.has(name):
		push_warning("Unknown command %s in script of %s" % [name, entity.entity_name])
		current_command_index += 1
		current_command_state = null
		return
	var complete: bool = _handlers[name].call(params)
	if complete:
		current_command_index += 1
		current_command_state = null


func trigger_condition(condition_type: int) -> void:
	if waiting_for_condition and wait_condition_type == condition_type:
		waiting_for_condition = false
		wait_condition_type = 0
		current_command_state = null
		current_command_index += 1


## Movement direction in tiles for the current orientation (py direction_map).
func _direction() -> Vector2i:
	match entity.orientation:
		"NE": return Vector2i(0, -1)   # north-east: tile y decreases
		"SE": return Vector2i(1, 0)
		"SW": return Vector2i(0, 1)
		"NW": return Vector2i(-1, 0)
	return Vector2i(0, 0)


func _tiles_per_tick() -> float:
	return float(entity.speed) / 16.0


func _move_horizontal(dx: float, dy: float) -> void:
	var pos: Vector3 = entity.get_world_pos()
	entity.set_world_pos(pos.x + dx, pos.y + dy, pos.z)


func _turn_table_cw() -> Dictionary:
	return {"NE": "SE", "SE": "SW", "SW": "NW", "NW": "NE"}


func _turn_table_ccw() -> Dictionary:
	return {"NE": "NW", "NW": "SW", "SW": "SE", "SE": "NE"}


func _turn(table: Dictionary, no_update: bool) -> void:
	entity.set_orientation(str(table.get(entity.orientation, entity.orientation)),
		not no_update)


func _vertical_step_toward(target_z: float) -> bool:
	var pos: Vector3 = entity.get_world_pos()
	var remaining := target_z - pos.z
	var speed := _tiles_per_tick()
	if absf(remaining) < speed:
		entity.set_world_pos(pos.x, pos.y, target_z)
		return true
	entity.set_world_pos(pos.x, pos.y, pos.z + speed * signf(remaining))
	return false


# === Movement commands ===

func cmd_move_relative(params: Dictionary) -> bool:
	if current_command_state == null:
		var distance_scale := float(params.get("Distance", 0.0))
		var speed_multiplier := pow(2.0, float(entity.speed - 1))
		var distance := distance_scale * speed_multiplier
		var dir := _direction()
		var pos: Vector3 = entity.get_world_pos()
		current_command_state = {
			"target": Vector2(pos.x + dir.x * distance, pos.y + dir.y * distance),
			"dir": dir,
			"speed": _tiles_per_tick(),
		}
		entity.is_moving = true
		entity.set_moving_state(true)
	var state: Dictionary = current_command_state
	var pos: Vector3 = entity.get_world_pos()
	var remaining := Vector2(state["target"]) - Vector2(pos.x, pos.y)
	if remaining.length() < float(state["speed"]):
		entity.set_world_pos(state["target"].x, state["target"].y, pos.z)
		entity.is_moving = true
		entity.set_moving_state(false)
		if VERBOSE:
			print("[MoveRelative] complete ", entity.entity_name)
		return true
	_move_horizontal(float(state["dir"].x) * float(state["speed"]),
		float(state["dir"].y) * float(state["speed"]))
	return false


func cmd_move_absolute(params: Dictionary) -> bool:
	entity.set_world_pos(float(params.get("X", 0.0)), float(params.get("Y", 0.0)),
		float(params.get("Z", 0.0)))
	return true


func cmd_move_timed(params: Dictionary) -> bool:
	if current_command_state == null:
		var dir := _direction()
		current_command_state = {
			"ticks_remaining": int(params.get("Ticks", 0)),
			"dir": dir,
			"speed": _tiles_per_tick(),
		}
	var state: Dictionary = current_command_state
	state["ticks_remaining"] = int(state["ticks_remaining"]) - 1
	if int(state["ticks_remaining"]) <= 0:
		return true
	_move_horizontal(float(state["dir"].x) * float(state["speed"]),
		float(state["dir"].y) * float(state["speed"]))
	return false


func cmd_move_random_timed(params: Dictionary) -> bool:
	if current_command_state == null:
		# py picks a random direction without changing the sprite orientation.
		var dir := _direction_for(["NE", "SE", "SW", "NW"].pick_random())
		current_command_state = {
			"ticks_remaining": int(params.get("Ticks", 0)),
			"dir": dir,
			"speed": _tiles_per_tick(),
		}
	var state: Dictionary = current_command_state
	state["ticks_remaining"] = int(state["ticks_remaining"]) - 1
	if int(state["ticks_remaining"]) <= 0:
		return true
	_move_horizontal(float(state["dir"].x) * float(state["speed"]),
		float(state["dir"].y) * float(state["speed"]))
	return false


func _direction_for(orientation: String) -> Vector2i:
	match orientation:
		"NE": return Vector2i(0, -1)
		"SE": return Vector2i(1, 0)
		"SW": return Vector2i(0, 1)
		"NW": return Vector2i(-1, 0)
	return Vector2i(0, 0)


func cmd_move_no_clip(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_move_until_collision(_params: Dictionary = {}) -> bool:
	if current_command_state == null:
		var dir := _direction()
		current_command_state = {"dir": dir, "speed": _tiles_per_tick()}
		entity.is_moving = true
		entity.set_moving_state(true)
	var state: Dictionary = current_command_state
	var pos: Vector3 = entity.get_world_pos()
	var speed := float(entity.speed) / 16.0
	var step := Vector2(float(state["dir"].x) * speed, float(state["dir"].y) * speed)
	var next := Vector2(pos.x, pos.y) + step
	# Heightmap columns are keyed in world space (cursor - 12).
	var next_tile := Vector2i(floori(next.x), floori(next.y))
	if level != null:
		# py: out of bounds, non-walkable terrain or a climb of more than
		# one tile stops the move (and completes it).
		if not level.is_standable(next_tile - Vector2i(12, 12), pos.z):
			entity.is_moving = false
			entity.set_moving_state(false)
			return true
	entity.set_world_pos(next.x, next.y, pos.z)
	return false


func cmd_move_up_relative(params: Dictionary) -> bool:
	if current_command_state == null:
		var pos: Vector3 = entity.get_world_pos()
		current_command_state = {"target_z": pos.z + float(params.get("Distance", 0.0))}
	# py misses a return here so the ref drifts upward every cycle; port fixes it.
	return _vertical_step_toward(float(current_command_state["target_z"]))


func cmd_move_up_absolute(params: Dictionary) -> bool:
	if current_command_state == null:
		current_command_state = {"target_z": float(params.get("Distance", 0.0))}
	return _vertical_step_toward(float(current_command_state["target_z"]))


func cmd_move_up_timed(params: Dictionary) -> bool:
	if current_command_state == null:
		var pos: Vector3 = entity.get_world_pos()
		current_command_state = {
			"ticks_remaining": int(params.get("Ticks", 0)),
			"speed": _tiles_per_tick(),
		}
	var state: Dictionary = current_command_state
	state["ticks_remaining"] = int(state["ticks_remaining"]) - 1
	if int(state["ticks_remaining"]) <= 0:
		return true
	var pos: Vector3 = entity.get_world_pos()
	# py never returns False here (it falls into re-init), the port completes
	# after the countdown instead of ascending/descending forever.
	entity.set_world_pos(pos.x, pos.y, pos.z + float(state["speed"]))
	return false


func cmd_move_up_to_init_pos(_params: Dictionary = {}) -> bool:
	var init_z: float = entity.initial_position_tiles.z
	return _vertical_step_toward(init_z)


func cmd_move_down_relative(params: Dictionary) -> bool:
	if current_command_state == null:
		var pos: Vector3 = entity.get_world_pos()
		current_command_state = {"target_z": pos.z - float(params.get("Distance", 0.0))}
	return _vertical_step_toward(float(current_command_state["target_z"]))


func cmd_move_down_absolute(params: Dictionary) -> bool:
	if current_command_state == null:
		current_command_state = {"target_z": float(params.get("Distance", 0.0))}
	return _vertical_step_toward(float(current_command_state["target_z"]))


func cmd_move_down_timed(params: Dictionary) -> bool:
	if current_command_state == null:
		current_command_state = {
			"ticks_remaining": int(params.get("Ticks", 0)),
			"speed": _tiles_per_tick(),
		}
	var state: Dictionary = current_command_state
	state["ticks_remaining"] = int(state["ticks_remaining"]) - 1
	if int(state["ticks_remaining"]) <= 0:
		return true
	var pos: Vector3 = entity.get_world_pos()
	entity.set_world_pos(pos.x, pos.y, pos.z - float(state["speed"]))
	return false


func cmd_move_down_until_collision(_params: Dictionary = {}) -> bool:
	# py stub-ish: descends until the column below cannot support it longer? The
	# py port only implements generic gravity elsewhere: keep simple descending.
	var pos: Vector3 = entity.get_world_pos()
	var tile := (Vector2i(floori(pos.x), floori(pos.y))
		- Vector2i(12, 12))
	var top: float = float(level.column_top(tile)) if level != null else 0.0
	if pos.z <= top:
		return true
	entity.set_world_pos(pos.x, pos.y, pos.z - 0.25)
	return false


func cmd_move_to_xy_pos_immediate(params: Dictionary) -> bool:
	var pos: Vector3 = entity.get_world_pos()
	entity.set_world_pos(float(params.get("X", 0.0)), float(params.get("Y", 0.0)), pos.z)
	return true


func cmd_move_to_z_pos_immediate(params: Dictionary) -> bool:
	var pos: Vector3 = entity.get_world_pos()
	entity.set_world_pos(pos.x, pos.y, float(params.get("Z", 0.0)))
	return true


func cmd_set_target_position(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_move_to_target_position(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_nudge_up(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_reset_to_initial_pos(_params: Dictionary = {}) -> bool:
	var init: Vector3 = entity.initial_position_tiles
	var pos: Vector3 = entity.get_world_pos()
	entity.set_world_pos(init.x, init.y, pos.z)
	return true		# py stub; port keeps z (the tile-swap use case relies on MoveUpToInitPos for z)


func cmd_jump(_params: Dictionary) -> bool:
	return true		# stub (py)


# === Rotation commands ===

func cmd_turn_cw(_params: Dictionary = {}) -> bool:
	_turn(_turn_table_cw(), false)
	return true


func cmd_turn_cw_no_update(_params: Dictionary = {}) -> bool:
	_turn(_turn_table_cw(), true)
	return true


func cmd_turn_ccw(_params: Dictionary = {}) -> bool:
	_turn(_turn_table_ccw(), false)
	return true


func cmd_turn_ccw_no_update(_params: Dictionary = {}) -> bool:
	_turn(_turn_table_ccw(), true)
	return true


func cmd_turn_180(_params: Dictionary = {}) -> bool:
	_turn(_turn_table_cw(), false)
	_turn(_turn_table_cw(), false)
	return true


func cmd_turn_180_no_update(_params: Dictionary = {}) -> bool:
	_turn(_turn_table_cw(), true)
	_turn(_turn_table_cw(), true)
	return true


func cmd_turn_ne(_params: Dictionary = {}) -> bool:
	entity.set_orientation("NE", true)
	return true


func cmd_turn_ne_no_update(_params: Dictionary = {}) -> bool:
	entity.set_orientation("NE", false)
	return true


func cmd_turn_nw(_params: Dictionary = {}) -> bool:
	entity.set_orientation("NW", true)
	return true


func cmd_turn_nw_no_update(_params: Dictionary = {}) -> bool:
	entity.set_orientation("NW", false)
	return true


func cmd_turn_se(_params: Dictionary = {}) -> bool:
	entity.set_orientation("SE", true)
	return true


func cmd_turn_se_no_update(_params: Dictionary = {}) -> bool:
	entity.set_orientation("SE", false)
	return true


func cmd_turn_sw(_params: Dictionary = {}) -> bool:
	entity.set_orientation("SW", true)
	return true


func cmd_turn_sw_no_update(_params: Dictionary = {}) -> bool:
	entity.set_orientation("SW", false)
	return true


func cmd_turn_random(_params: Dictionary = {}) -> bool:
	entity.set_orientation(["NE", "SE", "SW", "NW"].pick_random(), true)
	return true


func cmd_turn_to_face(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_rotate_player(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_update_sprite_orientation(_params: Dictionary = {}) -> bool:
	entity.set_sheet_for_orientation()
	return true


# === Timing / speed ===

func cmd_pause(params: Dictionary) -> bool:
	if current_command_state == null:
		current_command_state = {"ticks_remaining": int(params.get("Ticks", 0))}
	current_command_state["ticks_remaining"] = int(current_command_state["ticks_remaining"]) - 1
	return int(current_command_state["ticks_remaining"]) <= 0


func cmd_pause_4s(_params: Dictionary = {}) -> bool:
	# py assumes a 60 FPS main loop.
	if current_command_state == null:
		current_command_state = {"ticks_remaining": 240}
	current_command_state["ticks_remaining"] = int(current_command_state["ticks_remaining"]) - 1
	return int(current_command_state["ticks_remaining"]) <= 0


func cmd_freeze(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_slow_speed(_params: Dictionary = {}) -> bool:
	entity.speed = 1
	return true


func cmd_normal_speed(_params: Dictionary = {}) -> bool:
	entity.speed = 2
	return true


func cmd_fast_speed(_params: Dictionary = {}) -> bool:
	if entity.speed < 3:
		entity.speed += 1
	return true


func cmd_xfast_speed(_params: Dictionary = {}) -> bool:
	entity.speed = 4
	return true


func cmd_set_object_speed(params: Dictionary) -> bool:
	entity.speed = int(params.get("Unknown1", 1))
	return true


# === Visibility / physics toggles ===

func cmd_set_visible(params: Dictionary) -> bool:
	entity.visible = bool(params.get("Visible", true))
	return true


func cmd_set_solid(params: Dictionary) -> bool:
	entity.solid = bool(params.get("Solid", true))
	return true


func cmd_make_visible(_params: Dictionary = {}) -> bool:
	entity.visible = true
	return true


func cmd_make_invisible(_params: Dictionary = {}) -> bool:
	entity.visible = false
	return true


func cmd_hide(_params: Dictionary = {}) -> bool:
	entity.visible = false
	return true


func cmd_remove_sprite(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_show_when_collision_clear(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_enable_gravity(_params: Dictionary = {}) -> bool:
	entity.gravity = true
	return true


func cmd_disable_gravity(_params: Dictionary = {}) -> bool:
	entity.gravity = false
	return true


func cmd_enable_backwards_movement(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_disable_backwards_movement(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_enable_frame_update(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_disable_frame_update(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_flash_spin_appear(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_flash_spin_disappear(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_decay_flash(_params: Dictionary) -> bool:
	return true		# stub (py)


# === Dialog / items / flags ===

func cmd_play_sound(_params: Dictionary) -> bool:
	return true		# stub (py)

func cmd_show_dialog(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_print_text(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_give_item(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_take_item(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_if_has_item(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_if_flag_set(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_wait_for_flag_set(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_wait_for_flag_clear(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_set_flag(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_clear_flag(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_wait_for_condition(params: Dictionary) -> bool:
	if current_command_state == null:
		waiting_for_condition = true
		wait_condition_type = int(params.get("Condition", 0))
		should_loop = false		# py: waiting disables looping
		current_command_state = {"condition": wait_condition_type}
	return false


func cmd_activate_switch(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_reset_switch(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_start_cutscene(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_start_hi_cutscene(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_trigger_tile_swap(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_follow_player_no_jump(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_follow_player_with_jump(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_playback_input(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_reset_playback(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


# === Flow control ===

func cmd_goto_command(params: Dictionary) -> bool:
	# py stores index - 1 because update() increments after completion.
	current_command_index = maxi(int(params.get("Command", 0)) - 1, -1)
	return true


func cmd_repeat_begin(_params: Dictionary) -> bool:
	return true		# stub (py)


func cmd_repeat_end(_params: Dictionary = {}) -> bool:
	return true		# stub (py)


func cmd_loop(_params: Dictionary = {}) -> bool:
	current_command_index = -1
	return true


func cmd_end(_params: Dictionary = {}) -> bool:
	is_running = false
	return true


func cmd_unknown(_params: Dictionary) -> bool:
	return true
