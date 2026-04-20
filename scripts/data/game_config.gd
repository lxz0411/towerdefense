extends Resource
class_name GameConfig

const DEFAULT_PATH := "res://data/config/default_game_config.tres"

@export var print_system_init: bool = true
@export var grid_map_config_path: String = "res://data/config/default_grid_map.tres"
@export var path_tile_mapping_config_path: String = "res://data/config/default_path_tile_mapping.tres"
