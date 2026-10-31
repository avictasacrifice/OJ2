extends Control
## Одно сообщение + кнопка «Продолжить».
## Сцена: tutorial.tscn — корень Control + этот скрипт.

signal closed

@export_multiline var message := ""
@export var pause_game := false
@export var button_label := "Продолжить"

var _built := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build.call_deferred()


func _exit_tree() -> void:
	if UIKit.is_open():
		UIKit.close_screen()


func build() -> void:
	if _built:
		return
	_built = true

	UIKit.create_screen(true, pause_game)
	UIKit.vbox()
	UIKit.spacer(20)
	UIKit.text(message, UIKit.FONT_BODY, UIKit.C_TEXT, UIKit.Align.CENTER)
	UIKit.spacer(20)
	UIKit.button(button_label, _close, true, true)
	UIKit.pop_parent()
	UIKit.fade_in()


func _close() -> void:
	closed.emit()
	UIKit.close_screen()


func _unhandled_input(event: InputEvent) -> void:
	if not UIKit.is_open():
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
