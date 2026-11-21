extends Node3D

# ============================================================
# THE BEST SCENE
# Godot 4.4.1
# Полная переработанная версия
# ============================================================

const GAME_TITLE := "THE BEST SCENE"
const SAVE_PATH := "user://the_best_scene_save.json"
const SETTINGS_PATH := "user://the_best_scene_settings.json"

const WALK_SPEED := 4.0
const RUN_SPEED := 6.0
const CROUCH_SPEED := 1.8
const INTERACTION_DISTANCE := 3.5
const INVENTORY_LIMIT := 8
const WASH_DURATION := 35.0

var world: Node3D
var player: CharacterBody3D
var head: Node3D
var camera: Camera3D
var ray: RayCast3D
var flashlight: SpotLight3D
var monster: CharacterBody3D

var ui: CanvasLayer
var task_label: Label
var accuracy_label: Label
var message_label: Label
var target_label: Label
var inventory_box: HBoxContainer
var menu_panel: PanelContainer
var pause_panel: PanelContainer
var crosshair: Label

var inventory: Array[Dictionary] = []
var world_items: Array[Node3D] = []
var tasks: Dictionary = {}

var current_item := -1
var target: Node3D

var started := false
var paused := false
var crouching := false
var running := false
var flashlight_enabled := true

var wash_started := false
var wash_finished := false
var wash_timer := 0.0
var blood_cleaned := false
var monster_spawned := false
var monster_distance_timer := 0.0

var accuracy := 100.0
var game_seconds := 0.0
var message_seconds := 0.0

var joystick := Vector2.ZERO
var move_touch := -1
var look_touch := -1
var move_origin := Vector2.ZERO
var last_look := Vector2.ZERO

var run_touch := false
var crouch_touch := false
var jump_touch := false

var settings := {
	"sensitivity": 1.0,
	"subtitles": true,
	"show_crosshair": true
}

var random_generator := RandomNumberGenerator.new()


# ============================================================
# STARTUP
# ============================================================

func _ready() -> void:
	random_generator.randomize()
	setup_input()
	load_settings()
	create_environment()
	create_world()
	create_player()
	create_interface()
	show_main_menu()


func _process(delta: float) -> void:
	if message_seconds > 0.0:
		message_seconds -= delta
		if message_seconds <= 0.0 and is_instance_valid(message_label):
			message_label.text = ""

	if not started or paused:
		return

	game_seconds += delta

	if wash_started and not wash_finished:
		wash_timer += delta
		if wash_timer >= WASH_DURATION:
			finish_washing()

	update_target()
	update_hud()
	update_monster(delta)


func _physics_process(delta: float) -> void:
	if started and not paused and is_instance_valid(player):
		move_player(delta)


# ============================================================
# INPUT
# ============================================================

func setup_input() -> void:
	add_key("move_forward", KEY_W)
	add_key("move_back", KEY_S)
	add_key("move_left", KEY_A)
	add_key("move_right", KEY_D)
	add_key("run", KEY_SHIFT)
	add_key("crouch", KEY_CTRL)
	add_key("jump", KEY_SPACE)
	add_key("interact", KEY_E)
	add_key("drop_item", KEY_G)
	add_key("flashlight", KEY_F)

	for i in range(8):
		add_key("slot_" + str(i + 1), KEY_1 + i)


func add_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if started:
			toggle_pause()
		return

	if not started or paused:
		return

	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_camera(event.relative)

	if event is InputEventScreenTouch:
		screen_touch(event)

	if event is InputEventScreenDrag:
		screen_drag(event)

	if event.is_action_pressed("interact"):
		interact()

	if event.is_action_pressed("drop_item"):
		drop_item()

	if event.is_action_pressed("flashlight"):
		toggle_flashlight()

	if event.is_action_pressed("jump"):
		jump_touch = true

	if event.is_action_pressed("run"):
		run_touch = true
	if event.is_action_released("run"):
		run_touch = false

	if event.is_action_pressed("crouch"):
		crouch_touch = true
	if event.is_action_released("crouch"):
		crouch_touch = false

	for i in range(8):
		if event.is_action_pressed("slot_" + str(i + 1)):
			select_item(i)


func screen_touch(event: InputEventScreenTouch) -> void:
	var size := get_viewport().get_visible_rect().size
	var p := event.position

	if event.pressed:
		if p.x < size.x * 0.42 and p.y > size.y * 0.45:
			move_touch = event.index
			move_origin = p
			joystick = Vector2.ZERO
		elif p.x >= size.x * 0.42:
			look_touch = event.index
			last_look = p
	else:
		if event.index == move_touch:
			move_touch = -1
			joystick = Vector2.ZERO
		if event.index == look_touch:
			look_touch = -1


func screen_drag(event: InputEventScreenDrag) -> void:
	if event.index == move_touch:
		joystick = ((event.position - move_origin) / 75.0).limit_length(1.0)

	if event.index == look_touch:
		var difference := event.position - last_look
		last_look = event.position
		rotate_camera(difference)


