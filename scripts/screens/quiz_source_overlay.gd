extends Control
class_name QuizSourceOverlay
## Lets a player pick the quiz source: local files, or a category fetched
## live from opentdb.com. Any player, any controller, matching the rest of
## the lobby. Navigation: Blue/Green move the cursor, Orange/Yellow adjust
## the question amount, Red confirms the highlighted row. "Back" is just the
## top row of the category list, so no separate cancel gesture is needed on
## a controller (ESC also works, for keyboard testing).

signal closed(new_state: Dictionary)

enum Mode { SOURCE_SELECT, CATEGORY_SELECT }

const CATEGORY_API_URL := "https://opentdb.com/api_category.php"
const QUESTIONS_API_URL := "https://opentdb.com/api.php"
const AMOUNT_MIN := 5
const AMOUNT_MAX := 50
const AMOUNT_STEP := 5
const AMOUNT_DEFAULT := 15
const FETCH_COOLDOWN_SEC := 5.5

const BACK_ID := -2
const ANY_CATEGORY_ID := -1

@onready var title_label: Label = %TitleLabel
@onready var amount_row: Control = %AmountRow
@onready var amount_label: Label = %AmountLabel
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var rows_container: VBoxContainer = %RowsContainer
@onready var status_label: Label = %StatusLabel
@onready var category_request: HTTPRequest = %CategoryRequest
@onready var questions_request: HTTPRequest = %QuestionsRequest

var _mode: int = Mode.SOURCE_SELECT
var _cursor: int = 0
var _amount: int = AMOUNT_DEFAULT
var _categories: Array = []
var _category_rows: Array = []
var _row_labels: Array[Label] = []
var _fetching := false
var _cooldown_until_msec: int = 0
var _saved_state: Dictionary = {}


