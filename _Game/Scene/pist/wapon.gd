extends Node3D
class_name Weapon

signal shot_fired(hits: int)
signal recoil_requested(pitch: float, yaw: float)
signal knockback_requested(impulse: Vector3)

enum FireMode { SINGLE, AUTO, PUMP }

@export_group("Идентификация")
@export var weapon_name: String = "Pistol"

@export_group("Стрельба")
@export var fire_mode: FireMode = FireMode.SINGLE
@export var pellets: int = 1
@export var damage_per_pellet: float = 1.0
@export var spread_degrees: float = 0.5
@export var max_range: float = 60.0
@export var rounds_per_minute: float = 300.0

@export_group("Снаряд")
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 120.0

@export_group("Aim assist")
@export var use_aim_assist: bool = false
@export var aim_range: float = 200.0
@export var aim_assist_radius: float = 0.6
@export_flags_3d_physics var aim_mask: int = 0xFFFFFFFF
@export_flags_3d_physics var assist_mask: int = 2

@export_group("Падение урона")
@export var falloff_start: float = 20.0
@export var falloff_end: float = 45.0
@export var falloff_min_multiplier: float = 0.5

@export_group("Ссылки")
@export var camera: Camera3D
@export var muzzle: Node3D
@export var muzzle_flash: GPUParticles3D
@export var model_pivot: Node3D
@export var anim_player: AnimationPlayer
@export var anim_shoot_name: StringName = &""
@export var ignore_body: CollisionObject3D

@export_group("Звук")
@export var audio_shoot: AudioStream
@export var audio_pump: AudioStream
@export var audio_empty: AudioStream

@export_group("Отдача")
@export var recoil_pitch: float = 1.5
@export var recoil_yaw: float = 0.3
@export var knockback_strength: float = 1.0
@export var weapon_kick_back: float = 0.08
@export var weapon_kick_rot: float = 4.0
@export var weapon_recover_speed: float = 16.0

@export_group("Слои")
@export_flags_3d_physics var hit_mask: int = 1

@export_group("Ввод")
@export var action_fire: StringName = &"fire"

var _cooldown: float = 0.0
var _audio: AudioStreamPlayer
var _rest_pos: Vector3
var _rest_rot: Vector3
var _ignore_rid: RID
var _active: bool = true


func _ready() -> void:
	_audio = AudioStreamPlayer.new()
	add_child(_audio)

	if camera == null:
		camera = get_viewport().get_camera_3d()
	if model_pivot:
		_rest_pos = model_pivot.position
		_rest_rot = model_pivot.rotation_degrees

	_resolve_ignore_body()


func _resolve_ignore_body() -> void:
	var body: CollisionObject3D = ignore_body
	if body == null:
		for p in get_tree().get_nodes_in_group("player"):
			if p is CollisionObject3D:
				body = p as CollisionObject3D
				break
	if body:
		_ignore_rid = body.get_rid()


func set_active(value: bool) -> void:
	_active = value
	visible = value
	set_process(value)


func _process(delta: float) -> void:
	if not _active:
		return

	if _cooldown > 0.0:
		_cooldown -= delta
	_update_model_recover(delta)

	var wants_fire: bool
	match fire_mode:
		FireMode.AUTO:
			wants_fire = Input.is_action_pressed(action_fire)
		_:
			wants_fire = Input.is_action_just_pressed(action_fire)

	if wants_fire:
		try_shoot()


func try_shoot() -> void:
	if _cooldown > 0.0 or camera == null:
		return

	_cooldown = 60.0 / maxf(rounds_per_minute, 1.0)

	_fire()
	_apply_visuals()
	recoil_requested.emit(recoil_pitch, randf_range(-recoil_yaw, recoil_yaw))
	knockback_requested.emit(_compute_knockback())


func _fire() -> void:
	var origin: Vector3 = _aim_origin()
	var base_dir: Vector3 = -camera.global_basis.z
	var target: Dictionary = _find_aim_target(origin, base_dir) if use_aim_assist else {}
	var aim_point: Vector3 = target.get("point", origin + base_dir * max_range)
	var aim_collider: Object = target.get("collider", null)
	var aim_dir: Vector3 = (aim_point - origin).normalized()
	if aim_dir.length_squared() < 0.001:
		aim_dir = base_dir

	var spread_rad: float = deg_to_rad(spread_degrees)
	var hits: int = 0

	for i in range(pellets):
		if pellets == 1:
			if projectile_scene != null:
				_spawn_projectile(origin, aim_dir, aim_point, aim_collider)
			else:
				hits += _hitscan(origin, aim_dir, aim_point)
		else:
			var dir: Vector3 = _random_in_cone(aim_dir, spread_rad)
			var far_point: Vector3 = origin + dir * max_range
			if projectile_scene != null:
				_spawn_projectile(origin, dir, far_point, null)
			else:
				hits += _hitscan(origin, dir, Vector3.INF)

	shot_fired.emit(hits)



func _hitscan(origin: Vector3, dir: Vector3, forced_point: Vector3) -> int:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var end_point: Vector3 = forced_point if forced_point != Vector3.INF else origin + dir * max_range
	var query := PhysicsRayQueryParameters3D.create(origin, end_point)
	query.collision_mask = hit_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if _ignore_rid.is_valid():
		query.exclude = [_ignore_rid]

	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return 0

	var collider: Object = result.get("collider")
	if collider == null:
		return 0

	var dist: float = origin.distance_to(result.position)
	var dmg: float = damage_per_pellet * _damage_multiplier(dist)
	if collider.has_method("take_damage"):
		collider.take_damage(dmg)
		return 1
	return 0


