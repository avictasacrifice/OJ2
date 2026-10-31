extends Node
## UIKit v2 — минималистичный автолоад для сборки UI из кода.
## Тема: TOXIC HAZARD — кислотный лайм, терминальный неон, пиксельные углы.
##
## ШРИФТЫ:
##   UIKit.set_default_font(preload("res://fonts/pixel.ttf"))   # всем ролям
##   UIKit.load_font("title", "res://fonts/pixel_bold.ttf")     # одной роли
##   UIKit.set_font_size("title", 64)                            # размер
##   Роли: "title", "body", "button"
##
## ПИКСЕЛЬ:
##   Для чёткости используй размеры, кратные нативному размеру шрифта
##   (8, 16, 24, 32...). Пиксельные шрифты лучше рендерятся при
##   CORNER = 0, BORDER_W = 1 и целочисленных смещениях — это дефолт.

signal screen_closed(layer: CanvasLayer)

# =====================================================================
# Палитра TOXIC HAZARD
# =====================================================================
# --- base ---
const C_BG         := Color("#06090a")
const C_BG_ALT     := Color("#0b1410")
const C_PANEL      := Color("#122019")
const C_PANEL_HI   := Color("#1a2e24")
const C_BORDER     := Color("#2a4a38")
const C_DIVIDER    := Color("#1a2e24")

# --- text ---
const C_TEXT       := Color("#c8e8d0")
const C_TEXT_HI    := Color("#f0ffe8")
const C_TEXT_DIM   := Color("#7a9a85")
const C_TEXT_OFF   := Color("#425850")

# --- accent (primary / action) ---
const C_ACCENT     := Color("#ff2ea6")
const C_ACCENT_H   := Color("#ff4d3d")
const C_ACCENT_P   := Color("#ff4d3d")
const C_ACCENT_DIM := Color("#aaff2e")

# --- semantic ---
const C_SUCCESS    := Color("#4dff88")
const C_ACID       := Color("#aaff2e")
const C_PSYCH      := Color("#b15cff")
const C_PSYCH_H    := Color("#e0a6ff")
const C_CYAN       := Color("#2ee6ff")
const C_CYAN_H     := Color("#7ff6ff")
const C_WARN       := Color("#ffb340")
const C_WARN_H     := Color("#ffd060")
const C_MAGENTA    := Color("#ff2ea6")

# --- bars ---
const C_HP         := Color("#ff4d3d")
const C_ARMOR      := Color("#2ee6ff")
const C_SANITY     := Color("#b15cff")
const C_STAMINA    := Color("#aaff2e")
const C_AMMO       := Color("#ffb340")

# --- misc ---
const C_SHADOW     := Color("#06090a")
const C_OVERLAY    := Color("#0b1410")
const C_FOCUS      := Color("#2ee6ff")
const C_SELECT     := Color("#1a2e24")
const C_CURSOR     := Color("#f0ffe8")

# =====================================================================
# Метрики
# =====================================================================
const FONT_TITLE    := 52
const FONT_BODY     := 18
const FONT_BTN      := 18
const BTN_SIZE      := Vector2(260, 48)
const SCREEN_MARGIN := 40
const GAP           := 14
const PANEL_PAD     := 22
const SCREEN_LAYER  := 100
const HUD_LAYER     := 50
const CORNER        := 0      # 0 — чистый пиксель
const BORDER_W      := 1
const GLOW_SIZE     := 6

enum Align { CENTER, TOP_LEFT, TOP_CENTER, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_CENTER, BOTTOM_RIGHT, FULL }

# =====================================================================
# Состояние
# =====================================================================
var _stack: Array[Control] = []
var _layer: CanvasLayer = null

var _restore_mouse_mode: int = -1
var _restore_pause: bool = false
var _paused_by_screen: bool = false

# --- шрифты ---
var _fonts: Dictionary = {
	"title":  null,
	"body":   null,
	"button": null,
}
var _font_sizes: Dictionary = {
	"title":  FONT_TITLE,
	"body":   FONT_BODY,
	"button": FONT_BTN,
}

# --- HUD ---
var _hud_layer: CanvasLayer = null
var _hud_anchor: MarginContainer = null
var _hud_vbox: VBoxContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_hud_layer):
			_hud_layer.queue_free()


# =====================================================================
# Шрифты
# =====================================================================

