extends Node3D

const SYSTEM_ORDER: Array[String] = [
	"GridSystem",
	"PathfindingSystem",
	"EnemySystem",
	"TowerSystem",
	"WaveSystem",
	"UISystem",
]


func _ready() -> void:
	var loaded: Resource = load(GameConfig.DEFAULT_PATH)
	if loaded == null or not (loaded is GameConfig):
		push_error("SceneBootstrap: 无法加载 GameConfig")
		return
	var game_config := loaded as GameConfig
	GameManager.config = game_config

	var world := get_node_or_null("World") as Node3D
	var battlefield := get_node_or_null("World/Battlefield") as Node3D
	if world == null or battlefield == null:
		push_error("SceneBootstrap: World/Battlefield 缺失")
		return
	GameManager.register_world(world, battlefield)

	var grid_sys := get_node_or_null("Systems/GridSystem") as GameSystem
	var path_sys := get_node_or_null("Systems/PathfindingSystem") as GameSystem
	var enemy_sys := get_node_or_null("Systems/EnemySystem") as GameSystem
	var tower_sys := get_node_or_null("Systems/TowerSystem") as GameSystem
	var wave_sys := get_node_or_null("Systems/WaveSystem") as GameSystem
	var ui_sys := get_node_or_null("Systems/UISystem") as GameSystem
	if (
		grid_sys == null
		or path_sys == null
		or enemy_sys == null
		or tower_sys == null
		or wave_sys == null
		or ui_sys == null
	):
		push_error("SceneBootstrap: Systems 子节点不完整")
		return

	GameManager.register_systems(grid_sys, path_sys, enemy_sys, tower_sys, wave_sys, ui_sys)

	for name in SYSTEM_ORDER:
		var n := get_node_or_null("Systems/%s" % name)
		if n is GameSystem:
			(n as GameSystem).initialize(game_config)

	if game_config.print_system_init:
		print("SceneBootstrap: 3D 骨架就绪")
