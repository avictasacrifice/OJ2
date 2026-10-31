extends Control
## Экран выбора «1 из N» на базе UIKit.
##
## Два режима:
##   * options — фиксированный список (как раньше);
##   * pool    — большой список-пул, из которого скрипт сам катит N вариантов
##               (а-ля вампир-сюрвайворс). Для случайных наград — используй этот.
##
## Пример «награды за уровень»:
##   var s := preload("res://ui/choice.tscn").instantiate()
##   s.heading = "ВЫБЕРИТЕ УЛУЧШЕНИЕ"
##   s.pool = [
##       {"id": "hp",   "title": "+20 HP",  "desc": "Здоровье", "weight": 3.0},
##       {"id": "dmg",  "title": "+10% DMG","desc": "Урон",     "weight": 2.0},
##       {"id": "spd",  "title": "+5% SPD", "desc": "Скорость", "weight": 1.0},
##       {"id": "crit", "title": "+5% CRT", "desc": "Крит",     "weight": 1.0},
##       {"id": "heal", "title": "ПОЛНЫЙ ХИЛ", "desc": "Разово"},
##   ]
##   s.pick_count = 3
##   s.exclude_ids = Player.taken_upgrades     # уже взятые
##   s.option_selected.connect(func(id, _i, data): Player.apply_upgrade(data))
##   add_child(s)

signal option_selected(id: String, index: int, data: Dictionary)
signal canceled
signal rerolled

@export var heading := "ВЫБЕРИТЕ ВАРИАНТ"
@export var pause_game := false
@export var auto_close := true

## Фиксированный список (если задан — используется он, pool игнорируется).
@export var options: Array[Dictionary] = []

## Пул для рандома. Если options пуст, а pool — нет, скрипт катит pick_count штук.
@export var pool: Array[Dictionary] = []
@export var pick_count := 3
@export var exclude_ids: Array[String] = []     # уже полученные id
@export var unique_picks := true                # не показывать один и тот же вариант дважды в тройке
@export var weighted := true                    # учитывать поле "weight" (по умолчанию 1.0)
@export var allow_reroll := false               # показать кнопку «Перекатить»
@export var seed_value := 0                     # 0 = случайный сид; иначе — детерминированный

var _cards: Array[PanelContainer] = []
var _shown: Array[Dictionary] = []              # что реально показываем
var _built := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if seed_value != 0:
		seed(seed_value)
	build.call_deferred()
	build()


func _exit_tree() -> void:
	if UIKit.is_open():
		UIKit.close_screen()


# =====================================================================
# Публичный API
# =====================================================================
func build() -> void:
	if _built:
		return
	_built = true

	UIKit.create_screen(true, pause_game)
	UIKit.vbox()
	UIKit.title(heading)
	UIKit.spacer(30)

	UIKit.hbox(24)
	_rebuild_cards()
	UIKit.pop_parent()   # hbox

	if allow_reroll:
		UIKit.spacer(10)
		UIKit.button("Перекатить", _on_reroll)

	UIKit.pop_parent()   # vbox

	UIKit.dim("Esc — отмена", UIKit.Align.BOTTOM_CENTER)
	UIKit.fade_in()


## Перекатить варианты, не закрывая экран (можно звать снаружи).
func reroll() -> void:
	if _built:
		_on_reroll()


## Удобно звать из игры: возвращает выбранные id «на лету» (без экрана).
static func roll_ids(p_pool: Array[Dictionary], p_count: int, p_exclude: Array[String] = [],
		p_unique := true, p_weighted := true, p_seed := 0) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	if p_seed != 0:
		rng.seed = p_seed
	else:
		rng.randomize()

	var src: Array[Dictionary] = []
	for o in p_pool:
		if not p_exclude.has(str(o.get("id", ""))):
			src.append(o)

	var out: Array[String] = []
	while out.size() < p_count and not src.is_empty():
		var i := _weighted_index(src, rng) if p_weighted else rng.randi_range(0, src.size() - 1)
		out.append(str(src[i].get("id", "")))
		if p_unique:
			src.remove_at(i)
	return out


# =====================================================================
# Карточки
# =====================================================================
func _rebuild_cards() -> void:
	# Удалить старые карточки
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()

	_shown = _resolve_options()
	if _shown.is_empty():
		UIKit.dim("Нет доступных вариантов", UIKit.Align.CENTER)
		return

	for i in _shown.size():
		_build_card(_shown[i], i)


func _resolve_options() -> Array[Dictionary]:
	# Если задан фиксированный options — берём его как есть
	if not options.is_empty():
		return options.duplicate()

	# Иначе — случайная выборка из pool
	var src: Array[Dictionary] = []
	for o in pool:
		if not exclude_ids.has(str(o.get("id", ""))):
			src.append(o)

	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	var result: Array[Dictionary] = []
	while result.size() < pick_count and not src.is_empty():
		var i := _weighted_index(src, rng) if weighted else rng.randi_range(0, src.size() - 1)
		result.append(src[i])
		if unique_picks:
			src.remove_at(i)
	return result


func _build_card(opt: Dictionary, index: int) -> void:
	var v := UIKit.panel(UIKit.C_PANEL, UIKit.C_TEXT_DIM)
	var panel := v.get_parent().get_parent() as PanelContainer
	panel.custom_minimum_size = Vector2(230, 0)
	_cards.append(panel)

	UIKit.text(str(opt.get("title", "Вариант %d" % (index + 1))),
		28, UIKit.C_TEXT, UIKit.Align.CENTER)
	if opt.has("desc"):
		UIKit.dim(str(opt["desc"]), UIKit.Align.CENTER)
	UIKit.spacer(10)
	UIKit.button("Выбрать", _on_pick.bind(index), false, index == 0)
	UIKit.pop_parent()   # панель


# =====================================================================
# Выбор
# =====================================================================
func _on_pick(index: int) -> void:
	if index < 0 or index >= _shown.size():
		return
	var data := _shown[index]
	_highlight(index)
	var id := str(data.get("id", index))
	option_selected.emit(id, index, data)
	if auto_close:
		UIKit.close_screen()


func _on_reroll() -> void:
	_rebuild_cards()
	rerolled.emit()


func _highlight(index: int) -> void:
	for i in _cards.size():
		if not is_instance_valid(_cards[i]):
			continue
		var sb := _cards[i].get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if sb:
			sb.border_color = UIKit.C_ACCENT if i == index else UIKit.C_TEXT_DIM
			_cards[i].add_theme_stylebox_override("panel", sb)


func _unhandled_input(event: InputEvent) -> void:
	if not UIKit.is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		canceled.emit()
		UIKit.close_screen()


# =====================================================================
# Взвешенный выбор
# =====================================================================
static func _weighted_index(arr: Array[Dictionary], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for o in arr:
		total += maxf(0.0, float(o.get("weight", 1.0)))
	if total <= 0.0:
		return rng.randi_range(0, arr.size() - 1)

	var r := rng.randf() * total
	for i in arr.size():
		r -= maxf(0.0, float(arr[i].get("weight", 1.0)))
		if r <= 0.0:
			return i
	return arr.size() - 1
