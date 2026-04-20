extends Node3D
class_name Tower

@export var attack_interval: float = 0.8
@export var attack_power: int = 1
@export var debug_attack_log: bool = false
@export var show_range_debug: bool = false

var _coord: Vector2i = Vector2i.ZERO
var _grid: TileGrid
var _enemy_system: EnemySystem
var _cooldown: float = 0.0
var _range_offsets: Array[Vector2i] = []
var _range_debug_root: Node3D


func setup(coord: Vector2i, grid: TileGrid, enemy_system: EnemySystem) -> void:
	_coord = coord
	_grid = grid
	_enemy_system = enemy_system
	_cooldown = randf() * attack_interval
	_configure_range()
	if show_range_debug:
		_build_range_debug()


func _configure_range() -> void:
	# 子类覆盖
	_range_offsets = []


func _process(delta: float) -> void:
	if _enemy_system == null or _grid == null:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = attack_interval
	_on_attack_tick()


func _on_attack_tick() -> void:
	# 子类覆盖：基类不绑定具体攻击方式（可弹道/激光/范围/持续伤害等）
	pass


func find_target() -> Enemy:
	var enemies := _enemy_system.get_alive_enemies()
	for e in enemies:
		if e == null:
			continue
		var c := _grid.world_to_cell(e.global_position)
		if c.x < 0:
			continue
		var offset := c - _coord
		if _in_range(offset):
			return e
	return null


func _in_range(offset: Vector2i) -> bool:
	for r in _range_offsets:
		if r == offset:
			return true
	return false


func _build_range_debug() -> void:
	if _grid == null:
		return
	if _range_debug_root and is_instance_valid(_range_debug_root):
		_range_debug_root.queue_free()
	_range_debug_root = Node3D.new()
	_range_debug_root.name = "RangeDebug"
	add_child(_range_debug_root)

	var step := _grid.get_cell_step()
	var box := BoxMesh.new()
	box.size = Vector3(step * 0.38, 0.03, step * 0.38)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.42, 0.18, 0.38)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.25, 0.1)
	mat.emission_energy_multiplier = 0.8
	mat.no_depth_test = true

	for off in _range_offsets:
		var m := MeshInstance3D.new()
		m.mesh = box
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position = Vector3(off.x * step, 0.04, off.y * step)
		_range_debug_root.add_child(m)
