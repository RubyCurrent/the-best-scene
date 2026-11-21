
extends Node3D

# THE BEST SCENE - Mobile controls and improved house

var player: CharacterBody3D
var head: Node3D
var camera: Camera3D
var world_environment: WorldEnvironment

var gravity := 20.0
var walk_speed := 5.0
var sprint_speed := 8.5
var crouch_speed := 2.5
var jump_velocity := 5.2
var sensitivity := 0.0025
var step_height := 0.38

var active_mode := "touch"
var joystick := Vector2.ZERO
var joystick_finger := -1
var look_finger := -1
var run_pressed := false
var crouch_pressed := false
var jump_requested := false

var touch_ui: CanvasLayer
var ui_root: Control
var stick_visual: Control
var jump_button: Button
var run_button: Button
var crouch_button: Button
var menu_button: Button
var settings_panel: PanelContainer
var size_slider: HSlider
var mode_select: OptionButton
var edit_button: Button
var reset_button: Button

var size_level := 6
var edit_mode := false
var drag_target: Button
var drag_offset := Vector2.ZERO
var custom_positions := {}
var default_positions := {}
var control_buttons: Array[Button] = []

var house_light: OmniLight3D


class StickVisual extends Control:
	var value := Vector2.ZERO

	func _draw():
		var center = size / 2.0
		draw_circle(center, 75.0, Color(0.025, 0.035, 0.06, 0.72))
		draw_arc(center, 75.0, 0, TAU, 64, Color(0.7, 0.82, 1.0, 0.75), 3.0)
		draw_circle(center + value * 45.0, 30.0, Color(0.72, 0.82, 1.0, 0.9))
		draw_arc(center + value * 45.0, 30.0, 0, TAU, 40, Color.WHITE, 2.0)


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	create_input_actions()
	create_world()
	create_house()
	create_player()
	create_touch_controls()
	load_control_settings()
	layout_controls()

	if DisplayServer.is_touchscreen_available():
		active_mode = "touch"
		touch_ui.visible = true


func make_material(color: Color, roughness := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func add_box(box_name: String, box_size: Vector3, box_position: Vector3, color: Color, solid := true, parent: Node = self):
	var body: Node3D

	if solid:
		body = StaticBody3D.new()
	else:
		body = Node3D.new()

	body.name = box_name
	body.position = box_position

	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = box_size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = make_material(color)
	body.add_child(mesh_instance)

	if solid:
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = box_size
		collision.shape = shape
		body.add_child(collision)

	parent.add_child(body)
	return body


func create_input_actions():
	var actions = {
		"move_left": KEY_A,
		"move_right": KEY_D,
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"sprint": KEY_SHIFT,
		"jump": KEY_SPACE,
		"crouch": KEY_CTRL
	}

	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

		var key_event = InputEventKey.new()
		key_event.physical_keycode = actions[action]
		InputMap.action_add_event(action, key_event)


func create_world():
	world_environment = WorldEnvironment.new()
	var environment = Environment.new()

	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.006, 0.009, 0.025)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.30, 0.34, 0.48)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.1

	world_environment.environment = environment
	add_child(world_environment)

	add_box(
		"Night Ground",
		Vector3(150, 0.5, 150),
		Vector3(0, -0.35, 0),
		Color(0.018, 0.027, 0.035)
	)

	var moon = DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-45, -30, 0)
	moon.light_color = Color(0.42, 0.50, 0.78)
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	add_child(moon)


