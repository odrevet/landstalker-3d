extends Node3D
class_name EntityActor
## A scripted room entity, mirroring the landstalker-py Entity: a billboard
## sprite whose behaviour (position, orientation, visibility, movement) is
## driven by a ScriptCommands program loaded from its behaviour index.
## Tile-space coordinates (x, y) stay in raw TMX space like the py reference;
## our 3D world is the same space shifted by WARP_TILE_BASE horizontally and
## Z + 1 vertically (Z is the heightmap height level = top grid cell index).

const PIXEL_SIZE := 1.0 / 24.0
const WARP_TILE_BASE := 12
const ITEM_FRAMES := {
	229: [5, "04"],		# Hotel Register
	230: [6, "04"],		# Island Map
}
static var _SHEET_CACHE := {}

var entity_type := 0
var entity_name := ""
var speed := 0
var solid := true
var no_rotate := false
var gravity := true
var hostile := false
var is_moving := false
var fixed_frame = null
var orientation := "NE":
	set(value):
		orientation = value
		_update_sprite_display()
var position_tiles := Vector3.ZERO   # (raw x, raw y, height level z)

var script_handler: ScriptCommands
var game_level: Node          # level.gd: column tops / stand checks
var initial_position_tiles := Vector3.ZERO
var _captured_initial := false



## Sprite child lookup without relying on _ready (entities are also
## driven in headless tests before entering the tree).
func sprite_node() -> Sprite3D:
	return get_node_or_null("Sprite") as Sprite3D


static func create(meta: Dictionary) -> EntityActor:
	var actor := EntityActor.new()
	actor.entity_type = int(meta.get("type", 0))
	actor.entity_name = str(meta.get("name", "Unknown"))
	actor.speed = int(meta.get("speed", 0))
	actor.orientation = str(meta.get("orientation", "NE"))
	actor.solid = bool(meta.get("solid", true))
	actor.no_rotate = bool(meta.get("noRotate", false))
	actor.gravity = bool(meta.get("gravity", true))
	actor.hostile = bool(meta.get("hostile", false))
	actor.position_tiles = Vector3(
		float(meta.get("x", 0.0)) - WARP_TILE_BASE,
		float(meta.get("y", 0.0)) - WARP_TILE_BASE,
		float(meta.get("z", 0.0)))
	actor.name = actor.entity_name.replace(" ", "_")
	actor.visible = bool(meta.get("visible", true))

	var entity_id := actor.entity_type
	if SpriteDb.ENTITIES.has(entity_id):
		var entity: Dictionary = SpriteDb.ENTITIES[entity_id]
		var sprite_id := int(entity["sprite"])
		if SpriteDb.SPRITES.has(sprite_id):
			var sprite: Dictionary = SpriteDb.SPRITES[sprite_id]
			var anim_num := "004"
			if ITEM_FRAMES.has(entity_id):
				# Items show a fixed frame from their inventory sheet.
				actor.fixed_frame = ITEM_FRAMES[entity_id][0]
			else:
				# Idle display = first frame of the front or back walk cycle.
				anim_num = "001" if actor.orientation in ["SW", "SE"] else "000"
			var texture := actor._load_sheet(str(sprite["label"]), anim_num)
			if texture != null:
				var node := Sprite3D.new()
				node.name = "Sprite"
				var region := AtlasTexture.new()
				region.atlas = texture
				var frame_width: int = sprite["frame_width"]
				var height: int = texture.get_height()
				var frame_index: int = 0 if actor.fixed_frame == null else actor.fixed_frame
				region.region = Rect2(frame_index * frame_width, 0, frame_width, height)
				node.texture = region
				node.pixel_size = PIXEL_SIZE
				node.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
				# Feet on the ground: center the frame half its world height up.
				node.position = Vector3(0.0, height * PIXEL_SIZE * 0.5, 0.0)
				actor.add_child(node)
	# The orientation was assigned before the sprite child existed, so
	# apply the flip now.
	actor._update_sprite_display()
	return actor


func _ready() -> void:
	_sync_visual_transform()


func _physics_process(_delta: float) -> void:
	if not _captured_initial:
		_captured_initial = true
		initial_position_tiles = position_tiles
	if script_handler != null:
		script_handler.update()
	_apply_gravity()


const FALL_STEP := 0.25   # tiles per tick when a scripted entity hangs in air


## py applies gravity every frame to entities (game.apply_gravity_to_drawable):
## snap up onto the column top, or fall down gradually when floating.
func _apply_gravity() -> void:
	if not gravity or game_level == null:
		return
	var top: int = game_level.column_top(
		Vector2i(floori(position_tiles.x), floori(position_tiles.y))
			- Vector2i(WARP_TILE_BASE, WARP_TILE_BASE))
	if top < -900:
		return		# outside the map grid; py lets undecoded cells be impassable
	var ground := float(top)
	if position_tiles.z < ground:
		position_tiles.z = ground
		_sync_visual_transform()
	elif position_tiles.z > ground:
		position_tiles.z = maxf(ground, position_tiles.z - FALL_STEP)
		_sync_visual_transform()


func get_world_pos() -> Vector3:
	return position_tiles


func set_world_pos(x: float, y: float, z: float) -> void:
	position_tiles = Vector3(x, y, z)
	_sync_visual_transform()


func set_moving_state(moving: bool) -> void:
	is_moving = moving


func set_orientation(new_orientation: String, update_display := true) -> void:
	orientation = new_orientation
	if update_display and fixed_frame == null:
		set_sheet_for_orientation()


func set_sheet_for_orientation() -> void:
	if fixed_frame != null or sprite_node() == null:
		return
	var anim_num := "001" if orientation in ["SW", "SE"] else "000"
	var sprite := _get_sprite_props()
	if sprite.is_empty():
		return
	var texture := _load_sheet(str(sprite["label"]), anim_num)
	if texture == null:
		return
	var region := AtlasTexture.new()
	region.atlas = texture
	region.region = Rect2(0, 0, int(sprite["frame_width"]), texture.get_height())
	sprite_node().texture = region


func _update_sprite_display() -> void:
	var sprite := sprite_node()
	if sprite == null or fixed_frame != null:
		return
	sprite.flip_h = orientation in ["SE", "NW"] and not no_rotate


func _sync_visual_transform() -> void:
	position = Vector3(position_tiles.x, position_tiles.z + 1.0, position_tiles.y)


func _get_sprite_props() -> Dictionary:
	if not SpriteDb.ENTITIES.has(entity_type):
		return {}
	var entity: Dictionary = SpriteDb.ENTITIES[entity_type]
	var sprite_id := int(entity["sprite"])
	if not SpriteDb.SPRITES.has(sprite_id):
		return {}
	return SpriteDb.SPRITES[sprite_id]


func _load_sheet(label: String, anim_num: String) -> Texture2D:
	var path := "res://data/sprites/%sAnim%03d.png" % [label, int(anim_num)]
	if _SHEET_CACHE.has(path):
		return _SHEET_CACHE[path]
	var texture := load(path) as Texture2D
	if texture != null:
		_SHEET_CACHE[path] = texture
	return texture
