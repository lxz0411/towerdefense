extends GameSystem
class_name PathfindingSystem

signal path_updated(path_cells: Array[Vector2i])

const KEY_STRAIGHT_LR := "straight_lr"
const KEY_STRAIGHT_UD := "straight_ud"
const KEY_CORNER_RU := "corner_ru"
const KEY_CORNER_UL := "corner_ul"
const KEY_CORNER_LD := "corner_ld"
const KEY_CORNER_DR := "corner_dr"
const KEY_TEE_LRU := "tee_lru"
const KEY_TEE_RUD := "tee_rud"
const KEY_TEE_LUD := "tee_lud"
const KEY_TEE_LRD := "tee_lrd"
const KEY_CROSS := "cross"
const KEY_END_R := "goal_r"
const KEY_END_U := "goal_u"
const KEY_END_L := "goal_l"
const KEY_END_D := "goal_d"
const KEY_SPAWN_R := "spawn_r"
const KEY_SPAWN_U := "spawn_u"
const KEY_SPAWN_L := "spawn_l"
const KEY_SPAWN_D := "spawn_d"
const KEY_GOAL_R := "goal_r"
const KEY_GOAL_U := "goal_u"
const KEY_GOAL_L := "goal_l"
const KEY_GOAL_D := "goal_d"

const DIR_RIGHT := Vector2i(1, 0)
const DIR_UP := Vector2i(0, -1)
const DIR_LEFT := Vector2i(-1, 0)
const DIR_DOWN := Vector2i(0, 1)

const BIT_U := 1
const BIT_R := 2
const BIT_D := 4
const BIT_L := 8
const MAX_FLOW_TRACE_STEPS := 4096

var _grid_system: GridSystem
var _grid: TileGrid
var _map_cfg: GridMapConfig
var _tile_map_cfg: Resource
var _pathfinder: GridPathfinder = GridPathfinder.new()

var _entry_cell: Vector2i = Vector2i.ZERO
var _goal_cell: Vector2i = Vector2i.ZERO
var _spawn_outer_cell: Vector2i = Vector2i.ZERO
var _goal_outer_cell: Vector2i = Vector2i.ZERO
var _path_result: GridPathResult = GridPathResult.new()
## 当前由路径系统替换过的路径格（不含入口与终点）
var _painted_path_cells: Dictionary = {}
## Vector2i -> int 距离（到终点）
var _distance_by_cell: Dictionary = {}
## Vector2i -> Vector2i 下一步流向
var _flow_next_by_cell: Dictionary = {}
## enemy_id(int) -> Array[Vector2i]，个体临时路径（仅网格内）
var _temp_enemy_paths: Dictionary = {}


func initialize(config: GameConfig) -> void:
	_grid_system = GameManager.grid_system as GridSystem
	if _grid_system == null:
		push_error("PathfindingSystem: GridSystem 不可用")
		return

	_grid = _grid_system.get_tile_grid()
	_map_cfg = _grid_system.get_map_config()
	var loaded_tile_cfg := load(config.path_tile_mapping_config_path)
	if loaded_tile_cfg != null and loaded_tile_cfg.has_method("get_scene_path"):
		_tile_map_cfg = loaded_tile_cfg as Resource
	if _grid == null or _map_cfg == null or _tile_map_cfg == null:
		push_error("PathfindingSystem: 网格数据缺失")
		return

	var mid_z := floori(_map_cfg.cells_z / 2.0)
	_entry_cell = Vector2i(0, mid_z)
	_goal_cell = Vector2i(_map_cfg.cells_x - 1, mid_z)
	_spawn_outer_cell = Vector2i(-1, mid_z)
	_goal_outer_cell = Vector2i(_map_cfg.cells_x, mid_z)
	_update_spawn_goal_markers()
	_pathfinder.setup(_map_cfg.cells_x, _map_cfg.cells_z)
	_recalculate_navigation_field()
	_rebuild_main_path_from_flow()
	_apply_path_tiles()

	if config.print_system_init:
		print(
			"PathfindingSystem: FlowField 就绪 entry=%s goal=%s found=%s len=%d"
			% [_entry_cell, _goal_cell, _path_result.found, _path_result.length()]
		)


func get_entry_cell() -> Vector2i:
	return _entry_cell


func get_goal_cell() -> Vector2i:
	return _goal_cell


func get_path_result() -> GridPathResult:
	return _path_result


func get_current_path_cells() -> Array[Vector2i]:
	return _path_result.cells.duplicate()


func get_enemy_path_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _path_result.cells.is_empty():
		return out
	out.append(_spawn_outer_cell)
	out.append_array(_path_result.cells)
	out.append(_goal_outer_cell)
	return out


