extends Node3D
## 斜前视角：透视 + 无 roll，平台在 XZ 平面；非正俯视、非等距相机。

@export var look_target: Vector3 = Vector3(0, 0.35, 0)
@export var rig_position: Vector3 = Vector3(0, 10.5, 14.0)
@export var camera_fov_deg: float = 48.0


func _ready() -> void:
	global_position = rig_position
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.fov = camera_fov_deg
	look_at(look_target, Vector3.UP)
