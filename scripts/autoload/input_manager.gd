extends Node
## Buzz controller and keyboard input, unified into a single button_pressed
## signal. Autoloaded as "InputManager". LED handling for newer wireless 
## controllers is out of scope for now.

signal button_pressed(player: String, color: String)
signal raw_button_pressed(device: int, button_index: int)
signal controller_connected(device: int, controller_name: String)
signal controller_disconnected(device: int)

## Buzz controllers report as a single USB HID device with 20 buttons: 4
## players with 5 buttons each (Red buzzer, Blue, Orange, Green, Yellow).
## Physical layout from top to bottom on each controller: Blue, Orange,
## Green, Yellow.
const BUTTON_MAP := {
	"player1": {"red": 0, "blue": 4, "orange": 3, "green": 2, "yellow": 1},
	"player2": {"red": 5, "blue": 9, "orange": 8, "green": 7, "yellow": 6},
	"player3": {"red": 10, "blue": 14, "orange": 13, "green": 12, "yellow": 11},
	"player4": {"red": 15, "blue": 19, "orange": 18, "green": 17, "yellow": 16},
}
const RAW_BUTTON_COUNT := 20

## Keyboard fallback. Players 2 to 4 are a convenience for development and
## test. No real 4-controller setup is available during development.
const KEYBOARD_MAP := {
	KEY_J: {"player": "player1", "color": "red"},
	KEY_ENTER: {"player": "player1", "color": "red"},
	KEY_SPACE: {"player": "player1", "color": "red"},
	KEY_1: {"player": "player1", "color": "blue"},
	KEY_B: {"player": "player1", "color": "blue"},
	KEY_2: {"player": "player1", "color": "orange"},
	KEY_O: {"player": "player1", "color": "orange"},
	KEY_3: {"player": "player1", "color": "green"},
	KEY_G: {"player": "player1", "color": "green"},
	KEY_4: {"player": "player1", "color": "yellow"},
	KEY_Y: {"player": "player1", "color": "yellow"},

	KEY_U: {"player": "player2", "color": "red"},
	KEY_7: {"player": "player2", "color": "blue"},
	KEY_8: {"player": "player2", "color": "orange"},
	KEY_9: {"player": "player2", "color": "green"},
	KEY_0: {"player": "player2", "color": "yellow"},

	KEY_N: {"player": "player3", "color": "red"},
	KEY_KP_1: {"player": "player3", "color": "blue"},
	KEY_KP_2: {"player": "player3", "color": "orange"},
	KEY_KP_3: {"player": "player3", "color": "green"},
	KEY_KP_4: {"player": "player3", "color": "yellow"},

	KEY_M: {"player": "player4", "color": "red"},
	KEY_KP_6: {"player": "player4", "color": "blue"},
	KEY_KP_7: {"player": "player4", "color": "orange"},
	KEY_KP_8: {"player": "player4", "color": "green"},
	KEY_KP_9: {"player": "player4", "color": "yellow"},
}

var index_to_button: Dictionary = {}
var _previous_states: Dictionary = {}
var _player_color_to_keys: Dictionary = {}


func _ready() -> void:
	for player in BUTTON_MAP.keys():
		var buttons: Dictionary = BUTTON_MAP[player]
		for color in buttons.keys():
			index_to_button[buttons[color]] = {"player": player, "color": color}

	for keycode in KEYBOARD_MAP.keys():
		var mapped: Dictionary = KEYBOARD_MAP[keycode]
		var lookup_key: String = "%s|%s" % [mapped.player, mapped.color]
		if not _player_color_to_keys.has(lookup_key):
			_player_color_to_keys[lookup_key] = []
		_player_color_to_keys[lookup_key].append(keycode)

	Input.joy_connection_changed.connect(_on_controller_connection_changed)

	for device in Input.get_connected_joypads():
		_on_controller_connection_changed(device, true)

	print("[InputManager] Initialized. Waiting for Buzz controllers...")


func _process(_delta: float) -> void:
	for device in Input.get_connected_joypads():
		var prev: Dictionary = _previous_states.get(device, {})

		for i in range(RAW_BUTTON_COUNT):
			var pressed: bool = Input.is_joy_button_pressed(device, i)
			var was_pressed: bool = prev.get(i, false)

			if pressed and not was_pressed:
				raw_button_pressed.emit(device, i)
				if index_to_button.has(i):
					var info: Dictionary = index_to_button[i]
					button_pressed.emit(info.player, info.color)

			prev[i] = pressed

		_previous_states[device] = prev


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var mapped = KEYBOARD_MAP.get(event.physical_keycode)
		if mapped:
			button_pressed.emit(mapped.player, mapped.color)


func get_button_map() -> Dictionary:
	return BUTTON_MAP


## Returns true if a specific player color is currently held down on any
## connected controller.
func is_pressed(player: String, color: String) -> bool:
	var button_index = BUTTON_MAP.get(player, {}).get(color, -1)
	if button_index < 0:
		return false

	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, button_index):
			return true
	return false


## Returns true if a specific player color is currently held down, by
## controller or keyboard. The game uses this function for chord detection, for
## example when a player holds blue and yellow together.
func is_color_held(player: String, color: String) -> bool:
	if is_pressed(player, color):
		return true

	var keys: Array = _player_color_to_keys.get("%s|%s" % [player, color], [])
	for keycode in keys:
		if Input.is_key_pressed(keycode):
			return true
	return false


func _on_controller_connection_changed(device: int, connected: bool) -> void:
	if connected:
		var controller_name := Input.get_joy_name(device)
		print("[InputManager] Controller connected: device=%d name=\"%s\"" % [device, controller_name])
		controller_connected.emit(device, controller_name)
	else:
		_previous_states.erase(device)
		print("[InputManager] Controller disconnected: device=%d" % device)
		controller_disconnected.emit(device)