func rotate_camera(delta_mouse: Vector2) -> void:
	if not is_instance_valid(head) or not is_instance_valid(camera):
		return

	var sensitivity := float(settings.get("sensitivity", 1.0))
	head.rotate_y(-delta_mouse.x * 0.002 * sensitivity)
	camera.rotate_x(-delta_mouse.y * 0.002 * sensitivity)
	camera.rotation.x = clampf(camera.rotation.x, -1.45, 1.45)


# ============================================================
# ENVIRONMENT AND MATERIALS
# ============================================================

func create_environment() -> void:
	var environment_node := WorldEnvironment.new()
	var env := Environment.new()

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.018, 0.022, 0.03)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.43, 0.48)
	env.ambient_light_energy = 0.42

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 5.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.13, 0.15)
	env.fog_density = 0.006

	env.ssr_enabled = true
	env.ssr_max_steps = 32
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0

	environment_node.environment = env
	add_child(environment_node)


func material(
	color: Color,
	roughness: float = 0.8,
	metallic: float = 0.0
) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result


func add_box(
	parent: Node3D,
	pos: Vector3,
	size: Vector3,
	mat: Material,
	collision_enabled: bool = true,
	object_name: String = "Object"
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = object_name
	body.position = pos
	parent.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)

	if collision_enabled:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)

	return body


func add_light(
	pos: Vector3,
	color: Color,
	energy: float,
	range_value: float,
	shadows: bool = true
) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.shadow_enabled = shadows
	world.add_child(light)


# ============================================================
# WORLD
# ============================================================

func create_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	var floor_mat := material(Color(0.19, 0.18, 0.17), 0.92)
	var wall_mat := material(Color(0.31, 0.30, 0.29), 0.95)
	var dark_wall := material(Color(0.12, 0.13, 0.15), 0.9)
	var wood := material(Color(0.22, 0.105, 0.055), 0.72)
	var metal := material(Color(0.34, 0.37, 0.4), 0.35, 0.65)

	# Главная комната
	add_box(world, Vector3(0, -0.25, 0),
		Vector3(18, 0.5, 18), floor_mat)

	# Коридор
	add_box(world, Vector3(0, -0.25, -19),
		Vector3(7.2, 0.5, 24), floor_mat)

	# Левая комната
	add_box(world, Vector3(-14, -0.25, -20),
		Vector3(12, 0.5, 12), floor_mat)

	# Правая комната
	add_box(world, Vector3(14, -0.25, -20),
		Vector3(12, 0.5, 12), floor_mat)

	# Прачечная
	add_box(world, Vector3(0, -0.25, -38),
		Vector3(14, 0.5, 14), floor_mat)

	create_room_walls(wall_mat, dark_wall)
	create_furniture(wood, metal)
	create_decor()
	create_world_lighting()
	create_initial_items()
	create_washing_machine()


func create_room_walls(wall: Material, dark: Material) -> void:
	# Наружные стены главной комнаты
	add_box(world, Vector3(0, 2, 9),
		Vector3(18, 4, 0.4), wall)
	add_box(world, Vector3(-9, 2, 0),
		Vector3(0.4, 4, 18), wall)
	add_box(world, Vector3(9, 2, 0),
		Vector3(0.4, 4, 18), wall)

	# Стены коридора
	add_box(world, Vector3(-3.7, 2, -19),
		Vector3(0.35, 4, 24), dark)
	add_box(world, Vector3(3.7, 2, -19),
		Vector3(0.35, 4, 24), dark)

	# Левая комната: оставляем проход снизу
	add_box(world, Vector3(-14, 2, -26),
		Vector3(12, 4, 0.35), wall)
	add_box(world, Vector3(-20, 2, -20),
		Vector3(0.35, 4, 12), wall)
	add_box(world, Vector3(-8, 2, -20),
		Vector3(0.35, 4, 12), wall)

	# Правая комната
	add_box(world, Vector3(14, 2, -26),
		Vector3(12, 4, 0.35), wall)
	add_box(world, Vector3(20, 2, -20),
		Vector3(0.35, 4, 12), wall)
	add_box(world, Vector3(8, 2, -20),
		Vector3(0.35, 4, 12), wall)

	# Прачечная
	add_box(world, Vector3(0, 2, -45),
		Vector3(14, 4, 0.35), dark)
	add_box(world, Vector3(-7, 2, -38),
		Vector3(0.35, 4, 14), dark)
	add_box(world, Vector3(7, 2, -38),
		Vector3(0.35, 4, 14), dark)


