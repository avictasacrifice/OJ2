# PortalTrigger.gd
extends Area3D

@export_file("*.tscn") var target_scene: String
@export var player_group: StringName = &"player"
@export var fade_out_time: float = 0.5
@export var fade_in_time: float = 0.5

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(player_group):
		return
	if target_scene.is_empty():
		push_warning("Не указан target_scene у триггера %s" % name)
		return
	SceneTransition.change_scene(target_scene, fade_out_time, fade_in_time)
