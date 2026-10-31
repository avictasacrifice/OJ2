class_name TutorialTrigger
## Вызов: TutorialTrigger.text("сообщение")

const SCENE := preload("res://_Game/UI/tutorial.tscn")


static func text(msg: String, opts := {}) -> Control:
	var t: Control = SCENE.instantiate()
	t.message = msg

	if opts.has("pause"):
		t.pause_game = bool(opts["pause"])
	if opts.has("button"):
		t.button_label = str(opts["button"])

	var host: Node = null
	if opts.has("host") and opts["host"] is Node:
		host = opts["host"]
	if host == null:
		host = Engine.get_main_loop().current_scene
	host.add_child(t)
	return t