## Установить шрифт для роли. font = null возвращает дефолт Godot.
func set_font(role: String, font: Font) -> void:
	_fonts[role] = font


## Загрузить .ttf/.otf и назначить роли. Возвращает true при успехе.
func load_font(role: String, path: String) -> bool:
	if not ResourceLoader.exists(path):
		push_warning("UIKit.load_font: файл не найден — %s" % path)
		return false
	_fonts[role] = load(path)
	return true


## Сменить размер для роли (влияет на будущие элементы).
func set_font_size(role: String, size: int) -> void:
	_font_sizes[role] = size


## Поставить один шрифт всем ролям сразу.
func set_default_font(font: Font) -> void:
	for role in _fonts.keys():
		_fonts[role] = font


## Получить текущий шрифт роли (может быть null — дефолт движка).
func get_font(role: String) -> Font:
	return _fonts.get(role)


## Применить шрифт роли к произвольному Control (публично, для кастомных нод).
func apply_font(ctrl: Control, role: String) -> void:
	_apply_font(ctrl, role)


func _apply_font(ctrl: Control, role: String) -> void:
	var f: Font = _fonts.get(role)
	if f == null:
		return
	if ctrl is RichTextLabel:
		ctrl.add_theme_font_override("normal_font", f)
		ctrl.add_theme_font_override("bold_font", f)
		ctrl.add_theme_font_override("italics_font", f)
		ctrl.add_theme_font_override("bold_italics_font", f)
		ctrl.add_theme_font_override("mono_font", f)
	else:
		ctrl.add_theme_font_override("font", f)


func _role_size(role: String, fallback: int) -> int:
	return int(_font_sizes.get(role, fallback))


# =====================================================================
# Стек родителей
# =====================================================================
func _parent() -> Control:
	if _stack.is_empty():
		push_error("UIKit: сначала вызови create_screen()")
		return null
	return _stack.back()


func _add(node: Node) -> void:
	var p := _parent()
	if p:
		p.add_child(node)
	else:
		node.queue_free()


func push_parent(node: Control) -> void:
	if node == null:
		push_warning("UIKit: push_parent(null) — игнор")
		return
	_stack.push_back(node)


func pop_parent() -> void:
	if _stack.size() <= 1:
		push_warning("UIKit: нельзя pop корневого экрана")
		return
	_stack.pop_back()


# =====================================================================
# Экран
# =====================================================================
## release_mouse — показать курсор (и вернуть прежний режим при close_screen).
## pause_game    — пауза + приглушение звука (если есть Audio).
## dim           — полупрозрачная подложка.
func create_screen(release_mouse := false, pause_game := false, dim := false) -> Control:
	close_screen()

	_layer = CanvasLayer.new()
	_layer.layer = SCREEN_LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var screen := Control.new()
	screen.name = "UIKitScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_PASS
	_layer.add_child(screen)
	get_tree().root.add_child.call_deferred(_layer)

	_stack.clear()
	_stack.push_back(screen)

	if dim:
		backdrop()

	if release_mouse:
		_restore_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pause_game:
		_restore_pause = get_tree().paused
		_paused_by_screen = true
		get_tree().paused = true
		_audio_muffle(true)
	return screen


func close_screen() -> void:
	if is_instance_valid(_layer):
		var old := _layer
		old.queue_free()
		screen_closed.emit(old)
	_layer = null
	_stack.clear()

	if _restore_mouse_mode != -1:
		Input.mouse_mode = _restore_mouse_mode as Input.MouseMode
		_restore_mouse_mode = -1
	if _paused_by_screen:
		get_tree().paused = _restore_pause
		_paused_by_screen = false
		_audio_muffle(false)


func is_open() -> bool:
	return is_instance_valid(_layer)


