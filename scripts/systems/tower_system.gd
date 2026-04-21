extends GameSystem
class_name TowerSystem

const FREE_WALL_SCENE_PATH := "res://scenes/placement/free_wall.tscn"
const BASIC_ATTACK_TOWER_SCENE_PATH := "res://scenes/tower/basic_attack_tower.tscn"
const TYPE_WALL := "free_wall"
const TYPE_BASIC_ATTACK_TOWER := "basic_attack_tower"
const WALL_DEPLOY_TIME_SEC := 1.0

var _grid_system: GridSystem
var _path_system: PathfindingSystem
var _enemy_system: EnemySystem
var _wave_system: WaveSystem
var _grid: TileGrid
var _battle_camera: Camera3D
var _place_root: Node3D
var _free_wall_scene: PackedScene
var _basic_attack_tower_scene: PackedScene
## Vector2i -> { "type": String, "node": Node3D, "committed": bool, "deploying": bool, "timer": Timer }
var _placed_cells: Dictionary = {}
var _dragging_type: String = ""
var _ghost_node: Node3D
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _scene_by_type: Dictionary = {}


func initialize(config: GameConfig) -> void:
	_grid_system = GameManager.grid_system as GridSystem
	_path_system = GameManager.pathfinding_system as PathfindingSystem
	_enemy_system = GameManager.enemy_system as EnemySystem
	_wave_system = GameManager.wave_system as WaveSystem
	if _grid_system == null or _path_system == null or _enemy_system == null:
		push_error("TowerSystem: 缺少 GridSystem / PathfindingSystem / EnemySystem")
		return

	_grid = _grid_system.get_tile_grid()
	if _grid == null:
		push_error("TowerSystem: TileGrid 为空")
		return

	_free_wall_scene = load(FREE_WALL_SCENE_PATH) as PackedScene
	_basic_attack_tower_scene = load(BASIC_ATTACK_TOWER_SCENE_PATH) as PackedScene
	if _free_wall_scene == null or _basic_attack_tower_scene == null:
		push_error("TowerSystem: 无法加载放置场景")
		return
	_scene_by_type[TYPE_WALL] = _free_wall_scene
	_scene_by_type[TYPE_BASIC_ATTACK_TOWER] = _basic_attack_tower_scene

	_place_root = Node3D.new()
	_place_root.name = "Placements"
	if GameManager.battlefield_root == null:
		push_error("TowerSystem: battlefield_root 为空")
		return
	GameManager.battlefield_root.add_child(_place_root)

	if GameManager.world_root:
		_battle_camera = GameManager.world_root.get_node_or_null("CameraRig/Camera3D") as Camera3D
	set_process_input(true)

	if config.print_system_init:
		print("TowerSystem: 放置系统就绪（卡片拖拽放置）")


func _input(event: InputEvent) -> void:
	if _dragging_type.is_empty():
		return
	if event is InputEventMouseMotion:
		_update_drag_preview()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_try_place_dragged()
			end_drag()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			end_drag()


func begin_drag(placement_type: String) -> void:
	if not _scene_by_type.has(placement_type):
		return
	_dragging_type = placement_type
	_create_ghost_for_type(placement_type)
	_update_drag_preview()


func end_drag() -> void:
	_dragging_type = ""
	_hover_cell = Vector2i(-1, -1)
	if _ghost_node and is_instance_valid(_ghost_node):
		_ghost_node.queue_free()
	_ghost_node = null


func can_place_blocker(coord: Vector2i) -> bool:
	if _grid == null:
		return false
	if not _grid.is_valid_coord(coord):
		return false
	if _placed_cells.has(coord):
		return false
	# 先模拟：不能堵死路径
	return _path_system.can_block_cell(coord)


func place_blocker(coord: Vector2i, blocker_type: String, scene: PackedScene) -> bool:
	if scene == null:
		return false
	if not can_place_blocker(coord):
		print("PlaceReject: coord=%s reason=invalid_or_blocks_path" % coord)
		return false

	var inst := scene.instantiate()
	if not (inst is Node3D):
		push_warning("TowerSystem: blocker 场景根节点非 Node3D")
		return false

	var node := inst as Node3D
	_place_root.add_child(node)
	var pos := _grid.cell_center_local(coord)
	pos.y += 0.18
	node.position = pos

	var deploy_time := _resolve_deploy_time_sec(blocker_type, node)
	if _should_use_deploy_time() and deploy_time > 0.0:
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = deploy_time
		timer.timeout.connect(_on_deploy_timer_timeout.bind(coord))
		add_child(timer)
		timer.start()
		_placed_cells[coord] = {
			"type": blocker_type,
			"node": node,
			"committed": false,
			"deploying": true,
			"timer": timer
		}
		print("PlaceDeployStart: coord=%s type=%s deploy=%.2fs" % [coord, blocker_type, deploy_time])
		return true

	var committed := _commit_placement(coord, blocker_type, node)
	if not committed:
		node.queue_free()
		print("PlaceRollback: coord=%s reason=path_invalid_after_commit" % coord)
		return false
	return true


