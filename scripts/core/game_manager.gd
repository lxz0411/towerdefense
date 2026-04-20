extends Node

var config: GameConfig

var grid_system: GameSystem
var pathfinding_system: GameSystem
var enemy_system: GameSystem
var tower_system: GameSystem
var wave_system: GameSystem
var ui_system: GameSystem

var world_root: Node3D
var battlefield_root: Node3D


func register_systems(
	p_grid: GameSystem,
	p_path: GameSystem,
	p_enemy: GameSystem,
	p_tower: GameSystem,
	p_wave: GameSystem,
	p_ui: GameSystem
) -> void:
	grid_system = p_grid
	pathfinding_system = p_path
	enemy_system = p_enemy
	tower_system = p_tower
	wave_system = p_wave
	ui_system = p_ui


func register_world(p_world: Node3D, p_battlefield: Node3D) -> void:
	world_root = p_world
	battlefield_root = p_battlefield
