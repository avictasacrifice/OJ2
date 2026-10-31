extends Area3D
## Зона, которая один раз показывает сообщение при входе игрока.

@export_multiline var message := "Сообщение"
@export var pause_game := false
@export var once := true

var _fired := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _fired and once:
		return
	if not body.is_in_group("player"):
		return
	_fired = true
	TutorialTrigger.text(message, {"pause": pause_game})
