
extends Node3D

# ==================================================
# THE BEST SCENE
# STORY HORROR GAME
# Main.gd
# ==================================================

const GAME_TITLE := "THE BEST SCENE"
const MIN_ACCURACY := 95.0

const WALK_SPEED := 4.0
const RUN_SPEED := 6.2
const CROUCH_SPEED := 1.8
const MOUSE_SENSITIVITY := 0.002

const INTERACTION_DISTANCE := 3.2
const INVENTORY_CAPACITY := 8

var player: CharacterBody3D
var camera: Camera3D
var head: Node3D
var raycast: RayCast3D

var world_environment: WorldEnvironment
var world_root: Node3D

var inventory: Array[Dictionary] = []
var world_items: Array[Node3D] = []
var monster_nodes: Array[Node3D] = []
var task_data: Array[Dictionary] = []
var task_history: Array[Dictionary] = []

var current_item := -1
var held_item: Node3D
var interaction_target: Node3D

var current_chapter := 1
var current_task := 0
var total_accuracy := 100.0

var game_started := false
var paused := false
var movement_enabled := true
var flashlight_on := true
var crouching := false
var running := false

var jump_requested := false
var crouch_pressed := false
var run_pressed := false

var joystick_vector := Vector2.ZERO
var mobile_look := Vector2.ZERO

var flashlight_light: SpotLight3D

var interact_label: Label
var task_label: Label
var accuracy_label: Label
var inventory_panel: HBoxContainer
var message_label: Label
var crosshair: Label
var chapter_label: Label
var pause_panel: Panel
var interaction_hint: Label

var message_timer := 0.0
var blood_events := 0

var washing_machine_started := false
var washing_machine_finished := false

var game_time := 0.0
var monster_active := false
var ending_unlocked := false

var settings := {
    "mouse_sensitivity": 1.0,
    "show_crosshair": true,
    "subtitles": true
}

# ==================================================
# STARTUP
# ==================================================

func _ready() -> void:
    randomize()
    setup_input_actions()
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

    create_environment()
    create_world()
    create_player()
    create_game_interface()
    create_story()
    load_game_settings()

    game_started = true
    show_message("ВАШ РАБОЧИЙ ДЕНЬ НАЧИНАЕТСЯ", 4.0)


func _process(delta: float) -> void:
    if not game_started:
        return

    if message_timer > 0.0:
        message_timer -= delta
        if message_timer <= 0.0 and is_instance_valid(message_label):
            message_label.text = ""

    if paused:
        return

    game_time += delta

    update_interaction()
    update_interface()
    update_world_items(delta)
    update_story_events(delta)
    update_monsters(delta)


func _physics_process(delta: float) -> void:
    if not game_started or paused:
        return

    if not is_instance_valid(player):
        return

    update_player_movement(delta)


# ==================================================
# INPUT
# ==================================================

func setup_input_actions() -> void:
    add_key_action("move_forward", KEY_W)
    add_key_action("move_back", KEY_S)
    add_key_action("move_left", KEY_A)
    add_key_action("move_right", KEY_D)

    add_key_action("run", KEY_SHIFT)
    add_key_action("jump", KEY_SPACE)
    add_key_action("crouch", KEY_CTRL)
    add_key_action("interact", KEY_E)
    add_key_action("drop_item", KEY_G)
    add_key_action("flashlight", KEY_F)

    add_key_action("inventory_1", KEY_1)
    add_key_action("inventory_2", KEY_2)
    add_key_action("inventory_3", KEY_3)
    add_key_action("inventory_4", KEY_4)
    add_key_action("inventory_5", KEY_5)
    add_key_action("inventory_6", KEY_6)
    add_key_action("inventory_7", KEY_7)
    add_key_action("inventory_8", KEY_8)


func add_key_action(action_name: String, key_code: Key) -> void:
    if not InputMap.has_action(action_name):
        InputMap.add_action(action_name)

    var key_event := InputEventKey.new()
    key_event.physical_keycode = key_code

    InputMap.action_add_event(action_name, key_event)


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        toggle_pause()
        return

    if paused:
        return

    if event is InputEventMouseMotion:
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            rotate_camera(event.relative)

    if event.is_action_pressed("interact"):
        interact()

    if event.is_action_pressed("drop_item"):
        drop_current_item()

    if event.is_action_pressed("flashlight"):
        toggle_flashlight()

    if event.is_action_pressed("jump"):
        jump_requested = true

    if event.is_action_pressed("crouch"):
        crouch_pressed = true

    if event.is_action_released("crouch"):
        crouch_pressed = false

    if event.is_action_pressed("run"):
        run_pressed = true

    if event.is_action_released("run"):
        run_pressed = false

    for i in range(8):
        if event.is_action_pressed("inventory_" + str(i + 1)):
            select_inventory_item(i)


func rotate_camera(relative: Vector2) -> void:
    if not is_instance_valid(head):
        return

    var sensitivity: float = float(settings.get("mouse_sensitivity", 1.0))

    head.rotate_y(-relative.x * MOUSE_SENSITIVITY * sensitivity)
    camera.rotate_x(-relative.y * MOUSE_SENSITIVITY * sensitivity)

    camera.rotation.x = clampf(camera.rotation.x, -1.45, 1.45)


# ==================================================
# ENVIRONMENT AND LIGHTING
# ==================================================

func create_environment() -> void:
    world_environment = WorldEnvironment.new()
    world_environment.name = "WorldEnvironment"

    var environment := Environment.new()

    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.035, 0.04, 0.05)

    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.19, 0.20, 0.23)
    environment.ambient_light_energy = 0.22

    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

    environment.fog_enabled = true
    environment.fog_light_color = Color(0.12, 0.13, 0.15)
    environment.fog_density = 0.012

    world_environment.environment = environment
    add_child(world_environment)