func backdrop(color: Color = C_BG, alpha: float = 0.78) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(color, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	var p := _parent()
	if p:
		p.add_child(r)
		p.move_child(r, 0)
	return r


# =====================================================================
# Стили
# =====================================================================
func _style(bg: Color, border := Color.TRANSPARENT, border_w := BORDER_W, glow := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(CORNER)
	sb.content_margin_left   = 14
	sb.content_margin_right  = 14
	sb.content_margin_top    = 10
	sb.content_margin_bottom = 10
	if border != Color.TRANSPARENT:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if glow and border != Color.TRANSPARENT:
		sb.shadow_color = Color(border, 0.45)
		sb.shadow_size  = GLOW_SIZE
	return sb


func _style_button(btn: Button, accent: bool) -> void:
	if accent:
		btn.add_theme_stylebox_override("normal",  _style(C_ACCENT, C_ACCENT_H, BORDER_W, true))
		btn.add_theme_stylebox_override("hover",   _style(C_ACCENT_H, C_TEXT_HI, BORDER_W, true))
		btn.add_theme_stylebox_override("pressed", _style(C_ACCENT_P, C_ACCENT))
		btn.add_theme_stylebox_override("focus",   _style(C_ACCENT, C_TEXT_HI, 2, true))
		btn.add_theme_stylebox_override("disabled",_style(C_ACCENT_DIM, C_ACCENT_DIM))
		btn.add_theme_color_override("font_color",          C_BG)
		btn.add_theme_color_override("font_hover_color",    C_BG)
		btn.add_theme_color_override("font_pressed_color",  C_TEXT_HI)
		btn.add_theme_color_override("font_focus_color",    C_BG)
		btn.add_theme_color_override("font_disabled_color", C_TEXT_OFF)
	else:
		btn.add_theme_stylebox_override("normal",  _style(C_PANEL, C_BORDER))
		btn.add_theme_stylebox_override("hover",   _style(C_PANEL_HI, C_ACCENT, BORDER_W, true))
		btn.add_theme_stylebox_override("pressed", _style(C_ACCENT_P, C_ACCENT))
		btn.add_theme_stylebox_override("focus",   _style(C_PANEL_HI, C_FOCUS, 2, true))
		btn.add_theme_stylebox_override("disabled",_style(C_PANEL, C_DIVIDER))
		btn.add_theme_color_override("font_color",          C_TEXT)
		btn.add_theme_color_override("font_hover_color",    C_ACCENT_H)
		btn.add_theme_color_override("font_pressed_color",  C_TEXT_HI)
		btn.add_theme_color_override("font_focus_color",    C_ACCENT_H)
		btn.add_theme_color_override("font_disabled_color", C_TEXT_OFF)
	btn.add_theme_font_size_override("font_size", _role_size("button", FONT_BTN))


# =====================================================================
# Фабрики: текст
# =====================================================================

## size <= 0 → берётся размер роли "body".
func text(txt: String, size: int = -1, color: Color = C_TEXT, align: Align = Align.FULL) -> Label:
	var s := size if size > 0 else _role_size("body", FONT_BODY)
	return _label(txt, s, color, align, "body")


func _label(txt: String, size: int, color: Color, align: Align, role: String) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(lbl, role)

	var p := _parent()
	if p == null:
		lbl.queue_free()
		return lbl
	if p is Container:
		lbl.horizontal_alignment = _h_align(align)
	else:
		_apply_overlay_align(lbl, align)
	p.add_child(lbl)
	return lbl


func title(txt: String, color: Color = C_ACCENT) -> Label:
	var s := _role_size("title", FONT_TITLE)
	var lbl := _label(txt, s, color, Align.CENTER, "title")
	lbl.add_theme_color_override("font_outline_color", Color(color, 0.35))
	lbl.add_theme_constant_override("outline_size", 4)
	return lbl


## size <= 0 → размер роли "body".
func dim(txt: String, align: Align = Align.FULL, size: int = -1) -> Label:
	var s := size if size > 0 else _role_size("body", FONT_BODY)
	return _label(txt, s, C_TEXT_DIM, align, "body")


func rich_text(bbcode: String, size: int = -1, color: Color = C_TEXT) -> RichTextLabel:
	var s := size if size > 0 else _role_size("body", FONT_BODY)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.text = bbcode
	rt.add_theme_font_size_override("normal_font_size", s)
	rt.add_theme_color_override("default_color", color)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(rt, "body")
	_add(rt)
	return rt


func _h_align(align: Align) -> HorizontalAlignment:
	match align:
		Align.CENTER, Align.TOP_CENTER, Align.BOTTOM_CENTER:
			return HORIZONTAL_ALIGNMENT_CENTER
		Align.TOP_RIGHT, Align.BOTTOM_RIGHT:
			return HORIZONTAL_ALIGNMENT_RIGHT
	return HORIZONTAL_ALIGNMENT_LEFT


func _v_align(align: Align) -> VerticalAlignment:
	match align:
		Align.CENTER:
			return VERTICAL_ALIGNMENT_CENTER
		Align.BOTTOM_LEFT, Align.BOTTOM_CENTER, Align.BOTTOM_RIGHT:
			return VERTICAL_ALIGNMENT_BOTTOM
	return VERTICAL_ALIGNMENT_TOP


func _apply_overlay_align(lbl: Label, align: Align) -> void:
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_left   =  SCREEN_MARGIN
	lbl.offset_top    =  SCREEN_MARGIN
	lbl.offset_right  = -SCREEN_MARGIN
	lbl.offset_bottom = -SCREEN_MARGIN
	lbl.horizontal_alignment = _h_align(align)
	lbl.vertical_alignment   = _v_align(align)


# =====================================================================
# Фабрики: контейнеры
# =====================================================================
func vbox(centered := true, sep: int = GAP) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", sep)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	if centered:
		var wrap := CenterContainer.new()
		wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(box)
		_add(wrap)
	else:
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left   =  SCREEN_MARGIN
		box.offset_top    =  SCREEN_MARGIN
		box.offset_right  = -SCREEN_MARGIN
		box.offset_bottom = -SCREEN_MARGIN
		_add(box)
	push_parent(box)
	return box


func hbox(sep: int = GAP) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", sep)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_add(box)
	push_parent(box)
	return box


func margin(px: int = PANEL_PAD) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, px)
	_add(m)
	push_parent(m)
	return m


## Панель. Возвращает внутренний VBox и пушит только его.
func panel(bg: Color = C_PANEL, border: Color = C_BORDER, glow := false) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(bg, border, BORDER_W, glow))

	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, PANEL_PAD)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", GAP)
	v.alignment = BoxContainer.ALIGNMENT_CENTER

	pc.add_child(m)
	m.add_child(v)
	_add(pc)
	push_parent(v)
	return v


