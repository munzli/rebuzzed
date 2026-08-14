extends Node
## Loads and sequences quiz questions from every opentdb.com-format JSON file
## in the data folder. Autoloaded as "QuizEngine".
##
## The game reads the quiz files from disk next to the game, and does NOT
## bundle them into the exported .pck. This lets a player swap, edit, or add
## quiz files without a rebuild of the game. See get_external_data_dir() for
## how the game finds the directory. The game pools all questions from all
## files together and shuffles them into random order.
##
## Expected shape per file: {"response_code": 0, "results": [{"question",
## "correct_answer","incorrect_answers":[...],"difficulty",...}, ...]}
## See data/music-opentdb.json for an example, or fetch a fresh set from
## https://opentdb.com/api_config.php. On load, the game shuffles correct and
## incorrect answers into the 4 color slots. "boolean" (true/false) questions
## only fill 2 of the 4 color slots. The game leaves the rest blank.

const COLOR_KEYS: Array[String] = ["blue", "orange", "green", "yellow"]
const DIFFICULTY_POINTS := {"easy": 100, "medium": 150, "hard": 200}

## Saved player names (see lobby_screen.gd) live in this same data folder.
## The game skips this file when it scans for quiz files.
const SETTINGS_FILENAME := "settings.json"
const NON_QUIZ_FILENAMES := [SETTINGS_FILENAME]

# The 96 standard HTML4 named entities for U+00A0-U+00FF (Latin-1 Supplement),
# in codepoint order, for example "nbsp" -> U+00A0, "iexcl" -> U+00A1, up to
# "yuml" -> U+00FF. Covers all accented Latin letters (à, é, ô, ü, and more)
# that opentdb.com can use.
const _LATIN1_ENTITY_NAMES: Array[String] = [
	"nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy",
	"ordf", "laquo", "not", "shy", "reg", "macr", "deg", "plusmn", "sup2", "sup3",
	"acute", "micro", "para", "middot", "cedil", "sup1", "ordm", "raquo", "frac14", "frac12",
	"frac34", "iquest", "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil",
	"Egrave", "Eacute", "Ecirc", "Euml", "Igrave", "Iacute", "Icirc", "Iuml", "ETH", "Ntilde",
	"Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", "times", "Oslash", "Ugrave", "Uacute", "Ucirc",
	"Uuml", "Yacute", "THORN", "szlig", "agrave", "aacute", "acirc", "atilde", "auml", "aring",
	"aelig", "ccedil", "egrave", "eacute", "ecirc", "euml", "igrave", "iacute", "icirc", "iuml",
	"eth", "ntilde", "ograve", "oacute", "ocirc", "otilde", "ouml", "divide", "oslash", "ugrave",
	"uacute", "ucirc", "uuml", "yacute", "thorn", "yuml",
]

# Named entities outside the Latin-1 block that the text encoding of
# opentdb.com also uses.
const _EXTRA_ENTITIES := {
	"&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">",
	"&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“",
	"&ndash;": "–", "&mdash;": "—", "&trade;": "™",
}

var quiz: Dictionary = {}
var questions: Array = []
var current_index: int = 0
var total_questions: int = 0

var _entities: Dictionary = {}


func _ready() -> void:
	_build_entity_table()
	load_quiz()


## Returns the directory where external, user-editable data lives: a "data"
## folder next to the exported executable, or next to the .app bundle on
## macOS. The game uses this folder for quiz files, and other files reuse it
## too, for example the saved player names in lobby_screen.gd. Anything that
## should stay inspectable and editable without a change to the game binary
## can live here. When the game runs in the editor, there is no exported
## executable yet. In that case, the function falls back to the data/ folder
## of the project on disk. The game still reads this folder as an external
## file, not as res://.
func get_external_data_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://data")

	var exe_dir := OS.get_executable_path().get_base_dir()
	if OS.get_name() == "macOS" and exe_dir.ends_with("Contents/MacOS"):
		exe_dir = exe_dir.get_base_dir().get_base_dir().get_base_dir()  # .../MyGame.app -> parent dir
	return exe_dir.path_join("data")


## Reads every *.json file in the data folder, normalizes each as an
## opentdb.com payload, and pools all questions together in random order.
func load_quiz() -> Dictionary:
	var dir_path := get_external_data_dir()
	var filenames := DirAccess.get_files_at(dir_path)

	var pooled_questions: Array = []
	var titles: Array[String] = []

	for filename in filenames:
		if not filename.to_lower().ends_with(".json"):
			continue
		if NON_QUIZ_FILENAMES.has(filename):
			continue

		var file_path := dir_path.path_join(filename)
		var parsed := _read_json_file(file_path)
		if parsed.is_empty():
			continue

		var normalized := _normalize_opentdb(parsed)
		pooled_questions.append_array(normalized.questions)
		titles.append(normalized.quizTitle)

	pooled_questions.shuffle()
	for i in range(pooled_questions.size()):
		pooled_questions[i].id = i + 1

	quiz = {"quizTitle": _combined_title(titles), "questions": pooled_questions}
	questions = pooled_questions
	total_questions = questions.size()
	current_index = 0

	print(
		"[QuizEngine] Loaded %d questions from %d file(s) in %s"
		% [total_questions, titles.size(), dir_path]
	)
	return quiz