func create_furniture(wood: Material, metal: Material) -> void:
	# Кровать
	add_box(world, Vector3(-14, 0.45, -20),
		Vector3(3.7, 0.65, 4.2), wood, true, "BedFrame")

	add_box(world, Vector3(-14, 0.9, -20),
		Vector3(3.5, 0.3, 4.0),
		material(Color(0.48, 0.45, 0.42), 1.0))

	# Шкаф
	add_box(world, Vector3(14, 1.4, -23),
		Vector3(2.6, 2.8, 1.0), wood, true, "Wardrobe")

	# Диван
	add_box(world, Vector3(-5, 0.55, 2),
		Vector3(3.5, 1.1, 1.4),
		material(Color(0.18, 0.16, 0.16)))

	# Стол
	add_box(world, Vector3(5, 0.55, -3),
		Vector3(2.6, 0.18, 1.4), wood)

	for x in [-1.1, 1.1]:
		for z in [-0.5, 0.5]:
			add_box(world, Vector3(5 + x, 0.25, -3 + z),
				Vector3(0.12, 0.5, 0.12), metal)

	# Полки в прачечной
	add_box(world, Vector3(-4.8, 1.1, -40),
		Vector3(2.5, 0.12, 0.5), wood)
	add_box(world, Vector3(-4.8, 2.0, -40),
		Vector3(2.5, 0.12, 0.5), wood)


func create_decor() -> void:
	var picture_mat := material(Color(0.08, 0.09, 0.1), 0.7)
	var frame_mat := material(Color(0.24, 0.16, 0.1), 0.5)

	# Картина
	add_box(world, Vector3(0, 2.3, 8.75),
		Vector3(2.2, 1.4, 0.08), frame_mat, false)
	add_box(world, Vector3(0, 2.3, 8.68),
		Vector3(1.9, 1.1, 0.04), picture_mat, false)

	# Плинтусы
	var trim := material(Color(0.09, 0.08, 0.075), 0.8)
	add_box(world, Vector3(0, 0.12, 8.72),
		Vector3(17.5, 0.18, 0.12), trim, false)
	add_box(world, Vector3(-8.72, 0.12, 0),
		Vector3(0.12, 0.18, 17.5), trim, false)


func create_world_lighting() -> void:
	add_light(Vector3(0, 3.1, 0),
		Color(1.0, 0.78, 0.56), 0.8, 11.0)
	add_light(Vector3(0, 3.1, -17),
		Color(0.75, 0.82, 1.0), 0.65, 9.0)
	add_light(Vector3(-14, 3.0, -20),
		Color(1.0, 0.72, 0.52), 0.55, 9.0)
	add_light(Vector3(14, 3.0, -20),
		Color(0.72, 0.8, 1.0), 0.55, 9.0)
	add_light(Vector3(0, 3.0, -38),
		Color(0.7, 0.82, 1.0), 0.7, 10.0)


# ============================================================
# PLAYER
# ============================================================

func create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 0.2, 4)
	player.floor_snap_length = 0.25
	add_child(player)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	player.add_child(collision)

	head = Node3D.new()
	head.position.y = 1.58
	player.add_child(head)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 78.0
	camera.near = 0.05
	head.add_child(camera)

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -INTERACTION_DISTANCE)
	ray.collide_with_areas = true
	ray.collide_with_bodies = true
	ray.enabled = true
	camera.add_child(ray)

	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.1, -0.1, -0.2)
	flashlight.light_energy = 2.5
	flashlight.spot_range = 25.0
	flashlight.spot_angle = 38.0
	flashlight.shadow_enabled = true
	camera.add_child(flashlight)


func move_player(delta: float) -> void:
	var input_dir := Input.get_vector(
		"move_left", "move_right",
		"move_forward", "move_back"
	)

	if joystick.length() > 0.08:
		input_dir = joystick

	var direction := -head.global_basis.z * input_dir.y
	direction += head.global_basis.x * input_dir.x
	direction.y = 0.0
	direction = direction.normalized()

	crouching = crouch_touch or Input.is_action_pressed("crouch")
	running = (run_touch or Input.is_action_pressed("run")) and not crouching

	var speed := WALK_SPEED
	if running:
		speed = RUN_SPEED
	elif crouching:
		speed = CROUCH_SPEED

	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed

	if not player.is_on_floor():
		player.velocity.y -= 19.0 * delta
	elif jump_touch and not crouching:
		player.velocity.y = 5.0

	jump_touch = false

	var collision := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D

	if crouching:
		capsule.height = 1.15
		collision.position.y = 0.58
		head.position.y = 0.95
	else:
		capsule.height = 1.8
		collision.position.y = 0.9
		head.position.y = 1.58

	player.move_and_slide()


func toggle_flashlight() -> void:
	flashlight_enabled = not flashlight_enabled
	flashlight.visible = flashlight_enabled
	show_message("ФОНАРИК: " + ("ВКЛЮЧЁН" if flashlight_enabled else "ВЫКЛЮЧЕН"))


# ============================================================
# END OF PART 1
# ============================================================

# ============================================================
# ITEMS AND INVENTORY
# ============================================================

func create_item(
	item_id: String,
	display_name: String,
	pos: Vector3,
	color: Color,
	item_type: String = "general"
) -> Area3D:
	var item := Area3D.new()
	item.name = item_id
	item.position = pos
	item.collision_layer = 2
	item.collision_mask = 0

	item.set_meta("item_id", item_id)
	item.set_meta("display_name", display_name)
	item.set_meta("item_type", item_type)
	item.set_meta("interactable", true)

	world.add_child(item)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.28, 0.16, 0.25)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material(color, 0.55)
	item.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.3, 0.4)
	collision.shape = shape
	item.add_child(collision)

	world_items.append(item)
	return item