func create_lights(parent: Node3D) -> void:
    var main_light := DirectionalLight3D.new()
    main_light.name = "WeakCeilingLight"
    main_light.rotation_degrees = Vector3(-55, -25, 0)
    main_light.light_color = Color(0.65, 0.68, 0.72)
    main_light.light_energy = 0.12
    main_light.shadow_enabled = true
    parent.add_child(main_light)


func create_ceiling_light(parent: Node3D, position: Vector3, energy: float = 0.55) -> void:
    var light := OmniLight3D.new()
    light.position = position
    light.light_color = Color(0.85, 0.78, 0.62)
    light.light_energy = energy
    light.omni_range = 9.0
    light.shadow_enabled = true
    parent.add_child(light)


# ==================================================
# WORLD
# ==================================================

func create_world() -> void:
    world_root = Node3D.new()
    world_root.name = "World"
    add_child(world_root)

    create_main_building()
    create_corridor()
    create_bedroom()
    create_kitchen()
    create_laundry_room()

    create_lights(world_root)
    create_initial_items(world_root)
    create_washing_machine(world_root)
    create_furniture(world_root)


func create_main_building() -> void:
    create_room(
        world_root,
        Vector3(0, 0, 0),
        Vector3(18, 0.3, 18),
        Color(0.18, 0.18, 0.19)
    )

    create_wall(world_root, Vector3(0, 2, -9), Vector3(18, 4, 0.4))
    create_wall(world_root, Vector3(0, 2, 9), Vector3(18, 4, 0.4))
    create_wall(world_root, Vector3(-9, 2, 0), Vector3(0.4, 4, 18))
    create_wall(world_root, Vector3(9, 2, 0), Vector3(0.4, 4, 18))

    create_ceiling_light(world_root, Vector3(0, 3.5, 0), 0.45)


func create_corridor() -> void:
    create_room(
        world_root,
        Vector3(0, 0, -20),
        Vector3(7, 0.3, 24),
        Color(0.13, 0.13, 0.14)
    )

    create_wall(world_root, Vector3(-3.5, 2, -20), Vector3(0.35, 4, 24))
    create_wall(world_root, Vector3(3.5, 2, -20), Vector3(0.35, 4, 24))

    create_ceiling_light(world_root, Vector3(0, 3.5, -17), 0.28)
    create_ceiling_light(world_root, Vector3(0, 3.5, -24), 0.18)
    create_ceiling_light(world_root, Vector3(0, 3.5, -29), 0.12)


func create_bedroom() -> void:
    var center := Vector3(-14, 0, -20)

    create_room(
        world_root,
        center,
        Vector3(12, 0.3, 12),
        Color(0.16, 0.15, 0.15)
    )

    create_wall(world_root, center + Vector3(0, 2, -6), Vector3(12, 4, 0.35))
    create_wall(world_root, center + Vector3(-6, 2, 0), Vector3(0.35, 4, 12))
    create_wall(world_root, center + Vector3(6, 2, 0), Vector3(0.35, 4, 12))

    create_ceiling_light(world_root, center + Vector3(0, 3.4, 0), 0.22)


func create_kitchen() -> void:
    var center := Vector3(14, 0, -20)

    create_room(
        world_root,
        center,
        Vector3(12, 0.3, 12),
        Color(0.17, 0.17, 0.16)
    )

    create_wall(world_root, center + Vector3(0, 2, -6), Vector3(12, 4, 0.35))
    create_wall(world_root, center + Vector3(6, 2, 0), Vector3(0.35, 4, 12))
    create_wall(world_root, center + Vector3(-6, 2, 0), Vector3(0.35, 4, 12))

    create_ceiling_light(world_root, center + Vector3(0, 3.4, 0), 0.32)


func create_laundry_room() -> void:
    var center := Vector3(0, 0, -38)

    create_room(
        world_root,
        center,
        Vector3(14, 0.3, 12),
        Color(0.14, 0.15, 0.16)
    )

    create_wall(world_root, center + Vector3(0, 2, -6), Vector3(14, 4, 0.35))
    create_wall(world_root, center + Vector3(-7, 2, 0), Vector3(0.35, 4, 12))
    create_wall(world_root, center + Vector3(7, 2, 0), Vector3(0.35, 4, 12))

    create_ceiling_light(world_root, center + Vector3(0, 3.4, 0), 0.38)


# ==================================================
# GEOMETRY HELPERS
# ==================================================

func create_room(
    parent: Node3D,
    position: Vector3,
    size: Vector3,
    color: Color
) -> void:
    create_box(
        parent,
        position,
        size,
        color,
        true,
        "Floor"
    )


func create_wall(
    parent: Node3D,
    position: Vector3,
    size: Vector3
) -> void:
    create_box(
        parent,
        position,
        size,
        Color(0.22, 0.22, 0.23),
        true,
        "Wall"
    )


func create_box(
    parent: Node3D,
    position: Vector3,
    size: Vector3,
    color: Color,
    solid: bool = true,
    object_name: String = "Object"
) -> Node3D:
    var root := Node3D.new()
    root.name = object_name
    root.position = position
    parent.add_child(root)

    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size

    mesh_instance.mesh = mesh
    mesh_instance.material_override = make_material(color)
    root.add_child(mesh_instance)

    if solid:
        var body := StaticBody3D.new()
        root.remove_child(mesh_instance)
        root.add_child(body)
        body.add_child(mesh_instance)

        var collision := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        collision.shape = shape
        body.add_child(collision)

    return root


