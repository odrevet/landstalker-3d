extends Sprite3D
class_name EntityBillboard
## One static billboard per room entity, replicating the landstalker-py
## entity renderer: idle display (first frame of the walk sheet), orientation
## deciding back/front sheet plus horizontal flip, item overrides.

const PIXEL_SIZE := 1.0 / 24.0
const SHEET_CENTER_ABOVE_ORIGIN := 1.0

## Entity ID -> [frame index, animation number] for identity items.
const ITEM_FRAMES := {
	229: [5, "04"],		# Hotel Register
	230: [6, "04"],		# Island Map
}


static func create(meta: Dictionary) -> Node:
	var entity_type := int(meta.get("type", 0))
	if entity_type == 0 or not meta.get("visible", true):
		return null				# type 0 = Nigel placement, already instanced as hero
	if not SpriteDb.ENTITIES.has(entity_type):
		return null
	var entity: Dictionary = SpriteDb.ENTITIES[entity_type]
	var sprite_id := int(entity["sprite"])
	if not SpriteDb.SPRITES.has(sprite_id):
		return null
	var sprite: Dictionary = SpriteDb.SPRITES[sprite_id]

	var anim_num: String
	var frame_index := 0
	if ITEM_FRAMES.has(entity_type):
		# Items show a fixed frame from their inventory sheet.
		anim_num = "0" + ITEM_FRAMES[entity_type][1]
		frame_index = ITEM_FRAMES[entity_type][0]
	else:
		# Idle display = first frame of the front or back walk cycle.
		var orientation := str(meta.get("orientation", "NE"))
		anim_num = "001" if orientation in ["SW", "SE"] else "000"

	var label: String = sprite["label"]
	var texture := _load_texture(label, anim_num)
	if texture == null:
		return null

	var node := Sprite3D.new()
	node.name = "Entity%03d" % entity_type
	var region := AtlasTexture.new()
	region.atlas = texture
	var frame_width: int = sprite["frame_width"]
	var height: int = texture.get_height()
	region.region = Rect2(frame_index * frame_width, 0, frame_width, height)
	node.texture = region
	node.pixel_size = PIXEL_SIZE
	node.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	node.flip_h = str(meta.get("orientation", "NE")) in ["SE", "NW"] \
		and not meta.get("noRotate", false)
	# Feet on the ground: center the frame half its world height above origin.
	node.position = Vector3(0.0, height * PIXEL_SIZE * 0.5, 0.0)
	return node


static func _load_texture(label: String, anim_num: String) -> Texture2D:
	var path := "res://data/sprites/%sAnim%s.png" % [label, anim_num]
	if not ResourceLoader.exists(path):
		return null
	return load(path)