func create_initial_items() -> void:
	create_item(
		"dirty_clothes",
		"Грязная одежда",
		Vector3(-14, 0.35, -17),
		Color(0.35, 0.24, 0.2),
		"laundry"
	)

	create_item(
		"detergent",
		"Стиральный порошок",
		Vector3(2, 0.35, -37),
		Color(0.2, 0.5, 0.9),
		"laundry"
	)

	create_item(
		"rag",
		"Тряпка",
		Vector3(12, 0.35, -22),
		Color(0.8, 0.8, 0.75),
		"cleaning"
	)

	create_item(
		"key_bedroom",
		"Старый ключ",
		Vector3(-14, 0.35, -23),
		Color(0.85, 0.72, 0.25),
		"key"
	)


func pickup_item(item: Node3D) -> void:
	if inventory.size() >= INVENTORY_LIMIT:
		show_message("ИНВЕНТАРЬ ПОЛОН")
		return

	var id := str(item.get_meta("item_id", "unknown"))
	var display := str(item.get_meta("display_name", "Предмет"))
	var type := str(item.get_meta("item_type", "general"))

	var color := Color.WHITE
	var mesh := item.get_node_or_null("MeshInstance3D") as MeshInstance3D

	if mesh != null and mesh.material_override is StandardMaterial3D:
		color = mesh.material_override.albedo_color

	inventory.append({
		"id": id,
		"name": display,
		"type": type,
		"color": color.to_html(true)
	})

	world_items.erase(item)
	item.queue_free()

	current_item = inventory.size() - 1
	update_inventory()

	if id == "dirty_clothes":
		complete_task("clothes")
	elif id == "detergent":
		complete_task("detergent")
	elif id == "rag":
		complete_task("rag")

	show_message("ПОДОБРАНО: " + display)


func select_item(index: int) -> void:
	if index < 0 or index >= inventory.size():
		current_item = -1
	else:
		current_item = index

	update_inventory()


func drop_item() -> void:
	if current_item < 0 or current_item >= inventory.size():
		show_message("СНАЧАЛА ВЫБЕРИ ПРЕДМЕТ")
		return

	var data: Dictionary = inventory[current_item]
	var color := Color.from_string(
		str(data.get("color", "ffffff")),
		Color.WHITE
	)

	var drop_position := camera.global_position - camera.global_basis.z * 1.2
	drop_position.y = maxf(drop_position.y, 0.35)

	create_item(
		str(data["id"]),
		str(data["name"]),
		drop_position,
		color,
		str(data["type"])
	)

	inventory.remove_at(current_item)
	current_item = mini(current_item, inventory.size() - 1)
	update_inventory()

	show_message("ПРЕДМЕТ ВЫБРОШЕН")


func has_item(item_id: String) -> bool:
	for item in inventory:
		if str(item.get("id", "")) == item_id:
			return true
	return false


func remove_item(item_id: String) -> bool:
	for i in range(inventory.size() - 1, -1, -1):
		if str(inventory[i].get("id", "")) == item_id:
			inventory.remove_at(i)
			current_item = mini(current_item, inventory.size() - 1)
			update_inventory()
			return true
	return false


func update_inventory() -> void:
	if not is_instance_valid(inventory_box):
		return

	for child in inventory_box.get_children():
		child.queue_free()

	for i in range(INVENTORY_LIMIT):
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(62, 55)
		slot.text = str(i + 1)

		if i < inventory.size():
			slot.text = str(i + 1) + "\n" + str(inventory[i]["name"])
		else:
			slot.text = str(i + 1) + "\n—"

		if i == current_item:
			slot.modulate = Color(1.0, 0.85, 0.45)
		else:
			slot.modulate = Color.WHITE

		slot.pressed.connect(select_item.bind(i))
		inventory_box.add_child(slot)


# ============================================================
# INTERACTION
# ============================================================

func update_target() -> void:
	target = null

	if not is_instance_valid(ray):
		return

	ray.force_raycast_update()

	if ray.is_colliding():
		var collider := ray.get_collider() as Node
		var current := collider

		while current != null:
			if current.has_meta("item_id") or current.has_meta("action"):
				target = current as Node3D
				break
			current = current.get_parent()

	if not is_instance_valid(target):
		target_label.text = ""
		return

	target_label.text = "[E] " + str(
		target.get_meta("display_name", "Взаимодействовать")
	)


func interact() -> void:
	if not is_instance_valid(target):
		return

	if target.has_meta("item_id"):
		pickup_item(target)
		return

	var action := str(target.get_meta("action", ""))

	match action:
		"washing_machine":
			use_washing_machine()
		"blood":
			clean_blood()
		"exit":
			try_finish_game()
		_:
			show_message("С ЭТИМ НЕЛЬЗЯ ВЗАИМОДЕЙСТВОВАТЬ")


# ============================================================
# WASHING MACHINE
# ============================================================