func make_material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material


# ==================================================
# PLAYER
# ==================================================

func create_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(0, 1.1, 4)
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
    head.name = "Head"
    head.position.y = 1.58
    player.add_child(head)

    camera = Camera3D.new()
    camera.name = "Camera"
    camera.current = true
    camera.fov = 78.0
    head.add_child(camera)

    raycast = RayCast3D.new()
    raycast.name = "InteractionRay"
    raycast.target_position = Vector3(0, 0, -INTERACTION_DISTANCE)
    raycast.enabled = true
    camera.add_child(raycast)

    create_flashlight()


func create_flashlight() -> void:
    flashlight_light = SpotLight3D.new()
    flashlight_light.name = "Flashlight"
    flashlight_light.position = Vector3(0.12, -0.12, -0.2)
    flashlight_light.rotation_degrees = Vector3(-3, 0, 0)
    flashlight_light.light_color = Color(0.85, 0.91, 1.0)
    flashlight_light.light_energy = 2.2
    flashlight_light.spot_range = 24.0
    flashlight_light.spot_angle = 38.0
    flashlight_light.spot_angle_attenuation = 1.2
    flashlight_light.shadow_enabled = true
    camera.add_child(flashlight_light)


func toggle_flashlight() -> void:
    flashlight_on = not flashlight_on

    if is_instance_valid(flashlight_light):
        flashlight_light.visible = flashlight_on

    if flashlight_on:
        show_message("ФОНАРИК ВКЛЮЧЁН", 1.5)
    else:
        show_message("ФОНАРИК ВЫКЛЮЧЕН", 1.5)


# ==================================================
# END OF PART 1
# NEXT: PART 2/3
# ==================================================

# ==================================================
# PART 2: INVENTORY AND INTERACTION
# ==================================================

func update_player_movement(delta: float) -> void:
    if not is_instance_valid(player):
        return

    var input_dir := Input.get_vector(
        "move_left",
        "move_right",
        "move_forward",
        "move_back"
    )

    if joystick_vector.length() > 0.12:
        input_dir = joystick_vector

    var direction := Vector3.ZERO

    direction += -head.global_basis.z * input_dir.y
    direction += head.global_basis.x * input_dir.x
    direction.y = 0.0

    if direction.length() > 1.0:
        direction = direction.normalized()

    crouching = crouch_pressed or Input.is_action_pressed("crouch")
    running = (run_pressed or Input.is_action_pressed("run")) and not crouching

    var speed := WALK_SPEED

    if running:
        speed = RUN_SPEED
    elif crouching:
        speed = CROUCH_SPEED

    if movement_enabled:
        player.velocity.x = direction.x * speed
        player.velocity.z = direction.z * speed
    else:
        player.velocity.x = move_toward(player.velocity.x, 0.0, 10.0 * delta)
        player.velocity.z = move_toward(player.velocity.z, 0.0, 10.0 * delta)

    if not player.is_on_floor():
        player.velocity.y -= 19.0 * delta
    else:
        if jump_requested and not crouching:
            player.velocity.y = 5.0

    jump_requested = false

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


# ==================================================
# INTERACTION
# ==================================================

func update_interaction() -> void:
    interaction_target = null

    if not is_instance_valid(raycast):
        return

    raycast.force_raycast_update()

    if raycast.is_colliding():
        var collider := raycast.get_collider()

        if collider is Node:
            var node := collider as Node
            var target := node

            while target != null and not target.has_meta("item_id") and not target.has_meta("interactable"):
                target = target.get_parent()

            if target != null:
                interaction_target = target

    if is_instance_valid(interaction_target):
        if interaction_target.has_meta("item_id"):
            interact_label.text = "[E] Взять: " + str(interaction_target.get_meta("display_name", "Предмет"))
        elif interaction_target.has_meta("interactable"):
            interact_label.text = "[E] " + str(interaction_target.get_meta("display_name", "Взаимодействовать"))
        else:
            interact_label.text = ""
    else:
        interact_label.text = ""


func interact() -> void:
    if not is_instance_valid(interaction_target):
        return

    if interaction_target.has_meta("item_id"):
        pickup_item(interaction_target)
        return

    if interaction_target.has_meta("interactable"):
        var action := str(interaction_target.get_meta("action", ""))

        match action:
            "washing_machine":
                interact_washing_machine()
            "door":
                interact_door(interaction_target)
            "light_switch":
                interact_light_switch(interaction_target)
            "task_object":
                interact_task_object(interaction_target)


# ==================================================
# ITEM CREATION
# ==================================================

func create_item(
    parent: Node3D,
    item_id: String,
    display_name: String,
    position: Vector3,
    color: Color,
    item_type: String = "general"
) -> Node3D:
    var item := RigidBody3D.new()
    item.name = item_id
    item.position = position
    item.mass = 0.5
    item.gravity_scale = 1.0
    item.continuous_cd = true

    item.set_meta("item_id", item_id)
    item.set_meta("display_name", display_name)
    item.set_meta("item_type", item_type)
    item.set_meta("interactable", true)

    parent.add_child(item)

    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.22, 0.12, 0.22)
    mesh_instance.mesh = mesh
    mesh_instance.material_override = make_material(color, 0.65)
    item.add_child(mesh_instance)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(0.22, 0.12, 0.22)
    collision.shape = shape
    item.add_child(collision)

    var pickup_area := Area3D.new()
    pickup_area.name = "PickupArea"
    item.add_child(pickup_area)

    var area_collision := CollisionShape3D.new()
    var area_shape := SphereShape3D.new()
    area_shape.radius = 0.5
    area_collision.shape = area_shape
    pickup_area.add_child(area_collision)

    world_items.append(item)
    return item


