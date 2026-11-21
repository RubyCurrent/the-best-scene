
extends Node3D

class TouchStickVisual extends Control:
	var value := Vector2.ZERO

	func _draw():
		var center = size / 2.0
		draw_circle(center, 78.0, Color(0.05, 0.07, 0.10, 0.65))
		draw_arc(center, 78.0, 0, TAU, 64, Color(0.8, 0.85, 1.0, 0.65), 3.0)
		draw_circle(center + value * 48.0, 29.0, Color(0.85, 0.9, 1.0, 0.9))


var player: CharacterBody3D
var head: Node3D
var camera: Camera3D

var gravity := 18.0
var walk_speed := 5.0
var sprint_speed := 8.5
var jump_velocity := 5.0
var sensitivity := 0.0025

var active_mode := "keyboard"
var joystick := Vector2.ZERO
var joystick_finger := -1
var look_finger := -1
var run_pressed := false
var jump_requested := false

var touch_ui: CanvasLayer
var stick_visual: TouchStickVisual
var jump_button: Button
var run_button: Button


func _ready():
	create_world()
	create_house()
	create_player()
	create_touch_controls()

	if DisplayServer.is_touchscreen_available():
		active_mode = "touch"
		touch_ui.visible = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func make_material(color: Color, roughness := 0.85) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func add_box(box_name: String, box_size: Vector3, box_position: Vector3, color: Color, solid := true):
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

	add_child(body)
	return body


func create_world():
	var environment = WorldEnvironment.new()
	var world = Environment.new()

	world.background_mode = Environment.BG_COLOR
	world.background_color = Color(0.008, 0.012, 0.035)
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color(0.22, 0.25, 0.38)
	world.ambient_light_energy = 0.25

	environment.environment = world
	add_child(environment)

	add_box(
		"Outside Ground",
		Vector3(120, 0.5, 120),
		Vector3(0, -0.3, 0),
		Color(0.025, 0.035, 0.04)
	)

	var moon = DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -25, 0)
	moon.light_color = Color(0.35, 0.42, 0.65)
	moon.light_energy = 0.18
	add_child(moon)


