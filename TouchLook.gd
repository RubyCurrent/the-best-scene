extends Control

signal look_delta(delta: Vector2)

var active_fingers := {}

func _input(event):
    if event is InputEventScreenTouch:
        if event.pressed:
            if event.position.x >= get_viewport_rect().size.x / 2.0:
                active_fingers[event.index] = event.position
        else:
            active_fingers.erase(event.index)

    elif event is InputEventScreenDrag:
        if active_fingers.has(event.index):
            var delta = event.relative
            look_delta.emit(delta)
