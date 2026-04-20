extends Node3D
class_name BasicAttackBullet

@export var speed: float = 24.0
@export var hit_distance: float = 0.14
@export var max_life_sec: float = 1.8

var _target: Node3D
var _damage: int = 1
var _life: float = 0.0


func setup(target: Node3D, damage: int) -> void:
	_target = target
	_damage = max(1, damage)


func _process(delta: float) -> void:
	_life += delta
	if _life >= max_life_sec:
		queue_free()
		return
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return

	var target_pos := _target.global_position + Vector3(0, 0.22, 0)
	var to_target := target_pos - global_position
	var dist := to_target.length()
	if dist <= hit_distance:
		if _target.has_method("take_damage"):
			_target.call("take_damage", _damage)
		queue_free()
		return

	var step := speed * delta
	if step >= dist:
		global_position = target_pos
	else:
		global_position += to_target.normalized() * step
