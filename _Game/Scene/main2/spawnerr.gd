extends Node3D
class_name EnemySpawner

# ============================================================
#  СЦЕНЫ ВРАГОВ
# ============================================================

@export_group("Сцены врагов")
## Базовый враг (тип 1) — появляется всегда
@export var enemy_scene_primary: PackedScene

## Второй тип врага — появляется только после unlock
@export var enemy_scene_secondary: PackedScene

@export var enemy_container: Node3D

# ============================================================
#  НАВИГАЦИЯ
# ============================================================

@export_group("Навигация")
@export var navigation_region: NavigationRegion3D
@export_range(1, 32, 1) var navigation_layers: int = 1

# ============================================================
#  ДИСТАНЦИЯ ОТ ИГРОКА
# ============================================================

@export_group("Дистанция от игрока")
@export var player_group: StringName = &"player"
@export var min_spawn_distance: float = 12.0
@export var max_spawn_distance: float = 0.0
@export_range(1, 100, 1) var max_attempts: int = 25

# ============================================================
#  ТАЙМЕР И ЛИМИТЫ
# ============================================================

@export_group("Таймер и лимиты")
@export var spawn_interval: float = 3.0
@export var max_alive_enemies: int = 20
@export var autostart: bool = true
@export var first_spawn_delay: float = 1.0

# ============================================================
#  ПРОГРЕССИЯ СЛОЖНОСТИ
# ============================================================

@export_group("Прогрессия сложности")
## Стартовый множитель характеристик (обычно 1.0)
@export var difficulty_base: float = 1.0

## Во сколько раз растут характеристики за КАЖДУЮ минуту.
## 1.20  ->  +20% в минуту  ->  за 5 минут ≈ x2.49
## 1.15  ->  +15% в минуту  ->  за 5 минут ≈ x2.01
## 1.30  ->  +30% в минуту  ->  за 5 минут ≈ x3.71
@export var difficulty_growth_per_minute: float = 1.20

## Верхний потолок множителя (0 — без ограничения)
@export var difficulty_max_multiplier: float = 0.0

# ============================================================
#  ВТОРОЙ ТИП ВРАГА
# ============================================================

@export_group("Второй тип врага")
## Через сколько секунд от начала игры может появиться 2-й тип
@export var secondary_unlock_time: float = 120.0       # 2 минуты

## Шанс появления 2-го типа сразу после unlock
@export_range(0.0, 1.0, 0.01) var secondary_chance_start: float = 0.10

## Время (в секундах от начала), когда шанс достигает максимума
@export var secondary_chance_full_time: float = 240.0   # 4 минуты

## Максимальный шанс 2-го типа
@export_range(0.0, 1.0, 0.01) var secondary_chance_end: float = 0.90

# ============================================================
#  ОТЛАДКА
# ============================================================

@export_group("Отладка")
@export var debug_log: bool = false

# ============================================================
#  ВНУТРЕННИЕ
# ============================================================

var _timer: Timer
var _alive_enemies: Array[Node] = []
var _map_rid: RID
var _nav_ready: bool = false
var _game_timer: Node

# ============================================================
#  ЖИЗНЕННЫЙ ЦИКЛ
# ============================================================

func _ready() -> void:
	if enemy_scene_primary == null:
		push_warning("[EnemySpawner] enemy_scene_primary не назначена.")
		return

	if navigation_region == null:
		navigation_region = _find_navigation_region()
		if navigation_region == null:
			push_error("[EnemySpawner] NavigationRegion3D не найден.")
			return

	await get_tree().physics_frame
	await get_tree().physics_frame

	_map_rid = navigation_region.get_navigation_map()
	_nav_ready = true

	# Ищем игровой таймер (по группе)
	_game_timer = get_tree().get_first_node_in_group("game_timer")
	if _game_timer == null:
		push_warning("[EnemySpawner] game_timer не найден в группе 'game_timer'. Прогресс будет считаться нулевым.")

	if spawn_interval > 0.0:
		_timer = Timer.new()
		_timer.wait_time = spawn_interval
		_timer.one_shot = false
		_timer.autostart = false
		_timer.timeout.connect(_on_timer_timeout)
		add_child(_timer)

		if autostart:
			_timer.start(first_spawn_delay)

# ============================================================
#  ПУБЛИЧНЫЕ МЕТОДЫ
# ============================================================