func spacer(h: int = GAP) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(s)
	return s


func separator() -> HSeparator:
	var sep := HSeparator.new()
	var sb := StyleBoxLine.new()
	sb.color = C_DIVIDER
	sb.thickness = 1
	sep.add_theme_stylebox_override("separator", sb)
	_add(sep)
	return sep


# =====================================================================
# Фабрики: кнопки и поля
# =====================================================================
func button(txt: String, callback: Callable = Callable(), accent := false, focus := false) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = BTN_SIZE
	_style_button(btn, accent)
	_apply_font(btn, "button")
	if callback.is_valid():
		btn.pressed.connect(callback)
	btn.pressed.connect(_on_button_pressed)
	btn.mouse_entered.connect(_on_button_hover)
	_add(btn)
	if focus:
		btn.grab_focus.call_deferred()
	return btn


func input_field(placeholder: String = "") -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.custom_minimum_size = Vector2(260, 44)
	le.add_theme_stylebox_override("normal", _style(C_BG, C_BORDER))
	le.add_theme_stylebox_override("focus",  _style(C_BG_ALT, C_ACCENT, BORDER_W, true))
	le.add_theme_color_override("font_color",             C_TEXT)
	le.add_theme_color_override("font_placeholder_color", C_TEXT_DIM)
	le.add_theme_color_override("caret_color",            C_ACCENT)
	le.add_theme_color_override("selection_color",        Color(C_ACCENT, 0.35))
	le.add_theme_font_size_override("font_size", _role_size("body", FONT_BODY))
	_apply_font(le, "body")
	_add(le)
	return le


func slider(label: String, value: float, callback: Callable, min_v := 0.0, max_v := 1.0, step := 0.01) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)

	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.add_theme_font_size_override("font_size", _role_size("body", FONT_BODY))
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(lbl, "body")
	row.add_child(lbl)

	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.add_theme_stylebox_override("slider", _slider_box(C_PANEL_HI))
	s.add_theme_stylebox_override("grabber_area", _slider_box(C_ACCENT))
	s.add_theme_stylebox_override("grabber_area_highlight", _slider_box(C_ACCENT_H))
	if callback.is_valid():
		s.value_changed.connect(callback)
	row.add_child(s)

	_add(row)
	return s


