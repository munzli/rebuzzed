extends Control
## Standalone debug scene: logs raw controller button indices as a player
## presses them, so a real Buzz controller layout can be confirmed and
## corrected against InputManager.BUTTON_MAP. Not part of the normal game
## flow — run this scene directly from the editor.

const MAX_LINES := 200

@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var log_text: RichTextLabel = $VBoxContainer/LogText

var _log_lines: Array[String] = []


func _ready() -> void:
	InputManager.raw_button_pressed.connect(_on_raw_button_pressed)
	InputManager.controller_connected.connect(_on_controller_connected)
	InputManager.controller_disconnected.connect(_on_controller_disconnected)
	_update_status()


func _on_raw_button_pressed(device: int, button_index: int) -> void:
	var mapped = InputManager.index_to_button.get(button_index)
	var mapped_str := "%s %s" % [mapped.player, mapped.color] if mapped else "(unmapped)"
	_append_log("device=%d  raw_button=%d  ->  %s" % [device, button_index, mapped_str])


func _on_controller_connected(device: int, controller_name: String) -> void:
	_append_log("[connected] device=%d name=\"%s\"" % [device, controller_name])
	_update_status()


func _on_controller_disconnected(device: int) -> void:
	_append_log("[disconnected] device=%d" % device)
	_update_status()


func _update_status() -> void:
	var devices := Input.get_connected_joypads()
	if devices.is_empty():
		status_label.text = "No controllers connected. Plug in the Buzz controller USB receiver."
		return

	var parts: Array[String] = []
	for d in devices:
		parts.append("%d: %s" % [d, Input.get_joy_name(d)])
	status_label.text = "Connected: " + ", ".join(parts)


func _append_log(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > MAX_LINES:
		_log_lines.pop_front()
	log_text.text = "\n".join(_log_lines)
	print("[ControllerTest] " + line)
