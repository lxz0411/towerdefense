extends RefCounted
class_name GridPathfinder

## 4 邻接（上下左右）网格 A*。只负责逻辑，不依赖场景节点。

const _DIRS_4: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]
const _INF := 1_000_000_000

var _grid_size: Vector2i = Vector2i.ZERO
## Vector2i -> true（被阻挡）
var _blocked: Dictionary = {}


func setup(cells_x: int, cells_z: int) -> void:
	_grid_size = Vector2i(cells_x, cells_z)
	_blocked.clear()


func clear_blocked() -> void:
	_blocked.clear()


func set_blocked(coord: Vector2i, blocked: bool) -> void:
	if not is_valid_coord(coord):
		return
	if blocked:
		_blocked[coord] = true
	else:
		_blocked.erase(coord)


func is_blocked(coord: Vector2i) -> bool:
	return _blocked.has(coord)


func is_walkable(coord: Vector2i) -> bool:
	return is_valid_coord(coord) and not is_blocked(coord)


func is_valid_coord(coord: Vector2i) -> bool:
	return (
		coord.x >= 0
		and coord.y >= 0
		and coord.x < _grid_size.x
		and coord.y < _grid_size.y
	)


func find_path(start: Vector2i, goal: Vector2i) -> GridPathResult:
	var result := GridPathResult.new()
	result.start = start
	result.goal = goal

	if not is_valid_coord(start) or not is_valid_coord(goal):
		return result
	if not is_walkable(start) or not is_walkable(goal):
		return result

	var open_set: Array[Vector2i] = [start]
	var open_lookup: Dictionary = {start: true}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var f_score: Dictionary = {start: _heuristic(start, goal)}
	var visited_count := 0

	while not open_set.is_empty():
		var current := _pop_lowest_f(open_set, f_score)
		open_lookup.erase(current)
		visited_count += 1

		if current == goal:
			result.found = true
			result.cells = _reconstruct_path(came_from, current)
			result.total_cost = result.cells.size() - 1
			result.visited_count = visited_count
			return result

		var current_g := int(g_score.get(current, _INF))
		for d in _DIRS_4:
			var next := current + d
			if not is_walkable(next):
				continue

			var tentative_g := current_g + 1
			var old_g := int(g_score.get(next, _INF))
			if tentative_g >= old_g:
				continue

			came_from[next] = current
			g_score[next] = tentative_g
			f_score[next] = tentative_g + _heuristic(next, goal)
			if not open_lookup.has(next):
				open_set.append(next)
				open_lookup[next] = true

	result.visited_count = visited_count
	return result


func _pop_lowest_f(open_set: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var best_i := 0
	var best_coord := open_set[0]
	var best_f := int(f_score.get(best_coord, _INF))

	for i in range(1, open_set.size()):
		var c := open_set[i]
		var f := int(f_score.get(c, _INF))
		if f < best_f:
			best_f = f
			best_coord = c
			best_i = i

	open_set.remove_at(best_i)
	return best_coord


static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [current]
	var cursor := current
	while came_from.has(cursor):
		cursor = came_from[cursor]
		out.append(cursor)
	out.reverse()
	return out
