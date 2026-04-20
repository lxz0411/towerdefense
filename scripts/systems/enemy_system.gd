extends GameSystem
class_name EnemySystem

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
	print("EnemySpawn: id=%d count=%d path_len=%d" % [enemy.get_instance_id(), _alive_enemies.size(), path_cells.size()])
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
	_base_hp_placeholder -= 1
	print(
		"BaseDamaged(Placeholder): enemy_id=%d base_hp=%d alive=%d"
		% [id, _base_hp_placeholder, _alive_enemies.size()]
	)
	enemy.queue_free()


func _on_enemy_died(enemy: Enemy) -> void:
	var id := enemy.get_instance_id()
	_alive_enemies.erase(id)
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
