extends CharacterBody3D

@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export var gravity := 18.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var control_mode := "keyboard"
var touch_joystick: Control
var look_area: Control


func _ready():
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

    touch_joystick = get_node_or_null("../TouchControls/LeftJoystick")
    look_area = get_node_or_null("../TouchControls/LookArea")

    if DisplayServer.is_touchscreen_available():
        control_mode = "touch"


func _input(event):
    if event is InputEventKey and event.pressed:
        control_mode = "keyboard"

    elif event is InputEventMouseButton and event.pressed:
        control_mode = "keyboard"
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

    elif event is InputEventMouseMotion:
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            control_mode = "keyboard"
            head.rotate_y(-event.relative.x * mouse_sensitivity)
            camera.rotate_x(-event.relative.y * mouse_sensitivity)
            camera.rotation.x = clamp(
                camera.rotation.x,
                deg_to_rad(-85),
                deg_to_rad(85)
            )

    elif event is InputEventJoypadMotion:
        if abs(event.axis_value) > 0.2:
            control_mode = "gamepad"

    elif event is InputEventJoypadButton and event.pressed:
        control_mode = "gamepad"

    elif event is InputEventScreenTouch and event.pressed:
        control_mode = "touch"


func _physics_process(delta):
    if not is_on_floor():
        velocity.y -= gravity * delta

    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = jump_velocity

    var input_dir := Vector2.ZERO

    if control_mode == "keyboard":
        input_dir = Input.get_vector(
            "move_left",
            "move_right",
            "move_forward",
            "move_back"
        )

    elif control_mode == "gamepad":
        for id in Input.get_connected_joypads():
            input_dir = Vector2(
                Input.get_joy_axis(id, JOY_AXIS_LEFT_X),
                Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
            )

            if input_dir.length() > 0.2:
                break

    elif control_mode == "touch":
        if touch_joystick and "output" in touch_joystick:
            input_dir = touch_joystick.output

    input_dir = input_dir.limit_length(1.0)

    var direction := (
        head.global_basis.x * input_dir.x
        + head.global_basis.z * input_dir.y
    ).normalized()

    var speed := walk_speed

    if control_mode == "keyboard" and Input.is_action_pressed("sprint"):
        speed = sprint_speed

    velocity.x = direction.x * speed
    velocity.z = direction.z * speed

    move_and_slide()
