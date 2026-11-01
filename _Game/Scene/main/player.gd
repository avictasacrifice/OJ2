extends CharacterBody3D

signal weapon_unlocked(weapon_id: StringName)

@export var show_xp_bar: bool = true
var _hp_label: Label
var MAX_HEALTH := 10
@export var hp_bar_size := Vector2(280, 20)
@export var hp_bar_pos := Vector2(24, 24)
var _hp_bar: ProgressBar
var SPEED := 10.0
var MAX_SPEED := 50.0
const GRAVITY := 20.0
const JUMP_VELOCITY := 7.5
var health: int

var damage_mult := 1.0
var regen_per_sec := 0.0
var _regen_accum := 0.0
var _xp_bar: ProgressBar

const GROUND_ACCEL := 18.0
const FRICTION := 12.0
const STOP_SPEED := 1.8
const AIR_ACCEL := 12.0
const AIR_TURN_RATE := 5.5
const BHOP_SOFT_CAP := 16.0
const BHOP_EXCESS_KEEP := 0.88
const JUMP_CUT := 0.55
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.15
@export var auto_bhop := true

@export var MOUSE_SENSITIVITY := 0.0026
const PITCH_LIMIT := deg_to_rad(88.0)

const COMPRESS_DECEL := 2.0
const COMPRESS_STEER := 22.0
const COMPRESS_AIR_STEER := 14.0
const COMPRESS_AIR_DECEL_MULT := 0.35
const COMPRESS_WINDOW_MIN := 0.12
const COMPRESS_WINDOW_MAX := 0.40
const COMPRESS_OVERHOLD := 0.75
const LAUNCH_IMPULSE := 28.0
const LAUNCH_UP_POP := 5.5
const LAUNCH_MIN_CHARGE := 0.25
const LAUNCH_COOLDOWN := 0.25
const TUCK_DURATION := 0.22
const DASH_WINDOW := 0.40
const DASH_AIR_ACCEL_MULT := 1.8
const DASH_FRICTION_MULT := 0.15
const DASH_FOV_KICK := 18.0
const DASH_TURN_RATE := 7.0

const RECOIL_RECOVER := 12.0

@export var gameover: Control
@onready var camera: Camera3D = $Camera3D

const PAUSE_MENU_SCENE := preload("res://_Game/UI/_pause_menu.tscn")
var _pause_menu: Control = null

var _yaw := 0.0
var _mouse_pitch := 0.0
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0

var _is_compressing := false
var _compress_time := 0.0
var _tuck_timer := 0.0
var _jump_buffer_timer := 0.0
var _coyote_timer := 0.0
var _dash_timer := 0.0
var _launch_cooldown := 0.0
var _jump_cut_ready := false

var _col: CollisionShape3D
var _col_orig_height := 0.0
var _col_orig_center_y := 0.0
var _col_ready := false
var _base_fov := 0.0

var _damage_accum := 0.0
var _weapons: Array[Weapon] = []
var _weapon_unlocked: Array[bool] = []
var _weapon_index: int = 0


func _ready() -> void:
	_teardown()
	_build()


func _exit_tree() -> void:
	_teardown()


func _teardown() -> void:
	if is_instance_valid(LevelSystem) and LevelSystem.xp_changed.is_connected(_on_xp_changed):
		LevelSystem.xp_changed.disconnect(_on_xp_changed)
	if is_instance_valid(_hp_bar):
		_hp_bar.queue_free()
	_hp_bar = null
	if is_instance_valid(_hp_label):
		_hp_label.queue_free()
	_hp_label = null
	if is_instance_valid(_xp_bar):
		_xp_bar.queue_free()
	_xp_bar = null
	_pause_menu = null