func volume_slider(label: String, bus: StringName) -> HSlider:
	var audio := _audio()
	var start: float = audio.get_volume(bus) if audio else 1.0
	var cb := func(v: float) -> void:
		var a := _audio()
		if a:
			a.set_volume(bus, v)
	return slider(label, start, cb)


func _slider_box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(CORNER)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


# =====================================================================
# Бары (общий хелпер + два публичных метода)
# =====================================================================
func _make_bar(value: float, max_value: float, color: Color, size: Vector2) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = max_value
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = size
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(C_BG, 0.85)
	bg.set_corner_radius_all(CORNER)
	bg.border_color = C_BORDER
	bg.set_border_width_all(BORDER_W)

	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(CORNER)
	fill.shadow_color = Color(color, 0.5)
	fill.shadow_size = 3

	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	return pb


## Бар внутри экрана (меню/пауза). Требует create_screen().
func bar(value: float, max_value: float = 100.0, color: Color = C_HP, size := Vector2(220, 18)) -> ProgressBar:
	var pb := _make_bar(value, max_value, color, size)
	_add(pb)
	return pb


# =====================================================================
# HUD (постоянные бары поверх игры)
# =====================================================================

## Создать HUD-слой (идемпотентно). pos — отступ от верхнего левого угла.
func hud_create(pos := Vector2(24, 24), layer := HUD_LAYER) -> VBoxContainer:
	if is_instance_valid(_hud_layer):
		return _hud_vbox

	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "UIKitHUD"
	_hud_layer.layer = layer
	_hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(_hud_layer)

	_hud_anchor = MarginContainer.new()
	_hud_anchor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hud_anchor.add_theme_constant_override("margin_left", int(pos.x))
	_hud_anchor.add_theme_constant_override("margin_top",  int(pos.y))
	_hud_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_hud_anchor)

	_hud_vbox = VBoxContainer.new()
	_hud_vbox.add_theme_constant_override("separation", 6)
	_hud_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_anchor.add_child(_hud_vbox)

	return _hud_vbox


## Бар в HUD. Не требует create_screen() и не исчезает при открытии меню.
func hud_bar(value: float, max_value: float = 100.0, color: Color = C_HP, size := Vector2(280, 18)) -> ProgressBar:
	if not is_instance_valid(_hud_vbox):
		hud_create()
	var pb := _make_bar(value, max_value, color, size)
	_hud_vbox.add_child(pb)
	return pb


func hud_bar_set(pb: ProgressBar, value: float) -> void:
	if is_instance_valid(pb):
		pb.value = clampf(value, 0.0, pb.max_value)


func hud_bar_animate(pb: ProgressBar, target: float, duration := 0.25) -> void:
	if not is_instance_valid(pb):
		return
	var tw := create_tween()
	tw.tween_property(pb, "value", clampf(target, 0.0, pb.max_value), duration)


func hud_bar_color(pb: ProgressBar, color: Color) -> void:
	if not is_instance_valid(pb):
		return
	var fill := pb.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		var f := fill.duplicate() as StyleBoxFlat
		f.bg_color = color
		f.shadow_color = Color(color, 0.5)
		pb.add_theme_stylebox_override("fill", f)


func hud_close() -> void:
	if is_instance_valid(_hud_layer):
		_hud_layer.queue_free()
	_hud_layer = null
	_hud_anchor = null
	_hud_vbox = null


func hud_is_open() -> bool:
	return is_instance_valid(_hud_layer)


# =====================================================================
# Анимация
# =====================================================================
func fade_in(duration: float = 0.25) -> void:
	if _stack.is_empty():
		return
	var screen := _stack[0]
	if not is_instance_valid(screen):
		return
	screen.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(screen, "modulate:a", 1.0, duration)


# =====================================================================
# Интеграция с Audio
# =====================================================================
func _audio() -> Node:
	return get_node_or_null("/root/Audio")


func _on_button_pressed() -> void:
	var a := _audio()
	if a and a.has_method("play") and a.has_method("has_sound") and a.has_sound(&"ui_click"):
		a.play(&"ui_click")


func _on_button_hover() -> void:
	var a := _audio()
	if a and a.has_method("play") and a.has_method("has_sound") and a.has_sound(&"ui_hover"):
		a.play(&"ui_hover")


func _audio_muffle(enabled: bool) -> void:
	var a := _audio()
	if a and a.has_method("muffle"):
		a.muffle(enabled)
