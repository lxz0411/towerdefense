extends RefCounted
class_name TileGrid

## 正方形逻辑格网（XZ）。为避免与引擎内置 GridMap 节点同名，使用 TileGrid。

var _cfg: GridMapConfig
var _battlefield: Node3D
## 实际格距（与瓦片占地一致时可无缝拼接）。
var _cell_step: float = 1.0
## Vector2i(gx, gz) → GridCell；gz 存在 Vector2i.y。
var cells: Dictionary = {}


func _init(cfg: GridMapConfig, battlefield: Node3D) -> void:
	_cfg = cfg
	_battlefield = battlefield


func get_config() -> GridMapConfig:
	return _cfg


func get_cell_step() -> float:
	return _cell_step


func build_tile_instances(parent: Node3D, tile_scene: PackedScene) -> void:
	cells.clear()
	if tile_scene == null:
		push_error("TileGrid: tile_scene 为空")
		return

	_resolve_cell_step(tile_scene)

	for gz in range(_cfg.cells_z):
		for gx in range(_cfg.cells_x):
			var coord := Vector2i(gx, gz)
			var cell := GridCell.new()
			cell.coord = coord
			var inst := tile_scene.instantiate()
			if inst is Node3D:
				cell.tile_root = inst as Node3D
			else:
				cell.tile_root = null
				push_warning("TileGrid: 瓦片根节点非 Node3D，coord=%s" % coord)
			parent.add_child(inst)
			if cell.tile_root:
				cell.tile_root.position = cell_center_local(coord)
			cells[coord] = cell


func _resolve_cell_step(tile_scene: PackedScene) -> void:
	_cell_step = _cfg.cell_size
	if not _cfg.auto_cell_size_from_mesh:
		return
	var probe: Node = tile_scene.instantiate()
	var ab := _merged_mesh_aabb_from_root(probe)
	probe.free()
	if ab.size.x > 0.0001 and ab.size.z > 0.0001:
		_cell_step = maxf(ab.size.x, ab.size.z)
	elif ab.size.x > 0.0001:
		_cell_step = ab.size.x
	elif ab.size.z > 0.0001:
		_cell_step = ab.size.z


static func _merged_mesh_aabb_from_root(root: Node) -> AABB:
	return _merge_mesh_aabb_recursive(root, Transform3D.IDENTITY)


static func _merge_mesh_aabb_recursive(n: Node, parent_xf: Transform3D) -> AABB:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform

	var acc := AABB()
	var has_acc := false

	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			acc = xf * mi.get_aabb()
			has_acc = true

	for c in n.get_children():
		var sub := _merge_mesh_aabb_recursive(c, xf)
		if sub.size.length() > 0.000001:
			if not has_acc:
				acc = sub
				has_acc = true
			else:
				acc = acc.merge(sub)

	return acc


func cell_center_local(coord: Vector2i) -> Vector3:
	return Vector3(
		_cfg.grid_corner_offset.x + (coord.x + 0.5) * _cell_step,
		_cfg.grid_corner_offset.y + _cfg.tile_vertical_offset,
		_cfg.grid_corner_offset.z + (coord.y + 0.5) * _cell_step
	)


func cell_center_global(coord: Vector2i) -> Vector3:
	return _battlefield.to_global(cell_center_local(coord))


func world_to_cell(world_global: Vector3) -> Vector2i:
	var local := _battlefield.to_local(world_global)
	var rel_x := local.x - _cfg.grid_corner_offset.x
	var rel_z := local.z - _cfg.grid_corner_offset.z
	var gx := floori(rel_x / _cell_step)
	var gz := floori(rel_z / _cell_step)
	var c := Vector2i(gx, gz)
	if not is_valid_coord(c):
		return Vector2i(-1, -1)
	return c


func is_valid_coord(coord: Vector2i) -> bool:
	return (
		coord.x >= 0
		and coord.y >= 0
		and coord.x < _cfg.cells_x
		and coord.y < _cfg.cells_z
	)


func picking_plane_y_global() -> float:
	var local_y := _cfg.grid_corner_offset.y + _cfg.picking_plane_y_offset
	return _battlefield.to_global(Vector3(0, local_y, 0)).y
