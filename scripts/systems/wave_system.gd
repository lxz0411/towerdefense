extends GameSystem
class_name WaveSystem

signal state_changed(state: int, wave_index: int)
signal wave_started(wave_index: int, wave: WaveData)
signal wave_spawn_finished(wave_index: int)
signal wave_cleared(wave_index: int)
signal intermission_started(next_wave_index: int, duration_sec: float)
signal wave_ready_for_manual_start(next_wave_index: int)
signal all_waves_completed()
signal intermission_hook_requested(next_wave_index: int)

enum WaveState {
	IDLE,
	SPAWNING,
	CLEANUP,
	INTERMISSION,
	COMPLETED,
}

@export var debug_wave_log: bool = true
@export var auto_start_on_init: bool = false

var _enemy_system: EnemySystem
var _wave_config: WaveConfig
var _state: int = WaveState.IDLE
var _current_wave_index: int = -1
var _spawned_in_wave: int = 0
var _spawn_entry_index: int = 0
var _spawned_in_entry: int = 0
var _spawn_timer: Timer


func initialize(config: GameConfig) -> void:
	_enemy_system = GameManager.enemy_system as EnemySystem
	if _enemy_system == null:
		push_error("WaveSystem: 缺少 EnemySystem")
		return

	_wave_config = _load_wave_config(config.wave_config_path)
	if _wave_config == null:
		push_error("WaveSystem: 无法加载 WaveConfig")
		return

	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = false
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)

	set_process(true)

	if config.print_system_init:
		print("WaveSystem: 就绪 waves=%d intermission=%.2f" % [_wave_config.waves.size(), _wave_config.intermission_sec])
	if auto_start_on_init:
		start_battle()


func start_battle() -> bool:
	if _wave_config == null or _wave_config.waves.is_empty():
		push_warning("WaveSystem: 波次为空，无法开始")
		return false
	if _state == WaveState.IDLE:
		_start_wave(0)
		return true
	if _state == WaveState.INTERMISSION:
		_start_wave(_current_wave_index + 1)
		return true
	return false


func get_state() -> int:
	return _state


func get_state_name() -> String:
	match _state:
		WaveState.IDLE:
			return "IDLE"
		WaveState.SPAWNING:
			return "SPAWNING"
		WaveState.CLEANUP:
			return "CLEANUP"
		WaveState.INTERMISSION:
			return "INTERMISSION"
		WaveState.COMPLETED:
			return "COMPLETED"
		_:
			return "UNKNOWN"


func get_current_wave_number() -> int:
	return _current_wave_index + 1


func get_total_wave_count() -> int:
	if _wave_config == null:
		return 0
	return _wave_config.waves.size()


func is_battle_phase_active() -> bool:
	return _state == WaveState.SPAWNING or _state == WaveState.CLEANUP


func _process(_delta: float) -> void:
	if _state != WaveState.CLEANUP:
		return
	if _enemy_system.get_alive_count() == 0:
		_on_wave_cleared()


func _start_wave(wave_index: int) -> void:
	if _wave_config == null:
		return
	if wave_index < 0 or wave_index >= _wave_config.waves.size():
		_set_state(WaveState.COMPLETED)
		all_waves_completed.emit()
		if debug_wave_log:
			print("WaveSystem: 全部波次完成")
		return

	_current_wave_index = wave_index
	_spawned_in_wave = 0
	_spawn_entry_index = 0
	_spawned_in_entry = 0
	if not _advance_to_next_valid_entry():
		_set_state(WaveState.CLEANUP)
		wave_spawn_finished.emit(_current_wave_index)
		if debug_wave_log:
			print("WaveSpawnDone: wave=%d spawned=%d (empty entries)" % [_current_wave_index + 1, _spawned_in_wave])
		return
	_set_state(WaveState.SPAWNING)
	var wave := _wave_config.waves[wave_index] as WaveData
	var interval := _current_entry_interval_sec(wave)
	_spawn_timer.wait_time = interval
	_spawn_timer.start()
	wave_started.emit(_current_wave_index, wave)
	if debug_wave_log:
		print(
			"WaveStart: wave=%d/%d entries=%d interval=%.2f"
			% [wave_index + 1, _wave_config.waves.size(), wave.spawn_entries.size(), interval]
		)
	# 立即尝试首刷，避免“点击后无反馈”的等待感
	_on_spawn_timer_timeout()


