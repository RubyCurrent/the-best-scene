
extends Node3D

var player: CharacterBody3D
var head: Node3D
var camera: Camera3D

var gravity := 20.0
var walk_speed := 5.0
var sprint_speed := 8.5
var crouch_speed := 2.5
var jump_velocity := 5.2
var sensitivity := 0.0025

var active_mode := "touch"
var joystick := Vector2.ZERO
var joystick_finger := -1
var look_finger := -1
var drag_finger := -1

var run_pressed := false
var crouch_pressed := false
var jump_requested := false

var touch_ui: CanvasLayer
var ui_root: Control
var stick_visual: StickVisual

var jump_button: Button
var run_button: Button
var crouch_button: Button
var menu_button: Button

var settings_panel: PanelContainer
var size_slider: HSlider
var shape_select: OptionButton
var color_picker: ColorPickerButton
var edit_button: Button

var size_level := 7
var button_shape := "circle"
var button_color := Color(0.12, 0.42, 0.85, 0.9)

var edit_mode := false
var drag_target: Button
var drag_offset := Vector2.ZERO

var control_buttons: Array[Button] = []
var custom_positions := {}
var default_positions := {}

var house_light: OmniLight3D


class StickVisual extends Control:
	var value := Vector2.ZERO

	func _draw():
		var center := size / 2.0
		var radius := min(size.x, size.y) * 0.42

		draw_circle(center, radius, Color(0.02, 0.03, 0.06, 0.7))
		draw_arc(center, radius, 0, TAU, 64, Color(0.7, 0.82, 1.0, 0.8), 4.0)

		draw_circle(center + value * radius * 0.55, radius * 0.38, Color(0.55, 0.72, 1.0, 0.95))
		draw_arc(center + value * radius * 0.55, radius * 0.38, 0, TAU, 48, Color.WHITE, 2.0)


func _ready():
	create_input_actions()
	create_world()
	create_house()
	create_player()
	create_touch_controls()
	load_control_settings()
	layout_controls()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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

		var key_event := InputEventKey.new()
		key_event.physical_keycode = actions[action]
		InputMap.action_add_event(action, key_event)


func make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material


func add_box(box_name: String, box_size: Vector3, box_position: Vector3, color: Color, solid := true):
	var body: Node3D

	if solid:
		body = StaticBody3D.new()
	else:
		body = Node3D.new()

	body.name = box_name
	body.position = box_position

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = make_material(color)
	body.add_child(mesh_instance)

	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box_size
		collision.shape = shape
		body.add_child(collision)

	add_child(body)


func create_world():
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()

	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.006, 0.009, 0.025)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.38, 0.42, 0.58)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	environment_node.environment = environment
	add_child(environment_node)

	add_box("Ground", Vector3(150, 0.5, 150), Vector3(0, -0.35, 0), Color(0.025, 0.04, 0.05))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_color = Color(0.55, 0.62, 0.9)
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	add_child(sun)


func create_house():
	var wall := Color(0.22, 0.19, 0.17)
	var floor := Color(0.34, 0.24, 0.16)
	var wood := Color(0.12, 0.075, 0.045)

	add_box("Floor", Vector3(14, 0.2, 10), Vector3(0, 0.1, 0), floor)

	add_box("Back Wall Left", Vector3(5.5, 3.4, 0.4), Vector3(-4.25, 1.8, -5), wall)
	add_box("Back Wall Right", Vector3(5.5, 3.4, 0.4), Vector3(4.25, 1.8, -5), wall)
	add_box("Back Wall Top", Vector3(3, 1.4, 0.4), Vector3(0, 2.8, -5), wall)
	add_box("Back Wall Bottom", Vector3(3, 0.8, 0.4), Vector3(0, 0.5, -5), wall)

	add_box("Left Wall", Vector3(0.4, 3.4, 10), Vector3(-7, 1.8, 0), wall)
	add_box("Right Wall", Vector3(0.4, 3.4, 10), Vector3(7, 1.8, 0), wall)

	add_box("Front Wall Left", Vector3(5.8, 3.4, 0.4), Vector3(-4.1, 1.8, 5), wall)
	add_box("Front Wall Right", Vector3(5.8, 3.4, 0.4), Vector3(4.1, 1.8, 5), wall)
	add_box("Door Header", Vector3(2.4, 1.1, 0.4), Vector3(0, 3.0, 5), wall)

	add_box("Ceiling", Vector3(14.4, 0.3, 10.4), Vector3(0, 3.55, 0), Color(0.12, 0.105, 0.10))

	var glass_material := StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.025, 0.055, 0.16)
	glass_material.emission_enabled = true
	glass_material.emission = Color(0.025, 0.045, 0.13)
	glass_material.emission_energy_multiplier = 0.8

	var glass := MeshInstance3D.new()
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(2.8, 1.15, 0.06)
	glass.mesh = glass_mesh
	glass.material_override = glass_material
	glass.position = Vector3(0, 2.0, -4.76)
	add_child(glass)

	house_light = OmniLight3D.new()
	house_light.position = Vector3(0, 3.0, 0)
	house_light.light_color = Color(1.0, 0.72, 0.42)
	house_light.light_energy = 2.4
	house_light.omni_range = 15.0
	house_light.shadow_enabled = true
	add_child(house_light)

	add_box("Table", Vector3(2.2, 0.15, 1.2), Vector3(-3.5, 1.0, -1.5), wood)
	add_box("Bed", Vector3(2.5, 0.45, 3.0), Vector3(3.8, 0.45, -2.5), wood)
	add_box("Mattress", Vector3(2.4, 0.25, 2.9), Vector3(3.8, 0.8, -2.5), Color(0.42, 0.44, 0.52))
	add_box("Pillow", Vector3(1.0, 0.2, 0.55), Vector3(3.8, 1.02, -3.55), Color(0.82, 0.82, 0.88))

	for i in range(6):
		var height := 0.18 * float(i + 1)
		var depth := 0.42
		add_box(
			"Stair %d" % i,
			Vector3(1.8, height, depth),
			Vector3(-4.8, height / 2.0, 2.5 - i * depth),
			Color(0.25, 0.15, 0.09)
		)

	add_box("Cabinet", Vector3(1.4, 1.5, 0.7), Vector3(5.2, 0.85, 1.0), wood)


