extends Control
## Main gameplay screen: HUD, question, answers, timer, reveal, countdown.

signal game_over_requested()
signal quit_to_lobby_confirmed()

const COLORS: Array[String] = ["blue", "orange", "green", "yellow"]
const PLAYER_KEYS: Array[String] = ["player1", "player2", "player3", "player4"]
const REVEAL_DELAY := 4.0
const COUNTDOWN_DURATION := 3.0

@onready var score_boxes: Dictionary = {
	"player1": %ScoreBoxP1,
	"player2": %ScoreBoxP2,
	"player3": %ScoreBoxP3,
	"player4": %ScoreBoxP4,
}
@onready var answer_buttons: Dictionary = {
	"blue": %AnswerBlue,
	"orange": %AnswerOrange,
	"green": %AnswerGreen,
	"yellow": %AnswerYellow,
}
@onready var question_badge: Label = %QuestionBadge
@onready var question_text: Label = %QuestionText
@onready var timer_value_label: Label = %TimerValue
@onready var countdown_overlay: Control = %CountdownOverlay
@onready var countdown_pie: PieTimer = %CountdownPie
@onready var quit_confirm_overlay: Control = %QuitConfirmOverlay
@onready var quit_confirm_btn: Button = %QuitConfirmBtn
@onready var quit_cancel_btn: Button = %QuitCancelBtn

var display_names: Dictionary = {}
var stats: Dictionary = {"total_questions": 0, "player_correct": {}}
var _revealing := false
var _quit_chord_prev_held := false
var _first_locked_in_player := ""


func _ready() -> void:
	InputManager.button_pressed.connect(_on_button_pressed)
	GameState.timer_updated.connect(_on_timer_updated)
	GameState.time_expired.connect(_on_time_expired)
	for color in answer_buttons.keys():
		(answer_buttons[color] as AnswerButton).answer_clicked.connect(_on_answer_button_clicked)
	countdown_overlay.visible = false

	quit_confirm_overlay.visible = false
	quit_confirm_btn.pressed.connect(_confirm_quit_to_lobby)
	quit_cancel_btn.pressed.connect(_cancel_quit_to_lobby)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if quit_confirm_overlay.visible:
			_cancel_quit_to_lobby()
		else:
			_open_quit_confirm()
		get_viewport().set_input_as_handled()


## When any single player holds blue and yellow together, this also opens
## the confirm dialog, the same as ESC. The game polls this continuously,
## because it is a "hold both at once" gesture, not a discrete button press.
func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return

	var held := _quit_chord_held()
	if quit_confirm_overlay.visible:
		_quit_chord_prev_held = held
		return

	if held and not _quit_chord_prev_held:
		_open_quit_confirm()
	_quit_chord_prev_held = held


## Main calls this function when the lobby hands off to this screen.
func start_game(names: Dictionary) -> void:
	display_names = names
	stats = {"total_questions": QuizEngine.total_questions, "player_correct": {}}
	_revealing = false

	_update_hud()
	_display_question(QuizEngine.get_current_question())
	_update_progress()
	_update_all_scores()

	GameState.set_state(GameState.State.QUESTION_REVEAL)


func get_stats() -> Dictionary:
	return stats


func _quit_chord_held() -> bool:
	for player in PLAYER_KEYS:
		if InputManager.is_color_held(player, "blue") and InputManager.is_color_held(player, "yellow"):
			return true
	return false


func _open_quit_confirm() -> void:
	quit_confirm_overlay.visible = true
	GameState.stop_timer()


func _confirm_quit_to_lobby() -> void:
	quit_confirm_overlay.visible = false
	# Deferred: InputManager.button_pressed can still be mid-dispatch to other
	# listeners, for example LobbyScreen, for this same press. A synchronous
	# screen switch here can let LobbyScreen, once shown, see this same press
	# too. LobbyScreen can then mistake it for a player that joins.
	quit_to_lobby_confirmed.emit.call_deferred()


func _cancel_quit_to_lobby() -> void:
	quit_confirm_overlay.visible = false
	GameState.resume_timer()


func _update_hud() -> void:
	var joined_keys: Array = []
	for p in GameState.get_joined_players():
		joined_keys.append(p.key)

	for key in score_boxes.keys():
		var box: PlayerScoreBox = score_boxes[key]
		box.set_active(joined_keys.has(key))
		box.set_player_name(display_names.get(key, "P%s" % key.replace("player", "")))


func _display_question(question) -> void:
	if question == null:
		return

	for color in answer_buttons.keys():
		var btn: AnswerButton = answer_buttons[color]
		btn.reset()
		var answer_text: String = question.answers.get(color, "")
		btn.answer_text = answer_text
		# opentdb "boolean" questions only fill 2 of the 4 color slots.
		btn.visible = answer_text != ""

	question_text.text = question.question
	_reset_player_statuses()