func create_washing_machine() -> void:
	var machine := add_box(
		world,
		Vector3(0, 0.85, -42),
		Vector3(1.5, 1.7, 1.1),
		material(Color(0.48, 0.52, 0.56), 0.32, 0.45),
		true,
		"WashingMachine"
	)

	machine.set_meta("action", "washing_machine")
	machine.set_meta("display_name", "Стиральная машина")

	var door := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.4
	cylinder.bottom_radius = 0.4
	cylinder.height = 0.07
	door.mesh = cylinder
	door.position = Vector3(0, 0, -0.57)
	door.rotation_degrees.x = 90
	door.material_override = material(Color(0.035, 0.06, 0.08), 0.18, 0.25)
	machine.add_child(door)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.36
	ring_mesh.outer_radius = 0.43
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 0, -0.61)
	ring.rotation_degrees.x = 90
	ring.material_override = material(Color(0.72, 0.74, 0.76), 0.25, 0.8)
	machine.add_child(ring)


func use_washing_machine() -> void:
	if wash_started:
		if wash_finished:
			show_message("СТИРКА УЖЕ ЗАВЕРШЕНА")
		else:
			show_message("МАШИНА УЖЕ РАБОТАЕТ")
		return

	if not has_item("dirty_clothes"):
		show_message("НУЖНО НАЙТИ ГРЯЗНУЮ ОДЕЖДУ")
		return

	if not has_item("detergent"):
		show_message("НУЖЕН СТИРАЛЬНЫЙ ПОРОШОК")
		return

	remove_item("dirty_clothes")
	remove_item("detergent")

	wash_started = true
	wash_timer = 0.0

	complete_task("start_wash")
	show_message("СТИРКА ЗАПУЩЕНА. ПОДОЖДИТЕ.")


func finish_washing() -> void:
	if wash_finished:
		return

	wash_finished = true
	complete_task("wait_wash")

	create_blood(Vector3(0, 0.03, -41.0))
	spawn_monster(Vector3(0, 0.1, -30))

	show_message("ЧТО-ТО НЕ ТАК СО СТИРАЛЬНОЙ МАШИНОЙ...", 5.0)


func create_blood(pos: Vector3) -> void:
	var puddle := Area3D.new()
	puddle.name = "BloodPuddle"
	puddle.position = pos
	puddle.collision_layer = 2
	puddle.collision_mask = 0

	puddle.set_meta("action", "blood")
	puddle.set_meta("display_name", "Убрать пятно")

	world.add_child(puddle)

	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.75
	mesh.bottom_radius = 0.95
	mesh.height = 0.025
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material(
		Color(0.22, 0.015, 0.025),
		0.35
	)
	puddle.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.0
	shape.height = 0.2
	collision.shape = shape
	puddle.add_child(collision)


func clean_blood() -> void:
	if blood_cleaned:
		show_message("ЗДЕСЬ УЖЕ ЧИСТО")
		return

	if not has_item("rag"):
		show_message("НУЖНА ТРЯПКА")
		return

	if not wash_finished:
		show_message("СНАЧАЛА ДОЖДИТЕСЬ ОКОНЧАНИЯ СТИРКИ")
		return

	blood_cleaned = true
	remove_item("rag")

	var puddle := world.get_node_or_null("BloodPuddle")
	if is_instance_valid(puddle):
		puddle.queue_free()

	complete_task("clean_blood")
	show_message("ПЯТНО УБРАНО")


# ============================================================
# TASK SYSTEM
# ============================================================

func initialize_tasks() -> void:
	tasks = {
		"clothes": {
			"name": "Найдите грязную одежду",
			"done": false
		},
		"detergent": {
			"name": "Найдите стиральный порошок",
			"done": false
		},
		"rag": {
			"name": "Найдите тряпку",
			"done": false
		},
		"start_wash": {
			"name": "Загрузите вещи и запустите стирку",
			"done": false
		},
		"wait_wash": {
			"name": "Дождитесь окончания стирки",
			"done": false
		},
		"clean_blood": {
			"name": "Уберите странное пятно",
			"done": false
		}
	}


func complete_task(task_id: String) -> void:
	if not tasks.has(task_id):
		return

	if bool(tasks[task_id].get("done", false)):
		return

	tasks[task_id]["done"] = true
	update_hud()
	save_game()


func count_completed_tasks() -> int:
	var result := 0

	for key in tasks:
		if bool(tasks[key].get("done", false)):
			result += 1

	return result


func calculate_accuracy() -> float:
	var completed := count_completed_tasks()
	var total := tasks.size()

	if total <= 0:
		return 100.0

	# Процент определяется выполненными заданиями.
	return clampf(float(completed) / float(total) * 100.0, 0.0, 100.0)


# ============================================================
# MONSTER
# ============================================================

