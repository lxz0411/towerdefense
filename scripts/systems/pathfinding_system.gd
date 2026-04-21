extends GameSystem
class_name PathfindingSystem

signal path_updated(path_cells: Array[Vector2i])

const KEY_STRAIGHT_LR := "straight_lr"
const KEY_STRAIGHT_UD := "straight_ud"
const KEY_CORNER_RU := "corner_ru"
const KEY_CORNER_UL := "corner_ul"
const KEY_CORNER_LD := "corner_ld"
const KEY_CORNER_DR := "corner_dr"
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

var _grid_system: GridSystem
var _grid: TileGrid
var _map_cfg: GridMapConfig
var _tile_map_cfg: Resource
var _pathfinder := GridPathfinder.new()

var _entry_cell: Vector2i = Vector2i.ZERO
var _goal_cell: Vector2i = Vector2i.ZERO
var _spawn_outer_cell: Vector2i = Vector2i.ZERO
var _goal_outer_cell: Vector2i = Vector2i.ZERO
var _path_result := GridPathResult.new()
## 当前由路径系统替换过的路径格（不含入口与终点）
var _painted_path_cells: Dictionary = {}
## enemy_id(int) -> Array[Vector2i]，仅用于“个体临时路径”可视化
var _temp_enemy_paths: Dictionary = {}
## Vector2i -> 引用计数（多少条临时路径经过该格）
var _temp_painted_ref_count: Dictionary = {}


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
	_recalculate_path()
	_apply_path_tiles()

	if config.print_system_init:
		print(
			"PathfindingSystem: A* 就绪 entry=%s goal=%s found=%s len=%d"
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
	_recalculate_path()
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
	_recalculate_path()
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
	var probe := _pathfinder.find_path(_entry_cell, _goal_cell)
	_pathfinder.set_blocked(coord, false)
	return probe.found


func force_recalculate_path() -> GridPathResult:
	_recalculate_path()
	_apply_path_tiles()
	_emit_path_updated()
	return _path_result


func find_path_cells(start_cell: Vector2i, goal_cell: Vector2i) -> GridPathResult:
	return _pathfinder.find_path(start_cell, goal_cell)


func find_path_cells_allow_start_blocked(start_cell: Vector2i, goal_cell: Vector2i) -> GridPathResult:
	return _pathfinder.find_path_allow_start_blocked(start_cell, goal_cell)


func find_path_from_cell_to_goal(start_cell: Vector2i) -> GridPathResult:
	return _pathfinder.find_path(start_cell, _goal_cell)


func find_path_from_cell_to_goal_allow_start_blocked(start_cell: Vector2i) -> GridPathResult:
	return _pathfinder.find_path_allow_start_blocked(start_cell, _goal_cell)


func _recalculate_path() -> void:
	_path_result = _pathfinder.find_path(_entry_cell, _goal_cell)


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
	if not _path_result.found:
		_rebuild_temp_path_tiles()
		return
	if _path_result.cells.is_empty():
		_rebuild_temp_path_tiles()
		return

	var path_cells := _path_result.cells
	var last_i := path_cells.size() - 1
	for i in range(path_cells.size()):
		var cur := path_cells[i]
		var prev_cell := _spawn_outer_cell if i == 0 else path_cells[i - 1]
		var next_cell := _goal_outer_cell if i == last_i else path_cells[i + 1]
		var prev_dir := prev_cell - cur
		var next_dir := next_cell - cur

		var scene_key := KEY_STRAIGHT_LR
		if _is_turn(prev_dir, next_dir):
			scene_key = _corner_scene_for_dirs(prev_dir, next_dir)
		else:
			scene_key = _straight_scene_for_dir(prev_dir)

		var scene_path := _scene_path_for_key(scene_key)
		if scene_path.is_empty():
			push_warning("PathfindingSystem: 路径地块 key 未配置: %s" % scene_key)
			continue
		var ok := _grid_system.replace_tile_scene_at_cell(cur, scene_path, 0.0)
		if ok:
			_painted_path_cells[cur] = true
	_rebuild_temp_path_tiles()


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
	_rebuild_temp_path_tiles()


func clear_temp_enemy_path(enemy_id: int) -> void:
	if not _temp_enemy_paths.has(enemy_id):
		return
	_temp_enemy_paths.erase(enemy_id)
	_rebuild_temp_path_tiles()


func clear_all_temp_enemy_paths() -> void:
	if _temp_enemy_paths.is_empty() and _temp_painted_ref_count.is_empty():
		return
	_temp_enemy_paths.clear()
	_rebuild_temp_path_tiles()


func _sanitize_grid_cells(raw_cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in raw_cells:
		if _pathfinder.is_valid_coord(c):
			if out.is_empty() or out.back() != c:
				out.append(c)
	return out


func _rebuild_temp_path_tiles() -> void:
	for key in _temp_painted_ref_count.keys():
		var coord: Vector2i = key
		if not _painted_path_cells.has(coord):
			_grid_system.restore_default_tile_at_cell(coord)
	_temp_painted_ref_count.clear()

	for v in _temp_enemy_paths.values():
		if not (v is Array):
			continue
		var cells: Array[Vector2i] = []
		for item in v:
			if item is Vector2i:
				cells.append(item)
		_paint_one_temp_path(cells)


func _paint_one_temp_path(cells: Array[Vector2i]) -> void:
	if cells.size() < 2:
		return
	var last_i := cells.size() - 1
	for i in range(cells.size()):
		var cur := cells[i]
		var prev_cell := _virtual_prev_cell(cells, i)
		var next_cell := _virtual_next_cell(cells, i)
		var prev_dir := prev_cell - cur
		var next_dir := next_cell - cur

		var scene_key := KEY_STRAIGHT_LR
		if _is_turn(prev_dir, next_dir):
			scene_key = _corner_scene_for_dirs(prev_dir, next_dir)
		else:
			scene_key = _straight_scene_for_dir(prev_dir)

		var scene_path := _scene_path_for_key(scene_key)
		if scene_path.is_empty():
			continue
		var ok := _grid_system.replace_tile_scene_at_cell(cur, scene_path, 0.0)
		if ok:
			var old_count: int = int(_temp_painted_ref_count.get(cur, 0))
			_temp_painted_ref_count[cur] = old_count + 1
		if i == last_i:
			break


static func _virtual_prev_cell(cells: Array[Vector2i], i: int) -> Vector2i:
	if i > 0:
		return cells[i - 1]
	var cur := cells[i]
	var next := cells[i + 1]
	var dir := next - cur
	return cur - dir


static func _virtual_next_cell(cells: Array[Vector2i], i: int) -> Vector2i:
	if i < cells.size() - 1:
		return cells[i + 1]
	var cur := cells[i]
	var prev := cells[i - 1]
	var dir := cur - prev
	return cur + dir
