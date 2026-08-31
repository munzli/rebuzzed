extends Node
## Game state machine: player management, scoring, timer.
## Autoloaded as "GameState".
##
## States: LOBBY -> QUESTION_REVEAL -> ANSWERING -> VERIFICATION -> SCOREBOARD
## -> (repeat or GAME_OVER)

signal state_changed(from_state: int, to_state: int)
signal player_joined(player: String)
signal answer_selected(player: String, color: String)
signal answer_locked_in(player: String, color: String)
signal all_players_locked_in()
signal answers_verified(correct_color: String, results: Array)
signal timer_updated(value: int)
signal time_expired()

enum State { LOBBY, QUESTION_REVEAL, ANSWERING, VERIFICATION, SCOREBOARD, GAME_OVER }

const PLAYER_KEYS := ["player1", "player2", "player3", "player4"]

var current_state: int = State.LOBBY

var players: Dictionary = {}

var settings: Dictionary = {
	"time_per_question": 30,
	"speed_bonus_max": 100,
	"points_wrong": 0
}

var round_data: Dictionary = {
	"timer_start_time": 0,
	"timer_value": 20,
	"correct_answer": ""
}

var _timer: Timer


func _ready() -> void:
	_init_players()
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.one_shot = false
	_timer.timeout.connect(_on_timer_tick)
	add_child(_timer)


## Moves to a new state.
func set_state(new_state: int) -> void:
	var old_state := current_state
	current_state = new_state
	state_changed.emit(old_state, new_state)

	match new_state:
		State.LOBBY:
			reset_round()
		State.QUESTION_REVEAL:
			reset_round_selections()
			start_timer()
		State.VERIFICATION:
			stop_timer()


## Adds a player to the game. This happens when the player presses the Red
## buzzer in the lobby.
func player_join(player_key: String) -> bool:
	if not players.has(player_key):
		return false

	var p: Dictionary = players[player_key]
	p.joined = true
	p.score = 0
	p.selection = ""
	p.locked_in = false

	player_joined.emit(player_key)
	return true


func get_joined_players() -> Array:
	var result := []
	for key in PLAYER_KEYS:
		var p: Dictionary = players[key]
		if p.joined:
			var entry := p.duplicate()
			entry["key"] = key
			result.append(entry)
	return result


func get_joined_player_count() -> int:
	return get_joined_players().size()


## Records an answer selection when a player picks a color. The player can
## change the answer until they lock it in.
func select_answer(player_key: String, color: String) -> bool:
	if current_state != State.ANSWERING and current_state != State.QUESTION_REVEAL:
		return false
	if not players.has(player_key):
		return false

	var p: Dictionary = players[player_key]
	if not p.joined or p.locked_in:
		return false

	p.selection = color
	answer_selected.emit(player_key, color)
	return true


## Locks in the answer. This happens when the player presses Red to confirm.
func lock_in_answer(player_key: String) -> bool:
	if current_state != State.ANSWERING and current_state != State.QUESTION_REVEAL:
		return false
	if not players.has(player_key):
		return false

	var p: Dictionary = players[player_key]
	if not p.joined or p.selection == "":
		return false
	if p.locked_in:
		return false

	p.locked_in = true
	p.lock_in_time = Time.get_ticks_msec()

	answer_locked_in.emit(player_key, p.selection)

	if are_all_players_locked_in():
		all_players_locked_in.emit()

	return true


func are_all_players_locked_in() -> bool:
	var joined := get_joined_players()
	if joined.is_empty():
		return false
	for p in joined:
		if not p.locked_in:
			return false
	return true


func get_player_selections() -> Dictionary:
	var result := {}
	for key in PLAYER_KEYS:
		var p: Dictionary = players[key]
		if p.joined and p.selection != "":
			result[key] = {"color": p.selection, "locked_in": p.locked_in}
	return result


## Scores all answers and awards points. Base points come from the difficulty
## of the question (see the opentdb difficulty-to-points mapping in
## QuizEngine). Speed bonus: a faster lock-in gives more bonus points, up to
## speed_bonus_max.
func verify_all_answers(correct_color: String, base_points: int = 100) -> Array:
	round_data.correct_answer = correct_color
	var results := []
	var total_time_ms: int = settings.time_per_question * 1000

	for key in PLAYER_KEYS:
		var p: Dictionary = players[key]
		if not p.joined:
			continue

		var is_correct: bool = p.selection == correct_color
		var points_earned := 0
		var speed_bonus := 0

		if p.selection != "" and is_correct:
			points_earned = base_points

			if p.lock_in_time > 0 and round_data.timer_start_time > 0:
				var elapsed_ms: int = p.lock_in_time - round_data.timer_start_time
				var remaining_ratio: float = max(0.0, 1.0 - (float(elapsed_ms) / float(total_time_ms)))
				speed_bonus = roundi(remaining_ratio * settings.speed_bonus_max)
				points_earned += speed_bonus

			p.score += points_earned

		results.append({
			"player": key,
			"selection": p.selection,
			"isCorrect": is_correct,
			"pointsEarned": points_earned,
			"speedBonus": speed_bonus,
			"newScore": p.score
		})

	answers_verified.emit(correct_color, results)
	return results


func start_timer() -> void:
	round_data.timer_value = settings.time_per_question
	round_data.timer_start_time = Time.get_ticks_msec()
	timer_updated.emit(round_data.timer_value)
	_timer.start()


func stop_timer() -> void:
	_timer.stop()


## Resumes the timer without a reset of timer_value (unlike start_timer()).
## The game calls this function to resume the timer after a canceled
## "return to lobby" confirmation.
func resume_timer() -> void:
	_timer.start()


## Resets the selections for the round. The timer keeps running.
func reset_round_selections() -> void:
	round_data.correct_answer = ""
	round_data.timer_start_time = 0
	for key in PLAYER_KEYS:
		var p: Dictionary = players[key]
		p.selection = ""
		p.locked_in = false
		p.lock_in_time = 0


## Resets the round data for the next question.
func reset_round() -> void:
	stop_timer()
	reset_round_selections()
	round_data.timer_value = settings.time_per_question


func get_score(player_key: String = "player1") -> int:
	return players.get(player_key, {}).get("score", 0)


## Resets the game. This keeps the 'joined' flags, which reset when the
## lobby restarts.
func reset_game() -> void:
	for key in PLAYER_KEYS:
		var p: Dictionary = players[key]
		p.score = 0
		p.lock_in_time = 0
		p.selection = ""
		p.locked_in = false
	reset_round()


## Clears the 'joined' flags. The game calls this function when it returns
## to the lobby screen.
func clear_joined() -> void:
	for key in PLAYER_KEYS:
		players[key].joined = false


func _init_players() -> void:
	for key in PLAYER_KEYS:
		players[key] = _new_player()


func _new_player() -> Dictionary:
	return {
		"joined": false,
		"score": 0,
		"selection": "",
		"locked_in": false,
		"lock_in_time": 0
	}


func _on_timer_tick() -> void:
	round_data.timer_value -= 1
	timer_updated.emit(round_data.timer_value)
	if round_data.timer_value <= 0:
		stop_timer()
		time_expired.emit()