func spawn_monster(pos: Vector3) -> void:
	if monster_spawned:
		return

	monster_spawned = true

	monster = CharacterBody3D.new()
	monster.name = "TheWatcher"
	monster.position = pos
	monster.floor_snap_length = 0.2
	world.add_child(monster)

	var body_collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 2.1
	body_collision.shape = capsule
	body_collision.position.y = 1.05
	monster.add_child(body_collision)

	var body_mesh := MeshInstance3D.new()
	var body_shape := CapsuleMesh.new()
	body_shape.radius = 0.42
	body_shape.height = 2.1
	body_mesh.mesh = body_shape
	body_mesh.position.y = 1.05
	body_mesh.material_override = material(
		Color(0.025, 0.018, 0.025),
		0.95
	)
	monster.add_child(body_mesh)

	var eye_material := material(Color(0.65, 0.015, 0.02), 0.25)
	eye_material.emission_enabled = true
	eye_material.emission = Color(0.8, 0.01, 0.015)
	eye_material.emission_energy_multiplier = 2.0

	for x in [-0.13, 0.13]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.055
		eye_mesh.height = 0.11
		eye.mesh = eye_mesh
		eye.position = Vector3(x, 1.52, -0.37)
		eye.material_override = eye_material
		monster.add_child(eye)

	show_message("ТЫ ЗДЕСЬ НЕ ОДИН...", 5.0)


func update_monster(delta: float) -> void:
	if not monster_spawned or not is_instance_valid(monster):
		return

	if not is_instance_valid(player):
		return

	var direction := player.global_position - monster.global_position
	direction.y = 0.0

	var distance := direction.length()

	if distance > 0.05:
		direction = direction.normalized()
		monster.velocity.x = direction.x * 1.5
		monster.velocity.z = direction.z * 1.5
		monster.look_at(
			Vector3(player.global_position.x, monster.global_position.y,
			player.global_position.z),
			Vector3.UP
		)
	else:
		monster.velocity.x = 0.0
		monster.velocity.z = 0.0

	if not monster.is_on_floor():
		monster.velocity.y -= 18.0 * delta

	monster.move_and_slide()

	if distance < 2.0:
		monster_distance_timer += delta
		if monster_distance_timer >= 2.0:
			monster_distance_timer = 0.0
			accuracy = maxf(0.0, accuracy - 2.0)
			show_message("ТЫ ПОТЕРЯЛ КОНЦЕНТРАЦИЮ. ОТОЙДИ!", 2.0)
	else:
		monster_distance_timer = 0.0


# ============================================================
# END OF PART 2
# ============================================================

# ============================================================
# USER INTERFACE
# ============================================================

func create_interface() -> void:
	ui = CanvasLayer.new()
	ui.name = "GameUI"
	add_child(ui)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	ui.add_child(root)

	# Прицел
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 26)
	crosshair.add_theme_color_override("font_color", Color.WHITE)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-8, -17)
	root.add_child(crosshair)

	# Задания
	task_label = Label.new()
	task_label.position = Vector2(20, 20)
	task_label.custom_minimum_size = Vector2(330, 150)
	task_label.add_theme_font_size_override("font_size", 17)
	task_label.add_theme_color_override(
		"font_color",
		Color(0.9, 0.91, 0.94)
	)
	root.add_child(task_label)

	# Аккуратность
	accuracy_label = Label.new()
	accuracy_label.position = Vector2(20, 175)
	accuracy_label.add_theme_font_size_override("font_size", 20)
	accuracy_label.add_theme_color_override(
		"font_color",
		Color(0.9, 0.83, 0.62)
	)
	root.add_child(accuracy_label)

	# Сообщения
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 22)
	message_label.add_theme_color_override("font_color", Color.WHITE)
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.position = Vector2(-250, 80)
	message_label.custom_minimum_size = Vector2(500, 55)
	root.add_child(message_label)

	# Подсказка взаимодействия
	target_label = Label.new()
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.add_theme_font_size_override("font_size", 19)
	target_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.9, 0.65)
	)
	target_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	target_label.position = Vector2(-180, -125)
	target_label.custom_minimum_size = Vector2(360, 45)
	root.add_child(target_label)

	# Инвентарь
	inventory_box = HBoxContainer.new()
	inventory_box.alignment = BoxContainer.ALIGNMENT_CENTER
	inventory_box.add_theme_constant_override("separation", 5)
	inventory_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	inventory_box.position = Vector2(-270, -75)
	inventory_box.custom_minimum_size = Vector2(540, 60)
	root.add_child(inventory_box)

	# Главное меню
	menu_panel = make_panel(root, Vector2(420, 360))
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.position = Vector2(-210, -180)

	var menu_content := VBoxContainer.new()
	menu_content.add_theme_constant_override("separation", 14)
	menu_panel.add_child(menu_content)

	var title := Label.new()
	title.text = GAME_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override(
		"font_color",
		Color(0.85, 0.83, 0.77)
	)
	menu_content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "EVERYTHING MUST BE PERFECT"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override(
		"font_color",
		Color(0.55, 0.56, 0.6)
	)
	menu_content.add_child(subtitle)

	add_menu_button(menu_content, "НОВАЯ ИГРА", start_new_game)
	add_menu_button(menu_content, "ПРОДОЛЖИТЬ", continue_game)
	add_menu_button(menu_content, "ВЫХОД В МЕНЮ", show_main_menu)

	# Меню паузы
	pause_panel = make_panel(root, Vector2(360, 270))
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-180, -135)
	pause_panel.visible = false

	var pause_content := VBoxContainer.new()
	pause_content.add_theme_constant_override("separation", 14)
	pause_panel.add_child(pause_content)

	var pause_title := Label.new()
	pause_title.text = "ПАУЗА"
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_title.add_theme_font_size_override("font_size", 28)
	pause_content.add_child(pause_title)

	add_menu_button(pause_content, "ПРОДОЛЖИТЬ", toggle_pause)
	add_menu_button(pause_content, "СОХРАНИТЬ", save_game)
	add_menu_button(pause_content, "ГЛАВНОЕ МЕНЮ", show_main_menu)

	# Мобильные кнопки
	create_mobile_controls(root)

	update_inventory()
	update_hud()


