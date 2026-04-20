extends Resource
class_name GridMapConfig

## 正方形格网（逻辑在 XZ 上）。逻辑坐标 Vector2i：x → 世界 X，y → 世界 Z（格索引，非高度）。

@export var cells_x: int = 12
@export var cells_z: int = 8
## 为 true 时根据 tile 场景内 Mesh 的 AABB 在 XZ 上取步长（取 max(宽,深)），与模型真实尺寸一致，避免缝隙。
@export var auto_cell_size_from_mesh: bool = true
## auto 关闭时使用；或作为 AABB 无效时的回退。
@export var cell_size: float = 1.0
## 相对 Battlefield 根节点：第 (0,0) 格在 X/Z 上的最小角；Y 取平台顶面附近。
@export var grid_corner_offset: Vector3 = Vector3(-9.0, 0.11, -6.0)
@export var tile_scene_path: String = "res://Assets/SceneModels/Map/tile.glb"
## 瓦片模型枢轴与平台顶面的垂直微调（世界单位，沿 Battlefield 局部 Y）。
@export var tile_vertical_offset: float = 0.0
## 鼠标拾取用的水平面高度（相对 Battlefield）：corner.y + 该值。
@export var picking_plane_y_offset: float = 0.05
## 高亮块相对格心的额外抬高（沿局部 Y）。
@export var highlight_y_lift: float = 0.06
