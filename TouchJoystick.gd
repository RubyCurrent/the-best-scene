
extends Control

@export var joystick_radius := 90.0
@export var knob_radius := 32.0

var output := Vector2.ZERO
var finger_id := -1
var knob_position := Vector2.ZERO
var active := false


func _ready():
    custom_minimum_size = Vector2(200, 200)
    queue_redraw()


func _draw():
    var center = size / 2.0

    draw_circle(
        center,
        joystick_radius,
        Color(0.15, 0.15, 0.15, 0.45)
    )

    draw_arc(
        center,
        joystick_radius,
        0,
        TAU,
        64,
        Color(1, 1, 1, 0.35),
        3
    )

    var knob = center + knob_position

    draw_circle(
        knob,
        knob_radius,
        Color(0.8, 0.8, 0.8, 0.8)
    )


func _input(event):
    if event is InputEventScreenTouch:
        if event.pressed:
            if finger_id == -1 and get_global_rect().has_point(event.position):
                finger_id = event.index
                active = true
                _update_stick(event.position)

        elif event.index == finger_id:
            _release_stick()

    elif event is InputEventScreenDrag:
        if event.index == finger_id:
            _update_stick(event.position)


func _update_stick(position: Vector2):
    var center = global_position + size / 2.0
    var offset = position - center

    knob_position = offset.limit_length(joystick_radius)

    output = knob_position / joystick_radius

    if output.length() < 0.12:
        output = Vector2.ZERO

    queue_redraw()


func _release_stick():
    finger_id = -1
    active = false
    output = Vector2.ZERO
    knob_position = Vector2.ZERO
    queue_redraw()
