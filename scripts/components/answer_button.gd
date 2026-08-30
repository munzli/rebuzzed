extends Button
class_name AnswerButton
## One of the 4 colored answer buttons.

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

## Breathing room around the button's (possibly wrapped) text, on each side.
const TEXT_PADDING_HORIZONTAL := 24.0
const TEXT_PADDING_VERTICAL := 10.0

@export var color_name: String = "blue"

var answer_text: String = "":
	set(value):
		answer_text = value
		_update_label()

@onready var indicator_row: HBoxContainer = $IndicatorRow


func _ready() -> void:
	_apply_color_style()
	_update_label()


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
		_apply_text_padding(style)
		add_theme_stylebox_override("normal", style)
	else:
		self_modulate = Color(1, 1, 1, 0.35)


## Returns true if answer_text fits on one line within available_width,
## measured with this button's own font, font size, and text padding.
## GameScreen uses this to decide whether the answer column needs to widen,
## instead of always using the full question width.
func fits_without_wrap(available_width: float) -> bool:
	if answer_text == "":
		return true

	var font: Font = get_theme_font("font")
	var font_size: int = get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(
		answer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x
	return text_width <= available_width - TEXT_PADDING_HORIZONTAL * 2


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
	label.add_theme_font_size_override("font_size", 32)
	badge.add_child(label)

	indicator_row.add_child(badge)


func _apply_color_style() -> void:
	var base: Color = COLOR_HEX.get(color_name, Color.WHITE)

	var normal := StyleBoxFlat.new()
	normal.bg_color = base
	normal.set_corner_radius_all(4)
	_apply_text_padding(normal)
	add_theme_stylebox_override("normal", normal)

	add_theme_color_override("font_color", Color.WHITE)


## Adds breathing room around the button's (possibly wrapped) text, so a
## long answer does not touch the button's edges.
func _apply_text_padding(style: StyleBoxFlat) -> void:
	style.content_margin_left = TEXT_PADDING_HORIZONTAL
	style.content_margin_right = TEXT_PADDING_HORIZONTAL
	style.content_margin_top = TEXT_PADDING_VERTICAL
	style.content_margin_bottom = TEXT_PADDING_VERTICAL


func _update_label() -> void:
	text = answer_text
