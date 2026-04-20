extends GameSystem
class_name GridSystem

## 正方形格网 + 鼠标选格 + 高亮。射线与水平拾取面相交（XZ 战场）。

var _map_cfg: GridMapConfig
var _grid: TileGrid
var _tiles_root: Node3D
var _highlight: MeshInstance3D
var _plane_y_global: float = 0.0


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

	_grid.build_tile_instances(_tiles_root, tile_ps)
	_plane_y_global = _grid.picking_plane_y_global()
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


func _create_highlight() -> void:
	_highlight = MeshInstance3D.new()
	_highlight.name = "HoverHighlight"
	var step := _grid.get_cell_step()
	var box := BoxMesh.new()
	box.size = Vector3(step * 0.9, 0.04, step * 0.9)
	_highlight.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.85, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.6, 0.9)
	mat.emission_energy_multiplier = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight.material_override = mat
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.visible = false
	_tiles_root.add_child(_highlight)


func _process(_delta: float) -> void:
	if _grid == null or _highlight == null:
		return
	var cam := get_viewport().get_camera_3d()
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