func create_house():
	var wall = Color(0.22, 0.19, 0.17)
	var floor = Color(0.34, 0.24, 0.16)
	var dark_wood = Color(0.12, 0.075, 0.045)

	add_box("House Floor", Vector3(14, 0.2, 10), Vector3(0, 0.1, 0), floor)

	# Стены
	add_box("Back Wall Left", Vector3(5.5, 3.4, 0.4), Vector3(-4.25, 1.8, -5), wall)
	add_box("Back Wall Right", Vector3(5.5, 3.4, 0.4), Vector3(4.25, 1.8, -5), wall)
	add_box("Back Window Top", Vector3(3, 1.4, 0.4), Vector3(0, 2.8, -5), wall)
	add_box("Back Window Bottom", Vector3(3, 0.8, 0.4), Vector3(0, 0.5, -5), wall)

	add_box("Left Wall", Vector3(0.4, 3.4, 10), Vector3(-7, 1.8, 0), wall)
	add_box("Right Wall", Vector3(0.4, 3.4, 10), Vector3(7, 1.8, 0), wall)

	add_box("Front Wall Left", Vector3(5.8, 3.4, 0.4), Vector3(-4.1, 1.8, 5), wall)
	add_box("Front Wall Right", Vector3(5.8, 3.4, 0.4), Vector3(4.1, 1.8, 5), wall)
	add_box("Door Header", Vector3(2.4, 1.1, 0.4), Vector3(0, 3.0, 5), wall)

	add_box("Ceiling", Vector3(14.4, 0.3, 10.4), Vector3(0, 3.55, 0), Color(0.12, 0.105, 0.10))

	# Окно
	var glass_material = StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.025, 0.055, 0.16)
	glass_material.emission_enabled = true
	glass_material.emission = Color(0.025, 0.045, 0.13)
	glass_material.emission_energy_multiplier = 0.8

	var glass = MeshInstance3D.new()
	var glass_mesh = BoxMesh.new()
	glass_mesh.size = Vector3(2.8, 1.15, 0.06)
	glass.mesh = glass_mesh
	glass.material_override = glass_material
	glass.position = Vector3(0, 2.0, -4.76)
	add_child(glass)

	add_box("Window Frame Top", Vector3(3, 0.12, 0.15), Vector3(0, 2.65, -4.65), dark_wood, false)
	add_box("Window Frame Bottom", Vector3(3, 0.12, 0.15), Vector3(0, 1.35, -4.65), dark_wood, false)
	add_box("Window Frame Center", Vector3(0.12, 1.3, 0.15), Vector3(0, 2.0, -4.65), dark_wood, false)

	# Свет внутри
	house_light = OmniLight3D.new()
	house_light.position = Vector3(0, 3.0, 0)
	house_light.light_color = Color(1.0, 0.72, 0.42)
	house_light.light_energy = 2.4
	house_light.omni_range = 15.0
	house_light.shadow_enabled = true
	add_child(house_light)

	add_box("Ceiling Lamp", Vector3(0.7, 0.12, 0.7), Vector3(0, 3.32, 0), Color(1.0, 0.78, 0.48), false)

	# Стол
	add_box("Table Top", Vector3(2.2, 0.15, 1.2), Vector3(-3.5, 1.0, -1.5), dark_wood)
	add_box("Table Leg 1", Vector3(0.15, 1.0, 0.15), Vector3(-4.4, 0.5, -1.9), dark_wood)
	add_box("Table Leg 2", Vector3(0.15, 1.0, 0.15), Vector3(-2.6, 0.5, -1.9), dark_wood)
	add_box("Table Leg 3", Vector3(0.15, 1.0, 0.15), Vector3(-4.4, 0.5, -1.1), dark_wood)
	add_box("Table Leg 4", Vector3(0.15, 1.0, 0.15), Vector3(-2.6, 0.5, -1.1), dark_wood)

	# Кровать
	add_box("Bed Base", Vector3(2.5, 0.45, 3.0), Vector3(3.8, 0.45, -2.5), dark_wood)
	add_box("Bed Mattress", Vector3(2.4, 0.25, 2.9), Vector3(3.8, 0.8, -2.5), Color(0.42, 0.44, 0.52))
	add_box("Pillow", Vector3(1.0, 0.2, 0.55), Vector3(3.8, 1.02, -3.55), Color(0.82, 0.82, 0.88))

	# Ступени
	for i in range(6):
		var height = 0.18 * (i + 1)
		var depth = 0.42
		add_box(
			"Stair %d" % i,
			Vector3(1.8, height, depth),
			Vector3(-4.8, height / 2.0, 2.5 - i * depth),
			Color(0.25, 0.15, 0.09)
		)

	# Дополнительная мебель
	add_box("Cabinet", Vector3(1.4, 1.5, 0.7), Vector3(5.2, 0.85, 1.0), dark_wood)
	add_box("Cabinet Top", Vector3(1.5, 0.12, 0.8), Vector3(5.2, 1.65, 1.0), Color(0.28, 0.17, 0.10))


