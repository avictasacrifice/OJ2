extends CharacterBody3D
# ↑ ВАЖНО: тип корневой ноды CharacterBody3D

# ============================================================
#  НАСТРОЙКИ
# ============================================================
@export_group("Движение")
@export var move_speed: float = 3.5
@export var gravity: float = 20.0
@export var detection_range: float = 25.0
@export var stop_distance: float = 1.0
@export var rotation_speed: float = 8.0

@export_group("Поиск пути")
@export var navigation_agent: NavigationAgent3D
@export var path_update_interval: float = 0.2

@export_group("Качание модели")
@export var sway_amount: float = 0.2
@export var sway_speed: float = 8.0
@export var sway_smoothness: float = 10.0

@export_group("Атака")
@export var attack_range: float = 1.3
@export var damage: int = 1
@export var damage_cooldown: float = 1.0

@export_group("Прочее")
@export var player_group: StringName = &"player"
@export var blood_scene: PackedScene

# ============================================================
#  СОСТОЯНИЕ
# ============================================================
var health: int = 3

var _flash_material: StandardMaterial3D
var _player: Node3D = null
var _damage_timer: float = 0.0
var _is_dead: bool = false

var _path_timer: float = 0.0
var _sway_time: float = 0.0
@export var _mesh: MeshInstance3D


# ============================================================
#  ЖИЗНЕННЫЙ ЦИКЛ
# ============================================================
func _ready() -> void:
	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color.WHITE
	_mesh.material_override = _flash_material
	_refresh_player()

	if navigation_agent:
		navigation_agent.path_desired_distance = 0.5
		navigation_agent.target_desired_distance = max(stop_distance, 0.5)
		navigation_agent.avoidance_enabled = false
		# отложенная инициализация цели, чтобы навмеш успел проснуться
		call_deferred("_setup_nav_target")


func _setup_nav_target() -> void:
	if navigation_agent and _player and is_instance_valid(_player):
		navigation_agent.target_position = _player.global_position


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	if _damage_timer > 0.0:
		_damage_timer -= delta

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	_refresh_player()

	if not _player or not is_instance_valid(_player):
		_brake(delta)
		move_and_slide()
		_update_sway(delta, false)
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist <= detection_range and dist > stop_distance:
		var move_dir := _get_move_direction(delta)

		if move_dir.length_squared() > 0.0001:
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed

			var target_yaw := atan2(-move_dir.x, -move_dir.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, rotation_speed * delta)
	else:
		_brake(delta)

	move_and_slide()

	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	_update_sway(delta, moving)

	_try_hit_player(dist)


# ============================================================
#  НАПРАВЛЕНИЕ ДВИЖЕНИЯ
# ============================================================
func _get_move_direction(delta: float) -> Vector3:
	if navigation_agent and navigation_agent.is_inside_tree():
		_path_timer -= delta
		if _path_timer <= 0.0:
			_path_timer = path_update_interval
			navigation_agent.target_position = _player.global_position

		var next_pos := navigation_agent.get_next_path_position()
		var dir := next_pos - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			return dir.normalized()

	var d := _player.global_position - global_position
	d.y = 0.0
	if d.length() > 0.05:
		return d.normalized()
	return Vector3.ZERO


func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, move_speed * 6.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, move_speed * 6.0 * delta)


func _refresh_player() -> void:
	if _player and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group(player_group)
	if not players.is_empty():
		_player = players[0] as Node3D


# ============================================================
#  КАЧАНИЕ МОДЕЛИ
# ============================================================
func _update_sway(delta: float, is_moving: bool) -> void:
	if not _mesh:
		return

	if is_moving:
		_sway_time += delta * sway_speed
		var target_sway := sin(_sway_time) * sway_amount
		_mesh.rotation.z = lerp(_mesh.rotation.z, target_sway, sway_smoothness * delta)
	else:
		_sway_time = 0.0
		_mesh.rotation.z = lerp(_mesh.rotation.z, 0.0, sway_smoothness * delta)


# ============================================================
#  КОНТАКТНЫЙ УРОН
# ============================================================
func _try_hit_player(dist: float) -> void:
	if _damage_timer > 0.0:
		return
	if not _player or not is_instance_valid(_player):
		return

	var touching := dist <= attack_range

	if not touching:
		for i in get_slide_collision_count():
			if get_slide_collision(i).get_collider() == _player:
				touching = true
				break

	if not touching:
		return

	if _player.has_method("take_damage"):
		_player.take_damage(damage)
		_damage_timer = damage_cooldown


# ============================================================
#  ПОЛУЧЕНИЕ УРОНА / СМЕРТЬ
# ============================================================
func take_damage(amount: int) -> void:
	Audio.play(&"hit")
	if _is_dead:
		return

	health -= amount
	print("Враг: ", health)

	if health > 0:
		_spawn_blood(false)

	_flash_material.albedo_color = Color(1, 0, 0)
	await get_tree().create_timer(0.1).timeout

	if not is_instance_valid(self) or _is_dead:
		return
	_flash_material.albedo_color = Color.WHITE

	if health <= 0:
		die()


func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	print("Враг сдох")
	Shaker.play(0.1, 0.25, Tween.TRANS_EXPO)
	_spawn_blood(true)
	set_physics_process(false)
	queue_free()


# ============================================================
#  КРОВЬ
# ============================================================
func _spawn_blood(is_death: bool) -> void:
	if not blood_scene:
		return

	var blood = blood_scene.instantiate() as GPUParticles3D
	get_tree().current_scene.add_child(blood)

	blood.global_position = global_position + Vector3(0, 0, 0)

	blood.one_shot = true
	blood.explosiveness = 1.0
	blood.local_coords = false
	blood.emitting = false

	var mat = blood.process_material as ParticleProcessMaterial
	if mat:
		mat.direction = Vector3(0, 1, 0)
		mat.gravity = Vector3(0, -9.8, 0)

		if is_death:
			blood.amount = 200
			blood.lifetime = 4.0
			mat.initial_velocity_min = 5.0
			mat.initial_velocity_max = 12.0
			mat.spread = 180.0
			mat.scale_min = 0.5
			mat.scale_max = 1.5
		else:
			blood.amount = 30
			blood.lifetime = 4.0
			mat.initial_velocity_min = 2.0
			mat.initial_velocity_max = 5.0
			mat.spread = 45.0
			mat.scale_min = 0.2
			mat.scale_max = 0.5

	blood.restart()

	# отдельная функция вместо лямбды — надёжнее
	_free_blood_after(blood, blood.lifetime + 0.5)


func _free_blood_after(blood: GPUParticles3D, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(blood):
		blood.queue_free()