func make_panel(parent: Control, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.05, 0.96)
	style.border_color = Color(0.35, 0.33, 0.3, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 22
	style.content_margin_bottom = 22

	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func add_menu_button(
	parent: VBoxContainer,
	button_text: String,
	callback: Callable
) -> void:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 16)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.13, 0.15)
	normal.set_corner_radius_all(6)
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.22, 0.23, 0.25)
	hover.set_corner_radius_all(6)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.pressed.connect(callback)

	parent.add_child(button)


func create_mobile_controls(root: Control) -> void:
	# Кнопка взаимодействия
	var use_button := Button.new()
	use_button.text = "ИСПОЛЬЗОВАТЬ"
	use_button.custom_minimum_size = Vector2(130, 55)
	use_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	use_button.position = Vector2(-150, -145)
	use_button.pressed.connect(interact)
	root.add_child(use_button)

	# Прыжок
	var jump_button := Button.new()
	jump_button.text = "ПРЫЖОК"
	jump_button.custom_minimum_size = Vector2(90, 45)
	jump_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	jump_button.position = Vector2(-110, -205)
	jump_button.button_down.connect(func(): jump_touch = true)
	root.add_child(jump_button)

	# Бег
	var run_button := Button.new()
	run_button.text = "БЕГ"
	run_button.custom_minimum_size = Vector2(75, 45)
	run_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	run_button.position = Vector2(-235, -145)
	run_button.button_down.connect(func(): run_touch = true)
	run_button.button_up.connect(func(): run_touch = false)
	root.add_child(run_button)

	# Приседание
	var crouch_button := Button.new()
	crouch_button.text = "ПРИСЕСТЬ"
	crouch_button.custom_minimum_size = Vector2(90, 45)
	crouch_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	crouch_button.position = Vector2(-235, -90)
	crouch_button.button_down.connect(func(): crouch_touch = true)
	crouch_button.button_up.connect(func(): crouch_touch = false)
	root.add_child(crouch_button)

	# Фонарик
	var light_button := Button.new()
	light_button.text = "ФОНАРИК"
	light_button.custom_minimum_size = Vector2(90, 45)
	light_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	light_button.position = Vector2(-110, -265)
	light_button.pressed.connect(toggle_flashlight)
	root.add_child(light_button)

	# Выброс предмета
	var drop_button := Button.new()
	drop_button.text = "БРОСИТЬ"
	drop_button.custom_minimum_size = Vector2(90, 45)
	drop_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	drop_button.position = Vector2(-235, -200)
	drop_button.pressed.connect(drop_item)
	root.add_child(drop_button)


# ============================================================
# HUD
# ============================================================

func update_hud() -> void:
	if not is_instance_valid(task_label):
		return

	var text := "ТЕКУЩИЕ ЗАДАНИЯ\n"

	for id in tasks:
		var task: Dictionary = tasks[id]
		var completed := bool(task.get("done", false))
		var symbol := "[X]" if completed else "[ ]"

		text += symbol + " " + str(task.get("name", "")) + "\n"

	task_label.text = text

	accuracy_label.text = "АККУРАТНОСТЬ: " + str(
		roundi(accuracy)
	) + "%"

	if wash_started and not wash_finished:
		var remaining := maxf(0.0, WASH_DURATION - wash_timer)
		accuracy_label.text += "\nСТИРКА: " + str(ceili(remaining)) + " сек."


func show_message(text: String, duration: float = 3.0) -> void:
	if not is_instance_valid(message_label):
		return

	message_label.text = text
	message_seconds = duration


# ============================================================
# GAME FLOW
# ============================================================

func show_main_menu() -> void:
	started = false
	paused = false

	if is_instance_valid(menu_panel):
		menu_panel.visible = true

	if is_instance_valid(pause_panel):
		pause_panel.visible = false

	if is_instance_valid(world):
		world.visible = false

	if is_instance_valid(player):
		player.visible = false

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func start_new_game() -> void:
	clear_dynamic_world()

	inventory.clear()
	current_item = -1

	wash_started = false
	wash_finished = false
	wash_timer = 0.0
	blood_cleaned = false
	monster_spawned = false
	monster_distance_timer = 0.0

	accuracy = 100.0
	game_seconds = 0.0

	if is_instance_valid(monster):
		monster.queue_free()
	monster = null

	initialize_tasks()
	create_initial_items()

	if is_instance_valid(player):
		player.position = Vector3(0, 0.2, 4)
		player.velocity = Vector3.ZERO
		head.rotation = Vector3.ZERO
		camera.rotation = Vector3.ZERO

	started = true
	paused = false

	menu_panel.visible = false
	pause_panel.visible = false
	world.visible = true
	player.visible = true

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	update_inventory()
	update_hud()
	show_message("ВЫПОЛНЯЙТЕ ВСЁ АККУРАТНО.", 5.0)


