extends Button
class_name AnswerButton
## One of the 4 colored answer buttons.

signal answer_clicked(color: String)

const COLOR_HEX := {
	"blue": Color("1976d2"),
	"orange": Color("ff9800"),
	"green": Color("7cb342"),
	"yellow": Color("ffcc32"),
}

## Reuses the same 4 colors as the answer buttons above, in the same order.
const PLAYER_COLORS := {
	"player1": Color("1976d2"),
	"player2": Color("ff9800"),
	"player3": Color("7cb342"),
	"player4": Color("ffcc32"),
}

@export var color_name: String = "blue"

var answer_text: String = "":
	set(value):
		answer_text = value
		_update_label()

@onready var indicator_row: HBoxContainer = $IndicatorRow


func _ready() -> void:
	_apply_color_style()
	_update_label()
	pressed.connect(func(): answer_clicked.emit(color_name))


## Resets the button to the default, pre-reveal appearance, and clears
## player selections.
func reset() -> void:
	self_modulate = Color(1, 1, 1, 1)
	_apply_color_style()
	clear_indicators()


## The game calls this function once all players lock in. It dims wrong
## answers and highlights the correct one. The function uses self_modulate
## (not modulate), so the fade only affects the button itself, not the
## player-name indicator badges on top of it.
func set_reveal_state(is_correct_answer: bool) -> void:
	if is_correct_answer:
		self_modulate = Color(1, 1, 1, 1)
		var base: Color = COLOR_HEX.get(color_name, Color.WHITE)
		var style := StyleBoxFlat.new()
		style.bg_color = base
		style.set_corner_radius_all(4)
		style.set_border_width_all(4)
		style.border_color = Color.WHITE
		add_theme_stylebox_override("normal", style)
	else:
		self_modulate = Color(1, 1, 1, 0.35)


func clear_indicators() -> void:
	for child in indicator_row.get_children():
		child.queue_free()


## Adds an indicator badge at reveal: a solid, high-contrast pill with the
## name of the player (from the lobby name field). This keeps the badge
## readable, regardless of the answer color under it.
func add_indicator(player_key: String, display_name: String, locked_in: bool) -> void:
	var badge := PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color = PLAYER_COLORS.get(player_key, Color.WHITE)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	if locked_in:
		style.border_color = Color.WHITE
		style.set_border_width_all(2)
	badge.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = display_name
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	badge.add_child(label)

	indicator_row.add_child(badge)


func _apply_color_style() -> void:
	var base: Color = COLOR_HEX.get(color_name, Color.WHITE)

	var normal := StyleBoxFlat.new()
	normal.bg_color = base
	normal.set_corner_radius_all(4)
	add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = base.lightened(0.15)
	add_theme_stylebox_override("hover", hover)

	var pressed_style := normal.duplicate()
	pressed_style.bg_color = base.darkened(0.15)
	add_theme_stylebox_override("pressed", pressed_style)

	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_color_override("font_pressed_color", Color.WHITE)


func _update_label() -> void:
	text = answer_text
