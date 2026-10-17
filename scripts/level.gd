extends Node3D
## Round, single "stage" reused by every generated room scene.
## It owns the hero and the camera; each room scene only brings its own map.

@onready var _hero: CharacterBody3D = $Player


func _ready() -> void:
	_place_hero_on_map.call_deferred()


func _place_hero_on_map() -> void:
	var grid_map: GridMap = _find_grid_map()
	if grid_map == null:
		return
	_hero.global_position = _find_spawn_position(grid_map)


func _find_grid_map() -> GridMap:
	# The GridMap belongs to the room scene, next to the instanced level.
	var parent := get_parent()
	for child in parent.get_children():
		if child is GridMap:
			return child
	push_warning("No GridMap found beside the level, hero stays where it is.")
	return null


func _find_spawn_position(grid_map: GridMap) -> Vector3:
	var columns: Dictionary = {}
	for cell in grid_map.get_used_cells():
		var key := Vector2i(cell.x, cell.z)
		if not columns.has(key) or cell.y > columns[key]:
			columns[key] = cell.y

	if columns.is_empty():
		return _hero.global_position

	var center := _columns_center(columns)
	var nearest_column: Vector2i = columns.keys()[0]
	var nearest_distance := INF
	for key: Vector2i in columns:
		var distance: int = absi(key.x - center.x) + absi(key.y - center.y)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_column = key

	# Place the hero one cell above the highest block, so it lands on the floor.
	return grid_map.map_to_local(Vector3i(nearest_column.x, int(columns[nearest_column]) + 1, nearest_column.y)) + Vector3(0.0, 0.51, 0.0)


func _columns_center(columns: Dictionary) -> Vector2i:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for key: Vector2i in columns:
		min_x = mini(min_x, key.x)
		max_x = maxi(max_x, key.x)
		min_y = mini(min_y, key.y)
		max_y = maxi(max_y, key.y)
	return Vector2i(int((min_x + max_x) / 2.0), int((min_y + max_y) / 2.0))
