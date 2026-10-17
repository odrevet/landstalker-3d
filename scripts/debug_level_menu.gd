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

	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for name in _names:
		option.add_item(name)
	box.add_child(option)

	option.item_selected.connect(_on_level_selected)
	option.select(_current_level_index())


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
