extends Resource
class_name PathTileMappingConfig

## 路径地块映射配置表（key -> PackedScene 路径）

@export var scene_path_by_key: Dictionary = {
	"straight_lr": "res://Assets/SceneModels/Map/variants/tile-straight-LR.tscn",
	"straight_ud": "res://Assets/SceneModels/Map/variants/tile-straight-UD.tscn",
	"corner_ru": "res://Assets/SceneModels/Map/variants/tile-corner-square-RU.tscn",
	"corner_ul": "res://Assets/SceneModels/Map/variants/tile-corner-square-UL.tscn",
	"corner_ld": "res://Assets/SceneModels/Map/variants/tile-corner-square-LD.tscn",
	"corner_dr": "res://Assets/SceneModels/Map/variants/tile-corner-square-DR.tscn",
	"tee_lru": "res://Assets/SceneModels/Map/variants/tile-split-LRU.tscn",
	"tee_rud": "res://Assets/SceneModels/Map/variants/tile-split-RUD.tscn",
	"tee_lud": "res://Assets/SceneModels/Map/variants/tile-split-LUD.tscn",
	"tee_lrd": "res://Assets/SceneModels/Map/variants/tile-split-LRD.tscn",
	"cross": "res://Assets/SceneModels/Map/variants/tile-crossing-UDLR.tscn",
	"spawn_r": "res://Assets/SceneModels/Map/variants/tile-spawn-end-R.tscn",
	"spawn_u": "res://Assets/SceneModels/Map/variants/tile-spawn-end-U.tscn",
	"spawn_l": "res://Assets/SceneModels/Map/variants/tile-spawn-end-L.tscn",
	"spawn_d": "res://Assets/SceneModels/Map/variants/tile-spawn-end-D.tscn",
	"goal_r": "res://Assets/SceneModels/Map/variants/tile-end-R.tscn",
	"goal_u": "res://Assets/SceneModels/Map/variants/tile-end-U.tscn",
	"goal_l": "res://Assets/SceneModels/Map/variants/tile-end-L.tscn",
	"goal_d": "res://Assets/SceneModels/Map/variants/tile-end-D.tscn",
}


func get_scene_path(key: String) -> String:
	var v: Variant = scene_path_by_key.get(key, "")
	if v is String:
		return v
	return ""
