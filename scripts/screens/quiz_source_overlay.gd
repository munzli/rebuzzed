extends Control
class_name QuizSourceOverlay
## Lets a player pick the quiz source: local files, or a category fetched
## live from opentdb.com or the-trivia-api.com. This matches the rest of
## the lobby: any player, on any controller, can use it. Navigation: Blue
## or Green move the cursor. Orange or Yellow adjust the question amount.
## Red confirms the highlighted row. "Back" is just the top row of the
## category list, so a controller does not need a separate cancel gesture
## (ESC also works, for keyboard testing).
##
## Both opentdb.com and the-trivia-api.com list their categories live over
## the network: opentdb.com via api_category.php, the-trivia-api.com via its
## /v2/metadata endpoint (its category slugs are not otherwise documented).

signal closed(new_state: Dictionary)

enum Mode { SOURCE_SELECT, CATEGORY_SELECT }

const OPENTDB_CATEGORY_URL := "https://opentdb.com/api_category.php"
const OPENTDB_QUESTIONS_URL := "https://opentdb.com/api.php"
const TRIVIA_API_METADATA_URL := "https://the-trivia-api.com/v2/metadata"
const TRIVIA_API_QUESTIONS_URL := "https://the-trivia-api.com/v2/questions"
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
var _provider: String = ""
var _cursor: int = 0
var _amount: int = AMOUNT_DEFAULT
var _opentdb_categories: Array = []
var _trivia_api_categories: Array = []
var _category_rows: Array = []
var _row_labels: Array[Label] = []
var _fetching := false
var _opentdb_cooldown_until_msec: int = 0
var _trivia_api_cooldown_until_msec: int = 0
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
	_provider = ""
	title_label.text = "QUIZ SOURCE"
	amount_row.visible = false
	status_label.text = ""

	_category_rows = [
		{"id": "local", "name": "LOCAL FILES"},
		{"id": "opentdb", "name": "OPENTDB.COM"},
		{"id": "trivia_api", "name": "THE TRIVIA API"},
	]
	var saved_mode: String = String(_saved_state.get("mode", "local"))
	_cursor = 0
	for i in range(_category_rows.size()):
		if _category_rows[i].id == saved_mode:
			_cursor = i
			break
	_rebuild_rows()


func _show_category_select() -> void:
	_mode = Mode.CATEGORY_SELECT
	title_label.text = "CHOOSE A CATEGORY"
	amount_row.visible = true
	_update_amount_label()

	if _provider == "trivia_api":
		if _trivia_api_categories.is_empty():
			# Clears the still-visible previous rows immediately, instead of
			# leaving them on screen (and confirmable) until the fetch below
			# completes.
			_category_rows = []
			_rebuild_rows()
			_fetch_trivia_api_categories()
			return
		_populate_category_rows(_trivia_api_categories)
		return

	if _opentdb_categories.is_empty():
		# Clears the still-visible previous rows immediately, instead of
		# leaving them on screen (and confirmable) until the fetch below
		# completes.
		_category_rows = []
		_rebuild_rows()
		_fetch_opentdb_categories()
		return
	_populate_category_rows(_opentdb_categories)


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
			_provider = String(row.id)
			_show_category_select()
		return

	# typeof() must run first: GDScript's == errors on mismatched types
	# instead of just returning false, and a the-trivia-api.com category id
	# is a String, not an int like BACK_ID.
	if typeof(row.id) == TYPE_INT and row.id == BACK_ID:
		_show_source_select()
	else:
		_fetch_questions(row)


func _populate_category_rows(categories: Array) -> void:
	_category_rows = [
		{"id": BACK_ID, "name": "← BACK"},
		{"id": ANY_CATEGORY_ID, "name": "ANY CATEGORY"},
	]
	_category_rows.append_array(categories)

	# typeof() must run first: GDScript's == errors on mismatched types
	# instead of just returning false. saved_id can be a leftover the-trivia-
	# api.com String slug while these rows are opentdb.com's int ids, or the
	# reverse.
	var saved_id = _saved_state.get("category_id", ANY_CATEGORY_ID)
	_cursor = 0
	for i in range(_category_rows.size()):
		var row_id = _category_rows[i].id
		if typeof(row_id) == typeof(saved_id) and row_id == saved_id:
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
		label.add_theme_font_size_override("font_size", 32)
		rows_container.add_child(label)
		_row_labels.append(label)

	_update_row_highlight()


func _update_row_highlight() -> void:
	for i in range(_row_labels.size()):
		var label := _row_labels[i]
		label.add_theme_color_override("font_color", Color.WHITE if i == _cursor else Color(1, 1, 1, 0.5))
	if _cursor >= 0 and _cursor < _row_labels.size():
		scroll_container.ensure_control_visible(_row_labels[_cursor])