func _spawn_projectile(origin: Vector3, dir: Vector3, target_point: Vector3, target_collider: Object) -> void:
	var bullet: Node3D = projectile_scene.instantiate() as Node3D
	if bullet == null:
		return
	get_tree().current_scene.add_child(bullet)

	var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	bullet.global_transform = Transform3D(Basis.IDENTITY, origin).looking_at(origin + dir, up)

	if "speed" in bullet:
		bullet.speed = projectile_speed
	if "damage" in bullet:
		bullet.damage = damage_per_pellet
	if "hit_mask" in bullet:
		bullet.hit_mask = hit_mask
	if "falloff_start" in bullet:
		bullet.falloff_start = falloff_start
	if "falloff_end" in bullet:
		bullet.falloff_end = falloff_end
	if "falloff_min_multiplier" in bullet:
		bullet.falloff_min_multiplier = falloff_min_multiplier

	if bullet.has_method("set_origin"):
		bullet.set_origin(origin)
	if bullet.has_method("set_target"):
		bullet.set_target(target_point, target_collider)


func _find_aim_target(origin: Vector3, base_dir: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var to: Vector3 = origin + base_dir * aim_range
	var ray := PhysicsRayQueryParameters3D.create(origin, to, aim_mask)
	ray.collide_with_areas = true
	if _ignore_rid.is_valid():
		ray.exclude = [_ignore_rid]
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		return {"point": hit.position, "collider": hit.collider}

	if assist_mask != 0:
		var sphere := SphereShape3D.new()
		sphere.radius = aim_assist_radius
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sphere
		q.transform = Transform3D(Basis.IDENTITY, origin)
		q.motion = base_dir * aim_range
		q.collision_mask = assist_mask
		q.collide_with_areas = true
		if _ignore_rid.is_valid():
			q.exclude = [_ignore_rid]
		var motion := space.cast_motion(q)
		if motion.size() == 2 and motion[1] < 1.0:
			q.transform = Transform3D(Basis.IDENTITY, origin + base_dir * aim_range * motion[1])
			q.motion = Vector3.ZERO
			q.margin = 0.05
			var rest := space.get_rest_info(q)
			if not rest.is_empty():
				var target_point: Vector3 = rest.point
				var target_collider: Object = instance_from_id(rest.collider_id)
				var los := PhysicsRayQueryParameters3D.create(origin, target_point, aim_mask)
				los.collide_with_areas = true
				if _ignore_rid.is_valid():
					los.exclude = [_ignore_rid]
				var los_hit := space.intersect_ray(los)
				if los_hit.is_empty() or los_hit.collider == target_collider:
					return {"point": target_point, "collider": target_collider}

	return {"point": to, "collider": null}


func _aim_origin() -> Vector3:
	var b := camera.global_transform.basis
	return camera.global_position + b.x * camera.h_offset + b.y * camera.v_offset


func _damage_multiplier(dist: float) -> float:
	if dist <= falloff_start:
		return 1.0
	if dist >= falloff_end:
		return falloff_min_multiplier
	var t: float = (dist - falloff_start) / (falloff_end - falloff_start)
	return lerpf(1.0, falloff_min_multiplier, t)


func _random_in_cone(base_dir: Vector3, spread_rad: float) -> Vector3:
	var up_ref: Vector3 = Vector3.UP if absf(base_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right: Vector3 = base_dir.cross(up_ref).normalized()
	var up: Vector3 = right.cross(base_dir).normalized()
	var angle: float = randf() * TAU
	var radius: float = sqrt(randf()) * tan(spread_rad)
	return (base_dir + right * cos(angle) * radius + up * sin(angle) * radius).normalized()


func _compute_knockback() -> Vector3:
	var aim: Vector3 = -camera.global_basis.z
	var knock: Vector3 = -aim * knockback_strength
	if knock.y > 0.0:
		knock.y *= 0.5
	return knock


func _apply_visuals() -> void:
	if muzzle_flash:
		muzzle_flash.restart()
		muzzle_flash.emitting = true
	if model_pivot:
		model_pivot.position = _rest_pos + Vector3(0, 0, weapon_kick_back)
		model_pivot.rotation_degrees = _rest_rot + Vector3(-weapon_kick_rot, 0, 0)
	if anim_player and anim_shoot_name != &"":
		anim_player.speed_scale = 5.0
		anim_player.stop(true)
		anim_player.play(anim_shoot_name)

	_play_sound(audio_shoot, 0.0)
	if fire_mode == FireMode.PUMP and audio_pump:
		var delay: float = 60.0 / maxf(rounds_per_minute, 1.0) * 0.4
		get_tree().create_timer(delay).timeout.connect(_play_pump)


func _play_pump() -> void:
	if is_instance_valid(self):
		_play_sound(audio_pump, -4.0)


func _update_model_recover(delta: float) -> void:
	if model_pivot == null:
		return
	model_pivot.position = model_pivot.position.lerp(_rest_pos, weapon_recover_speed * delta)
	model_pivot.rotation_degrees = model_pivot.rotation_degrees.lerp(_rest_rot, weapon_recover_speed * delta)


func _play_sound(stream: AudioStream, volume_db: float) -> void:
	if stream == null or _audio == null:
		return
	_audio.stream = stream
	_audio.volume_db = volume_db
	_audio.play()