func _on_spawn_timer_timeout() -> void:
	if _wave_config == null or _current_wave_index < 0:
		return
	if _state != WaveState.SPAWNING:
		return

	var wave := _wave_config.waves[_current_wave_index] as WaveData
	if _spawn_entry_index >= wave.spawn_entries.size():
		_finish_wave_spawn()
		return

	var entry := wave.spawn_entries[_spawn_entry_index] as WaveSpawnEntry
	if entry == null:
		_spawn_entry_index += 1
		_spawned_in_entry = 0
		_on_spawn_timer_timeout()
		return

	var target_count := maxi(0, entry.enemy_count)
	if _spawned_in_entry >= target_count:
		_spawn_entry_index += 1
		_spawned_in_entry = 0
		if not _advance_to_next_valid_entry():
			_finish_wave_spawn()
			return
		_spawn_timer.wait_time = _current_entry_interval_sec(wave)
		return

	var enemy := _enemy_system.spawn_enemy_by_type(entry.enemy_type)
	if enemy != null:
		_spawned_in_entry += 1
		_spawned_in_wave += 1
		if debug_wave_log:
			print(
				"WaveSpawnTick: wave=%d entry=%d type=%s spawned=%d/%d wave_total=%d"
				% [
					_current_wave_index + 1,
					_spawn_entry_index + 1,
					entry.enemy_type,
					_spawned_in_entry,
					target_count,
					_spawned_in_wave
				]
			)


func _on_wave_cleared() -> void:
	if _state != WaveState.CLEANUP:
		return
	var cleared_index := _current_wave_index
	wave_cleared.emit(cleared_index)
	if debug_wave_log:
		print("WaveCleared: wave=%d" % [cleared_index + 1])

	var next_wave_index := cleared_index + 1
	if _wave_config == null or next_wave_index >= _wave_config.waves.size():
		_set_state(WaveState.COMPLETED)
		all_waves_completed.emit()
		if debug_wave_log:
			print("WaveSystem: 全部波次完成")
		return

	_set_state(WaveState.INTERMISSION)
	var duration := maxf(0.0, _wave_config.intermission_sec)
	intermission_started.emit(next_wave_index, duration)
	wave_ready_for_manual_start.emit(next_wave_index)
	intermission_hook_requested.emit(next_wave_index)
	if debug_wave_log:
		print(
			"IntermissionStart: next_wave=%d duration=%.2f (manual start required)"
			% [next_wave_index + 1, duration]
		)


func _set_state(next_state: int) -> void:
	_state = next_state
	state_changed.emit(_state, _current_wave_index)


func _load_wave_config(path: String) -> WaveConfig:
	var final_path := path
	if final_path.is_empty():
		final_path = WaveConfig.DEFAULT_PATH
	var loaded := load(final_path)
	if loaded is WaveConfig:
		return loaded as WaveConfig
	return null


func _finish_wave_spawn() -> void:
	_spawn_timer.stop()
	_set_state(WaveState.CLEANUP)
	wave_spawn_finished.emit(_current_wave_index)
	if debug_wave_log:
		print("WaveSpawnDone: wave=%d spawned=%d" % [_current_wave_index + 1, _spawned_in_wave])


func _advance_to_next_valid_entry() -> bool:
	if _wave_config == null or _current_wave_index < 0:
		return false
	var wave := _wave_config.waves[_current_wave_index] as WaveData
	while _spawn_entry_index < wave.spawn_entries.size():
		var entry := wave.spawn_entries[_spawn_entry_index] as WaveSpawnEntry
		if entry != null and entry.enemy_count > 0:
			return true
		_spawn_entry_index += 1
		_spawned_in_entry = 0
	return false


func _current_entry_interval_sec(wave: WaveData) -> float:
	if wave == null or _spawn_entry_index < 0 or _spawn_entry_index >= wave.spawn_entries.size():
		return 0.1
	var entry := wave.spawn_entries[_spawn_entry_index] as WaveSpawnEntry
	if entry == null:
		return 0.1
	return maxf(0.05, entry.spawn_interval_sec)