func create_house():
	var wall_color = Color(0.22, 0.19, 0.17)
	var floor_color = Color(0.30, 0.22, 0.16)
	var ceiling_color = Color(0.12, 0.11, 0.12)

	# Пол дома
	add_box(
		"House Floor",
		Vector3(14, 0.2, 10),
		Vector3(0, 0.1, 0),
		floor_color
	)

	# Задняя стена с окном
	add_box("Back Wall Left", Vector3(5.5, 3.4, 0.4), Vector3(-4.25, 1.8, -5), wall_color)
	add_box("Back Wall Right", Vector3(5.5, 3.4, 0.4), Vector3(4.25, 1.8, -5), wall_color)
	add_box("Back Window Top", Vector3(3, 1.4, 0.4), Vector3(0, 2.8, -5), wall_color)
	add_box("Back Window Bottom", Vector3(3, 0.8, 0.4), Vector3(0, 0.5, -5), wall_color)

	# Боковые стены
	add_box("Left Wall", Vector3(0.4, 3.4, 10), Vector3(-7, 1.8, 0), wall_color)
	add_box("Right Wall", Vector3(0.4, 3.4, 10), Vector3(7, 1.8, 0), wall_color)

	# Передняя стена с дверным проёмом
	add_box("Front Wall Left", Vector3(5.8, 3.4, 0.4), Vector3(-4.1, 1.8, 5), wall_color)
	add_box("Front Wall Right", Vector3(5.8, 3.4, 0.4), Vector3(4.1, 1.8, 5), wall_color)
	add_box("Door Header", Vector3(2.4, 1.1, 0.4), Vector3(0, 3.0, 5), wall_color)

	# Потолок
	add_box(
		"Ceiling",
		Vector3(14.4, 0.3, 10.4),
		Vector3(0, 3.55, 0),
		ceiling_color
	)

	# Стекло окна
	var glass_material = StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.04, 0.09, 0.22, 0.65)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.emission_enabled = true
	glass_material.emission = Color(0.015, 0.035, 0.12)
	glass_material.emission_energy_multiplier = 0.5

	var glass = MeshInstance3D.new()
	var glass_mesh = BoxMesh.new()
	glass_mesh.size = Vector3(2.8, 1.15, 0.06)
	glass.mesh = glass_mesh
	glass.material_override = glass_material
	glass.position = Vector3(0, 2.0, -4.76)
	add_child(glass)

	# Оконная рама
	add_box("Window Frame Top", Vector3(3, 0.12, 0.15), Vector3(0, 2.65, -4.65), Color(0.08, 0.07, 0.06), false)
	add_box("Window Frame Bottom", Vector3(3, 0.12, 0.15), Vector3(0, 1.35, -4.65), Color(0.08, 0.07, 0.06), false)
	add_box("Window Frame Center", Vector3(0.12, 1.3, 0.15), Vector3(0, 2.0, -4.65), Color(0.08, 0.07, 0.06), false)

	# Внутренний свет
	var lamp = OmniLight3D.new()
	lamp.position = Vector3(0, 3.0, 0)
	lamp.light_color = Color(1.0, 0.72, 0.42)
	lamp.light_energy = 1.8
	lamp.omni_range = 13.0
	lamp.omni_attenuation = 1.4
	add_child(lamp)

	# Лампа на потолке
	add_box("Ceiling Lamp", Vector3(0.7, 0.12, 0.7), Vector3(0, 3.32, 0), Color(1.0, 0.75, 0.4), false)

	# Стол
	add_box("Table Top", Vector3(2.2, 0.15, 1.2), Vector3(-3.5, 1.0, -1.5), Color(0.24, 0.12, 0.07))
	add_box("Table Leg 1", Vector3(0.15, 1.0, 0.15), Vector3(-4.4, 0.5, -1.9), Color(0.12, 0.07, 0.04))
	add_box("Table Leg 2", Vector3(0.15, 1.0, 0.15), Vector3(-2.6, 0.5, -1.9), Color(0.12, 0.07, 0.04))
	add_box("Table Leg 3", Vector3(0.15, 1.0, 0.15), Vector3(-4.4, 0.5, -1.1), Color(0.12, 0.07, 0.04))
	add_box("Table Leg 4", Vector3(0.15, 1.0, 0.15), Vector3(-2.6, 0.5, -1.1), Color(0.12, 0.07, 0.04))

	# Кровать
	add_box("Bed Base", Vector3(2.5, 0.45, 3.0), Vector3(3.8, 0.45, -2.5), Color(0.16, 0.12, 0.10))
	add_box("Bed Mattress", Vector3(2.4, 0.25, 2.9), Vector3(3.8, 0.8, -2.5), Color(0.55, 0.55, 0.62))
	add_box("Pillow", Vector3(1.0, 0.2, 0.55), Vector3(3.8, 1.02, -3.55), Color(0.85, 0.85, 0.9))


func create_player():
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 1.2, 1.5)
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
	camera.position.y = 0.25
	camera.fov = 80.0
	head.add_child(camera)


func style_button(button: Button, color: Color):
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)

	var normal = StyleBoxFlat.new()
	normal.bg_color = color
	normal.corner_radius_top_left = 18
	normal.corner_radius_top_right = 18
	normal.corner_radius_bottom_left = 18
	normal.corner_radius_bottom_right = 18
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(1, 1, 1, 0.45)

	button.add_theme_stylebox_override("normal", normal)

	var pressed = normal.duplicate()
	pressed.bg_color = color.darkened(0.35)
	button.add_theme_stylebox_override("pressed", pressed)


