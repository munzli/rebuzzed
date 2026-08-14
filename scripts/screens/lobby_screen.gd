extends Control
## Lobby: players join with the Red buzzer, then any player enters the
## Blue -> Orange -> Green -> Yellow sequence to start the game.

signal start_requested()

const REQUIRED_SEQUENCE: Array[String] = ["blue", "orange", "green", "yellow"]
const SEQUENCE_TIMEOUT := 2.0
const COLOR_ICONS := {"blue": "🟦", "orange": "🟧", "green": "🟩", "yellow": "🟨"}

## The bundled color emoji font draws its glyphs with a lot of internal
## padding relative to their advance width. At the same nominal font size,
## these glyphs look much smaller than the blocky glyphs of PressStart2P.
## These icon sizes are boosted well above SEQUENCE_ICON_FONT_SIZE (used for
## the plain-text "TO START:" and arrow labels) to compensate.
const SEQUENCE_ICON_FONT_SIZE := 20
const SEQUENCE_ICON_EMOJI_FONT_SIZE := 26
const SEQUENCE_ICON_EMOJI_PRESSED_FONT_SIZE := 48
const SEQUENCE_ICON_SLOT_SIZE := Vector2(56, 56)

## Color emoji glyphs sit lower within their line box than the glyphs of the
## pixel font. As a result, every emoji Label gets nudged up by this many
## pixels (see _make_emoji_icon()).
const EMOJI_Y_NUDGE := -6.0

const KEYBOARD_HELP_FONT_SIZE := 14
const KEYBOARD_HELP_EMOJI_FONT_SIZE := 22
const KEYBOARD_HELP_EMOJI_SLOT_SIZE := Vector2(32, 32)

## Primary key per player action, mirroring InputManager.KEYBOARD_MAP (P2 to
## P4 are the development and test convenience keys).
const KEYBOARD_HELP := [
	{"label": "P1", "red": "J", "blue": "1", "orange": "2", "green": "3", "yellow": "4"},
	{"label": "P2", "red": "U", "blue": "7", "orange": "8", "green": "9", "yellow": "0"},
	{"label": "P3", "red": "N", "blue": "Num1", "orange": "Num2", "green": "Num3", "yellow": "Num4"},
	{"label": "P4", "red": "M", "blue": "Num6", "orange": "Num7", "green": "Num8", "yellow": "Num9"},
]

@onready var name_inputs: Dictionary = {
	"player1": %NameInputP1,
	"player2": %NameInputP2,
	"player3": %NameInputP3,
	"player4": %NameInputP4,
}
@onready var slot_status: Dictionary = {
	"player1": %SlotStatusP1,
	"player2": %SlotStatusP2,
	"player3": %SlotStatusP3,
	"player4": %SlotStatusP4,
}
@onready var slot_panels: Dictionary = {
	"player1": %SlotPanelP1,
	"player2": %SlotPanelP2,
	"player3": %SlotPanelP3,
	"player4": %SlotPanelP4,
}
@onready var instruction_label: Label = %InstructionLabel
@onready var sequence_row: HBoxContainer = %SequenceRow
@onready var keyboard_grid: GridContainer = %KeyboardGrid
@onready var keyboard_help_panel: PanelContainer = %Panel

var _joined: Dictionary = {"player1": false, "player2": false, "player3": false, "player4": false}
var _start_sequence: Array[String] = []
var _sequence_timer: Timer
var _sequence_icon_labels: Array[Label] = []


func _ready() -> void:
	_sequence_timer = Timer.new()
	_sequence_timer.one_shot = true
	_sequence_timer.wait_time = SEQUENCE_TIMEOUT
	_sequence_timer.timeout.connect(_on_sequence_timeout)
	add_child(_sequence_timer)

	InputManager.button_pressed.connect(_on_button_pressed)
	_style_keyboard_help_panel()
	_build_keyboard_help()
	_build_sequence_row()
	_load_player_names()
	activate()


## Main calls this function whenever this screen becomes active (fresh
## lobby state).
func activate() -> void:
	_start_sequence.clear()
	for key in _joined.keys():
		_joined[key] = false
		slot_panels[key].modulate = Color(1, 1, 1, 0.6)
		slot_status[key].text = "Press 🔴 to join"
	_update_instruction()


func get_display_name(player: String) -> String:
	var input: LineEdit = name_inputs[player]
	var typed := input.text.strip_edges()
	if typed != "":
		return typed
	return "P%s" % player.replace("player", "")


func _settings_path() -> String:
	return QuizEngine.get_external_data_dir().path_join(QuizEngine.SETTINGS_FILENAME)


## Pre-fills the name fields with whoever played last, read from
## data/settings.json (same external, user-editable folder as the quiz files).
func _load_player_names() -> void:
	var path := _settings_path()
	if not FileAccess.file_exists(path):
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var names: Dictionary = parsed.get("player_names", {})
	for key in name_inputs.keys():
		if names.has(key):
			(name_inputs[key] as LineEdit).text = str(names[key])


## Saves whatever text is currently in the name fields, so the fields show
## it again the next time a player starts the game.
func _save_player_names() -> void:
	var names := {}
	for key in name_inputs.keys():
		names[key] = (name_inputs[key] as LineEdit).text

	var file := FileAccess.open(_settings_path(), FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify({"player_names": names}, "\t"))
	file.close()