func create_player():
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 1.2, 1.5)
	player.floor_snap_length = 0.3
	add_child(player)

	var collision = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision.shape = capsule
	player.add_child(collision)

	head = Node3D.new()
	head.position.y = 0.65
	player.add_child(head)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 82
	camera.position.y = 0.25
	head.add_child(camera)


func style_button(button: Button, color: Color):
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 34)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)

	var normal = StyleBoxFlat.new()
	normal.bg_color = color
	normal.corner_radius_top_left = 24
	normal.corner_radius_top_right = 24
	normal.corner_radius_bottom_left = 24
	normal.corner_radius_bottom_right = 24
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.85, 0.9, 1.0, 0.7)
	button.add_theme_stylebox_override("normal", normal)

	var pressed = normal.duplicate()
	pressed.bg_color = color.darkened(0.4)
	button.add_theme_stylebox_override("pressed", pressed)


func create_touch_controls():
	touch_ui = CanvasLayer.new()
	touch_ui.name = "TouchControls"
	add_child(touch_ui)

	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
	touch_ui.add_child(ui_root)

	var stick = StickVisual.new()
	stick.name = "Joystick"
	stick.custom_minimum_size = Vector2(170, 170)
	stick.size = Vector2(170, 170)
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(stick)
	stick_visual = stick

	jump_button = Button.new()
	jump_button.text = "^"
	style_button(jump_button, Color(0.12, 0.35, 0.75, 0.82))
	ui_root.add_child(jump_button)
	jump_button.pressed.connect(func(): jump_requested = true)

	run_button = Button.new()
	run_button.text = "»"
	style_button(run_button, Color(0.12, 0.52, 0.25, 0.82))
	ui_root.add_child(run_button)
	run_button.button_down.connect(func(): run_pressed = true)
	run_button.button_up.connect(func(): run_pressed = false)

	crouch_button = Button.new()
	crouch_button.text = "⌄"
	style_button(crouch_button, Color(0.45, 0.30, 0.12, 0.82))
	ui_root.add_child(crouch_button)
	crouch_button.button_down.connect(func(): crouch_pressed = true)
	crouch_button.button_up.connect(func(): crouch_pressed = false)

	menu_button = Button.new()
	menu_button.text = "⚙"
	style_button(menu_button, Color(0.12, 0.14, 0.20, 0.9))
	menu_button.add_theme_font_size_override("font_size", 26)
	menu_button.size = Vector2(62, 62)
	ui_root.add_child(menu_button)
	menu_button.pressed.connect(toggle_settings)

	control_buttons = [jump_button, run_button, crouch_button]
	default_positions = {
		jump_button: Vector2(0.86, 0.70),
		run_button: Vector2(0.86, 0.88),
		crouch_button: Vector2(0.70, 0.88)
	}

	for button in control_buttons:
		button.gui_input.connect(_on_control_gui_input.bind(button))

	create_settings_menu()
	touch_ui.visible = true


