extends GameSystem
class_name GridSystem

## 正方形格网 + 鼠标选格 + 高亮。射线与水平拾取面相交（XZ 战场）。

var _map_cfg: GridMapConfig
var _grid: TileGrid
var _tiles_root: Node3D
var _highlight: MeshInstance3D
var _plane_y_global: float = 0.0
var _battle_camera: Camera3D
var _default_tile_scene: PackedScene
var _scene_cache: Dictionary = {}

const SPAWN_TILE_SCENE_PATH := "res://Assets/SceneModels/Map/tile-spawn-end.glb"
const GOAL_TILE_SCENE_PATH := "res://Assets/SceneModels/Map/tile-end.glb"
var _spawn_marker: Node3D
var _goal_marker: Node3D

func initialize(config: GameConfig) -> void:
	var loaded: Resource = load(config.grid_map_config_path)
	if loaded == null or not (loaded is GridMapConfig):
		push_error("GridSystem: 无法加载 GridMapConfig: %s" % config.grid_map_config_path)
		return

	_map_cfg = loaded as GridMapConfig
	if GameManager.battlefield_root == null:
		push_error("GridSystem: GameManager.battlefield_root 为空")
		return

	_tiles_root = Node3D.new()
	_tiles_root.name = "GridTiles"
	GameManager.battlefield_root.add_child(_tiles_root)

	_grid = TileGrid.new(_map_cfg, GameManager.battlefield_root)
	var tile_ps: PackedScene = load(_map_cfg.tile_scene_path) as PackedScene
	if tile_ps == null:
		push_error("GridSystem: 无法加载 tile PackedScene: %s" % _map_cfg.tile_scene_path)
		return
	_default_tile_scene = tile_ps
	_scene_cache[_map_cfg.tile_scene_path] = tile_ps

	_grid.build_tile_instances(_tiles_root, tile_ps)
	_plane_y_global = _grid.picking_plane_y_global()
	if GameManager.world_root:
		_battle_camera = GameManager.world_root.get_node_or_null("CameraRig/Camera3D") as Camera3D
	_create_highlight()
	set_process(true)

	if config.print_system_init:
		print(
			"GridSystem: 格网 %dx%d cell_step=%.3f (auto_mesh=%s) 拾取面Y=%.3f"
			% [
				_map_cfg.cells_x,
				_map_cfg.cells_z,
				_grid.get_cell_step(),
				_map_cfg.auto_cell_size_from_mesh,
				_plane_y_global
			]
		)


func get_tile_grid() -> TileGrid:
	return _grid


func get_map_config() -> GridMapConfig:
	return _map_cfg


func replace_tile_scene_at_cell(coord: Vector2i, scene_path: String, rotation_y: float = 0.0) -> bool:
	return _replace_tile_scene_at_cell(coord, scene_path, rotation_y)


func restore_default_tile_at_cell(coord: Vector2i) -> bool:
	if _default_tile_scene == null:
		return false
	return _replace_tile_with_packed_scene(coord, _default_tile_scene, 0.0)


func _create_highlight() -> void:
	_highlight = MeshInstance3D.new()
	_highlight.name = "HoverHighlight"
	var step := _grid.get_cell_step()
	var box := BoxMesh.new()
	box.size = Vector3(step * 0.92, 0.06, step * 0.92)
	_highlight.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.85, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.6, 0.9)
	mat.emission_energy_multiplier = 1.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	_highlight.material_override = mat
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.visible = false
	_tiles_root.add_child(_highlight)


func _process(_delta: float) -> void:
	if _grid == null or _highlight == null:
		return
	var cam: Camera3D = _battle_camera
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d()
	if cam == null:
		_highlight.visible = false
		return

	var screen := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var hit: Vector3 = _ray_to_horizontal_plane(origin, dir, _plane_y_global)
	if is_nan(hit.x):
		_highlight.visible = false
		return

	var cell := _grid.world_to_cell(hit)
	if not _grid.is_valid_coord(cell):
		_highlight.visible = false
		return

	var center := _grid.cell_center_local(cell)
	_highlight.visible = true
	_highlight.position = center + Vector3(0.0, _map_cfg.highlight_y_lift, 0.0)


static func _ray_to_horizontal_plane(origin: Vector3, dir: Vector3, plane_y: float) -> Vector3:
	if absf(dir.y) < 1e-6:
		return Vector3(NAN, NAN, NAN)
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0:
		return Vector3(NAN, NAN, NAN)
	return origin + dir * t


func set_spawn_goal_markers(
	spawn_coord: Vector2i,
	goal_coord: Vector2i,
	spawn_scene_path: String = SPAWN_TILE_SCENE_PATH,
	goal_scene_path: String = GOAL_TILE_SCENE_PATH
) -> void:
	if _grid == null:
		return
	_place_spawn_goal_marker_node(spawn_coord, spawn_scene_path, "_spawn_marker")
	_place_spawn_goal_marker_node(goal_coord, goal_scene_path, "_goal_marker")


func _replace_tile_scene_at_cell(coord: Vector2i, scene_path: String, rotation_y: float) -> bool:
	if not _grid.cells.has(coord):
		push_warning("GridSystem: 目标格不存在，无法替换瓦片 coord=%s" % coord)
		return false

	var cell := _grid.cells[coord] as GridCell
	if cell == null:
		return false

	var marker_scene := _get_scene_cached(scene_path)
	if marker_scene == null:
		push_warning("GridSystem: 无法加载角点瓦片: %s" % scene_path)
		return false

	return _replace_tile_with_packed_scene(coord, marker_scene, rotation_y)


func _place_spawn_goal_marker_node(coord: Vector2i, scene_path: String, slot_name: String) -> void:
	var scene := _get_scene_cached(scene_path)
	if scene == null:
		push_warning("GridSystem: 无法加载标记场景: %s" % scene_path)
		return

	var existing: Node3D = null
	if slot_name == "_spawn_marker":
		existing = _spawn_marker
	elif slot_name == "_goal_marker":
		existing = _goal_marker
	if existing and is_instance_valid(existing):
		existing.queue_free()

	var inst := scene.instantiate()
	if not (inst is Node3D):
		return
	var node := inst as Node3D
	_tiles_root.add_child(node)
	node.position = _grid.cell_center_local(coord)
	if slot_name == "_spawn_marker":
		_spawn_marker = node
	elif slot_name == "_goal_marker":
		_goal_marker = node


func _replace_tile_with_packed_scene(coord: Vector2i, tile_scene: PackedScene, rotation_y: float) -> bool:
	var cell := _grid.cells[coord] as GridCell
	if cell == null:
		return false

	if cell.tile_root and is_instance_valid(cell.tile_root):
		cell.tile_root.queue_free()

	var marker_inst := tile_scene.instantiate()
	if marker_inst is Node3D:
		var marker_root := marker_inst as Node3D
		_tiles_root.add_child(marker_root)
		marker_root.position = _grid.cell_center_local(coord)
		marker_root.rotation.y = rotation_y
		cell.tile_root = marker_root
		return true

	push_warning("GridSystem: 角点瓦片根节点非 Node3D")
	return false


func _get_scene_cached(scene_path: String) -> PackedScene:
	if _scene_cache.has(scene_path):
		return _scene_cache[scene_path] as PackedScene
	var loaded := load(scene_path) as PackedScene
	if loaded:
		_scene_cache[scene_path] = loaded
	return loaded
