extends Node3D
class_name Enemy

signal reached_goal(enemy: Enemy)
signal died(enemy: Enemy)

@export var move_speed: float = 2.8
@export var waypoint_reach_distance: float = 0.06
@export var debug_log: bool = false
@export var debug_log_interval: float = 0.6
@export var max_hp: int = 5

var _path_points: Array[Vector3] = []
var _path_index: int = 1
var _fixed_y: float = 0.0
var _arrived: bool = false
var _dead: bool = false
var _debug_accum: float = 0.0
var _hp: int = 1


func setup_path(points: Array[Vector3], speed: float, debug_enabled: bool) -> void:
	_path_points = points.duplicate()
	move_speed = speed
	debug_log = debug_enabled
	_arrived = false
	_dead = false
	_debug_accum = 0.0
	_hp = max_hp

	if _path_points.is_empty():
		return

	_fixed_y = _path_points[0].y
	global_position = _path_points[0]
	_path_index = 1


func _process(delta: float) -> void:
	if _arrived or _dead or _path_points.is_empty():
		return

	if _path_index >= _path_points.size():
		_arrive_goal()
		return

	var target := _path_points[_path_index]
	target.y = _fixed_y
	var pos := global_position
	pos.y = _fixed_y
	var to_target := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var dist := to_target.length()

	if dist <= waypoint_reach_distance:
		_path_index += 1
		return

	var step := move_speed * delta
	if step >= dist:
		pos = Vector3(target.x, _fixed_y, target.z)
	else:
		pos += to_target.normalized() * step
		pos.y = _fixed_y
	global_position = pos

	if debug_log:
		_debug_accum += delta
		if _debug_accum >= debug_log_interval:
			_debug_accum = 0.0
			print("EnemyMove: pos=", global_position, " next_wp=", _path_index)


func _arrive_goal() -> void:
	if _arrived or _dead:
		return
	_arrived = true
	set_process(false)
	reached_goal.emit(self)


func take_damage(amount: int) -> void:
	if _dead or _arrived:
		return
	_hp -= max(0, amount)
	if _hp <= 0:
		_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	set_process(false)
	died.emit(self)