func set_entry_and_goal(entry_cell: Vector2i, goal_cell: Vector2i) -> bool:
	if not _pathfinder.is_valid_coord(entry_cell) or not _pathfinder.is_valid_coord(goal_cell):
		return false
	if _pathfinder.is_blocked(entry_cell) or _pathfinder.is_blocked(goal_cell):
		return false
	_entry_cell = entry_cell
	_goal_cell = goal_cell
	_update_spawn_goal_markers()
	_recalculate_navigation_field()
	_rebuild_main_path_from_flow()
	_apply_path_tiles()
	_emit_path_updated()
	return _path_result.found


func is_cell_blocked(coord: Vector2i) -> bool:
	return _pathfinder.is_blocked(coord)


func set_cell_blocked(coord: Vector2i, blocked: bool) -> bool:
	if not _pathfinder.is_valid_coord(coord):
		return false
	if coord == _entry_cell or coord == _goal_cell:
		return false

	_pathfinder.set_blocked(coord, blocked)
	_recalculate_navigation_field()
	_rebuild_main_path_from_flow()
	_apply_path_tiles()
	_emit_path_updated()
	return _path_result.found


func can_block_cell(coord: Vector2i) -> bool:
	if not _pathfinder.is_valid_coord(coord):
		return false
	if coord == _entry_cell or coord == _goal_cell:
		return false
	if _pathfinder.is_blocked(coord):
		return true

	_pathfinder.set_blocked(coord, true)
	_recalculate_navigation_field()
	var reachable := _is_reachable(_entry_cell)
	_pathfinder.set_blocked(coord, false)
	_recalculate_navigation_field()
	return reachable


func force_recalculate_path() -> GridPathResult:
	_recalculate_navigation_field()
	_rebuild_main_path_from_flow()
	_apply_path_tiles()
	_emit_path_updated()
	return _path_result


func find_path_cells(start_cell: Vector2i, goal_cell: Vector2i) -> GridPathResult:
	return _pathfinder.find_path(start_cell, goal_cell)


func find_path_cells_allow_start_blocked(start_cell: Vector2i, goal_cell: Vector2i) -> GridPathResult:
	return _pathfinder.find_path_allow_start_blocked(start_cell, goal_cell)


func find_path_from_cell_to_goal(start_cell: Vector2i) -> GridPathResult:
	if _is_reachable(start_cell):
		return _trace_flow_path_to_goal(start_cell)
	return _pathfinder.find_path(start_cell, _goal_cell)


func find_path_from_cell_to_goal_allow_start_blocked(start_cell: Vector2i) -> GridPathResult:
	if _is_reachable(start_cell):
		return _trace_flow_path_to_goal(start_cell)
	return _pathfinder.find_path_allow_start_blocked(start_cell, _goal_cell)


func _recalculate_navigation_field() -> void:
	_distance_by_cell.clear()
	_flow_next_by_cell.clear()
	if not _pathfinder.is_walkable(_goal_cell):
		return

	var queue: Array[Vector2i] = [_goal_cell]
	_distance_by_cell[_goal_cell] = 0
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		var cur_dist := int(_distance_by_cell.get(cur, 0))
		for d in _flow_neighbor_priority():
			var prev := cur + d
			if not _pathfinder.is_walkable(prev):
				continue
			if _distance_by_cell.has(prev):
				continue
			_distance_by_cell[prev] = cur_dist + 1
			queue.append(prev)

	for key in _distance_by_cell.keys():
		var cell: Vector2i = key
		if cell == _goal_cell:
			continue
		var best_next := _pick_next_cell_by_flow(cell)
		if best_next != cell:
			_flow_next_by_cell[cell] = best_next


func _rebuild_main_path_from_flow() -> void:
	_path_result = _trace_flow_path_to_goal(_entry_cell)


func _update_spawn_goal_markers() -> void:
	if _grid_system == null:
		return
	# 出生点朝向：外侧 -> 内侧入口
	var spawn_dir := _entry_cell - _spawn_outer_cell
	# 终点朝向：外侧 -> 内侧终点（开口朝向地图内部）
	var goal_dir := _goal_cell - _goal_outer_cell
	var spawn_key := _spawn_scene_for_dir(spawn_dir)
	var goal_key := _goal_scene_for_dir(goal_dir)
	var spawn_scene := _scene_path_for_key(spawn_key)
	var goal_scene := _scene_path_for_key(goal_key)
	if spawn_scene.is_empty():
		spawn_scene = "res://Assets/SceneModels/Map/tile-spawn-end.glb"
	if goal_scene.is_empty():
		goal_scene = "res://Assets/SceneModels/Map/tile-end.glb"
	_grid_system.set_spawn_goal_markers(_spawn_outer_cell, _goal_outer_cell, spawn_scene, goal_scene)


