extends GameSystem
class_name EnemySystem

signal enemy_spawned(enemy: Enemy, enemy_type: String)
signal enemy_removed(enemy: Enemy)
signal alive_count_changed(count: int)

const ENEMY_SCENE_PATH := "res://scenes/enemy/enemy.tscn"
const ENEMY_Y_OFFSET := 0.22

@export var auto_spawn_count: int = 8
@export var spawn_interval_sec: float = 0.75
@export var enemy_move_speed: float = 2.8
@export var debug_enemy_movement: bool = false
@export var auto_start_spawning: bool = false
@export var enemy_max_hp: int = 100

var _grid_system: GridSystem
var _path_system: PathfindingSystem
var _enemy_scene: PackedScene
var _spawn_root: Node3D
var _spawn_timer: Timer
var _spawned_count: int = 0
var _alive_enemies: Dictionary = {}
var _base_hp_placeholder: int = 20
var _is_spawning: bool = false


func initialize(config: GameConfig) -> void:
	_grid_system = GameManager.grid_system as GridSystem
	_path_system = GameManager.pathfinding_system as PathfindingSystem
	if _grid_system == null or _path_system == null:
		push_error("EnemySystem: 缺少 GridSystem 或 PathfindingSystem")
		return

	_enemy_scene = load(ENEMY_SCENE_PATH) as PackedScene
	if _enemy_scene == null:
		push_error("EnemySystem: 无法加载 Enemy 场景: %s" % ENEMY_SCENE_PATH)
		return

	_spawn_root = Node3D.new()
	_spawn_root.name = "Enemies"
	if GameManager.battlefield_root == null:
		push_error("EnemySystem: battlefield_root 为空")
		return
	GameManager.battlefield_root.add_child(_spawn_root)

	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = false
	_spawn_timer.wait_time = maxf(0.1, spawn_interval_sec)
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)
	_path_system.path_updated.connect(_on_path_updated)
	if auto_start_spawning:
		start_spawning()

	if config.print_system_init:
		print(
			"EnemySystem: 就绪 auto_spawn=%d interval=%.2f speed=%.2f"
			% [auto_spawn_count, spawn_interval_sec, enemy_move_speed]
		)


func start_spawning() -> void:
	if _spawn_timer == null:
		return
	if _is_spawning:
		return
	_is_spawning = true
	_spawn_timer.start()
	print("EnemySystem: start_spawning")


func stop_spawning() -> void:
	if _spawn_timer == null:
		return
	_spawn_timer.stop()
	_is_spawning = false
	print("EnemySystem: stop_spawning")


func spawn_enemy_once() -> Enemy:
	return spawn_enemy_by_type("basic_enemy")


func spawn_enemy_by_type(enemy_type: String) -> Enemy:
	if _enemy_scene == null or _grid_system == null or _path_system == null:
		return null

	var path_cells := _path_system.get_enemy_path_cells()
	if path_cells.size() < 2:
		push_warning("EnemySystem: 当前路径无效，跳过生成")
		return null

	var tile_grid := _grid_system.get_tile_grid()
	if tile_grid == null:
		return null

	var path_points: Array[Vector3] = []
	for c in path_cells:
		var p := tile_grid.cell_center_global(c)
		p.y += ENEMY_Y_OFFSET
		path_points.append(p)

	var enemy_node := _enemy_scene.instantiate()
	if not (enemy_node is Enemy):
		push_error("EnemySystem: Enemy 场景根节点未挂 Enemy 脚本")
		return null

	var enemy := enemy_node as Enemy
	enemy.max_hp = enemy_max_hp
	_spawn_root.add_child(enemy)
	enemy.setup_path(path_points, enemy_move_speed, debug_enemy_movement)
	enemy.reached_goal.connect(_on_enemy_reached_goal)
	enemy.died.connect(_on_enemy_died)
	_alive_enemies[enemy.get_instance_id()] = enemy
	enemy_spawned.emit(enemy, enemy_type)
	alive_count_changed.emit(_alive_enemies.size())
	print(
		"EnemySpawn: type=%s id=%d count=%d path_len=%d"
		% [enemy_type, enemy.get_instance_id(), _alive_enemies.size(), path_cells.size()]
	)
	return enemy


func _on_spawn_timer_timeout() -> void:
	if _spawned_count >= auto_spawn_count:
		stop_spawning()
		return
	var spawned := spawn_enemy_once()
	if spawned != null:
		_spawned_count += 1


func _on_enemy_reached_goal(enemy: Enemy) -> void:
	var id := enemy.get_instance_id()
	_alive_enemies.erase(id)
	_path_system.clear_temp_enemy_path(id)
	enemy_removed.emit(enemy)
	alive_count_changed.emit(_alive_enemies.size())
	_base_hp_placeholder -= 1
	print(
		"BaseDamaged(Placeholder): enemy_id=%d base_hp=%d alive=%d"
		% [id, _base_hp_placeholder, _alive_enemies.size()]
	)
	enemy.queue_free()