func _ready() -> void:
	visible = false
	InputManager.button_pressed.connect(_on_button_pressed)
	category_request.request_completed.connect(_on_category_request_completed)
	questions_request.request_completed.connect(_on_questions_request_completed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_ESCAPE:
			_close({})
			get_viewport().set_input_as_handled()
		KEY_UP:
			_move_cursor(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_move_cursor(1)
			get_viewport().set_input_as_handled()


## Opens the overlay. The lobby passes in the last-used picker state (from
## data/settings.json), so the cursor starts where the group left off.
func open(saved_state: Dictionary = {}) -> void:
	_saved_state = saved_state
	_amount = clampi(int(saved_state.get("amount", AMOUNT_DEFAULT)), AMOUNT_MIN, AMOUNT_MAX)
	_fetching = false
	status_label.text = ""
	visible = true
	_show_source_select()


func _show_source_select() -> void:
	_mode = Mode.SOURCE_SELECT
	title_label.text = "QUIZ SOURCE"
	amount_row.visible = false
	status_label.text = ""

	_category_rows = [
		{"id": "local", "name": "LOCAL FILES"},
		{"id": "online", "name": "ONLINE (opentdb.com)"},
	]
	_cursor = 1 if _saved_state.get("mode", "local") == "online" else 0
	_rebuild_rows()


func _show_category_select() -> void:
	_mode = Mode.CATEGORY_SELECT
	title_label.text = "CHOOSE A CATEGORY"
	amount_row.visible = true
	_update_amount_label()

	if _categories.is_empty():
		_fetch_categories()
		return

	_populate_category_rows()


func _on_button_pressed(_player: String, color: String) -> void:
	if not visible or _fetching:
		return

	match color:
		"blue":
			_move_cursor(-1)
		"green":
			_move_cursor(1)
		"orange":
			_adjust_amount(-AMOUNT_STEP)
		"yellow":
			_adjust_amount(AMOUNT_STEP)
		"red":
			_confirm_cursor()


func _move_cursor(delta: int) -> void:
	if _row_labels.is_empty():
		return
	status_label.text = ""
	_cursor = clampi(_cursor + delta, 0, _row_labels.size() - 1)
	_update_row_highlight()


func _adjust_amount(delta: int) -> void:
	if _mode != Mode.CATEGORY_SELECT:
		return
	_amount = clampi(_amount + delta, AMOUNT_MIN, AMOUNT_MAX)
	_update_amount_label()


func _update_amount_label() -> void:
	amount_label.text = "QUESTIONS: %d   (🟧 −5 / 🟨 +5)" % _amount


func _confirm_cursor() -> void:
	if _cursor < 0 or _cursor >= _category_rows.size():
		return
	var row: Dictionary = _category_rows[_cursor]

	if _mode == Mode.SOURCE_SELECT:
		if row.id == "local":
			QuizEngine.load_quiz()
			_close({"mode": "local", "amount": _amount})
		else:
			_show_category_select()
		return

	if row.id == BACK_ID:
		_show_source_select()
	else:
		_fetch_questions(row)


func _populate_category_rows() -> void:
	_category_rows = [
		{"id": BACK_ID, "name": "← BACK"},
		{"id": ANY_CATEGORY_ID, "name": "ANY CATEGORY"},
	]
	_category_rows.append_array(_categories)

	var saved_id: int = int(_saved_state.get("category_id", ANY_CATEGORY_ID))
	_cursor = 0
	for i in range(_category_rows.size()):
		if int(_category_rows[i].id) == saved_id:
			_cursor = i
			break

	_rebuild_rows()


func _rebuild_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()
	_row_labels.clear()

	for row in _category_rows:
		var label := Label.new()
		label.text = row.name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows_container.add_child(label)
		_row_labels.append(label)

	_update_row_highlight()


func _update_row_highlight() -> void:
	for i in range(_row_labels.size()):
		var label := _row_labels[i]
		label.add_theme_color_override("font_color", Color.WHITE if i == _cursor else Color(1, 1, 1, 0.5))
	if _cursor >= 0 and _cursor < _row_labels.size():
		scroll_container.ensure_control_visible(_row_labels[_cursor])


func _fetch_categories() -> void:
	status_label.text = "Loading categories..."
	var err := category_request.request(CATEGORY_API_URL)
	if err != OK:
		status_label.text = "Could not reach opentdb.com."


func _on_category_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "Network error. Press 🔴 on BACK and try again."
		_category_rows = [{"id": BACK_ID, "name": "← BACK"}]
		_cursor = 0
		_rebuild_rows()
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("trivia_categories"):
		status_label.text = "Unexpected response from opentdb.com."
		_category_rows = [{"id": BACK_ID, "name": "← BACK"}]
		_cursor = 0
		_rebuild_rows()
		return

	_categories = []
	for c in parsed.trivia_categories:
		_categories.append({"id": int(c.id), "name": String(c.name)})

	status_label.text = ""
	_populate_category_rows()


func _fetch_questions(row: Dictionary) -> void:
	if Time.get_ticks_msec() < _cooldown_until_msec:
		status_label.text = "Please wait a moment before fetching again."
		return

	_fetching = true
	status_label.text = "Fetching questions..."

	var url := "%s?amount=%d" % [QUESTIONS_API_URL, _amount]
	if int(row.id) != ANY_CATEGORY_ID:
		url += "&category=%d" % int(row.id)

	var err := questions_request.request(url)
	if err != OK:
		_fetching = false
		status_label.text = "Could not reach opentdb.com."


func _on_questions_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_fetching = false
	_cooldown_until_msec = Time.get_ticks_msec() + int(FETCH_COOLDOWN_SEC * 1000)

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "Network error. Try again in a few seconds."
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		status_label.text = "Unexpected response from opentdb.com."
		return

	var code: int = int(parsed.get("response_code", -1))
	if code == 5:
		status_label.text = "Too many requests. Wait a few seconds and try again."
		return
	if code != 0:
		status_label.text = "No questions available for that category. Try another."
		return

	var category_row: Dictionary = _category_rows[_cursor]
	var category_name: String = String(category_row.name)
	QuizEngine.load_remote_quiz(parsed, category_name)
	_close({
		"mode": "online",
		"category_id": int(category_row.id),
		"category_name": category_name,
		"amount": _amount,
	})


func _close(new_state: Dictionary) -> void:
	# Deferred: InputManager.button_pressed can still be mid-dispatch to other
	# listeners, for example LobbyScreen, for this same press. Closing the
	# overlay synchronously here would let LobbyScreen's still-open guard
	# check miss this same press and mistake it for a player that joins.
	_finish_close.call_deferred(new_state)


func _finish_close(new_state: Dictionary) -> void:
	visible = false
	closed.emit(new_state)
