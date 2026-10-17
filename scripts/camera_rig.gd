extends Node3D
## Camera rig that follows a target node defined outside the scenes using it,
## so every room shares the same hero camera tuning.

@export var target_path: NodePath


@onready var _target: Node3D = get_node_or_null(target_path)


func _ready() -> void:
	if _target == null:
		push_warning("CameraRig: target not found, camera stays put.")
		return
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	if _target:
		global_position = _target.global_position
