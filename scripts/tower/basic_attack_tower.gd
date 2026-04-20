extends Tower
class_name BasicAttackTower

const BULLET_SCENE_PATH := "res://scenes/tower/basic_attack_bullet.tscn"

var _bullet_scene: PackedScene


func _configure_range() -> void:
	# 周围一圈 8 格（Chebyshev 距离=1，不含中心）
	_range_offsets.clear()
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var off := Vector2i(dx, dz)
			if off == Vector2i.ZERO:
				continue
			_range_offsets.append(off)


func _ready() -> void:
	_bullet_scene = load(BULLET_SCENE_PATH) as PackedScene


func _on_attack_tick() -> void:
	var target := find_target()
	if target == null:
		return
	_fire_bullet(target)
	if debug_attack_log:
		print(
			"BasicAttackTower: fire target=%d dmg=%d"
			% [target.get_instance_id(), attack_power]
		)


func _fire_bullet(target: Enemy) -> void:
	if _bullet_scene == null:
		# 兜底：若子弹场景丢失，回退瞬时命中
		target.take_damage(attack_power)
		return

	var n := _bullet_scene.instantiate()
	if not (n is Node3D):
		target.take_damage(attack_power)
		return

	var b := n as Node3D
	get_tree().current_scene.add_child(b)
	b.global_position = global_position + Vector3(0, 0.32, 0)
	if b.has_method("setup"):
		b.call("setup", target, attack_power)
