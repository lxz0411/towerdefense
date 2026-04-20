extends GameSystem
class_name TowerSystem


func initialize(config: GameConfig) -> void:
	if config.print_system_init:
		print("TowerSystem: 占位")