func _build() -> void:
	health = MAX_HEALTH
	damage_mult = 1.0
	regen_per_sec = 0.0
	_regen_accum = 0.0
	_damage_accum = 0.0
	_yaw = 0.0
	_mouse_pitch = 0.0
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	_is_compressing = false
	_compress_time = 0.0
	_tuck_timer = 0.0
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_dash_timer = 0.0
	_launch_cooldown = 0.0
	_jump_cut_ready = false

	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_base_fov = camera.fov
	camera.rotation.x = 0.0

	_col = find_child("CollisionShape3D", true, false) as CollisionShape3D
	_col_ready = false
	if _col and _col.shape is CapsuleShape3D:
		var cap := _col.shape as CapsuleShape3D
		_col_orig_height = cap.height
		_col_orig_center_y = _col.position.y
		_col_ready = true

	_weapons.clear()
	_weapon_unlocked.clear()
	var pistol := camera.get_node_or_null("Pistol") as Weapon
	var shotgun := camera.get_node_or_null("Shotgun") as Weapon
	if pistol:
		_weapons.append(pistol)
		_weapon_unlocked.append(false)
	if shotgun:
		_weapons.append(shotgun)
		_weapon_unlocked.append(false)

	for w in _weapons:
		w.recoil_requested.connect(_on_weapon_recoil)
		w.knockback_requested.connect(_on_weapon_knockback)

	if _weapons.size() > 0:
		_weapon_unlocked[0] = true
		_select_weapon(0)

	UIKit.hud_create(hp_bar_pos)
	_hp_bar = UIKit.hud_bar(float(health), float(MAX_HEALTH), UIKit.C_HP, hp_bar_size)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 14)
	_hp_label.add_theme_color_override("font_color", UIKit.C_TEXT_HI)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.position = Vector2(hp_bar_pos.x + hp_bar_size.x + 8, hp_bar_pos.y)
	_hp_label.text = "%d/%d" % [health, MAX_HEALTH]
	UIKit._hud_layer.add_child(_hp_label)

	if show_xp_bar:
		_create_xp_bar()
		if not LevelSystem.xp_changed.is_connected(_on_xp_changed):
			LevelSystem.xp_changed.connect(_on_xp_changed)
		_on_xp_changed(LevelSystem.xp, LevelSystem.xp_to_next)


func _create_xp_bar() -> void:
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.max_value = LevelSystem.xp_to_next
	_xp_bar.value = 0
	_xp_bar.anchor_left = 0.5
	_xp_bar.anchor_right = 0.5
	_xp_bar.anchor_top = 1.0
	_xp_bar.anchor_bottom = 1.0
	_xp_bar.offset_left = -300
	_xp_bar.offset_right = 300
	_xp_bar.offset_top = -106
	_xp_bar.offset_bottom = -86

	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0, 0, 0, 0.55)
	sb_bg.border_color = UIKit.C_TEXT_DIM
	sb_bg.set_border_width_all(2)
	sb_bg.set_corner_radius_all(3)
	_xp_bar.add_theme_stylebox_override("background", sb_bg)

	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = UIKit.C_ACCENT
	sb_fill.set_corner_radius_all(3)
	_xp_bar.add_theme_stylebox_override("fill", sb_fill)

	UIKit._hud_layer.add_child(_xp_bar)


func _on_xp_changed(current: int, needed: int) -> void:
	if not is_instance_valid(_xp_bar):
		return
	_xp_bar.max_value = maxi(needed, 1)
	UIKit.hud_bar_animate(_xp_bar, float(current), 0.15)


func apply_upgrade(data: Dictionary) -> void:
	match str(data.get("id", "")):
		"hp":
			MAX_HEALTH += 20
			health = mini(health + 20, MAX_HEALTH)
			_update_hp_bar()
		"dmg":
			damage_mult *= 1.10
			for w in _weapons:
				w.damage_per_pellet *= 1.10
		"spd":
			SPEED *= 1.05
			MAX_SPEED *= 1.05
		"regen":
			regen_per_sec += 1.0
		"heal":
			heal(999999)
		"shotgun":
			unlock_weapon_by_name("Shotgun")


func unlock_weapon_by_name(weapon_id: String) -> void:
	for i in _weapons.size():
		if String(_weapons[i].name) == weapon_id or _weapons[i].weapon_name == weapon_id:
			_unlock_weapon(i)
			return
	push_warning("[Player] Оружие не найдено: %s" % weapon_id)


func is_weapon_unlocked(weapon_id: String) -> bool:
	for i in _weapons.size():
		if String(_weapons[i].name) == weapon_id or _weapons[i].weapon_name == weapon_id:
			return _weapon_unlocked[i]
	return false


