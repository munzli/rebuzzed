extends PanelContainer
class_name PlayerScoreBox
## HUD box for one player: name, score, selection and lock status.

## Reuses the same 4 colors as the answer buttons, in the same order.
const PLAYER_COLORS := {
	"player1": Color("1976d2"),
	"player2": Color("ff9800"),
	"player3": Color("7cb342"),
	"player4": Color("ffcc32"),
}

@export var player_key: String = "player1"

@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var score_label: Label = $VBoxContainer/ScoreLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var incorrect_mark: Label = $IncorrectMark

var _first_locked_in := false


func _ready() -> void:
	_apply_border_color()
	set_active(false)


func set_active(active: bool) -> void:
	modulate.a = 1.0 if active else 0.4


func set_player_name(player_name: String) -> void:
	name_label.text = player_name


func set_score(score: int) -> void:
	score_label.text = _format_number(score)


func set_status(status: String) -> void:
	status_label.text = status


## Shows or hides a big red X over the box, for a wrong or unanswered
## reveal.
func set_incorrect(is_incorrect: bool) -> void:
	incorrect_mark.visible = is_incorrect


## Highlights the box with a gold border for whichever player locked in
## first this round.
func set_first_locked_in(is_first: bool) -> void:
	_first_locked_in = is_first
	_apply_border_color()


func _apply_border_color() -> void:
	var c: Color = PLAYER_COLORS.get(player_key, Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.border_color = c
	style.set_border_width_all(5 if _first_locked_in else 3)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)


func _format_number(n: int) -> String:
	var digits := str(n)
	var result := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		result = digits[i] + result
		count += 1
		if count % 3 == 0 and i != 0:
			result = "," + result
	return result