func _apply_path_tiles() -> void:
	_restore_painted_path_tiles()
	var display_paths := _build_display_paths_for_render()
	if display_paths.is_empty():
		return
	var mask_by_cell := _build_mask_by_cell(display_paths)
	for key in mask_by_cell.keys():
		var cell: Vector2i = key
		var mask := int(mask_by_cell[key])
		var scene_key := _scene_key_for_mask(mask)
		if scene_key.is_empty():
			continue
		var scene_path := _scene_path_for_key(scene_key)
		if scene_path.is_empty():
			push_warning("PathfindingSystem: 路径地块 key 未配置: %s mask=%d cell=%s" % [scene_key, mask, cell])
			continue
		var ok := _grid_system.replace_tile_scene_at_cell(cell, scene_path, 0.0)
		if ok:
			_painted_path_cells[cell] = true


func _restore_painted_path_tiles() -> void:
	for key in _painted_path_cells.keys():
		var coord: Vector2i = key
		_grid_system.restore_default_tile_at_cell(coord)
	_painted_path_cells.clear()


static func _is_turn(in_dir: Vector2i, out_dir: Vector2i) -> bool:
	# 中间格若两侧方向相反（例如 LEFT 与 RIGHT）则是直线；
	# 只有互相垂直时才是转角。
	return in_dir != -out_dir


static func _straight_scene_for_dir(path_dir: Vector2i) -> String:
	if path_dir.x != 0:
		return KEY_STRAIGHT_LR
	return KEY_STRAIGHT_UD


static func _corner_scene_for_dirs(in_dir: Vector2i, out_dir: Vector2i) -> String:
	# 资源后缀语义（实测）：
	# R=-X(DIR_LEFT), L=+X(DIR_RIGHT), D=-Z(DIR_UP), U=+Z(DIR_DOWN)
	if _has_pair(in_dir, out_dir, DIR_LEFT, DIR_DOWN):
		return KEY_CORNER_RU
	if _has_pair(in_dir, out_dir, DIR_DOWN, DIR_RIGHT):
		return KEY_CORNER_UL
	if _has_pair(in_dir, out_dir, DIR_RIGHT, DIR_UP):
		return KEY_CORNER_LD
	if _has_pair(in_dir, out_dir, DIR_UP, DIR_LEFT):
		return KEY_CORNER_DR
	push_warning("PathfindingSystem: 未识别转角方向 in=%s out=%s，回退 DR" % [in_dir, out_dir])
	return KEY_CORNER_DR


static func _spawn_scene_for_dir(dir: Vector2i) -> String:
	if dir == DIR_LEFT:
		return KEY_SPAWN_R
	if dir == DIR_DOWN:
		return KEY_SPAWN_U
	if dir == DIR_RIGHT:
		return KEY_SPAWN_L
	return KEY_SPAWN_D # DIR_UP


static func _goal_scene_for_dir(dir: Vector2i) -> String:
	if dir == DIR_LEFT:
		return KEY_GOAL_R
	if dir == DIR_DOWN:
		return KEY_GOAL_U
	if dir == DIR_RIGHT:
		return KEY_GOAL_L
	return KEY_GOAL_D # DIR_UP


static func _has_pair(a: Vector2i, b: Vector2i, p: Vector2i, q: Vector2i) -> bool:
	return (a == p and b == q) or (a == q and b == p)


func _scene_path_for_key(key: String) -> String:
	if _tile_map_cfg == null:
		return ""
	return _tile_map_cfg.get_scene_path(key)


func _emit_path_updated() -> void:
	path_updated.emit(_path_result.cells.duplicate())


func set_temp_enemy_path(enemy_id: int, raw_cells: Array[Vector2i]) -> void:
	var cells := _sanitize_grid_cells(raw_cells)
	if cells.size() < 2:
		clear_temp_enemy_path(enemy_id)
		return
	_temp_enemy_paths[enemy_id] = cells
	_apply_path_tiles()


func clear_temp_enemy_path(enemy_id: int) -> void:
	if not _temp_enemy_paths.has(enemy_id):
		return
	_temp_enemy_paths.erase(enemy_id)
	_apply_path_tiles()


func clear_all_temp_enemy_paths() -> void:
	if _temp_enemy_paths.is_empty():
		return
	_temp_enemy_paths.clear()
	_apply_path_tiles()


