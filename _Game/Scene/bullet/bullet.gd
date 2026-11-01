extends Area3D

@export var speed: float = 60.0
@export var lifetime: float = 2.0
@export var damage: float = 1.0
@export var hit_margin: float = 0.2
@export_flags_3d_physics var hit_mask: int = 0xFFFFFFFF

@export_group("Падение урона")
@export var falloff_start: float = 20.0
@export var falloff_end: float = 45.0
@export var falloff_min_multiplier: float = 0.5

var _origin: Vector3 = Vector3.ZERO
var _target_point := Vector3.ZERO
var _target_collider: Object = null
var _has_target := false
var _exclude: Array[RID] = []
var _done := false


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
	if player:
		_exclude.append(player.get_rid())
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func set_origin(origin: Vector3) -> void:
	_origin = origin


func set_target(point: Vector3, collider: Object) -> void:
	_target_point = point
	_target_collider = collider
	_has_target = collider != null


func _physics_process(delta: float) -> void:
	if _done:
		return

	var dir := -global_transform.basis.z
	var step := speed * delta
	var from := global_position
	var to := from + dir * (step + hit_margin)

	var q := PhysicsRayQueryParameters3D.create(from, to, hit_mask, _exclude)
	q.collide_with_areas = true
	q.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		_on_hit(hit.collider)
		return

	if _has_target and from.distance_to(_target_point) <= step:
		global_position = _target_point
		if is_instance_valid(_target_collider):
			_on_hit(_target_collider)
		else:
			_finish()
		return

	global_position = from + dir * step


func _on_hit(collider: Object) -> void:
	var target := collider
	if not target.has_method("take_damage") and target is Node:
		var parent := (target as Node).get_parent()
		if parent and parent.has_method("take_damage"):
			target = parent
	if target.has_method("take_damage"):
		var dist: float = _origin.distance_to(global_position)
		target.take_damage(damage * _damage_multiplier(dist))
	_finish()


func _damage_multiplier(dist: float) -> float:
	if dist <= falloff_start:
		return 1.0
	if dist >= falloff_end:
		return falloff_min_multiplier
	var t: float = (dist - falloff_start) / (falloff_end - falloff_start)
	return lerpf(1.0, falloff_min_multiplier, t)


func _finish() -> void:
	_done = true
	queue_free()