func _unlock_weapon(index: int) -> void:
	if index < 0 or index >= _weapons.size():
		return
	if _weapon_unlocked[index]:
		return
	_weapon_unlocked[index] = true
	weapon_unlocked.emit(StringName(_weapons[index].name))
	_select_weapon(index)
	_show_unlock_toast("ДРОБОВИК ОТКРЫТ")


func _show_unlock_toast(text: String) -> void:
	if not is_instance_valid(UIKit) or UIKit._hud_layer == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 44)
	lbl.add_theme_color_override("font_color", Color("#ffcc33"))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	lbl.offset_top = 140
	lbl.offset_left = -400
	lbl.offset_right = 400
	lbl.offset_bottom = 220
	lbl.modulate.a = 0.0
	UIKit._hud_layer.add_child(lbl)

	var tw := create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.3)
	tw.tween_interval(1.4)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(lbl.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if UIKit.is_open():
			return
		_open_pause_menu()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_mouse_pitch = clampf(_mouse_pitch - event.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)

	if event.is_action_pressed("weapon_next"):
		_cycle_weapon(1)
	elif event.is_action_pressed("weapon_1"):
		_select_weapon(0)
	elif event.is_action_pressed("weapon_2"):
		_select_weapon(1)


func _select_weapon(index: int) -> void:
	if index < 0 or index >= _weapons.size():
		return
	if not _weapon_unlocked[index]:
		return
	_weapon_index = index
	for i in _weapons.size():
		_weapons[i].set_active(i == index and _weapon_unlocked[i])


func _cycle_weapon(step: int) -> void:
	if _weapons.is_empty():
		return
	var n := _weapons.size()
	var idx := _weapon_index
	for _i in n:
		idx = (idx + step + n) % n
		if _weapon_unlocked[idx]:
			_select_weapon(idx)
			return


func _on_weapon_recoil(pitch: float, yaw: float) -> void:
	_recoil_pitch += pitch
	_recoil_yaw += yaw


func _on_weapon_knockback(impulse: Vector3) -> void:
	velocity += impulse.limit_length(2.5)


func _open_pause_menu() -> void:
	if is_instance_valid(_pause_menu):
		return
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	_pause_menu.tree_exited.connect(func() -> void: _pause_menu = null)
	get_tree().current_scene.add_child.call_deferred(_pause_menu)


func _physics_process(delta: float) -> void:
	if regen_per_sec > 0.0 and health > 0 and health < MAX_HEALTH:
		_regen_accum += regen_per_sec * delta
		if _regen_accum >= 1.0:
			var whole := int(_regen_accum)
			_regen_accum -= whole
			heal(whole)

	_recoil_pitch = lerpf(_recoil_pitch, 0.0, RECOIL_RECOVER * delta)
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, RECOIL_RECOVER * delta)
	rotation.y = _yaw + _recoil_yaw
	camera.rotation.x = clampf(_mouse_pitch + deg_to_rad(_recoil_pitch), -PITCH_LIMIT, PITCH_LIMIT)

	var on_floor := is_on_floor()

	if on_floor:
		_coyote_timer = COYOTE_TIME
	elif _coyote_timer > 0.0:
		_coyote_timer -= delta

	if _dash_timer > 0.0:
		_dash_timer -= delta
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta
	if _launch_cooldown > 0.0:
		_launch_cooldown -= delta

	if Input.is_action_just_pressed("space"):
		_jump_buffer_timer = JUMP_BUFFER
	if auto_bhop and Input.is_action_pressed("space") and on_floor:
		_jump_buffer_timer = JUMP_BUFFER

	if not on_floor:
		velocity.y -= GRAVITY * delta

	var jumped := false
	if _jump_buffer_timer > 0.0 and (on_floor or _coyote_timer > 0.0):
		if _is_compressing:
			_end_compress(false)
		velocity.y = JUMP_VELOCITY
		_apply_bhop_soft_cap()
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_cut_ready = true
		jumped = true

	if _jump_cut_ready:
		if velocity.y <= 0.0:
			_jump_cut_ready = false
		elif not Input.is_action_pressed("space"):
			velocity.y *= JUMP_CUT
			_jump_cut_ready = false

	var shift_held := Input.is_action_pressed("compress")
	var shift_just := Input.is_action_just_pressed("compress")
	var tuck_just := Input.is_action_just_pressed("tuck")

	if shift_just and not _is_compressing and _launch_cooldown <= 0.0:
		_start_compress()
	if _is_compressing and not shift_held:
		_end_compress(true)
	if tuck_just and on_floor and not _is_compressing and not jumped:
		_tuck_timer = TUCK_DURATION
		_set_crouch_shape(true)
	if _tuck_timer > 0.0:
		_tuck_timer -= delta
		if _tuck_timer <= 0.0 and not _is_compressing:
			_set_crouch_shape(false)

	var input_dir := Input.get_vector("a", "d", "w", "s")
	var wish_dir := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	wish_dir.y = 0.0
	wish_dir = wish_dir.normalized() if wish_dir.length_squared() > 0.01 else Vector3.ZERO

	if not on_floor:
		if _is_compressing:
			_process_compress(delta, wish_dir, true)
		else:
			_process_air(delta, wish_dir)
	else:
		if jumped:
			pass
		elif _is_compressing:
			_process_compress(delta, wish_dir, false)
		else:
			_process_ground(delta, wish_dir)

	_clamp_horizontal()
	move_and_slide()

	var target_fov := _base_fov + (DASH_FOV_KICK if _dash_timer > 0.0 else 0.0)
	camera.fov = move_toward(camera.fov, target_fov, 400.0 * delta)

	if _is_compressing:
		_compress_time += delta