func _on_enemy_died(enemy: Enemy) -> void:
	var id := enemy.get_instance_id()
	_alive_enemies.erase(id)
	_path_system.clear_temp_enemy_path(id)
	enemy_removed.emit(enemy)
	alive_count_changed.emit(_alive_enemies.size())
	_on_enemy_drop_placeholder(enemy.global_position)
	enemy.queue_free()
	print("EnemyDied: enemy_id=%d alive=%d" % [id, _alive_enemies.size()])


func _on_enemy_drop_placeholder(world_pos: Vector3) -> void:
	# 预留：后续接资源掉落系统
	print("DropPlaceholder: pos=", world_pos)


func get_alive_enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for v in _alive_enemies.values():
		if v is Enemy:
			var e := v as Enemy
			if is_instance_valid(e):
				out.append(e)
	return out


func get_alive_count() -> int:
	return _alive_enemies.size()


func _on_path_updated(_path_cells: Array[Vector2i]) -> void:
	_retarget_alive_enemies_to_latest_path()


func _retarget_alive_enemies_to_latest_path() -> void:
	if _grid_system == null or _path_system == null:
		return
	var tile_grid := _grid_system.get_tile_grid()
	if tile_grid == null:
		return

	var alive := get_alive_enemies()
	if alive.is_empty():
		_path_system.clear_all_temp_enemy_paths()
		return

	for enemy in alive:
		var temp_cells: Array[Vector2i] = []
		var points := _build_enemy_remaining_points(enemy, tile_grid, temp_cells)
		if points.size() >= 2:
			enemy.retarget_path(points)
		var enemy_id := enemy.get_instance_id()
		if temp_cells.is_empty():
			_path_system.clear_temp_enemy_path(enemy_id)
		else:
			_path_system.set_temp_enemy_path(enemy_id, temp_cells)
	if debug_enemy_movement:
		print("EnemySystem: 路径更新，已重定向敌人数量=%d" % alive.size())


func _build_enemy_remaining_points(enemy: Enemy, tile_grid: TileGrid, out_temp_cells: Array[Vector2i]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var world_pos := enemy.global_position
	var start_cell := tile_grid.world_to_cell(world_pos)
	var path_cells: Array[Vector2i] = []
	var full_main_path := _path_system.get_enemy_path_cells()

	if start_cell.x >= 0:
		# 优先策略：先尝试连回主路径；只有连不到主路径时，才直连终点
		var via_main := _build_temp_path_via_main_anchor(start_cell, full_main_path)
		if via_main.size() >= 2:
			path_cells = via_main
			out_temp_cells.append_array(via_main)
		else:
			var direct := _path_system.find_path_from_cell_to_goal(start_cell)
			if direct.found and direct.cells.size() >= 2:
				path_cells = direct.cells.duplicate()
				out_temp_cells.append_array(path_cells)
			else:
				var allow_start := _path_system.find_path_from_cell_to_goal_allow_start_blocked(start_cell)
				if allow_start.found and allow_start.cells.size() >= 2:
					path_cells = allow_start.cells.duplicate()
					out_temp_cells.append_array(path_cells)
	else:
		path_cells = full_main_path

	if path_cells.is_empty():
		# 敌人与新主路径完全断开时，保留其“个人临时剩余路径”，避免走非路径地块
		return enemy.get_remaining_path_points()

	if not full_main_path.is_empty():
		var goal_outer: Vector2i = full_main_path.back()
		if path_cells.back() != goal_outer:
			path_cells.append(goal_outer)

	var current := world_pos
	current.y += ENEMY_Y_OFFSET
	out.append(current)
	for c in path_cells:
		var p := tile_grid.cell_center_global(c)
		p.y += ENEMY_Y_OFFSET
		out.append(p)
	return out


func _build_temp_path_via_main_anchor(start_cell: Vector2i, full_main_path: Array[Vector2i]) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_len := 1_000_000_000
	if full_main_path.size() < 2:
		return best

	var last_inner_idx := full_main_path.size() - 2
	for i in range(1, last_inner_idx + 1):
		var anchor := full_main_path[i]
		var to_anchor := _path_system.find_path_cells(start_cell, anchor)
		if not to_anchor.found:
			to_anchor = _path_system.find_path_cells_allow_start_blocked(start_cell, anchor)
		if not to_anchor.found:
			continue
		if to_anchor.cells.size() < 2:
			continue

		var candidate: Array[Vector2i] = to_anchor.cells.duplicate()
		for j in range(i + 1, last_inner_idx + 1):
			candidate.append(full_main_path[j])
		if candidate.size() < best_len:
			best_len = candidate.size()
			best = candidate
	return best
