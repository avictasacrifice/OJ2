extends Node

@export var duration := 300.0
@export var pause_with_game := false

var _time_left := 0.0
var _running := false
var _finished := false

var _label: Label
var _win_screen: Control


func _ready() -> void:
	_time_left = duration
	_build_label()
	_build_win_screen()
	_running = true
	add_to_group("game_timer")


func _process(delta: float) -> void:
	if not _running or _finished:
		return
	if pause_with_game and get_tree().paused:
		return

	_time_left = maxf(_time_left - delta, 0.0)
	_update_label()

	if _time_left <= 0.0:
		_finish()


func get_elapsed() -> float:
	return duration - _time_left


func get_progress() -> float:
	return clampf(get_elapsed() / duration, 0.0, 1.0)


func is_finished() -> bool:
	return _finished


func get_time_left() -> float:
	return _time_left


func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 32)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 5)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 20
	_label.offset_bottom = 60
	layer.add_child(_label)
	_update_label()


func _build_win_screen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	_win_screen = Control.new()
	_win_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_win_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_win_screen.visible = false
	layer.add_child(_win_screen)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_win_screen.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_win_screen.add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)

	var title := Label.new()
	title.text = "ПОБЕДА"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color("#aaff2e"))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var msg := Label.new()
	msg.text = "Ты выжил. Канализация отпустила тебя"
	msg.add_theme_font_size_override("font_size", 24)
	msg.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(msg)

	var quit := Button.new()
	quit.text = "Выход"
	quit.custom_minimum_size = Vector2(240, 48)
	quit.pressed.connect(func() -> void: get_tree().quit())
	v.add_child(quit)


func _update_label() -> void:
	if not is_instance_valid(_label):
		return
	var m := int(_time_left) / 60
	var s := int(_time_left) % 60
	_label.text = "%02d:%02d" % [m, s]
	if _time_left <= 10.0:
		_label.add_theme_color_override("font_color", Color("#ff4d3d"))
	else:
		_label.add_theme_color_override("font_color", Color.WHITE)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_running = false

	if is_instance_valid(_win_screen):
		_win_screen.visible = true

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
