extends Resource
class_name WaveConfig

const DEFAULT_PATH := "res://data/config/default_wave_config.tres"

@export var intermission_sec: float = 5.0
@export var waves: Array[WaveData] = []
