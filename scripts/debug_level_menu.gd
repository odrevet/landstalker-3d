extends CanvasLayer
## Debug panel letting you jump to any generated room scene.
## Shared through scenes/level.tscn, so every room has it for free.
## Toggle the panel with F12.

const ROOMS_DIR := "res://scenes/rooms"
const TOGGLE_KEY := KEY_F12

var _paths: PackedStringArray = []
var _names: PackedStringArray = []


func _ready() -> void:
	layer = 100
	_collect_room_scenes()
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == TOGGLE_KEY:
		visible = not visible
		get_viewport().set_input_as_handled()


func _collect_room_scenes() -> void:
	var dir := DirAccess.open(ROOMS_DIR)
	if dir == null:
		push_warning("DebugLevelMenu: cannot open %s." % ROOMS_DIR)
		return
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			_names.append(file.trim_suffix(".tscn"))
			_paths.append(ROOMS_DIR + "/" + file)
	_names.sort()
	_paths.sort()


func _build_ui() -> void:
	if _names.is_empty():
		set_process(false)
		return

	var panel := PanelContainer.new()
	panel.position = Vector2(8.0, 8.0)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Change level (F12 to hide)"
	box.add_child(title)

	_add_room_info(box)

	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for name in _names:
		option.add_item(name)
	box.add_child(option)

	option.item_selected.connect(_on_level_selected)
	option.select(_current_level_index())


## Map name and warp info are stored as scene metadata by
## mapdata/convert_tmx_to_tscn.py when rooms are generated.
func _add_room_info(box: VBoxContainer) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var name_label := Label.new()
	var room_name := String(scene.get_meta("room_name", ""))
	if not room_name.is_empty():
		name_label.text = room_name
		box.add_child(name_label)

	var info_parts := PackedStringArray()
	var room_map := String(scene.get_meta("room_map", ""))
	if not room_map.is_empty():
		info_parts.append(room_map)
	info_parts.append(_warp_summary(scene))
	var info_label := Label.new()
	info_label.text = " · ".join(info_parts)
	box.add_child(info_label)


func _warp_summary(scene: Node) -> String:
	var parts := PackedStringArray()
	var warps: Array = JSON.parse_string(String(scene.get_meta("warps_json", "[]")))
	parts.append(
		"warp" if warps.size() == 1 else "%d warps" % warps.size()
	)
	var fall := int(scene.get_meta("warp_fall_dest", -1))
	if fall >= 0:
		parts.append("fall → %s" % _room_name(fall))
	var climb := int(scene.get_meta("warp_climb_dest", -1))
	if climb >= 0:
		parts.append("climb → %s" % _room_name(climb))
	return " · ".join(parts)


## Room numbers index into the same RoomNNN scene set.
func _room_name(number: int) -> String:
	return "Room%03d" % number


func _current_level_index() -> int:
	var scene := get_tree().current_scene
	if scene == null:
		return 0
	var index := _names.find(String(scene.scene_file_path).get_file().get_basename())
	return maxi(index, 0)


func _on_level_selected(index: int) -> void:
	if index < 0 or index >= _paths.size():
		return
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == _paths[index]:
		return
	get_tree().change_scene_to_file(_paths[index])
