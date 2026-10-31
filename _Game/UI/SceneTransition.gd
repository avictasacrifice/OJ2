# SceneTransition.gd  (Autoload)
extends CanvasLayer

var _rect: ColorRect
var _is_transitioning := false

func _ready() -> void:
	layer = 100
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 1)               # стартуем с чёрного
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	# Плавно открываем самую первую сцену
	await _fade_to(0.0, 0.5)

func change_scene(path: String, fade_out: float = 0.5, fade_in: float = 0.5) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP   # блокируем клики во время перехода

	await _fade_to(1.0, fade_out)

	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Не удалось загрузить сцену %s (код %d)" % [path, err])
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_is_transitioning = false
		return

	# Даём Godot пару кадров, чтобы новая сцена успела войти в дерево
	await get_tree().process_frame
	await get_tree().process_frame

	await _fade_to(0.0, fade_in)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false

func _fade_to(alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", alpha, duration)
	await tween.finished