func clear_dynamic_world() -> void:
	for item in world_items:
		if is_instance_valid(item):
			item.queue_free()

	world_items.clear()

	var blood := world.get_node_or_null("BloodPuddle")
	if is_instance_valid(blood):
		blood.queue_free()


func continue_game() -> void:
	start_new_game()
	load_game()


func toggle_pause() -> void:
	if not started:
		return

	paused = not paused
	pause_panel.visible = paused
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE
		if paused
		else Input.MOUSE_MODE_CAPTURED
	)


# ============================================================
# GAME END
# ============================================================

func try_finish_game() -> void:
	if count_completed_tasks() < tasks.size():
		show_message("НЕ ВСЕ ЗАДАНИЯ ВЫПОЛНЕНЫ")
		return

	if accuracy < 95.0:
		show_message("АККУРАТНОСТИ НЕДОСТАТОЧНО ДЛЯ ПОБЕДЫ")
		return

	started = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_message("ГЛАВА ЗАВЕРШЕНА. АККУРАТНОСТЬ: " + str(roundi(accuracy)) + "%", 10.0)


# ============================================================
# SAVE AND LOAD
# ============================================================

func save_game() -> void:
	var data := {
		"inventory": inventory,
		"tasks": tasks,
		"accuracy": accuracy,
		"wash_started": wash_started,
		"wash_finished": wash_finished,
		"wash_timer": wash_timer,
		"blood_cleaned": blood_cleaned,
		"monster_spawned": monster_spawned,
		"player_position": [
			player.position.x,
			player.position.y,
			player.position.z
		],
		"player_rotation": [
			head.rotation.x,
			head.rotation.y,
			head.rotation.z
		],
		"game_seconds": game_seconds
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)

	if file == null:
		show_message("ОШИБКА СОХРАНЕНИЯ")
		return

	file.store_string(JSON.stringify(data))
	file.close()

	show_message("ИГРА СОХРАНЕНА")


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		show_message("СОХРАНЕНИЕ НЕ НАЙДЕНО")
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)

	if file == null:
		show_message("НЕ УДАЛОСЬ ОТКРЫТЬ СОХРАНЕНИЕ")
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not parsed is Dictionary:
		show_message("ФАЙЛ СОХРАНЕНИЯ ПОВРЕЖДЁН")
		return

	var data: Dictionary = parsed

	inventory.clear()

	var saved_inventory: Variant = data.get("inventory", [])
	if saved_inventory is Array:
		for item in saved_inventory:
			if item is Dictionary:
				inventory.append(item)

	var saved_tasks: Variant = data.get("tasks", {})
	if saved_tasks is Dictionary:
		for key in saved_tasks:
			if tasks.has(key) and saved_tasks[key] is Dictionary:
				tasks[key]["done"] = bool(
					saved_tasks[key].get("done", false)
				)

	accuracy = clampf(float(data.get("accuracy", 100.0)), 0.0, 100.0)
	wash_started = bool(data.get("wash_started", false))
	wash_finished = bool(data.get("wash_finished", false))
	wash_timer = clampf(
		float(data.get("wash_timer", 0.0)),
		0.0,
		WASH_DURATION
	)
	blood_cleaned = bool(data.get("blood_cleaned", false))
	monster_spawned = bool(data.get("monster_spawned", false))
	game_seconds = maxf(0.0, float(data.get("game_seconds", 0.0)))

	var saved_position: Variant = data.get("player_position", [])

	if saved_position is Array and saved_position.size() >= 3:
		player.position = Vector3(
			float(saved_position[0]),
			float(saved_position[1]),
			float(saved_position[2])
		)

	var saved_rotation: Variant = data.get("player_rotation", [])

	if saved_rotation is Array and saved_rotation.size() >= 3:
		head.rotation = Vector3(
			float(saved_rotation[0]),
			float(saved_rotation[1]),
			float(saved_rotation[2])
		)

	if wash_finished and not blood_cleaned:
		if not is_instance_valid(world.get_node_or_null("BloodPuddle")):
			create_blood(Vector3(0, 0.03, -41.0))

	if monster_spawned and not is_instance_valid(monster):
		spawn_monster(Vector3(0, 0.1, -30))

	update_inventory()
	update_hud()
	show_message("СОХРАНЕНИЕ ЗАГРУЖЕНО")


# ============================================================
# SETTINGS
# ============================================================

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return

	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if parsed is Dictionary:
		for key in parsed:
			settings[key] = parsed[key]


func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)

	if file == null:
		return

	file.store_string(JSON.stringify(settings))
	file.close()


# ============================================================
# END OF MAIN.GD
# ============================================================
