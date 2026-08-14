extends Control
## Root: swaps between Lobby / Game / GameOver screens.

const PLAYER_KEYS := ["player1", "player2", "player3", "player4"]

@onready var lobby_screen := %LobbyScreen
@onready var game_screen := %GameScreen
@onready var game_over_screen := %GameOverScreen


func _ready() -> void:
	lobby_screen.start_requested.connect(_on_start_requested)
	game_screen.game_over_requested.connect(_on_game_over_requested)
	game_screen.quit_to_lobby_confirmed.connect(_return_to_lobby)
	game_over_screen.restart_requested.connect(_return_to_lobby)

	_show_only(lobby_screen)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()


func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_start_requested() -> void:
	var names := {}
	for key in PLAYER_KEYS:
		names[key] = lobby_screen.get_display_name(key)

	_show_only(game_screen)
	game_screen.start_game(names)


func _on_game_over_requested() -> void:
	_show_only(game_over_screen)
	game_over_screen.show_results(game_screen.display_names, game_screen.get_stats())


func _return_to_lobby() -> void:
	GameState.stop_timer()
	GameState.clear_joined()
	lobby_screen.activate()
	_show_only(lobby_screen)


func _show_only(target: Control) -> void:
	lobby_screen.visible = target == lobby_screen
	game_screen.visible = target == game_screen
	game_over_screen.visible = target == game_over_screen