func create_initial_items(parent: Node3D) -> void:
    create_item(parent, "detergent", "Стиральный порошок", Vector3(2, 0.5, -37), Color(0.2, 0.55, 0.9), "laundry")
    create_item(parent, "dirty_clothes", "Грязная одежда", Vector3(-2, 0.4, -37), Color(0.35, 0.25, 0.2), "laundry")
    create_item(parent, "key_bedroom", "Ключ от комнаты", Vector3(-14, 0.4, -17), Color(0.85, 0.72, 0.25), "key")
    create_item(parent, "flashlight_battery", "Батарейка", Vector3(13, 0.4, -18), Color(0.2, 0.85, 0.35), "battery")
    create_item(parent, "rag", "Тряпка", Vector3(12, 0.4, -22), Color(0.8, 0.8, 0.75), "cleaning")
    create_item(parent, "kitchen_key", "Ключ от кухни", Vector3(-2, 0.4, 2), Color(0.9, 0.75, 0.3), "key")


# ==================================================
# INVENTORY
# ==================================================

func pickup_item(item: Node3D) -> void:
    if inventory.size() >= INVENTORY_CAPACITY:
        show_message("ИНВЕНТАРЬ ПОЛОН", 2.0)
        return

    var item_data := {
        "id": str(item.get_meta("item_id", "unknown")),
        "name": str(item.get_meta("display_name", "Предмет")),
        "type": str(item.get_meta("item_type", "general")),
        "color": get_item_color(item),
        "amount": 1
    }

    inventory.append(item_data)

    if item in world_items:
        world_items.erase(item)

    item.queue_free()

    current_item = inventory.size() - 1
    update_inventory_gui()

    show_message("ПРЕДМЕТ ВЗЯТ: " + item_data["name"], 2.0)


func get_item_color(item: Node3D) -> Color:
    var mesh_instance := item.get_node_or_null("MeshInstance3D") as MeshInstance3D

    if mesh_instance and mesh_instance.material_override is StandardMaterial3D:
        return (mesh_instance.material_override as StandardMaterial3D).albedo_color

    return Color.WHITE


func select_inventory_item(index: int) -> void:
    if index < 0 or index >= inventory.size():
        current_item = -1
    else:
        current_item = index

    update_inventory_gui()
    update_held_item_visual()


func update_held_item_visual() -> void:
    if is_instance_valid(held_item):
        held_item.queue_free()

    held_item = null

    if current_item < 0 or current_item >= inventory.size():
        return

    var data: Dictionary = inventory[current_item]

    held_item = Node3D.new()
    held_item.name = "HeldItem"
    held_item.position = Vector3(0.35, -0.3, -0.65)
    camera.add_child(held_item)

    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.16, 0.12, 0.16)
    mesh_instance.mesh = mesh
    mesh_instance.material_override = make_material(data.get("color", Color.WHITE))
    held_item.add_child(mesh_instance)


func drop_current_item() -> void:
    if current_item < 0 or current_item >= inventory.size():
        return

    var data: Dictionary = inventory[current_item]

    var dropped := RigidBody3D.new()
    dropped.name = str(data["id"])
    dropped.set_meta("item_id", data["id"])
    dropped.set_meta("display_name", data["name"])
    dropped.set_meta("item_type", data["type"])
    dropped.set_meta("interactable", true)

    dropped.position = camera.global_position + (-camera.global_basis.z * 1.2)
    world_root.add_child(dropped)

    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.22, 0.12, 0.22)
    mesh_instance.mesh = mesh
    mesh_instance.material_override = make_material(data["color"])
    dropped.add_child(mesh_instance)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(0.22, 0.12, 0.22)
    collision.shape = shape
    dropped.add_child(collision)

    dropped.linear_velocity = -camera.global_basis.z * 3.0 + Vector3.UP * 1.0

    world_items.append(dropped)

    inventory.remove_at(current_item)

    if inventory.is_empty():
        current_item = -1
    else:
        current_item = clampi(current_item, 0, inventory.size() - 1)

    if is_instance_valid(held_item):
        held_item.queue_free()

    held_item = null
    update_inventory_gui()

    show_message("ПРЕДМЕТ ВЫБРОШЕН", 1.5)


func use_current_item() -> void:
    if current_item < 0 or current_item >= inventory.size():
        show_message("СНАЧАЛА ВЫБЕРИТЕ ПРЕДМЕТ", 2.0)
        return

    var data: Dictionary = inventory[current_item]

    match data["id"]:
        "detergent":
            show_message("ПОРОШОК МОЖНО ИСПОЛЬЗОВАТЬ У СТИРАЛЬНОЙ МАШИНЫ", 2.5)
        "dirty_clothes":
            show_message("ЭТУ ОДЕЖДУ НУЖНО ПОЛОЖИТЬ В СТИРАЛЬНУЮ МАШИНУ", 2.5)
        "rag":
            show_message("ТРЯПКА МОЖЕТ ПРИГОДИТЬСЯ ДЛЯ УБОРКИ", 2.0)
        "key":
            show_message("КЛЮЧ. ВОЗМОЖНО, ОН ОТКРЫВАЕТ КАКУЮ-ТО ДВЕРЬ", 2.5)
        _:
            show_message("ЭТОТ ПРЕДМЕТ ПОКА НЕ НУЖЕН", 2.0)


# ==================================================
# WASHING MACHINE
# ==================================================