func create_settings_menu():
	settings_panel = PanelContainer.new()
	settings_panel.visible = false
	settings_panel.custom_minimum_size = Vector2(310, 330)
	settings_panel.position = Vector2(20, 20)
	ui_root.add_child(settings_panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.075, 0.97)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.35, 0.45, 0.65)
	settings_panel.add_theme_stylebox_override("panel", style)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	settings_panel.add_child(column)

	var title = Label.new()
	title.text = "УПРАВЛЕНИЕ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	var mode_label = Label.new()
	mode_label.text = "Тип управления"
	column.add_child(mode_label)

	mode_select = OptionButton.new()
	mode_select.add_item("Сенсорное", 0)
	mode_select.add_item("Клавиатура", 1)
	mode_select.add_item("Геймпад", 2)
	mode_select.item_selected.connect(_on_mode_selected)
	column.add_child(mode_select)

	var size_label = Label.new()
	size_label.text = "Размер кнопок: 1 - 10"
	column.add_child(size_label)

	size_slider = HSlider.new()
	size_slider.min_value = 1
	size_slider.max_value = 10
	size_slider.step = 1
	size_slider.value = size_level
	size_slider.value_changed.connect(_on_size_changed)
	column.add_child(size_slider)

	edit_button = Button.new()
	edit_button.text = "Переместить кнопки"
	edit_button.pressed.connect(toggle_edit_mode)
	column.add_child(edit_button)

	reset_button = Button.new()
	reset_button.text = "Сбросить расположение"
	reset_button.pressed.connect(reset_controls)
	column.add_child(reset_button)

	var close_button = Button.new()
	close_button.text = "Закрыть"
	close_button.pressed.connect(toggle_settings)
	column.add_child(close_button)


func toggle_settings():
	settings_panel.visible = not settings_panel.visible

	if settings_panel.visible:
		edit_mode = false
		edit_button.text = "Переместить кнопки"


func _on_mode_selected(index: int):
	match index:
		0:
			active_mode = "touch"
			touch_ui.visible = true
		1:
			active_mode = "keyboard"
			touch_ui.visible = false
		2:
			active_mode = "gamepad"
			touch_ui.visible = false


func _on_size_changed(value: float):
	size_level = int(value)
	layout_controls()
	save_control_settings()


func toggle_edit_mode():
	edit_mode = not edit_mode

	if edit_mode:
		edit_button.text = "Готово"
	else:
		edit_button.text = "Переместить кнопки"
		drag_target = null

	save_control_settings()


func reset_controls():
	custom_positions.clear()
	layout_controls()
	save_control_settings()


func button_scale() -> float:
	return 0.65 + (size_level - 1) * 0.12


func layout_controls():
	if not is_instance_valid(ui_root) or not is_instance_valid(stick_visual):
		return

	var screen = get_viewport().get_visible_rect().size
	var scale_factor = button_scale()
	var button_size = Vector2(76, 76) * scale_factor
	var margin = 18.0

	stick_visual.position = Vector2(margin, screen.y - 190 - margin)
	stick_visual.size = Vector2(170, 170)

	menu_button.position = Vector2(screen.x - 76, 16)
	menu_button.size = Vector2(60, 60)

	for button in control_buttons:
		button.size = button_size

		var normalized = default_positions[button]

		if custom_positions.has(button.name):
			normalized = custom_positions[button.name]

		button.position = Vector2(
			normalized.x * screen.x - button_size.x / 2.0,
			normalized.y * screen.y - button_size.y / 2.0
		)

		button.add_theme_font_size_override("font_size", int(34 * scale_factor))

		clamp_button(button)


func clamp_button(button: Button):
	var screen = get_viewport().get_visible_rect().size
	button.position.x = clamp(button.position.x, 4.0, max(4.0, screen.x - button.size.x - 4.0))
	button.position.y = clamp(button.position.y, 4.0, max(4.0, screen.y - button.size.y - 4.0))


func _on_control_gui_input(event: InputEvent, button: Button):
	if not edit_mode:
		return

	if event is InputEventScreenTouch and event.pressed:
		drag_target = button
		drag_offset = event.position - button.position
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and event.pressed:
		drag_target = button
		drag_offset = event.position
		get_viewport().set_input_as_handled()