func create_player():
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 1.2, 1.5)
	player.floor_snap_length = 0.3
	add_child(player)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
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


func create_touch_controls():
	touch_ui = CanvasLayer.new()
	touch_ui.name = "TouchControls"
	add_child(touch_ui)

	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
	touch_ui.add_child(ui_root)

	stick_visual = StickVisual.new()
	stick_visual.name = "Joystick"
	stick_visual.size = Vector2(190, 190)
	stick_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(stick_visual)

	jump_button = Button.new()
	jump_button.name = "JumpButton"
	jump_button.text = "^"
	ui_root.add_child(jump_button)
	jump_button.pressed.connect(func(): jump_requested = true)

	run_button = Button.new()
	run_button.name = "RunButton"
	run_button.text = "»"
	ui_root.add_child(run_button)
	run_button.button_down.connect(func(): run_pressed = true)
	run_button.button_up.connect(func(): run_pressed = false)

	crouch_button = Button.new()
	crouch_button.name = "CrouchButton"
	crouch_button.text = "⌄"
	ui_root.add_child(crouch_button)
	crouch_button.button_down.connect(func(): crouch_pressed = true)
	crouch_button.button_up.connect(func(): crouch_pressed = false)

	menu_button = Button.new()
	menu_button.name = "MenuButton"
	menu_button.text = "⚙"
	menu_button.size = Vector2(60, 60)
	ui_root.add_child(menu_button)
	menu_button.pressed.connect(toggle_settings)

	control_buttons = [jump_button, run_button, crouch_button]

	default_positions = {
		"JumpButton": Vector2(0.86, 0.55),
		"RunButton": Vector2(0.86, 0.84),
		"CrouchButton": Vector2(0.65, 0.84)
	}

	create_settings_menu()
	refresh_button_styles()


func create_settings_menu():
	settings_panel = PanelContainer.new()
	settings_panel.visible = false
	settings_panel.position = Vector2(16, 82)
	settings_panel.custom_minimum_size = Vector2(300, 440)
	ui_root.add_child(settings_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.045, 0.075, 0.98)
	panel_style.set_corner_radius_all(18)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.35, 0.45, 0.65)
	settings_panel.add_theme_stylebox_override("panel", panel_style)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(290, 420)
	settings_panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 9)
	scroll.add_child(column)

	var title := Label.new()
	title.text = "НАСТРОЙКИ УПРАВЛЕНИЯ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	column.add_child(title)

	var mode_label := Label.new()
	mode_label.text = "Тип управления"
	column.add_child(mode_label)

	var mode_select := OptionButton.new()
	mode_select.add_item("Сенсорное")
	mode_select.add_item("Клавиатура")
	mode_select.add_item("Геймпад")
	mode_select.item_selected.connect(_on_mode_selected)
	column.add_child(mode_select)

	var size_label := Label.new()
	size_label.text = "Размер кнопок: 1–10"
	column.add_child(size_label)

	size_slider = HSlider.new()
	size_slider.min_value = 1
	size_slider.max_value = 10
	size_slider.step = 1
	size_slider.value = size_level
	size_slider.value_changed.connect(_on_size_changed)
	column.add_child(size_slider)

	var shape_label := Label.new()
	shape_label.text = "Форма кнопок"
	column.add_child(shape_label)

	shape_select = OptionButton.new()
	shape_select.add_item("Круг")
	shape_select.add_item("Квадрат")
	shape_select.item_selected.connect(_on_shape_selected)
	column.add_child(shape_select)

	var color_label := Label.new()
	color_label.text = "Цвет кнопок"
	column.add_child(color_label)

	color_picker = ColorPickerButton.new()
	color_picker.color = button_color
	color_picker.custom_minimum_size = Vector2(0, 42)
	color_picker.color_changed.connect(_on_color_changed)
	column.add_child(color_picker)

	edit_button = Button.new()
	edit_button.text = "Переместить кнопки"
	edit_button.pressed.connect(toggle_edit_mode)
	column.add_child(edit_button)

	var reset_button := Button.new()
	reset_button.text = "Сбросить расположение"
	reset_button.pressed.connect(reset_controls)
	column.add_child(reset_button)

	var close_button := Button.new()
	close_button.text = "Закрыть"
	close_button.pressed.connect(toggle_settings)
	column.add_child(close_button)