func create_washing_machine(parent: Node3D) -> void:
    var machine := create_box(
        parent,
        Vector3(0, 0.8, -42),
        Vector3(1.4, 1.6, 1.0),
        Color(0.55, 0.57, 0.59),
        true,
        "WashingMachine"
    )

    machine.set_meta("interactable", true)
    machine.set_meta("display_name", "Стиральная машина")
    machine.set_meta("action", "washing_machine")

    var door := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.42
    cylinder.bottom_radius = 0.42
    cylinder.height = 0.08
    door.mesh = cylinder
    door.position = Vector3(0, 0, -0.54)
    door.rotation_degrees.x = 90
    door.material_override = make_material(Color(0.08, 0.1, 0.12), 0.2)
    machine.add_child(door)

    var area := Area3D.new()
    area.name = "InteractionArea"
    machine.add_child(area)

    var area_collision := CollisionShape3D.new()
    var area_shape := BoxShape3D.new()
    area_shape.size = Vector3(2.0, 2.0, 2.0)
    area_collision.shape = area_shape
    area.add_child(area_collision)


func interact_washing_machine() -> void:
    if washing_machine_started:
        if washing_machine_finished:
            show_message("СТИРКА ЗАВЕРШЕНА. НО ЧТО-ТО НЕ ТАК...", 3.0)
        else:
            show_message("МАШИНА УЖЕ РАБОТАЕТ", 2.0)
        return

    var has_clothes := false
    var has_detergent := false

    for item in inventory:
        if item["id"] == "dirty_clothes":
            has_clothes = true
        if item["id"] == "detergent":
            has_detergent = true

    if not has_clothes:
        show_message("СНАЧАЛА НУЖНО ПОЛОЖИТЬ ГРЯЗНУЮ ОДЕЖДУ", 3.0)
        return

    if not has_detergent:
        show_message("НУЖЕН СТИРАЛЬНЫЙ ПОРОШОК", 2.5)
        return

    remove_inventory_item("dirty_clothes")
    remove_inventory_item("detergent")

    washing_machine_started = true

    complete_task("laundry_prepare", 100.0)

    show_message("СТИРАЛЬНАЯ МАШИНА ЗАПУЩЕНА", 3.0)


func remove_inventory_item(item_id: String) -> void:
    for i in range(inventory.size() - 1, -1, -1):
        if inventory[i]["id"] == item_id:
            inventory.remove_at(i)

            if current_item >= inventory.size():
                current_item = inventory.size() - 1

    update_inventory_gui()


func washing_machine_event() -> void:
    if not washing_machine_started or washing_machine_finished:
        return

    washing_machine_finished = true
    blood_events += 1

    create_blood_puddle(Vector3(0, 0.18, -42))

    show_message("ПОЧЕМУ ИЗ МАШИНЫ ТЕЧЁТ КРОВЬ?..", 5.0)

    spawn_monster(Vector3(0, 0, -31))


func create_blood_puddle(position: Vector3) -> void:
    var blood := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.8
    mesh.bottom_radius = 0.8
    mesh.height = 0.025
    blood.mesh = mesh
    blood.position = position
    blood.material_override = make_material(Color(0.35, 0.015, 0.025))
    world_root.add_child(blood)


# ==================================================
# STORY TASKS
# ==================================================

func create_story() -> void:
    task_data = [
        {
            "id": "bedroom",
            "title": "Осмотрите спальню",
            "description": "Проверьте комнату и найдите ключ.",
            "completed": false,
            "accuracy": 100.0
        },
        {
            "id": "clothes",
            "title": "Найдите грязную одежду",
            "description": "Найдите одежду и возьмите её.",
            "completed": false,
            "accuracy": 100.0
        },
        {
            "id": "detergent",
            "title": "Найдите порошок",
            "description": "Порошок находится в прачечной.",
            "completed": false,
            "accuracy": 100.0
        },
        {
            "id": "laundry_prepare",
            "title": "Запустите стирку",
            "description": "Положите одежду и порошок в машину.",
            "completed": false,
            "accuracy": 100.0
        },
        {
            "id": "laundry_wait",
            "title": "Дождитесь окончания стирки",
            "description": "Необходимо дождаться завершения цикла.",
            "completed": false,
            "accuracy": 100.0
        },
        {
            "id": "blood",
            "title": "Разберитесь с кровью",
            "description": "Найдите тряпку и уберите следы.",
            "completed": false,
            "accuracy": 100.0
        }
    ]

    current_task = 0
    update_task_display()


func complete_task(task_id: String, accuracy: float) -> void:
    for i in range(task_data.size()):
        if task_data[i]["id"] == task_id:
            if task_data[i]["completed"]:
                return

            task_data[i]["completed"] = true
            task_data[i]["accuracy"] = clampf(accuracy, 0.0, 100.0)

            task_history.append({
                "id": task_id,
                "accuracy": accuracy,
                "time": game_time
            })

            recalculate_accuracy()

            show_message("ЗАДАНИЕ ВЫПОЛНЕНО", 2.5)
            update_task_display()
            return


func recalculate_accuracy() -> void:
    if task_history.is_empty():
        total_accuracy = 100.0
        return

    var total := 0.0

    for result in task_history:
        total += float(result["accuracy"])

    total_accuracy = total / float(task_history.size())


func update_story_events(delta: float) -> void:
    if washing_machine_started and not washing_machine_finished:
        if game_time > 90.0:
            washing_machine_event()

    if washing_machine_finished:
        complete_task("laundry_wait", 100.0)


# ==================================================
# END OF PART 2
# NEXT: PART 3/3
# ==================================================


