extends Control
## Меню паузы + настройки. Открывается по Esc из игрока.
## Сцена: pause_menu.tscn — корень Control + этот скрипт. Больше ничего.

signal quit_to_menu

@export_file("*.tscn") var menu_scene: String = "res://scenes/main_menu.tscn"

var _main_panel: VBoxContainer
var _settings_panel: VBoxContainer
var _screen_root: Control
var _fs_button: Button
var _built := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build.call_deferred()


func _exit_tree() -> void:
	if UIKit.is_open():
		UIKit.close_screen()


# =====================================================================
# Построение
# =====================================================================
func build() -> void:
	if _built:
		return
	_built = true

	# release_mouse, pause_game, dim
	UIKit.create_screen(true, true, true)
	_screen_root = UIKit._stack[0]

	_main_panel     = _make_panel()
	_settings_panel = _make_panel()
	_settings_panel.visible = false

	_fill_main()
	_fill_settings()

	UIKit.fade_in()


func _make_panel() -> VBoxContainer:
	var wrap := CenterContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(wrap)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UIKit.GAP)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(v)
	return v


# =====================================================================
# Главный экран
# =====================================================================
func _fill_main() -> void:
	UIKit.push_parent(_main_panel)
	UIKit.title("ПАУЗА")
	UIKit.spacer(20)
	UIKit.button("Продолжить",     _on_resume, true, true)
	UIKit.button("Настройки",      _show_settings)
	UIKit.button("В главное меню", _on_quit_to_menu)
	UIKit.button("Выход",          _on_quit)
	UIKit.pop_parent()


# =====================================================================
# Настройки
# =====================================================================
func _fill_settings() -> void:
	UIKit.push_parent(_settings_panel)
	UIKit.title("НАСТРОЙКИ")
	UIKit.spacer(20)

	# Громкость (работает, если в проекте есть автолоад Audio)
	UIKit.volume_slider("Музыка", &"Music")
	UIKit.volume_slider("Звуки",  &"SFX")

	UIKit.separator()

	# Чувствительность мыши
	var sens := 0.0026
	for p in get_tree().get_nodes_in_group("player"):
		if "mouse_sensitivity" in p:
			sens = p.mouse_sensitivity
			break
	UIKit.slider("Чувствительность", sens, _on_sensitivity_changed, 0.0005, 0.01, 0.0001)

	UIKit.separator()

	# Полный экран
	_fs_button = UIKit.button(_fs_label(), _toggle_fullscreen)

	UIKit.spacer(20)
	UIKit.button("Назад", _show_main, false, true)
	UIKit.pop_parent()


func _on_sensitivity_changed(value: float) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if "mouse_sensitivity" in p:
			p.mouse_sensitivity = value
			break


func _fs_label() -> String:
	var on := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	return "Полный экран: %s" % ("Вкл" if on else "Выкл")


func _toggle_fullscreen() -> void:
	var on := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if on else DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	if is_instance_valid(_fs_button):
		_fs_button.text = _fs_label()


# =====================================================================
# Навигация и действия
# =====================================================================
func _show_settings() -> void:
	_main_panel.visible = false
	_settings_panel.visible = true


func _show_main() -> void:
	_settings_panel.visible = false
	_main_panel.visible = true


func _on_resume() -> void:
	queue_free()   # _exit_tree закроет UIKit-слой → снимет паузу и вернёт мышь


func _on_quit_to_menu() -> void:
	quit_to_menu.emit()
	queue_free()
	if menu_scene != "" and ResourceLoader.exists(menu_scene):
		get_tree().change_scene_to_file.call_deferred(menu_scene)


func _on_quit() -> void:
	queue_free()
	get_tree().quit.call_deferred()


# =====================================================================
# Esc: в настройках — «Назад», в главном — «Продолжить»
# =====================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not UIKit.is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _settings_panel and _settings_panel.visible:
			_show_main()
		else:
			_on_resume()