func _accelerate(vel: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	var current_speed := vel.dot(wish_dir)
	var add_speed := wish_speed - current_speed
	if add_speed <= 0.0:
		return vel
	var accel_speed := minf(accel * wish_speed * delta, add_speed)
	return vel + wish_dir * accel_speed


func _rotate_horizontal_toward(vel: Vector3, target_dir: Vector3, max_radians: float) -> Vector3:
	var hv := Vector3(vel.x, 0.0, vel.z)
	var hs := hv.length()
	if hs < 0.5 or target_dir.length_squared() < 0.01:
		return vel
	var cur_dir := hv / hs
	var ang := cur_dir.signed_angle_to(target_dir, Vector3.UP)
	var step := clampf(ang, -max_radians, max_radians)
	var new_dir := cur_dir.rotated(Vector3.UP, step)
	vel.x = new_dir.x * hs
	vel.z = new_dir.z * hs
	return vel


func _apply_bhop_soft_cap() -> void:
	if _dash_timer > 0.0:
		return
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var hs := hv.length()
	if hs <= BHOP_SOFT_CAP:
		return
	var new_hs := BHOP_SOFT_CAP + (hs - BHOP_SOFT_CAP) * BHOP_EXCESS_KEEP
	var r := new_hs / hs
	velocity.x *= r
	velocity.z *= r


func _process_ground(delta: float, wish_dir: Vector3) -> void:
	var h_vel := Vector3(velocity.x, 0.0, velocity.z)
	var speed := h_vel.length()
	if speed > 0.01:
		var f_mult := DASH_FRICTION_MULT if _dash_timer > 0.0 else 1.0
		var control := maxf(speed, STOP_SPEED)
		var drop := control * FRICTION * f_mult * delta
		var new_speed := maxf(speed - drop, 0.0)
		if new_speed < 0.01:
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			var ratio := new_speed / speed
			velocity.x *= ratio
			velocity.z *= ratio
	if wish_dir != Vector3.ZERO:
		velocity = _accelerate(velocity, wish_dir, SPEED, GROUND_ACCEL, delta)


func _process_air(delta: float, wish_dir: Vector3) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var accel := AIR_ACCEL
	if _dash_timer > 0.0:
		accel *= DASH_AIR_ACCEL_MULT
	velocity = _accelerate(velocity, wish_dir, SPEED, accel, delta)
	var hs := Vector3(velocity.x, 0.0, velocity.z).length()
	if hs > SPEED * 1.2:
		var rate := AIR_TURN_RATE
		if _dash_timer > 0.0:
			rate = maxf(rate, DASH_TURN_RATE)
		velocity = _rotate_horizontal_toward(velocity, wish_dir, rate * delta)


func _process_compress(delta: float, wish_dir: Vector3, airborne: bool) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var hs := hv.length()
	if hs > 0.05:
		var mult := COMPRESS_AIR_DECEL_MULT if airborne else 1.0
		var decel := minf(COMPRESS_DECEL * mult * delta, hs)
		velocity.x -= (hv.x / hs) * decel
		velocity.z -= (hv.z / hs) * decel
	if wish_dir != Vector3.ZERO:
		var steer := COMPRESS_AIR_STEER if airborne else COMPRESS_STEER
		var target_speed := SPEED * (0.9 if airborne else 0.7)
		velocity = _accelerate(velocity, wish_dir, target_speed, steer, delta)
		if airborne:
			var hs2 := Vector3(velocity.x, 0.0, velocity.z).length()
			if hs2 > SPEED * 1.2:
				velocity = _rotate_horizontal_toward(velocity, wish_dir, steer * 0.5 * delta)


func _clamp_horizontal() -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var hs := hv.length()
	if hs > MAX_SPEED:
		var r := MAX_SPEED / hs
		velocity.x *= r
		velocity.z *= r


func _start_compress() -> void:
	_is_compressing = true
	_compress_time = 0.0
	_set_crouch_shape(true)


func _end_compress(do_launch: bool) -> void:
	_is_compressing = false
	_set_crouch_shape(_tuck_timer > 0.0)
	if do_launch:
		var charge := _compute_charge(_compress_time)
		if charge > 0.0:
			var launch_dir := -transform.basis.z
			launch_dir.y = 0.0
			launch_dir = launch_dir.normalized()
			velocity.x += launch_dir.x * LAUNCH_IMPULSE * charge
			velocity.z += launch_dir.z * LAUNCH_IMPULSE * charge
			var up := LAUNCH_UP_POP * maxf(charge, 0.5)
			if velocity.y < up:
				velocity.y = up
			_jump_cut_ready = false
			_dash_timer = DASH_WINDOW
			_launch_cooldown = LAUNCH_COOLDOWN
			Shaker.play(0.18, 0.3, Tween.TRANS_EXPO)
	_compress_time = 0.0


func _compute_charge(t: float) -> float:
	if t < COMPRESS_WINDOW_MIN:
		return lerpf(LAUNCH_MIN_CHARGE, 0.4, t / COMPRESS_WINDOW_MIN)
	elif t <= COMPRESS_WINDOW_MAX:
		return lerpf(0.4, 1.0, (t - COMPRESS_WINDOW_MIN) / (COMPRESS_WINDOW_MAX - COMPRESS_WINDOW_MIN))
	elif t <= COMPRESS_OVERHOLD:
		return lerpf(1.0, LAUNCH_MIN_CHARGE, (t - COMPRESS_WINDOW_MAX) / (COMPRESS_OVERHOLD - COMPRESS_WINDOW_MAX))
	else:
		return LAUNCH_MIN_CHARGE


func _set_crouch_shape(crouched: bool) -> void:
	if not _col_ready:
		return
	var cap := _col.shape as CapsuleShape3D
	if crouched:
		cap.height = _col_orig_height * 0.5
		_col.position.y = _col_orig_center_y - _col_orig_height * 0.25
	else:
		cap.height = _col_orig_height
		_col.position.y = _col_orig_center_y


func take_damage(amount: float) -> void:
	_damage_accum += amount
	var whole := int(floor(_damage_accum))
	if whole <= 0:
		return
	_damage_accum -= whole
	health = maxi(health - whole, 0)
	_update_hp_bar()
	if health <= 0:
		_on_died()


func heal(amount: int) -> void:
	health = mini(health + amount, MAX_HEALTH)
	_update_hp_bar()


func _update_hp_bar() -> void:
	if not is_instance_valid(_hp_bar):
		return
	UIKit.hud_bar_animate(_hp_bar, float(health), 0.15)
	var ratio := float(health) / float(MAX_HEALTH)
	var color := UIKit.C_HP
	if ratio <= 0.25:
		color = UIKit.C_ACCENT
	elif ratio <= 0.5:
		color = UIKit.C_WARN
	UIKit.hud_bar_color(_hp_bar, color)
	if is_instance_valid(_hp_label):
		_hp_label.text = "%d/%d" % [health, MAX_HEALTH]


func _on_died() -> void:
	UIKit.hud_close()
	gameover.build("пососи")