func _input(event):
	if event is InputEventScreenDrag and drag_target != null and edit_mode:
		var old_position = drag_target.position
		drag_target.position = event.position - drag_offset
		clamp_button(drag_target)

		if buttons_overlap(drag_target):
			drag_target.position = old_position

		get_viewport().set_input_as_handled()

	elif event is InputEventScreenTouch and not event.pressed:
		drag_target = null

	elif event is InputEventMouseMotion and drag_target != null and edit_mode:
		var old_position = drag_target.position
		drag_target.position = event.position - drag_offset
		clamp_button(drag_target)

		if buttons_overlap(drag_target):
			drag_target.position = old_position

	elif event is InputEventMouseButton and not event.pressed:
		drag_target = null

	elif event is InputEventScreenTouch:
		if event.pressed:
			if settings_panel.visible or menu_button.get_global_rect().has_point(event.position):
				return

			if edit_mode:
				return

			if event.position.x < get_viewport().get_visible_rect().size.x * 0.48:
				if joystick_finger == -1:
					joystick_finger = event.index
					update_joystick(event.position)
			else:
				look_finger = event.index
				active_mode = "touch"
				touch_ui.visible = true

		else:
			if event.index == joystick_finger:
				joystick_finger = -1
				joystick = Vector2.ZERO
				stick_visual.value = Vector2.ZERO
				stick_visual.queue_redraw()

			if event.index == look_finger:
				look_finger = -1

	elif event is InputEventScreenDrag:
		if event.index == joystick_finger:
			update_joystick(event.position)
		elif event.index == look_finger and not edit_mode:
			rotate_camera(event.relative)

	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_camera(event.relative)

	elif event is InputEventKey and event.pressed:
		active_mode = "keyboard"


func buttons_overlap(button: Button) -> bool:
	for other in control_buttons:
		if other == button:
			continue

		if button.get_rect().intersects(other.get_rect()):
			return true

	return false


func update_joystick(pos: Vector2):
	var center = stick_visual.global_position + stick_visual.size / 2.0
	var offset = pos - center
	joystick = (offset / 75.0).limit_length(1.0)

	if joystick.length() < 0.12:
		joystick = Vector2.ZERO

	stick_visual.value = joystick
	stick_visual.queue_redraw()


func rotate_camera(delta_input: Vector2):
	head.rotate_y(-delta_input.x * sensitivity)
	camera.rotation.x -= delta_input.y * sensitivity
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))


func save_control_settings():
	var config = ConfigFile.new()
	config.set_value("controls", "size", size_level)

	for button in control_buttons:
		if is_instance_valid(button):
			var screen = get_viewport().get_visible_rect().size
			config.set_value(
				"positions",
				button.name,
				Vector2(
					(button.position.x + button.size.x / 2.0) / screen.x,
					(button.position.y + button.size.y / 2.0) / screen.y
				)
			)

	config.save("user://controls.cfg")


func load_control_settings():
	var config = ConfigFile.new()

	if config.load("user://controls.cfg") != OK:
		return

	size_level = int(config.get_value("controls", "size", 6))

	for button in control_buttons:
		var position = config.get_value("positions", button.name, null)
		if position != null:
			custom_positions[button.name] = position

	if is_instance_valid(size_slider):
		size_slider.value = size_level


func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		call_deferred("layout_controls")


func _physics_process(delta):
	if not is_instance_valid(player):
		return

	var crouching = crouch_pressed or Input.is_action_pressed("crouch")

	var capsule = player.get_node("CollisionShape3D")
	if crouching:
		capsule.shape.height = 1.15
		head.position.y = 0.35
	else:
		capsule.shape.height = 1.8
		head.position.y = 0.65

	if not player.is_on_floor():
		player.velocity.y -= gravity * delta
	else:
		if jump_requested or Input.is_action_just_pressed("jump"):
			if not crouching:
				player.velocity.y = jump_velocity

	jump_requested = false

	var input_dir := Vector2.ZERO

	if active_mode == "touch":
		input_dir = joystick
	elif active_mode == "keyboard":
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	elif active_mode == "gamepad":
		for id in Input.get_connected_joypads():
			input_dir = Vector2(
				Input.get_joy_axis(id, JOY_AXIS_LEFT_X),
				Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
			)
			if input_dir.length() > 0.2:
				break

	var direction = (
		head.global_basis.x * input_dir.x
		+ head.global_basis.z * input_dir.y
	).normalized()

	var current_speed = walk_speed

	if crouching:
		current_speed = crouch_speed
	elif (active_mode == "touch" and run_pressed) or (active_mode == "keyboard" and Input.is_action_pressed("sprint")):
		current_speed = sprint_speed

	
