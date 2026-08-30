extends Node
## Attaches a bundled color-emoji fallback font to the default UI font at
## startup. This makes missing emoji in the pixel font show the same way in
## every build.
##
## The system font fallback of the operating system is not reliable for
## this. The editor binary links to a modern system FreeType library at run
## time. This library can show the COLR/CPAL color emoji font of the
## operating system. An exported release template links its own older
## FreeType library at compile time. This template has no support for
## COLR/CPAL. As a result, those glyphs do not show.
##
## CBDT/CBLC (bitmap) color glyphs have wider support across builds. This is
## the font format bundled here.

const MAIN_FONT_PATH := "res://assets/fonts/WindowsCommandPrompt.ttf"
const EMOJI_FALLBACK_PATH := "res://assets/fonts/NotoColorEmoji.ttf"


func _ready() -> void:
	var main_font := load(MAIN_FONT_PATH) as FontFile
	var emoji_font := load(EMOJI_FALLBACK_PATH) as FontFile
	if main_font and emoji_font:
		main_font.fallbacks = [emoji_font]
