extends RefCounted
class_name GridPathResult

## A* 结果结构：纯逻辑数据，供敌人系统和调试层共用。

var found: bool = false
var start: Vector2i = Vector2i(-1, -1)
var goal: Vector2i = Vector2i(-1, -1)
var cells: Array[Vector2i] = []
var total_cost: int = -1
var visited_count: int = 0


func length() -> int:
	return cells.size()


func is_empty() -> bool:
	return cells.is_empty()