func spawn_one() -> Node:
	if not _nav_ready:
		return null

	if _game_timer and _game_timer.has_method("is_finished") and _game_timer.is_finished():
		return null

	if max_alive_enemies > 0 and _alive_enemies.size() >= max_alive_enemies:
		return null

	var pos := _get_valid_spawn_position()
	if pos == Vector3.ZERO:
		if debug_log:
			print("[EnemySpawner] Не найдено валидной точки.")
		return null

	# --- Выбор сцены врага ---
	var elapsed: float = _get_elapsed()
	var scene: PackedScene = _choose_enemy_scene(elapsed)
	if scene == null:
		return null

	var enemy := scene.instantiate()

	# --- Применяем экспоненциальный множитель ДО добавления в дерево ---
	var mult := get_difficulty_multiplier()
	if enemy.has_method("apply_difficulty"):
		enemy.apply_difficulty(mult)
	elif debug_log:
		print("[EnemySpawner] %s не имеет apply_difficulty()." % enemy.name)

	# --- Порядок важен: сначала в дерево, потом global_position ---
	var parent: Node = enemy_container if enemy_container != null else get_tree().current_scene
	parent.add_child(enemy)
	if enemy is Node3D:
		(enemy as Node3D).global_position = pos

	_alive_enemies.append(enemy)
	enemy.tree_exited.connect(_on_enemy_exited.bind(enemy))

	if debug_log:
		print("[EnemySpawner] Спавн %s | t=%.1fс | mult=%.2f | pos=%s" % [scene.resource_path.get_file(), elapsed, mult, pos])
	return enemy

func spawn_batch(count: int) -> void:
	for i in range(count):
		if spawn_one() == null:
			break

func start_spawning() -> void:
	if _timer: _timer.start()

func stop_spawning() -> void:
	if _timer: _timer.stop()

func get_alive_count() -> int:
	return _alive_enemies.size()

# ============================================================
#  ПРОГРЕССИЯ
# ============================================================

## Экспоненциальный множитель характеристик.
## mult = base * growth^minutes
func get_difficulty_multiplier() -> float:
	var minutes := _get_elapsed() / 60.0
	var m := difficulty_base * pow(difficulty_growth_per_minute, minutes)
	if difficulty_max_multiplier > 0.0:
		m = minf(m, difficulty_max_multiplier)
	return m

## Шанс появления 2-го типа (0..1) в зависимости от времени.
func get_secondary_chance() -> float:
	var e := _get_elapsed()
	if e < secondary_unlock_time:
		return 0.0
	if e >= secondary_chance_full_time:
		return secondary_chance_end
	var t := (e - secondary_unlock_time) / maxf(secondary_chance_full_time - secondary_unlock_time, 0.001)
	return lerpf(secondary_chance_start, secondary_chance_end, t)

func _choose_enemy_scene(_elapsed: float) -> PackedScene:
	if enemy_scene_secondary == null:
		return enemy_scene_primary

	var chance := get_secondary_chance()
	if randf() < chance:
		return enemy_scene_secondary
	return enemy_scene_primary

func _get_elapsed() -> float:
	if _game_timer and _game_timer.has_method("get_elapsed"):
		return _game_timer.get_elapsed()
	return 0.0

# ============================================================
#  ВНУТРЕННЕЕ
# ============================================================

func _on_timer_timeout() -> void:
	spawn_one()

func _on_enemy_exited(enemy: Node) -> void:
	_alive_enemies.erase(enemy)

func _find_navigation_region() -> NavigationRegion3D:
	var regions := get_tree().get_nodes_in_group("navigation_region")
	for r in regions:
		if r is NavigationRegion3D:
			return r as NavigationRegion3D
	return _find_first_navigation_region(get_tree().current_scene)

func _find_first_navigation_region(node: Node) -> NavigationRegion3D:
	if node is NavigationRegion3D:
		return node as NavigationRegion3D
	for child in node.get_children():
		var f := _find_first_navigation_region(child)
		if f != null:
			return f
	return null

func _get_valid_spawn_position() -> Vector3:
	var player := _get_player()
	var player_pos: Vector3 = player.global_position if player != null else Vector3.ZERO
	var has_player := player != null

	for i in range(max_attempts):
		var point: Vector3 = NavigationServer3D.map_get_random_point(_map_rid, navigation_layers, false)
		if point == Vector3.ZERO:
			continue
		point = NavigationServer3D.map_get_closest_point(_map_rid, point)

		if has_player:
			var d := point.distance_to(player_pos)
			if d < min_spawn_distance:
				continue
			if max_spawn_distance > 0.0 and d > max_spawn_distance:
				continue
		return point

	return Vector3.ZERO

func _get_player() -> Node3D:
	for n in get_tree().get_nodes_in_group(player_group):
		if n is Node3D:
			return n as Node3D
	return null