func _reset_player_statuses() -> void:
	_first_locked_in_player = ""
	for key in score_boxes.keys():
		var box: PlayerScoreBox = score_boxes[key]
		box.set_status("")
		box.set_incorrect(false)
		box.set_first_locked_in(false)


func _update_progress() -> void:
	var progress: Dictionary = QuizEngine.get_progress()
	question_badge.text = "QUESTION %02d/%02d" % [progress.current, progress.total]


func _update_all_scores() -> void:
	for p in GameState.get_joined_players():
		if score_boxes.has(p.key):
			(score_boxes[p.key] as PlayerScoreBox).set_score(p.score)


func _on_button_pressed(player: String, color: String) -> void:
	if not is_visible_in_tree():
		return

	if quit_confirm_overlay.visible:
		# Red confirms, from any player. Any other button cancels and resumes.
		if color == "red":
			_confirm_quit_to_lobby()
		else:
			_cancel_quit_to_lobby()
		return

	if COLORS.has(color):
		_select_answer(player, color)
	elif color == "red":
		var p: Dictionary = GameState.players.get(player, {})
		if p.get("joined", false) and p.get("selection", "") != "":
			_lock_in(player)


func _on_answer_button_clicked(color: String) -> void:
	# Mouse clicks always act as player 1.
	_select_answer("player1", color)


func _select_answer(player: String, color: String) -> void:
	var btn: AnswerButton = answer_buttons.get(color)
	if btn == null or not btn.visible:
		return
	if GameState.select_answer(player, color):
		# The code does not update the per-button indicators here on purpose.
		# Which color a player selects stays hidden from everyone else until
		# the reveal.
		_update_player_status(player)


func _lock_in(player: String) -> void:
	if GameState.lock_in_answer(player):
		if _first_locked_in_player == "":
			_first_locked_in_player = player
			var box: PlayerScoreBox = score_boxes.get(player)
			if box:
				box.set_first_locked_in(true)
		_update_player_status(player)
		if GameState.are_all_players_locked_in():
			_reveal_answer()


func _update_player_status(player: String) -> void:
	var box: PlayerScoreBox = score_boxes.get(player)
	if not box:
		return
	var p: Dictionary = GameState.players[player]
	if p.locked_in:
		box.set_status("⚡" if player == _first_locked_in_player else "✔️")
	elif p.selection != "":
		box.set_status("...")
	else:
		box.set_status("")


func _update_player_indicators() -> void:
	for color in answer_buttons.keys():
		(answer_buttons[color] as AnswerButton).clear_indicators()

	var selections: Dictionary = GameState.get_player_selections()
	for player in selections.keys():
		var data: Dictionary = selections[player]
		var btn: AnswerButton = answer_buttons.get(data.color)
		if btn:
			var display_name: String = display_names.get(player, "P%s" % player.replace("player", ""))
			btn.add_indicator(player, display_name, data.locked_in)


func _on_timer_updated(value: int) -> void:
	var mins := value / 60
	var secs := value % 60
	timer_value_label.text = "%d:%02d" % [mins, secs]

	if value <= 10:
		timer_value_label.add_theme_color_override("font_color", Color("ff0033"))
	else:
		timer_value_label.remove_theme_color_override("font_color")


func _on_time_expired() -> void:
	_reveal_answer()


func _reveal_answer() -> void:
	if _revealing:
		return
	_revealing = true
	GameState.stop_timer()

	var question = QuizEngine.get_current_question()
	if question == null:
		_revealing = false
		return

	var correct_color: String = question.correct
	var base_points: int = question.get("points", 100)
	var results: Array = GameState.verify_all_answers(correct_color, base_points)

	for r in results:
		if r.isCorrect:
			stats.player_correct[r.player] = stats.player_correct.get(r.player, 0) + 1
		if score_boxes.has(r.player):
			(score_boxes[r.player] as PlayerScoreBox).set_incorrect(not r.isCorrect)

	for color in answer_buttons.keys():
		(answer_buttons[color] as AnswerButton).set_reveal_state(color == correct_color)

	# The game shows who picked what only at reveal, never while players are
	# still choosing.
	_update_player_indicators()
	_update_all_scores()

	await get_tree().create_timer(REVEAL_DELAY).timeout

	if QuizEngine.has_more_questions():
		QuizEngine.next_question()
		await _show_countdown()
		_display_question(QuizEngine.get_current_question())
		_update_progress()
		_revealing = false
		GameState.set_state(GameState.State.QUESTION_REVEAL)
	else:
		_revealing = false
		game_over_requested.emit()


## Smoothly drains a pie timer over COUNTDOWN_DURATION before the next 
## question appears.
func _show_countdown() -> void:
	countdown_overlay.visible = true
	countdown_pie.progress = 1.0

	var tween := create_tween()
	tween.tween_property(countdown_pie, "progress", 0.0, COUNTDOWN_DURATION)
	await tween.finished

	countdown_overlay.visible = false