# ==================================================
# PART 3: GUI, MONSTERS, SAVING AND ENDINGS
# ==================================================

# ==================================================
# GUI CREATION
# ==================================================

func create_game_interface() -> void:
    var layer := CanvasLayer.new()
    layer.name = "GameInterface"
    add_child(layer)

    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(root)

    crosshair = Label.new()
    crosshair.text = "+"
    crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    crosshair.add_theme_font_size_override("font_size", 28)
    crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
    crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    crosshair.position = Vector2(-12, -18)
    crosshair.size = Vector2(24, 36)
    root.add_child(crosshair)

    task_label = Label.new()
    task_label.position = Vector2(24, 24)
    task_label.size = Vector2(390, 90)
    task_label.add_theme_font_size_override("font_size", 17)
    task_label.add_theme_color_override("font_color", Color.WHITE)
    root.add_child(task_label)

    accuracy_label = Label.new()
    accuracy_label.position = Vector2(24, 120)
    accuracy_label.size = Vector2(250, 35)
    accuracy_label.add_theme_font_size_override("font_size", 16)
    accuracy_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.65))
    root.add_child(accuracy_label)

    chapter_label = Label.new()
    chapter_label.position = Vector2(24, 160)
    chapter_label.size = Vector2(300, 30)
    chapter_label.add_theme_font_size_override("font_size", 14)
    chapter_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
    root.add_child(chapter_label)

    interact_label = Label.new()
    interact_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    interact_label.position = Vector2(-190, -110)
    interact_label.size = Vector2(380, 45)
    interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    interact_label.add_theme_font_size_override("font_size", 18)
    interact_label.add_theme_color_override("font_color", Color.WHITE)
    root.add_child(interact_label)

    message_label = Label.new()
    message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    message_label.position = Vector2(-300, 80)
    message_label.size = Vector2(600, 55)
    message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    message_label.add_theme_font_size_override("font_size", 21)
    message_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85))
    root.add_child(message_label)

    inventory_panel = HBoxContainer.new()
    inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    inventory_panel.position = Vector2(-220, -55)
    inventory_panel.size = Vector2(440, 50)
    inventory_panel.add_theme_constant_override("separation", 8)
    root.add_child(inventory_panel)

    update_inventory_gui()
    update_task_display()
    update_interface()

    create_mobile_controls(root)
    create_pause_menu(root)


func create_mobile_controls(root: Control) -> void:
    var left_button := create_ui_button(root, "◉", Vector2(35, -150), Vector2(105, 105))
    left_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    left_button.button_down.connect(func(): joystick_vector = Vector2(-1, 0))
    left_button.button_up.connect(func(): joystick_vector = Vector2.ZERO)

    var right_button := create_ui_button(root, "RUN", Vector2(-245, -145), Vector2(85, 65))
    right_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    right_button.button_down.connect(func(): run_pressed = true)
    right_button.button_up.connect(func(): run_pressed = false)

    var interact_button := create_ui_button(root, "E", Vector2(-135, -230), Vector2(75, 75))
    interact_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    interact_button.pressed.connect(interact)

    var jump_button := create_ui_button(root, "^", Vector2(-55, -145), Vector2(65, 65))
    jump_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    jump_button.pressed.connect(func(): jump_requested = true)

    var drop_button := create_ui_button(root, "DROP", Vector2(-140, -65), Vector2(70, 48))
    drop_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    drop_button.pressed.connect(drop_current_item)

    var flashlight_button := create_ui_button(root, "F", Vector2(-65, -65), Vector2(55, 48))
    flashlight_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    flashlight_button.pressed.connect(toggle_flashlight)


func create_ui_button(
    parent: Control,
    text_value: String,
    position_value: Vector2,
    size_value: Vector2
) -> Button:
    var button := Button.new()
    button.text = text_value
    button.position = position_value
    button.size = size_value
    button.add_theme_font_size_override("font_size", 17)
    button.add_theme_color_override("font_color", Color.WHITE)

    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.08, 0.09, 0.11, 0.78)
    normal.set_corner_radius_all(14)
    normal.set_border_width_all(1)
    normal.border_color = Color(0.5, 0.52, 0.56, 0.6)

    button.add_theme_stylebox_override("normal", normal)

    var hover := StyleBoxFlat.new()
    hover.bg_color = Color(0.2, 0.22, 0.25, 0.95)
    hover.set_corner_radius_all(14)
    button.add_theme_stylebox_override("hover", hover)

    parent.add_child(button)
    return button


func update_inventory_gui() -> void:
    if not is_instance_valid(inventory_panel):
        return

    for child in inventory_panel.get_children():
        child.queue_free()

    for i in range(INVENTORY_CAPACITY):
        var slot := Button.new()
        slot.custom_minimum_size = Vector2(48, 48)
        slot.add_theme_font_size_override("font_size", 15)

        if i < inventory.size():
            slot.text = str(i + 1) + "\n" + str(inventory[i]["name"]).substr(0, 5)
        else:
            slot.text = str(i + 1)

        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.08, 0.09, 0.11, 0.88)
        style.set_corner_radius_all(8)
        style.set_border_width_all(1)

        if i == current_item:
            style.border_color = Color(0.3, 0.85, 0.65)
        else:
            style.border_color = Color(0.4, 0.4, 0.43)

        slot.add_theme_stylebox_override("normal", style)
        slot.pressed.connect(select_inventory_item.bind(i))
        inventory_panel.add_child(slot)