func create_touch_controls():
	touch_ui = CanvasLayer.new()
	touch_ui.name = "TouchControls"
	add_child(touch_ui)

	stick_visual = TouchStickVisual.new()
	stick_visual.name = "Joystick"
	stick_visual.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stick_visual.offset_left = 25
	stick_visual.offset_top = -205
	stick_visual.offset_right = 205
	stick_visual.offset_bottom = -25
	stick_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_ui.add_child(stick_visual)

	jump_button = Button.new()
	jump_button.text = "ПРЫЖОК"
	jump_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	jump_button.offset_left = -155
	jump_button.offset_top = -205
	jump_button.offset_right = -25
	jump_button.offset_bottom = -135
	jump_button.focus_mode = Control.FOCUS_NONE
	style_button(jump_button, Color(0.12, 0.38, 0.75, 0.85))
	touch_ui.add_child(jump_button)
	jump_button.pressed.connect(_on_jump_pressed)

	run_button = Button.new()
	run_button.text = "БЕГ"
	run_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	run_button.offset_left = -155
	run_button.offset_top = -120
	run_button.offset_right = -25
	run_button.offset_bottom = -50
	run_button.focus_mode = Control.FOCUS_NONE
	style_button(run_button, Color(0.12, 0.55, 0.25, 0.85))
	touch_ui.add_child(run_button)
	run_button.button_down.connect(_on_run_down)
	run_button.button_up.connect(_on_run_up)

	touch_ui.visible = DisplayServer.is_touchscreen_available()


func _on_jump_pressed():
	jump_requested = true


func _on_run_down():
	run_pressed = true


func _on_run_up():
	run_pressed = false


func is_touch_button_position(pos: Vector2) -> bool:
	if jump_button and jump_button.get_global_rect().has_point(pos):
		return true

	if run_button and run_button.get_global_rect().has_point(pos):
		return true

	return false


func _input(event):
	if event is InputEventKey:
		if event.pressed:
			active_mode = "keyboard"
			touch_ui.visible = false

	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			active_mode = "keyboard"
			rotate_camera(event.relative)

	elif event is InputEventMouseButton:
		if event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	elif event is InputEventScreenTouch:
		if event.pressed:
			if is_touch_button_position(event.position):
				return

			active_mode = "touch"
			touch_ui.visible = true

			if event.position.x < get_viewport().get_visible_rect().size.x * 0.5:
				if joystick_finger == -1:
					joystick_finger = event.index
					update_joystick(event.position)
			else:
				look_finger = event.index

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

		elif event.index == look_finger:
			if not is_touch_button_position(event.position):
				rotate_camera(event.relative)


func update_joystick(pos: Vector2):
	var center = stick_visual.global_position + stick_visual.size / 2.0
	var offset = pos - center

	joystick = (offset / 78.0).limit_length(1.0)

	if joystick.length() < 0.12:
		joystick = Vector2.ZERO

	stick_visual.value = joystick
	stick_visual.queue_redraw()


func rotate_camera(delta_input: Vector2):
	head.rotate_y(-delta_input.x * sensitivity)

	camera.rotation.x -= delta_input.y * sensitivity
	camera.rotation.x = clamp(
		camera.rotation.x,
		deg_to_rad(-85),
		deg_to_rad(85)
	)


func _physics_process(delta):
	if not player:
		return

	if not player.is_on_floor():
		player.velocity.y -= gravity * delta
	else:
		if jump_requested or Input.is_key_pressed(KEY_SPACE):
			player.velocity.y = jump_velocity

	jump_requested = false

	var input_dir := Vector2.ZERO

	if active_mode == "keyboard":
		input_dir = Input.get_vector(
			"ui_left",
			"ui_right",
			"ui_up",
			"ui_down"
		)

	elif active_mode == "touch":
		input_dir = joystick

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

	if active_mode == "keyboard" and Input.is_key_pressed(KEY_SHIFT):
		current_speed = sprint_speed
	elif active_mode == "touch" and run_pressed:
		current_speed = sprint_speed

	player.velocity.x = direction.x * current_speed
	player.velocity.z = direction.z * current_speed

	player.move_and_slide()
