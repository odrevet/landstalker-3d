extends CanvasLayer
## Debug panel letting you jump to any generated room scene.
## Shared through scenes/level.tscn, so every room has it for free.
## Toggle the panel with F12.

const ROOMS_DIR := "res://scenes/rooms"
const TOGGLE_KEY := KEY_F12

var _paths: PackedStringArray = []
var _names: PackedStringArray = []
var _titles: PackedStringArray = []

var _option: OptionButton
var _title_scan_thread: Thread

## Static so a shared menu reuses titles scanned by a previous room scene.
static var _cached_titles: PackedStringArray = PackedStringArray()
static var _titles_loaded := false


func _ready() -> void:
	layer = 100
	_collect_room_scenes()
	_build_ui()


func _exit_tree() -> void:
	_stop_title_scan_thread()


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

	_option = OptionButton.new()
	_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in _names.size():
		_option.add_item(_item_text(i))
	box.add_child(_option)

	_option.item_selected.connect(_on_level_selected)
	_option.select(_current_level_index())

	# Map titles live in the generated scenes; when already scanned (by a
	# previous room scene, static cache) reuse them, else scan in the
	# background and refresh the combo items once the thread completes.
	if _titles_loaded:
		_titles = _cached_titles
		_refresh_option_items()
	else:
		_title_scan_thread = Thread.new()
		_title_scan_thread.start(_scan_titles)


func _item_text(index: int) -> String:
	var id := _names[index]
	var title := _titles[index] if index < _titles.size() else ""
	return "%s · %s" % [id, title] if not title.is_empty() else id


## Read `metadata/room_name` straight from the scene file: no instantiate,
## no resource cache, thread-safe and fast enough for every room at once.
func _scan_titles() -> void:
	var regex := RegEx.new()
	# No anchors: the first match is the room root node (only node carrying it).
	regex.compile("metadata/room_name = \"(.*)\"")
	var titles := PackedStringArray()
	for path in _paths:
		var line := ""
		var text := FileAccess.get_file_as_string(path)
		var result := regex.search(text)
		if result != null:
			line = result.get_string(1)
		titles.append(_unescape_tscn(line))
	_apply_titles.call_deferred(titles)


func _unescape_tscn(value: String) -> String:
	return value.replace("\\\"", "\"").replace("\\\\", "\\")


## The thread must be joined before the node is freed (level switch, quit).
func _stop_title_scan_thread() -> void:
	if _title_scan_thread != null:
		_title_scan_thread.wait_to_finish()
		_title_scan_thread = null


func _apply_titles(titles: PackedStringArray) -> void:
	_stop_title_scan_thread()
	_titles = titles
	_cached_titles = titles
	_titles_loaded = true
	_refresh_option_items()


func _refresh_option_items() -> void:
	if _option == null:
		return
	for i in _titles.size():
		_option.set_item_text(i, _item_text(i))


## Map name and warp info are stored as scene metadata by
## mapdata/convert_tmx_to_tscn.py when rooms are generated.
func _add_room_info(box: VBoxContainer) -> void:
	var room := _current_room_root()
	if room == null:
		return

	var name_label := Label.new()
	var room_name := String(room.get_meta("room_name", ""))
	if not room_name.is_empty():
		name_label.text = room_name
		box.add_child(name_label)

	var info_parts := PackedStringArray()
	var room_map := String(room.get_meta("room_map", ""))
	if not room_map.is_empty():
		info_parts.append(room_map)
	var entities: Array = room.get_meta("entities", [])
	info_parts.append("%d entities" % entities.size())
	info_parts.append(_warp_summary(room))
	var info_label := Label.new()
	info_label.text = " · ".join(info_parts)
	box.add_child(info_label)


## The room scene root normally is the current scene; fall back to searching
## the tree so the panel also works when a room is instanced by hand.
func _current_room_root() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		return scene
	for child in get_tree().root.get_children():
		if child != self and child.has_meta("room_name"):
			return child
	return null


func _warp_summary(room: Node) -> String:
	var parts := PackedStringArray()
	var warps: Array = room.get_meta("warps", [])
	parts.append(
		"warp" if warps.size() == 1 else "%d warps" % warps.size()
	)
	var fall := int(room.get_meta("warp_fall_dest", -1))
	if fall >= 0:
		parts.append("fall → %s" % _room_name(fall))
	var climb := int(room.get_meta("warp_climb_dest", -1))
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