func update_interface() -> void:
    if is_instance_valid(accuracy_label):
        accuracy_label.text = "АККУРАТНОСТЬ: " + str(roundi(total_accuracy)) + "%"

    if is_instance_valid(chapter_label):
        chapter_label.text = "ГЛАВА " + str(current_chapter)

    if is_instance_valid(crosshair):
        crosshair.visible = bool(settings.get("show_crosshair", true))


func update_task_display() -> void:
    if not is_instance_valid(task_label):
        return

    var next_task := ""

    for task in task_data:
        if not task["completed"]:
            next_task = str(task["title"])
            break

    if next_task == "":
        task_label.text = "ВСЕ ЗАДАНИЯ ВЫПОЛНЕНЫ"
    else:
        task_label.text = "ТЕКУЩЕЕ ЗАДАНИЕ:\n" + next_task


func show_message(message: String, duration: float = 2.5) -> void:
    if not is_instance_valid(message_label):
        return

    message_label.text = message
    message_timer = duration


# ==================================================
# PAUSE MENU
# ==================================================

func create_pause_menu(root: Control) -> void:
    pause_panel = Panel.new()
    pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    pause_panel.position = Vector2(-190, -180)
    pause_panel.size = Vector2(380, 360)
    pause_panel.visible = false

    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.035, 0.04, 0.055, 0.97)
    style.set_corner_radius_all(18)
    style.set_border_width_all(1)
    style.border_color = Color(0.35, 0.38, 0.42)
    pause_panel.add_theme_stylebox_override("panel", style)

    root.add_child(pause_panel)

    var title := Label.new()
    title.text = "THE BEST SCENE"
    title.position = Vector2(30, 20)
    title.size = Vector2(320, 45)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 23)
    pause_panel.add_child(title)

    var resume := create_ui_button(pause_panel, "ПРОДОЛЖИТЬ", Vector2(65, 90), Vector2(250, 50))
    resume.pressed.connect(toggle_pause)

    var save := create_ui_button(pause_panel, "СОХРАНИТЬ", Vector2(65, 155), Vector2(250, 50))
    save.pressed.connect(save_game)

    var settings_button := create_ui_button(pause_panel, "НАСТРОЙКИ", Vector2(65, 220), Vector2(250, 50))
    settings_button.pressed.connect(show_settings_message)

    var exit := create_ui_button(pause_panel, "В ГЛАВНОЕ МЕНЮ", Vector2(65, 285), Vector2(250, 50))
    exit.pressed.connect(show_exit_message)


func toggle_pause() -> void:
    paused = not paused

    if is_instance_valid(pause_panel):
        pause_panel.visible = paused

    if paused:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    else:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func show_settings_message() -> void:
    show_message("НАСТРОЙКИ: ЧУВСТВИТЕЛЬНОСТЬ " + str(settings["mouse_sensitivity"]), 3.0)


func show_exit_message() -> void:
    show_message("ПРОГРЕСС МОЖНО СОХРАНИТЬ ПЕРЕД ВЫХОДОМ", 3.0)


# ==================================================
# MONSTERS
# ==================================================

func spawn_monster(position: Vector3) -> void:
    if monster_active:
        return

    monster_active = true

    var monster := CharacterBody3D.new()
    monster.name = "UnknownCreature"
    monster.position = position
    monster.set_meta("monster", true)
    world_root.add_child(monster)

    var body_mesh := MeshInstance3D.new()
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.42
    capsule.height = 2.3
    body_mesh.mesh = capsule
    body_mesh.material_override = make_material(Color(0.025, 0.025, 0.03))
    monster.add_child(body_mesh)

    var collision := CollisionShape3D.new()
    var collision_shape := CapsuleShape3D.new()
    collision_shape.radius = 0.42
    collision_shape.height = 2.3
    collision.shape = collision_shape
    collision.position.y = 1.1
    monster.add_child(collision)

    monster_nodes.append(monster)

    show_message("ТЫ СЛЫШИШЬ ЧЬИ-ТО ШАГИ...", 4.0)


func update_monsters(delta: float) -> void:
    for monster in monster_nodes:
        if not is_instance_valid(monster):
            continue

        var distance := monster.global_position.distance_to(player.global_position)

        if distance > 0.9:
            var direction := (player.global_position - monster.global_position).normalized()
            monster.velocity.x = direction.x * 1.5
            monster.velocity.z = direction.z * 1.5
            monster.velocity.y -= 18.0 * delta
            monster.move_and_slide()

        if distance < 1.4:
            show_message("ОН СЛИШКОМ БЛИЗКО...", 1.0)


# ==================================================
# DOORS AND OBJECTS
# ==================================================

func create_door(
    parent: Node3D,
    position: Vector3,
    display_name: String,
    locked: bool = false
) -> Node3D:
    var door := create_box(
        parent,
        position,
        Vector3(1.2, 2.5, 0.16),
        Color(0.22, 0.12, 0.08),
        true,
        "Door"
    )

    door.set_meta("interactable", true)
    door.set_meta("display_name", display_name)
    door.set_meta("action", "door")
    door.set_meta("locked", locked)
    door.set_meta("opened", false)

    return door


func interact_door(door: Node3D) -> void:
    if bool(door.get_meta("locked", false)):
        var has_key := false

        for item in inventory:
            if item["type"] == "key":
                has_key = true
                break

        if not has_key:
            show_message("ДВЕРЬ ЗАПЕРТА. НУЖЕН КЛЮЧ.", 2.5)
            return

        door.set_meta("locked", false)

    var opened := bool(door.get_meta("opened", false))
    door.set_meta("opened", not opened)

    if opened:
        show_message("ДВЕРЬ ЗАКРЫТА", 1.5)
    else:
        show_message("ДВЕРЬ ОТКРЫТА", 1.5)


