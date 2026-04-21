extends GameSystem
class_name UISystem

var _enemy_system: EnemySystem
var _tower_system: TowerSystem
var _wave_system: WaveSystem
var _start_enemy_btn: Button
var _card_bar: HBoxContainer


func initialize(config: GameConfig) -> void:
	_enemy_system = GameManager.enemy_system as EnemySystem
	_tower_system = GameManager.tower_system as TowerSystem
	_wave_system = GameManager.wave_system as WaveSystem
	_create_start_enemy_button()
	_create_bottom_cards()
	_bind_wave_events()

	if config.print_system_init:
		print("UISystem: 就绪（开始刷怪按钮）")


func _create_start_enemy_button() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var ui_root := scene_root.get_node_or_null("UILayer/UIRoot") as Control
	if ui_root == null:
		push_warning("UISystem: 找不到 UILayer/UIRoot")
		return

	_start_enemy_btn = Button.new()
	_start_enemy_btn.name = "StartEnemyButton"
	_start_enemy_btn.text = "开始刷怪"
	_start_enemy_btn.custom_minimum_size = Vector2(140, 40)
	_start_enemy_btn.position = Vector2(16, 16)
	_start_enemy_btn.pressed.connect(_on_start_enemy_button_pressed)
	ui_root.add_child(_start_enemy_btn)


func _on_start_enemy_button_pressed() -> void:
	if _wave_system == null:
		return
	var started := _wave_system.start_battle()
	if started:
		_start_enemy_btn.disabled = true
		_start_enemy_btn.text = "战斗中..."
	else:
		_start_enemy_btn.disabled = false
		_start_enemy_btn.text = "无法开始(看控制台)"


func _create_bottom_cards() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var ui_root := scene_root.get_node_or_null("UILayer/UIRoot") as Control
	if ui_root == null:
		return

	_card_bar = HBoxContainer.new()
	_card_bar.name = "CardBar"
	_card_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card_bar.add_theme_constant_override("separation", 12)
	_card_bar.anchor_left = 0.5
	_card_bar.anchor_top = 1.0
	_card_bar.anchor_right = 0.5
	_card_bar.anchor_bottom = 1.0
	_card_bar.offset_left = -190
	_card_bar.offset_top = -82
	_card_bar.offset_right = 190
	_card_bar.offset_bottom = -16
	ui_root.add_child(_card_bar)

	_add_card_button("墙体", TowerSystem.TYPE_WALL)
	_add_card_button("基础攻击塔", TowerSystem.TYPE_BASIC_ATTACK_TOWER)


func _add_card_button(label: String, placement_type: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(160, 56)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.gui_input.connect(_on_card_gui_input.bind(placement_type))
	_card_bar.add_child(btn)


func _on_card_gui_input(event: InputEvent, placement_type: String) -> void:
	if _tower_system == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_tower_system.begin_drag(placement_type)


func _bind_wave_events() -> void:
	if _wave_system == null:
		return
	_wave_system.wave_started.connect(_on_wave_started)
	_wave_system.intermission_started.connect(_on_wave_intermission_started)
	_wave_system.all_waves_completed.connect(_on_all_waves_completed)


func _on_wave_started(wave_index: int, _wave: WaveData) -> void:
	if _start_enemy_btn == null:
		return
	_start_enemy_btn.disabled = true
	_start_enemy_btn.text = "战斗中: W%d" % [wave_index + 1]


func _on_wave_intermission_started(next_wave_index: int, duration_sec: float) -> void:
	if _start_enemy_btn == null:
		return
	_start_enemy_btn.disabled = false
	_start_enemy_btn.text = "开始下一波(W%d) 间隙%.1fs" % [next_wave_index + 1, duration_sec]


func _on_all_waves_completed() -> void:
	if _start_enemy_btn == null:
		return
	_start_enemy_btn.disabled = true
	_start_enemy_btn.text = "全部波次完成"
