extends Control
## Final scoreboard, stats, and restart.

signal restart_requested()

@onready var final_scores_list: VBoxContainer = %FinalScoresList
@onready var play_again_btn: Button = %PlayAgainBtn


func _ready() -> void:
	play_again_btn.pressed.connect(func(): restart_requested.emit())
	InputManager.button_pressed.connect(_on_button_pressed)


func show_results(display_names: Dictionary, stats: Dictionary) -> void:
	for child in final_scores_list.get_children():
		child.queue_free()

	var joined: Array = GameState.get_joined_players()
	joined.sort_custom(func(a, b): return a.score > b.score)

	var total_questions: int = stats.get("total_questions", 0)
	var player_correct: Dictionary = stats.get("player_correct", {})

	for i in range(joined.size()):
		var player: Dictionary = joined[i]
		var fallback_name := "P%s" % player.key.replace("player", "")
		var display_name: String = display_names.get(player.key, fallback_name)
		var correct_count: int = player_correct.get(player.key, 0)
		final_scores_list.add_child(
			_build_score_row(i, player, display_name, correct_count, total_questions)
		)


func _build_score_row(
	rank_index: int, player: Dictionary, display_name: String, correct_count: int, total_questions: int
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if rank_index == 0:
		row.modulate = Color("ffd700")

	var rank_label := Label.new()
	rank_label.text = _rank_text(rank_index)
	rank_label.custom_minimum_size = Vector2(60, 0)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Medal emoji (top 3) need a bigger size than the "#4" text fallback, to
	# look right next to the pixel font. The bundled color emoji font draws
	# glyphs with a lot of internal padding relative to their advance width.
	rank_label.add_theme_font_size_override("font_size", 32 if rank_index < 3 else 20)
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(220, 0)
	row.add_child(name_label)

	var score_label := Label.new()
	score_label.text = _format_number(int(player.score))
	score_label.custom_minimum_size = Vector2(100, 0)
	row.add_child(score_label)

	var correct_label := Label.new()
	correct_label.text = "%d/%d ✔️" % [correct_count, total_questions]
	correct_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	row.add_child(correct_label)

	return row


func _rank_text(i: int) -> String:
	match i:
		0: return "🏆"
		1: return "🥈"
		2: return "🥉"
		_: return "#%d" % (i + 1)


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


func _on_button_pressed(_player: String, color: String) -> void:
	if not is_visible_in_tree():
		return
	if color == "red":
		# Deferred: InputManager.button_pressed can still be mid-dispatch to
		# other listeners, for example LobbyScreen, for this same press. A
		# synchronous screen switch here can let LobbyScreen, once shown, see
		# this same press too. LobbyScreen can then mistake it for a player
		# that joins.
		restart_requested.emit.call_deferred()