func interact_light_switch(target: Node3D) -> void:
    var state := bool(target.get_meta("enabled", true))
    target.set_meta("enabled", not state)
    show_message("ВЫ ЩЁЛКНУЛИ ВЫКЛЮЧАТЕЛЕМ", 2.0)


func interact_task_object(target: Node3D) -> void:
    show_message("ВЫ ВЗАИМОДЕЙСТВОВАЛИ С ПРЕДМЕТОМ", 2.0)


# ==================================================
# FURNITURE
# ==================================================

func create_furniture(parent: Node3D) -> void:
    create_box(
        parent,
        Vector3(-5, 0.65, 2),
        Vector3(3, 1.3, 1.3),
        Color(0.22, 0.12, 0.08),
        true,
        "Sofa"
    )

    create_box(
        parent,
        Vector3(5, 0.5, -3),
        Vector3(2, 1.0, 1),
        Color(0.27, 0.23, 0.19),
        true,
        "Table"
    )

    create_box(
        parent,
        Vector3(-14, 0.5, -20),
        Vector3(3.5, 1.0, 4),
        Color(0.18, 0.12, 0.1),
        true,
        "Bed"
    )

    create_box(
        parent,
        Vector3(14, 0.8, -24),
        Vector3(3, 1.6, 0.8),
        Color(0.3, 0.3, 0.31),
        true,
        "KitchenCabinet"
    )


# ==================================================
# WORLD ITEM UPDATES
# ==================================================

func update_world_items(delta: float) -> void:
    for item in world_items:
        if not is_instance_valid(item):
            continue

        if item is RigidBody3D:
            var body := item as RigidBody3D

            if body.global_position.y < -10:
                body.queue_free()


# ==================================================
# SAVE AND LOAD
# ==================================================

const SAVE_PATH := "user://the_best_scene_save.json"
const SETTINGS_PATH := "user://the_best_scene_settings.json"


func save_game() -> void:
    var data := {
        "chapter": current_chapter,
        "task": current_task,
        "accuracy": total_accuracy,
        "inventory": inventory,
        "washing_started": washing_machine_started,
        "washing_finished": washing_machine_finished,
        "game_time": game_time,
        "task_history": task_history
    }

    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)

    if file == null:
        show_message("НЕ УДАЛОСЬ СОХРАНИТЬ ИГРУ", 2.5)
        return

    file.store_string(JSON.stringify(data))
    file.close()

    show_message("ИГРА СОХРАНЕНА", 2.0)


func load_game() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        show_message("СОХРАНЕНИЕ НЕ НАЙДЕНО", 2.0)
        return

    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)

    if file == null:
        return

    var parsed = JSON.parse_string(file.get_as_text())
    file.close()

    if not parsed is Dictionary:
        show_message("ОШИБКА СОХРАНЕНИЯ", 2.0)
        return

    current_chapter = int(parsed.get("chapter", 1))
    current_task = int(parsed.get("task", 0))
    total_accuracy = float(parsed.get("accuracy", 100.0))
    inventory = parsed.get("inventory", [])
    washing_machine_started = bool(parsed.get("washing_started", false))
    washing_machine_finished = bool(parsed.get("washing_finished", false))
    game_time = float(parsed.get("game_time", 0.0))
    task_history = parsed.get("task_history", [])

    update_inventory_gui()
    update_task_display()
    update_interface()

    show_message("СОХРАНЕНИЕ ЗАГРУЖЕНО", 2.0)


func load_game_settings() -> void:
    if not FileAccess.file_exists(SETTINGS_PATH):
        return

    var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)

    if file == null:
        return

    var parsed = JSON.parse_string(file.get_as_text())
    file.close()

    if parsed is Dictionary:
        for key in parsed:
            settings[key] = parsed[key]


func save_game_settings() -> void:
    var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)

    if file == null:
        return

    file.store_string(JSON.stringify(settings))
    file.close()


# ==================================================
# ENDINGS AND ACCURACY
# ==================================================

func check_ending() -> void:
    var all_completed := true

    for task in task_data:
        if not task["completed"]:
            all_completed = false
            break

    if not all_completed:
        return

    if total_accuracy >= MIN_ACCURACY:
        ending_unlocked = true
        show_message("ВЫПОЛНЕНО. АККУРАТНОСТЬ: " + str(roundi(total_accuracy)) + "%", 6.0)
    else:
        show_message("ЗАДАНИЯ ВЫПОЛНЕНЫ, НО АККУРАТНОСТИ НЕДОСТАТОЧНО", 6.0)


func apply_accuracy_penalty(amount: float) -> void:
    total_accuracy = clampf(total_accuracy - amount, 0.0, 100.0)
    update_interface()


func finish_game() -> void:
    check_ending()

    if ending_unlocked:
        save_game()
        show_message("КОНЕЦ. СПАСИБО ЗА ИГРУ.", 8.0)


# ==================================================
# FINAL FUNCTIONS
# ==================================================

func show_interaction_error() -> void:
    show_message("НЕВОЗМОЖНО ВЗАИМОДЕЙСТВОВАТЬ", 2.0)


func reset_game() -> void:
    inventory.clear()
    task_history.clear()

    current_chapter = 1
    current_task = 0
    total_accuracy = 100.0

    washing_machine_started = false
    washing_machine_finished = false
    ending_unlocked = false

    game_time = 0.0
    blood_events = 0

    save_game()


# ==================================================
# END OF THE BEST SCENE MAIN SCRIPT
# ==================================================

