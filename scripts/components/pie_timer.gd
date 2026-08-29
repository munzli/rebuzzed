extends Control
class_name PieTimer
## Circular "pie" progress indicator, drawn procedurally (no texture assets
## needed). `progress` is a 0..1 fraction: 1.0 = full circle, 0.0 = empty,
## sweeping clockwise from the top like a clock face.

@export var fill_color: Color = Color("f44336")
@export var background_color: Color = Color(1, 1, 1, 0.15)
@export var segments: int = 64

var progress: float = 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius: float = min(size.x, size.y) / 2.0

	draw_circle(center, radius, background_color)

	if progress <= 0.0:
		return

	var start_angle := -PI / 2.0
	var end_angle := start_angle + progress * TAU

	var points := PackedVector2Array()
	points.append(center)
	for i in range(segments + 1):
		var t: float = lerpf(start_angle, end_angle, float(i) / float(segments))
		points.append(center + Vector2(cos(t), sin(t)) * radius)

	draw_colored_polygon(points, fill_color)
