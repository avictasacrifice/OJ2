extends Node3D
class_name EnemySpawner

# ============================================================
#  ЭКСПОРТНЫЕ ПЕРЕМЕННЫЕ
# ============================================================

@export_group("Сцена врага")
## Сцена врага, которую нужно спавнить
@export var enemy_scene: PackedScene

## Родитель для заспавненных врагов (если null — добавление в текущую сцену)
@export var enemy_container: Node3D

@export_group("Навигация")
## Регион навигации, по которому будем выбирать точки спавна.
## Если не задан — берётся первый NavigationRegion3D в дереве сцены.
@export var navigation_region: NavigationRegion3D

## Слой навигации, по которому искать случайную точку
@export_range(1, 32, 1) var navigation_layers: int = 1

@export_group("Дистанция от игрока")
## Игрок будет искаться по этой группе
@export var player_group: StringName = &"player"

## Минимальное расстояние от игрока до точки спавна (в метрах)
@export var min_spawn_distance: float = 12.0

## Максимальное расстояние от игрока до точки спавна (в метрах).
## Поставь 0 или отрицательное значение, чтобы отключить верхний предел.
@export var max_spawn_distance: float = 0.0

## Сколько раз пробовать найти подходящую точку за один вызов
@export_range(1, 100, 1) var max_attempts: int = 25

@export_group("Таймер и лимиты")
## Интервал между спавнами в секундах (0 — спавн отключён по таймеру)
@export var spawn_interval: float = 3.0

## Максимум одновременно живых врагов (0 — без ограничения)
@export var max_alive_enemies: int = 20

## Начинать ли автоспавн сразу при старте сцены
@export var autostart: bool = true

## Случайная задержка перед первым спавном (для естественности)
@export var first_spawn_delay: float = 1.0

@export_group("Отладка")
## Выводить ли в консоль сообщения о спавне
@export var debug_log: bool = false

# ============================================================
#  ВНУТРЕННИЕ ПЕРЕМЕННЫЕ
# ============================================================

var _timer: Timer
var _alive_enemies: Array[Node] = []
var _map_rid: RID
var _nav_ready: bool = false

# ============================================================
#  ЖИЗНЕННЫЙ ЦИКЛ
# ============================================================

func _ready() -> void:
	# Валидация сцены врага
	if enemy_scene == null:
		push_warning("[EnemySpawner] enemy_scene не назначена — спавн невозможен.")
		return

	# Ищем регион навигации, если не задан вручную
	if navigation_region == null:
		navigation_region = _find_navigation_region()
		if navigation_region == null:
			push_error("[EnemySpawner] NavigationRegion3D не найден в сцене.")
			return

	# Ждём, пока навигационный сервер синхронизируется — иначе map_get_random_point вернёт ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	_map_rid = navigation_region.get_navigation_map()
	_nav_ready = true

	# Настраиваем таймер
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
#  ПУБЛИЧНЫЕ МЕТОДЫ (можно дёргать извне)
# ============================================================

## Заспавнить одного врага. Возвращает Node или null при неудаче.
func spawn_one() -> Node:
	if not _nav_ready:
		if debug_log:
			print("[EnemySpawner] Навигация ещё не готова.")
		return null

	if max_alive_enemies > 0 and _alive_enemies.size() >= max_alive_enemies:
		if debug_log:
			print("[EnemySpawner] Достигнут лимит живых врагов (%d)." % max_alive_enemies)
		return null

	var pos := _get_valid_spawn_position()
	if pos == Vector3.ZERO:
		if debug_log:
			print("[EnemySpawner] Не удалось найти подходящую точку спавна.")
		return null

	var enemy := enemy_scene.instantiate()
	
	var parent: Node = enemy_container if enemy_container != null else get_tree().current_scene
	parent.add_child(enemy)
	
	if enemy is Node3D:
		(enemy as Node3D).global_position = pos


	_alive_enemies.append(enemy)
	# Убираем из списка, когда враг умирает/удаляется
	enemy.tree_exited.connect(_on_enemy_exited.bind(enemy))

	if debug_log:
		print("[EnemySpawner] Заспавнен %s в %s" % [enemy.name, pos])
	return enemy

## Заспавнить несколько врагов сразу
func spawn_batch(count: int) -> void:
	for i in range(count):
		if spawn_one() == null:
			break

## Запустить автоспавн
func start_spawning() -> void:
	if _timer != null:
		_timer.start()

## Остановить автоспавн
func stop_spawning() -> void:
	if _timer != null:
		_timer.stop()

## Вернуть текущее количество живых врагов
func get_alive_count() -> int:
	return _alive_enemies.size()

# ============================================================
#  ВНУТРЕННЯЯ ЛОГИКА
# ============================================================

func _on_timer_timeout() -> void:
	spawn_one()

func _on_enemy_exited(enemy: Node) -> void:
	_alive_enemies.erase(enemy)

func _find_navigation_region() -> NavigationRegion3D:
	var regions := get_tree().get_nodes_in_group("navigation_region")
	if regions.size() > 0 and regions[0] is NavigationRegion3D:
		return regions[0] as NavigationRegion3D

	# Фолбэк: ищем первого потомка нужного типа
	return _find_first_navigation_region(get_tree().current_scene)

func _find_first_navigation_region(node: Node) -> NavigationRegion3D:
	if node is NavigationRegion3D:
		return node as NavigationRegion3D
	for child in node.get_children():
		var found := _find_first_navigation_region(child)
		if found != null:
			return found
	return null

func _get_valid_spawn_position() -> Vector3:
	var player := _get_player()
	var player_pos: Vector3 = player.global_position if player != null else Vector3.ZERO
	var has_player := player != null

	for i in range(max_attempts):
		# uniformly = false — быстрее, для коридоров достаточно
		var point: Vector3 = NavigationServer3D.map_get_random_point(_map_rid, navigation_layers, false)
		if point == Vector3.ZERO:
			continue

		# Прилипаем к навигационной поверхности (защита от микро-погрешностей)
		point = NavigationServer3D.map_get_closest_point(_map_rid, point)

		if has_player:
			var d := point.distance_to(player_pos)
			if d < min_spawn_distance:
				continue
			if max_spawn_distance > 0.0 and d > max_spawn_distance:
				continue

		# Дополнительная проверка: если выбрали максимум попыток и точка всё ещё «плохая»
		return point

	return Vector3.ZERO

func _get_player() -> Node3D:
	var nodes := get_tree().get_nodes_in_group(player_group)
	for n in nodes:
		if n is Node3D:
			return n as Node3D
	return null