func _sanitize_grid_cells(raw_cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in raw_cells:
		if _pathfinder.is_valid_coord(c):
			if out.is_empty():
				out.append(c)
				continue
			var last: Vector2i = out[out.size() - 1]
			if last != c:
				out.append(c)
	return out


func _is_reachable(cell: Vector2i) -> bool:
	return _distance_by_cell.has(cell)


func _trace_flow_path_to_goal(start_cell: Vector2i) -> GridPathResult:
	var result := GridPathResult.new()
	result.start = start_cell
	result.goal = _goal_cell
	if not _pathfinder.is_valid_coord(start_cell):
		return result
	if not _is_reachable(start_cell):
		return result
	var out: Array[Vector2i] = [start_cell]
	var cur := start_cell
	var visited: Dictionary = {start_cell: true}
	for _i in range(MAX_FLOW_TRACE_STEPS):
		if cur == _goal_cell:
			result.found = true
			result.cells = out
			result.total_cost = out.size() - 1
			result.visited_count = out.size()
			return result
		if not _flow_next_by_cell.has(cur):
			return result
		var next := _flow_next_by_cell.get(cur, cur) as Vector2i
		if visited.has(next):
			return result
		visited[next] = true
		out.append(next)
		cur = next
	return result


func _pick_next_cell_by_flow(cell: Vector2i) -> Vector2i:
	if not _distance_by_cell.has(cell):
		return cell
	var cur_dist := int(_distance_by_cell[cell])
	var best := cell
	var best_dist := cur_dist
	for d in _flow_neighbor_priority():
		var nb := cell + d
		if not _distance_by_cell.has(nb):
			continue
		var dist := int(_distance_by_cell[nb])
		if dist < best_dist:
			best_dist = dist
			best = nb
	return best


func _flow_neighbor_priority() -> Array[Vector2i]:
	# 固定 tie-break，保证同图状态下结果稳定
	return [DIR_DOWN, DIR_LEFT, DIR_UP, DIR_RIGHT]


func _build_display_paths_for_render() -> Array:
	var paths: Array = []
	if _path_result.found and _path_result.cells.size() >= 2:
		var main_with_outer: Array[Vector2i] = []
		main_with_outer.append(_spawn_outer_cell)
		main_with_outer.append_array(_path_result.cells)
		main_with_outer.append(_goal_outer_cell)
		paths.append(main_with_outer)
	for v in _temp_enemy_paths.values():
		if v is Array and (v as Array).size() >= 2:
			paths.append((v as Array).duplicate())
	return paths


func _build_mask_by_cell(paths: Array) -> Dictionary:
	var edge_dir_by_cell: Dictionary = {}
	for p in paths:
		if not (p is Array):
			continue
		var cells := p as Array
		for i in range(cells.size() - 1):
			if not (cells[i] is Vector2i and cells[i + 1] is Vector2i):
				continue
			var a := cells[i] as Vector2i
			var b := cells[i + 1] as Vector2i
			var d := b - a
			var bit_ab := _bit_for_step(d)
			var bit_ba := _bit_for_step(-d)
			if bit_ab == 0 or bit_ba == 0:
				continue
			if _pathfinder.is_valid_coord(a):
				var old_a := int(edge_dir_by_cell.get(a, 0))
				edge_dir_by_cell[a] = old_a | bit_ab
			if _pathfinder.is_valid_coord(b):
				var old_b := int(edge_dir_by_cell.get(b, 0))
				edge_dir_by_cell[b] = old_b | bit_ba
	return edge_dir_by_cell


func _bit_for_step(step: Vector2i) -> int:
	if step == DIR_LEFT:
		return BIT_R
	if step == DIR_RIGHT:
		return BIT_L
	if step == DIR_UP:
		return BIT_D
	if step == DIR_DOWN:
		return BIT_U
	return 0


func _scene_key_for_mask(mask: int) -> String:
	match mask:
		BIT_L | BIT_R:
			return KEY_STRAIGHT_LR
		BIT_U | BIT_D:
			return KEY_STRAIGHT_UD
		BIT_R | BIT_U:
			return KEY_CORNER_RU
		BIT_U | BIT_L:
			return KEY_CORNER_UL
		BIT_L | BIT_D:
			return KEY_CORNER_LD
		BIT_D | BIT_R:
			return KEY_CORNER_DR
		BIT_L | BIT_R | BIT_U:
			return KEY_TEE_LRU
		BIT_R | BIT_U | BIT_D:
			return KEY_TEE_RUD
		BIT_L | BIT_U | BIT_D:
			return KEY_TEE_LUD
		BIT_L | BIT_R | BIT_D:
			return KEY_TEE_LRD
		BIT_U | BIT_R | BIT_D | BIT_L:
			return KEY_CROSS
		BIT_R:
			return KEY_END_R
		BIT_U:
			return KEY_END_U
		BIT_L:
			return KEY_END_L
		BIT_D:
			return KEY_END_D
		_:
			return ""