func style_button(button: Button, color: Color):
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 36)

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(2)
	style.border_color = Color(0.88, 0.93, 1.0, 0.85)

	var radius := int(button.size.x / 2.0) if button_shape == "circle" else 12
	style.set_corner_radius_all(radius)

	button.add_theme_stylebox_override("normal", style)

	var pressed := style.duplicate()
	pressed.bg_color = color.darkened(0.38)
	button.add_theme_stylebox_override("pressed", pressed)

	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.18)
	button.add_theme_stylebox_override("hover", hover)


func refresh_button_styles():
	if not is_instance_valid(jump_button):
		return

	style_button(jump_button, button_color)
	style_button(run_button, button_color)
	style_button(crouch_button, button_color)
	style_button(menu_button, Color(0.12, 0.14, 0.20, 0.94))


func button_scale() -> float:
	return 0.72 + float(size_level - 1) * 0.105


func layout_controls():
	if not is_instance_valid(ui_root):
		return

	var screen := get_viewport().get_visible_rect().size
	var margin := 12.0

	var side := 76.0 * button_scale()
	side = min(side, screen.x * 0.29)
	side = min(side, screen.y * 0.23)
	side = max(side, 42.0)

	stick_visual.size = Vector2(190, 190)
	stick_visual.position = Vector2(margin, max(margin, screen.y - 202))

	menu_button.size = Vector2(60, 60)
	menu_button.position = Vector2(max(margin, screen.x - 72), margin)

	for button in control_buttons:
		button.size = Vector2(side, side)

		var normalized: Vector2 = default_positions[button.name]
		if custom_positions.has(button.name):
			normalized = custom_positions[button.name]

		button.position = Vector2(
			normalized.x * screen.x - side / 2.0,
			normalized.y * screen.y - side / 2.0
		)

		button.add_theme_font_size_override("font_size", int(side * 0.48))
		clamp_button(button)

	refresh_button_styles()


func clamp_button(button: Button):
	var screen := get_viewport().get_visible_rect().size
	button.position.x = clampf(button.position.x, 4.0, maxf(4.0, screen.x - button.size.x - 4.0))
	button.position.y = clampf(button.position.y, 4.0, maxf(4.0, screen.y - button.size.y - 4.0))


func toggle_settings():
	settings_panel.visible = not settings_panel.visible

	if settings_panel.visible:
		edit_mode = false
		drag_target = null
		drag_finger = -1
		edit_button.text = "Переместить кнопки"
		save_control_settings()


func toggle_edit_mode():
	edit_mode = not edit_mode
	drag_target = null
	drag_finger = -1

	if edit_mode:
		edit_button.text = "Готово"
	else:
		edit_button.text = "Переместить кнопки"
		save_control_settings()


func _on_mode_selected(index: int):
	match index:
		0:
			active_mode = "touch"
			touch_ui.visible = true
		1:
			active_mode = "keyboard"
			touch_ui.visible = true
		2:
			active_mode = "gamepad"
			touch_ui.visible = true


func _on_size_changed(value: float):
	size_level = int(value)
	layout_controls()
	save_control_settings()


func _on_shape_selected(index: int):
	button_shape = "circle" if index == 0 else "square"
	refresh_button_styles()
	save_control_settings()


func _on_color_changed(value: Color):
	button_color = value
	refresh_button_styles()
	save_control_settings()


func reset_controls():
	custom_positions.clear()
	layout_controls()
	save_control_settings()


func is_over_button(position: Vector2) -> bool:
	for button in control_buttons:
		if button.get_global_rect().has_point(position):
			return true
	return false