## Builds the Blue -> Orange -> Green -> Yellow row once, as individual
## fixed-size Label "slots". An increase in the font size of one icon then
## never shifts its neighbors, because the layout size of each slot is
## independent of its content.
func _build_sequence_row() -> void:
	var prefix := Label.new()
	prefix.text = "TO START:"
	prefix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prefix.add_theme_font_size_override("font_size", SEQUENCE_ICON_FONT_SIZE)
	sequence_row.add_child(prefix)

	for i in range(REQUIRED_SEQUENCE.size()):
		if i > 0:
			var arrow := Label.new()
			arrow.text = "→"
			arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			arrow.add_theme_font_size_override("font_size", SEQUENCE_ICON_FONT_SIZE)
			sequence_row.add_child(arrow)

		var icon_text: String = COLOR_ICONS[REQUIRED_SEQUENCE[i]]
		var built := _make_emoji_icon(icon_text, SEQUENCE_ICON_EMOJI_FONT_SIZE, SEQUENCE_ICON_SLOT_SIZE)
		sequence_row.add_child(built.wrapper)
		_sequence_icon_labels.append(built.label)


## Builds an emoji Label wrapped in a plain (non-Container) Control, so a
## fixed pixel nudge survives the layout passes of the outer Container. A
## Container can otherwise reset any position offset applied directly to a
## direct child every time it re-sorts, for example when the font size of a
## sibling changes.
func _make_emoji_icon(
	text: String, font_size: int, slot_size: Vector2 = Vector2.ZERO
) -> Dictionary:
	var wrapper := Control.new()
	if slot_size != Vector2.ZERO:
		wrapper.custom_minimum_size = slot_size

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_top += EMOJI_Y_NUDGE
	label.offset_bottom += EMOJI_Y_NUDGE
	wrapper.add_child(label)

	return {"wrapper": wrapper, "label": label}


func _style_keyboard_help_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(4)
	keyboard_help_panel.add_theme_stylebox_override("panel", style)


func _build_keyboard_help() -> void:
	keyboard_grid.add_child(_keyboard_help_label("", true))
	for header in ["🔴", "🟦", "🟧", "🟩", "🟨"]:
		var size := KEYBOARD_HELP_EMOJI_FONT_SIZE
		var built := _make_emoji_icon(header, size, KEYBOARD_HELP_EMOJI_SLOT_SIZE)
		keyboard_grid.add_child(built.wrapper)

	for row in KEYBOARD_HELP:
		keyboard_grid.add_child(_keyboard_help_label(row.label, true))
		keyboard_grid.add_child(_keyboard_help_label(row.red))
		keyboard_grid.add_child(_keyboard_help_label(row.blue))
		keyboard_grid.add_child(_keyboard_help_label(row.orange))
		keyboard_grid.add_child(_keyboard_help_label(row.green))
		keyboard_grid.add_child(_keyboard_help_label(row.yellow))


func _keyboard_help_label(text: String, emphasized: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", KEYBOARD_HELP_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9 if emphasized else 0.55))
	return label


func _on_button_pressed(player: String, color: String) -> void:
	if not is_visible_in_tree():
		return

	if color == "red":
		_player_join(player)
	elif REQUIRED_SEQUENCE.has(color):
		_handle_start_sequence(color)


func _player_join(player: String) -> void:
	if _joined.get(player, false):
		return

	_joined[player] = true
	slot_panels[player].modulate = Color(1, 1, 1, 1)
	slot_status[player].text = "READY!"
	_update_instruction()


func _handle_start_sequence(color: String) -> void:
	var joined_count: int = _joined.values().count(true)
	if joined_count == 0:
		return

	_start_sequence.append(color)
	_sequence_timer.start()

	var expected: String = REQUIRED_SEQUENCE[_start_sequence.size() - 1]
	if color != expected:
		_start_sequence.clear()
		_update_instruction()
		return

	if _start_sequence.size() == REQUIRED_SEQUENCE.size():
		_start_sequence.clear()
		# Deferred: InputManager.button_pressed is still mid-dispatch to other
		# listeners, for example GameScreen, for this same press. A
		# synchronous screen switch here can let GameScreen, once shown, see
		# this same press too. GameScreen can then mistake it for an answer
		# selection.
		_begin_game.call_deferred()
		return

	_update_instruction()


func _on_sequence_timeout() -> void:
	_start_sequence.clear()
	_update_instruction()


## Shows the full Blue -> Orange -> Green -> Yellow sequence. Icons
## already pressed grow larger in place (fixed-size slots).
func _update_instruction() -> void:
	var joined_count: int = _joined.values().count(true)

	instruction_label.visible = joined_count == 0
	sequence_row.visible = joined_count > 0

	if joined_count == 0:
		instruction_label.text = "PRESS 🔴 TO JOIN"
		return

	for i in range(_sequence_icon_labels.size()):
		var font_size: int = SEQUENCE_ICON_EMOJI_FONT_SIZE
		if i < _start_sequence.size():
			font_size = SEQUENCE_ICON_EMOJI_PRESSED_FONT_SIZE
		_sequence_icon_labels[i].add_theme_font_size_override("font_size", font_size)


func _begin_game() -> void:
	_save_player_names()
	QuizEngine.reset()
	GameState.reset_game()
	for key in _joined.keys():
		if _joined[key]:
			GameState.player_join(key)
	start_requested.emit()
