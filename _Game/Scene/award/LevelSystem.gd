extends Node

signal xp_changed(current: int, needed: int)
signal leveled_up(new_level: int)

@export var enabled: bool = true
@export var upgrades_enabled: bool = true
@export var base_xp_needed := 10
@export var xp_growth := 1.25

const CHOICE_SCENE := preload("res://_Game/Scene/award/control.tscn")

var level: int = 1
var xp: int = 0
var xp_to_next: int = 10

var _pool: Array[Dictionary] = []
var _taken_ids: Array[String] = []
var _pending_choices := 0
var _choice_open := false
var _choice_node: Node = null


func _ready() -> void:
	xp_to_next = _calc_needed(level)
	register_upgrades([
		{"id": "hp",      "title": "+20 HP",       "desc": "Здоровье",    "weight": 3.0, "stackable": true},
		{"id": "dmg",     "title": "+10% Урон",    "desc": "Урон",        "weight": 2.0, "stackable": true},
		{"id": "spd",     "title": "+5% Скорость", "desc": "Скорость",    "weight": 1.0, "stackable": true},
		{"id": "regen",   "title": "+1 HP/сек",    "desc": "Регенерация", "weight": 0.6, "stackable": true},
		{"id": "shotgun", "title": "ДРОБОВИК",     "desc": "Помповый. 8 дробин. Страшен в упор.", "weight": 1.0, "stackable": false},
	])


func register_upgrade(u: Dictionary) -> void:
	_pool.append(u)


func register_upgrades(arr: Array) -> void:
	for u in arr:
		register_upgrade(u)


func _calc_needed(lvl: int) -> int:
	return int(round(base_xp_needed * pow(xp_growth, lvl - 1)))


func add_xp(amount: int) -> void:
	if not enabled or amount <= 0:
		return
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = _calc_needed(level)
		leveled_up.emit(level)
		if upgrades_enabled:
			_pending_choices += 1
	xp_changed.emit(xp, xp_to_next)
	_try_show_next()


func _try_show_next() -> void:
	if not enabled or not upgrades_enabled:
		return
	if _choice_open or _pending_choices <= 0:
		return
	_pending_choices -= 1
	_choice_open = true
	_show_choice()


func _show_choice() -> void:
	var s := CHOICE_SCENE.instantiate()
	s.heading = "УРОВЕНЬ %d" % level
	s.pause_game = true
	s.pool = _pool.duplicate(true)
	s.pick_count = 3
	s.exclude_ids = _taken_ids.duplicate()
	s.auto_close = true
	s.option_selected.connect(_on_pick)
	s.canceled.connect(_on_cancel)
	_choice_node = s
	get_tree().current_scene.add_child.call_deferred(s)


func _on_pick(id: String, _index: int, data: Dictionary) -> void:
	if not data.get("stackable", false) and not _taken_ids.has(id):
		_taken_ids.append(id)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("apply_upgrade"):
		p.apply_upgrade(data)
	_after_choice()


func _on_cancel() -> void:
	_after_choice()


func _after_choice() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("heal"):
		p.heal(999999)
	_choice_open = false
	if is_instance_valid(_choice_node):
		_choice_node.queue_free.call_deferred()
	_choice_node = null
	_try_show_next.call_deferred()