func get_current_question() -> Variant:
	if current_index < 0 or current_index >= questions.size():
		return null
	return questions[current_index]


func next_question() -> Variant:
	if current_index < questions.size() - 1:
		current_index += 1
		return get_current_question()
	return null


func previous_question() -> Variant:
	if current_index > 0:
		current_index -= 1
		return get_current_question()
	return null


func go_to_question(index: int) -> Variant:
	if index >= 0 and index < questions.size():
		current_index = index
		return get_current_question()
	return null


func check_answer(selected_color: String) -> Variant:
	var question = get_current_question()
	if question == null:
		return null

	var is_correct: bool = question.get("correct", "") == selected_color
	return {
		"correct": is_correct,
		"correctAnswer": question.get("correct", ""),
		"selectedAnswer": selected_color,
		"points": question.get("points", 0) if is_correct else 0
	}


func get_progress() -> Dictionary:
	var total = max(total_questions, 1)
	return {
		"current": current_index + 1,
		"total": total_questions,
		"percentage": roundi(float(current_index + 1) / float(total) * 100.0)
	}


func has_more_questions() -> bool:
	return current_index < questions.size() - 1


## Reshuffles the question order and rewinds to the first question. The game
## calls this function at the start of every game, so replays do not repeat
## the same order.
func reset() -> void:
	questions.shuffle()
	current_index = 0


func get_title() -> String:
	return quiz.get("quizTitle", "Quiz")


func _combined_title(titles: Array[String]) -> String:
	if titles.is_empty():
		return "Quiz"
	if titles.size() == 1:
		return titles[0]
	return "Mixed Quiz (%d sets)" % titles.size()


func _read_json_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[QuizEngine] Failed to open %s: %s" % [path, FileAccess.get_open_error()])
		return {}

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY or not parsed.has("results"):
		push_error(
			"[QuizEngine] %s is not a valid opentdb.com quiz file (expected a \"results\" array)"
			% path
		)
		return {}

	return parsed


## Converts an opentdb.com results payload into the native question format of
## the game. The function shuffles correct and incorrect answers into the 4
## color slots, so the correct answer is not in the same position every
## time.
func _normalize_opentdb(data: Dictionary) -> Dictionary:
	var out_questions: Array = []
	var results: Array = data.get("results", [])

	for i in range(results.size()):
		var r: Dictionary = results[i]

		var pool: Array = [
			{"text": _decode_html_entities(String(r.get("correct_answer", ""))), "correct": true}
		]
		for incorrect in r.get("incorrect_answers", []):
			pool.append({"text": _decode_html_entities(String(incorrect)), "correct": false})
		pool.shuffle()

		var answers := {}
		var correct_color := ""
		for j in range(COLOR_KEYS.size()):
			var color: String = COLOR_KEYS[j]
			if j < pool.size():
				answers[color] = pool[j].text
				if pool[j].correct:
					correct_color = color
			else:
				# opentdb "boolean" (true/false) questions only have 2 answers. The code
				# leaves the remaining color slots blank, so the UI hides them.
				answers[color] = ""

		out_questions.append({
			"id": i + 1,
			"question": _decode_html_entities(String(r.get("question", ""))),
			"answers": answers,
			"correct": correct_color,
			"points": DIFFICULTY_POINTS.get(r.get("difficulty", ""), 100),
		})

	return {
		"quizTitle": data.get("quizTitle", "OpenTDB Quiz"),
		"questions": out_questions,
	}


func _build_entity_table() -> void:
	for i in range(_LATIN1_ENTITY_NAMES.size()):
		_entities["&%s;" % _LATIN1_ENTITY_NAMES[i]] = char(0xA0 + i)
	for k in _EXTRA_ENTITIES.keys():
		_entities[k] = _EXTRA_ENTITIES[k]


## Decodes HTML entities used by the default text encoding of opentdb.com:
## numeric entities like &#039;, plus the full set of named entities above.
func _decode_html_entities(text: String) -> String:
	var result := text

	var regex := RegEx.new()
	regex.compile("&#(x?[0-9a-fA-F]+);")
	for m in regex.search_all(result):
		var whole: String = m.get_string(0)
		var code_str: String = m.get_string(1)
		var code_point: int
		if code_str.begins_with("x") or code_str.begins_with("X"):
			code_point = ("0x" + code_str.substr(1)).hex_to_int()
		else:
			code_point = code_str.to_int()
		result = result.replace(whole, char(code_point))

	for entity in _entities.keys():
		result = result.replace(entity, _entities[entity])

	# The code must decode &amp; last. If not, it can corrupt the "&...;"
	# syntax of other entities.
	result = result.replace("&amp;", "&")

	return result
