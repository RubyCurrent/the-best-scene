
extends Node3D

var player: CharacterBody3D
var head: Node3D
var camera: Camera3D

var joystick: Vector2 = Vector2.ZERO
var joystick_finger := -1
var look_finger := -1
var joystick_center := Vector2.ZERO
var joystick_pos := Vector2.ZERO

var active_mode := "keyboard"
var gravity := 18.0
var speed := 5.0
var sensitivity := 0.0025

var touch_ui: CanvasLayer
var stick_base: Control
var stick_knob: Control
var look_zone: Control


func _ready():
    create_world()
    create_player()
    create_touch_controls()

    if DisplayServer.is_touchscreen_available():
        active_mode = "touch"
    else:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func create_world():
    var ground = StaticBody3D.new()
    ground.name = "Ground"

    var mesh = MeshInstance3D.new()
    var box = BoxMesh.new()
    box.size = Vector3(100, 1, 100)
    mesh.mesh = box

    var material = StandardMaterial3D.new()
    material.albedo_color = Color(0.3, 0.35, 0.4)
    mesh.material_override = material
    mesh.position.y = -0.5
    ground.add_child(mesh)

    var collision = CollisionShape3D.new()
    var shape = BoxShape3D.new()
    shape.size = Vector3(100, 1, 100)
    collision.shape = shape
    collision.position.y = -0.5
    ground.add_child(collision)

    add_child(ground)


func create_player():
    player = CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(0, 1, 0)
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
    head.add_child(camera)


func create_touch_controls():
    touch_ui = CanvasLayer.new()
    touch_ui.name = "TouchControls"
    add_child(touch_ui)

    stick_base = Control.new()
    stick_base.custom_minimum_size = Vector2(180, 180)
    stick_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    stick_base.position = Vector2(35, -210)
    stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
    touch_ui.add_child(stick_base)

    stick_knob = Control.new()
    stick_knob.custom_minimum_size = Vector2(65, 65)
    stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
    stick_base.add_child(stick_knob)

    look_zone = Control.new()
    look_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
    look_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
    touch_ui.add_child(look_zone)

    touch_ui.visible = DisplayServer.is_touchscreen_available()


func _input(event):
    if event is InputEventKey:
        if event.pressed:
            active_mode = "keyboard"
            touch_ui.visible = false

    elif event is InputEventMouseMotion:
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            active_mode = "keyboard"
            rotate_camera(event.relative)

    elif event is InputEventJoypadMotion:
        if abs(event.axis_value) > 0.2:
            active_mode = "gamepad"
            touch_ui.visible = false

    elif event is InputEventJoypadButton:
        if event.pressed:
            active_mode = "gamepad"
            touch_ui.visible = false

    elif event is InputEventMouseButton:
        if event.pressed:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

    elif event is InputEventScreenTouch:
        if event.pressed:
            if event.position.x < get_viewport().size.x * 0.5:
                if joystick_finger == -1:
                    joystick_finger = event.index
                    joystick_center = event.position
                    active_mode = "touch"
                    touch_ui.visible = true
            else:
                look_finger = event.index
                active_mode = "touch"
                touch_ui.visible = true
        else:
            if event.index == joystick_finger:
                joystick_finger = -1
                joystick = Vector2.ZERO
                stick_knob.position = Vector2.ZERO

            if event.index == look_finger:
                look_finger = -1

    elif event is InputEventScreenDrag:
        if event.index == joystick_finger:
            var offset = event.position - joystick_center
            joystick = (offset / 85.0).limit_length(1.0)
            stick_knob.position = joystick * 55.0

        elif event.index == look_finger:
            rotate_camera(event.relative)


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

    if Input.is_action_just_pressed("jump") and player.is_on_floor():
        player.velocity.y = 4.5

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

    var current_speed = speed

    if Input.is_key_pressed(KEY_SHIFT):
        current_speed = 8.0

    player.velocity.x = direction.x * current_speed
    player.velocity.z = direction.z * current_speed

    player.move_and_slide()