func _fetch_opentdb_categories() -> void:
	# Locks button input (see _on_button_pressed) until the fetch completes,
	# the same as a question fetch. Without this, a player can switch to a
	# different row, or a different provider, while the fetch is still in
	# flight. The player can then confirm a row that no longer matches what
	# the fetch returns.
	_fetching = true
	status_label.text = "Loading categories..."
	var err := category_request.request(OPENTDB_CATEGORY_URL)
	if err != OK:
		_fetching = false
		status_label.text = "Could not reach opentdb.com."


func _fetch_trivia_api_categories() -> void:
	# Same input lock as _fetch_opentdb_categories() above, and for the same
	# reason.
	_fetching = true
	status_label.text = "Loading categories..."
	var err := category_request.request(TRIVIA_API_METADATA_URL)
	if err != OK:
		_fetching = false
		status_label.text = "Could not reach the-trivia-api.com."


func _on_category_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_fetching = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "Network error. Press 🔴 on BACK and try again."
		_category_rows = [{"id": BACK_ID, "name": "← BACK"}]
		_cursor = 0
		_rebuild_rows()
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())

	if _provider == "trivia_api":
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("byCategory"):
			status_label.text = "Unexpected response from the-trivia-api.com."
			_category_rows = [{"id": BACK_ID, "name": "← BACK"}]
			_cursor = 0
			_rebuild_rows()
			return

		var slugs: Array = parsed.byCategory.keys()
		slugs.sort()
		_trivia_api_categories = []
		for slug in slugs:
			_trivia_api_categories.append(
				{"id": String(slug), "name": QuizEngine.trivia_api_category_display_name(String(slug))}
			)

		status_label.text = ""
		_populate_category_rows(_trivia_api_categories)
		return

	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("trivia_categories"):
		status_label.text = "Unexpected response from opentdb.com."
		_category_rows = [{"id": BACK_ID, "name": "← BACK"}]
		_cursor = 0
		_rebuild_rows()
		return

	_opentdb_categories = []
	for c in parsed.trivia_categories:
		_opentdb_categories.append({"id": int(c.id), "name": String(c.name)})

	status_label.text = ""
	_populate_category_rows(_opentdb_categories)


func _fetch_questions(row: Dictionary) -> void:
	var cooldown_until: int = (
		_trivia_api_cooldown_until_msec if _provider == "trivia_api" else _opentdb_cooldown_until_msec
	)
	if Time.get_ticks_msec() < cooldown_until:
		status_label.text = "Please wait a moment before fetching again."
		return

	_fetching = true
	status_label.text = "Fetching questions..."

	var url: String
	if _provider == "trivia_api":
		url = "%s?limit=%d&types=text_choice" % [TRIVIA_API_QUESTIONS_URL, _amount]
		# typeof() must run first: GDScript's == errors on mismatched types
		# instead of just returning false, and a real category id here is a
		# String, not an int like ANY_CATEGORY_ID.
		var is_any_category: bool = typeof(row.id) == TYPE_INT and row.id == ANY_CATEGORY_ID
		if not is_any_category:
			url += "&categories=%s" % String(row.id)
	else:
		url = "%s?amount=%d" % [OPENTDB_QUESTIONS_URL, _amount]
		if int(row.id) != ANY_CATEGORY_ID:
			url += "&category=%d" % int(row.id)

	var err := questions_request.request(url)
	if err != OK:
		_fetching = false
		status_label.text = "Could not reach the quiz server."


func _on_questions_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_fetching = false
	var cooldown_until := Time.get_ticks_msec() + int(FETCH_COOLDOWN_SEC * 1000)
	if _provider == "trivia_api":
		_trivia_api_cooldown_until_msec = cooldown_until
	else:
		_opentdb_cooldown_until_msec = cooldown_until

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "Network error. Try again in a few seconds."
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var category_row: Dictionary = _category_rows[_cursor]
	var category_name: String = String(category_row.name)

	if _provider == "trivia_api":
		if typeof(parsed) != TYPE_ARRAY:
			status_label.text = "Unexpected response from the-trivia-api.com."
			return
		if parsed.is_empty():
			status_label.text = "No questions available for that category. Try another."
			return
		QuizEngine.load_trivia_api_quiz(parsed, category_name)
	else:
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
		QuizEngine.load_remote_quiz(parsed, category_name)

	_close({
		"mode": _provider,
		"category_id": category_row.id,
		"category_name": category_name,
		"amount": _amount,
	})


func _close(new_state: Dictionary) -> void:
	# Deferred: InputManager.button_pressed can still be mid-dispatch to other
	# listeners, for example LobbyScreen, for this same press. A synchronous
	# close here can let LobbyScreen's still-open guard check miss this same
	# press, and mistake it for a player that joins.
	_finish_close.call_deferred(new_state)


func _finish_close(new_state: Dictionary) -> void:
	visible = false
	closed.emit(new_state)