func remove_placement(coord: Vector2i) -> bool:
	if not _placed_cells.has(coord):
		return false

	var info: Dictionary = _placed_cells[coord] as Dictionary
	var node: Node3D = info.get("node", null) as Node3D
	var timer: Timer = info.get("timer", null) as Timer
	var committed := bool(info.get("committed", false))
	if timer and is_instance_valid(timer):
		timer.stop()
		timer.queue_free()
	if node and is_instance_valid(node):
		node.queue_free()
	_placed_cells.erase(coord)
	if committed:
		_path_system.set_cell_blocked(coord, false)
	print("RemoveOk: coord=%s" % coord)
	return true


func place_free_wall(coord: Vector2i) -> bool:
	return place_blocker(coord, TYPE_WALL, _free_wall_scene)


func place_basic_attack_tower(coord: Vector2i) -> bool:
	return place_blocker(coord, TYPE_BASIC_ATTACK_TOWER, _basic_attack_tower_scene)


func _mouse_cell() -> Vector2i:
	var cam: Camera3D = _battle_camera
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d()
	if cam == null or _grid == null:
		return Vector2i(-1, -1)

	var screen := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var hit := _ray_to_horizontal_plane(origin, dir, _grid.picking_plane_y_global())
	if is_nan(hit.x):
		return Vector2i(-1, -1)
	return _grid.world_to_cell(hit)


static func _ray_to_horizontal_plane(origin: Vector3, dir: Vector3, plane_y: float) -> Vector3:
	if absf(dir.y) < 1e-6:
		return Vector3(NAN, NAN, NAN)
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0:
		return Vector3(NAN, NAN, NAN)
	return origin + dir * t


func _create_ghost_for_type(placement_type: String) -> void:
	if _ghost_node and is_instance_valid(_ghost_node):
		_ghost_node.queue_free()
	var ps := _scene_by_type.get(placement_type, null) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate()
	if not (inst is Node3D):
		return
	_ghost_node = inst as Node3D
	_set_ghost_style_recursive(_ghost_node)
	_place_root.add_child(_ghost_node)


func _set_ghost_style_recursive(n: Node) -> void:
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.7, 0.9)
		mat.emission_energy_multiplier = 0.8
		mat.no_depth_test = true
		m.material_override = mat
	for c in n.get_children():
		_set_ghost_style_recursive(c)


func _update_drag_preview() -> void:
	if _ghost_node == null or _grid == null:
		return
	var cell := _mouse_cell()
	_hover_cell = cell
	if cell.x < 0:
		_ghost_node.visible = false
		return
	_ghost_node.visible = true
	var pos := _grid.cell_center_local(cell)
	pos.y += 0.18
	_ghost_node.position = pos


func _try_place_dragged() -> void:
	if _hover_cell.x < 0:
		return
	if _dragging_type == TYPE_WALL:
		place_free_wall(_hover_cell)
	elif _dragging_type == TYPE_BASIC_ATTACK_TOWER:
		place_basic_attack_tower(_hover_cell)


func _on_deploy_timer_timeout(coord: Vector2i) -> void:
	if not _placed_cells.has(coord):
		return
	var info: Dictionary = _placed_cells[coord] as Dictionary
	var node: Node3D = info.get("node", null) as Node3D
	var blocker_type := String(info.get("type", ""))
	if node == null or not is_instance_valid(node):
		_placed_cells.erase(coord)
		return

	var committed := _commit_placement(coord, blocker_type, node)
	if not committed:
		node.queue_free()
		_placed_cells.erase(coord)
		print("PlaceRollback: coord=%s reason=path_invalid_after_deploy" % coord)
		return

	var timer: Timer = info.get("timer", null) as Timer
	if timer and is_instance_valid(timer):
		timer.queue_free()


func _commit_placement(coord: Vector2i, blocker_type: String, node: Node3D) -> bool:
	var committed := _path_system.set_cell_blocked(coord, true)
	if not committed:
		return false

	_placed_cells[coord] = {
		"type": blocker_type,
		"node": node,
		"committed": true,
		"deploying": false,
		"timer": null
	}
	if node.has_method("setup"):
		node.call("setup", coord, _grid, _enemy_system)
	print("PlaceOk: coord=%s type=%s" % [coord, blocker_type])
	return true


func _should_use_deploy_time() -> bool:
	if _wave_system == null:
		return false
	return _wave_system.is_battle_phase_active()


func _resolve_deploy_time_sec(blocker_type: String, node: Node3D) -> float:
	if blocker_type == TYPE_WALL:
		return WALL_DEPLOY_TIME_SEC
	if node is Tower:
		return maxf(0.0, (node as Tower).deploy_time_sec)
	return 0.0