func buttons_overlap(button: Button) -> bool:
	for other in control_buttons:
		if other == button:
			continue

		var first := Rect2(button.position, button.size)
		var second := Rect2(other.position, other.size)

		if first.intersects(second):
			return true

	return false


func move_dragged_button(position: Vector2):
	if not is_instance_valid(drag_target):
		return

	var old_position := drag_target.position
	drag_target.position = position
	clamp_button(drag_target)

	if buttons_overlap(drag_target):
		drag_target.position = old_position


func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if edit_mode:
				for button in control_buttons:
					if button.get_global_rect().has_point(event.position):
						drag_target = button
						drag_finger = event.index
						drag_offset = event.position - button.position
						get_viewport().set_input_as_handled()
						return
			else:
				if settings_panel.visible:
					return

				if menu_button.get_global_rect().has_point(event.position):
					return

				if is_over_button(event.position):
					return

				if event.position.x < get_viewport().get_visible_rect().size.x * 0.48:
					if joystick_finger == -1:
						joystick_finger = event.index
						update_joystick(event.position)
				elif look_finger == -1:
					look_finger = event.index

		else:
			if edit_mode and event.index == drag_finger:
				drag_target = null
				drag_finger = -1
				get_viewport().set_input_as_handled()
				return

			if event.index == joystick_finger:
				joystick_finger = -1
				joystick = Vector2.ZERO
				stick_visual.value = Vector2.ZERO
				stick_visual.queue_redraw()

			if event.index == look_finger:
				look_finger = -1

	elif event is InputEventScreenDrag:
		if edit_mode and drag_target != null and event.index == drag_finger:
			move_dragged_button(event.position - drag_offset)
			get_viewport().set_input_as_handled()
		elif event.index == joystick_finger:
			update_joystick(event.position)
		elif event.index == look_finger and not edit_mode:
			rotate_camera(event.screen_relative)

	elif event is InputEventMouseButton:
		if edit_mode and event.pressed:
			for button in control_buttons:
				if button.get_global_rect().has_point(event.position):
					drag_target = button
					drag_offset = event.position - button.position
					get_viewport().set_input_as_handled()
					return

		elif edit_mode and not event.pressed:
			drag_target = null
			save_control_settings()

	elif event is InputEventMouseMotion:
		if edit_mode and drag_target != null:
			move_dragged_button(event.position - drag_offset)
			get_viewport().set_input_as_handled()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_camera(event.relative)

	elif event is InputEventKey and event.pressed:
		active_mode = "keyboard"


func update_joystick(position: Vector2):
	var center := stick_visual.global_position + stick_visual.size / 2.0
	var radius := min(stick_visual.size.x, stick_visual.size.y) * 0.40

	joystick = ((position - center) / radius).limit_length(1.0)

	if joystick.length() < 0.12:
		joystick = Vector2.ZERO

	stick_visual.value = joystick
	stick_visual.queue_redraw()


func rotate_camera(delta_input: Vector2):
	head.rotate_y(-delta_input.x * sensitivity)
	camera.rotation.x -= delta_input.y * sensitivity
	camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))


func save_control_settings():
	var config := ConfigFile.new()

	config.set_value("controls", "size", size_level)
	config.set_value("controls", "shape", button_shape)
	config.set_value("controls", "color", button_color)

	var screen := get_viewport().get_visible_rect().size

	for button in control_buttons:
		config.set_value(
			"positions",
			button.name,
			Vector2(
				(button.position.x + button.size.x / 2.0) / maxf(1.0, screen.x),
				(button.position.y + button.size.y / 2.0) / maxf(1.0, screen.y)
			)
		)

	config.save("user://controls.cfg")


func load_control_settings():
	var config := ConfigFile.new()

	if config.load("user://controls.cfg") != OK:
		return

	size_level = clampi(int(config.get_value("controls", "size", 7)), 1, 10)
	button_shape = str(config.get_value("controls", "shape", "circle"))
	button_color = config.get_value("controls", "color", button_color)

	for button in control_buttons:
		var saved_position = config.get_value("positions", button.name, null)
		if saved_position != null:
			custom_positions[button.name] = saved_position

	size_slider.value = size_level
	shape_select.select(0 if button_shape == "circle" else 1)
	color_picker.color = button_color

	refresh_button_styles()


func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		call_deferred("layout_controls")


func _physics_process(delta):
	if not is_instance_valid(player):
		return

	var crouching := crouch_pressed or Input.is_action_pressed("crouch")

	var collision := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D

	if crouching:
		capsule.height = 1.15
		head.position.y = 0.35
	else:
		capsule.height = 1.8
		head.position.y = 0.65

	if not player.is_on_floor():
		player.velocity.y -= gravity * delta
	else:
		if (jump_requested or Input.is_action_just_pressed("jump")) and not crouching:
			player.velocity.y = jump_
