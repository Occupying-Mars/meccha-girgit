extends SceneTree
## Builds the game's UI Theme (font + colors + styled controls) and saves it to
## assets/ui/theme.tres. Run: godot --headless --script tools/godot/build_theme.gd

const BG := Color("13151f")
const PANEL := Color("1e2130")
const PANEL_HI := Color("2a2e42")
const BORDER := Color("3a3f59")
const ACCENT := Color("5be08a")       # girgit green
const ACCENT_DK := Color("12151c")
const TEXT := Color("e9ecf5")
const MUTED := Color("9aa1bb")
const DANGER := Color("ff6b6b")


func _init() -> void:
	var theme := Theme.new()
	var font := load("res://assets/ui/fonts/Display.ttf")
	theme.default_font = font
	theme.default_font_size = 18

	# --- Panel -------------------------------------------------------------
	theme.set_type_variation("Card", "Panel")
	theme.set_stylebox("panel", "Panel", _flat(PANEL, 14, 1, BORDER, 0))
	theme.set_stylebox("panel", "PanelContainer", _flat(PANEL, 14, 1, BORDER, 0))

	# --- Buttons -----------------------------------------------------------
	theme.set_stylebox("normal", "Button", _flat(PANEL_HI, 10, 1, BORDER, 10))
	theme.set_stylebox("hover", "Button", _flat(ACCENT.darkened(0.1), 10, 0, BORDER, 10))
	theme.set_stylebox("pressed", "Button", _flat(ACCENT.darkened(0.25), 10, 0, BORDER, 10))
	theme.set_stylebox("disabled", "Button", _flat(PANEL.darkened(0.1), 10, 1, BORDER, 10))
	theme.set_stylebox("focus", "Button", _flat(Color.TRANSPARENT, 10, 2, ACCENT, 0))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT_DK)
	theme.set_color("font_pressed_color", "Button", ACCENT_DK)
	theme.set_color("font_disabled_color", "Button", MUTED.darkened(0.2))
	theme.set_font_size("font_size", "Button", 18)

	# --- Labels ------------------------------------------------------------
	theme.set_color("font_color", "Label", TEXT)
	theme.set_font_size("font_size", "Label", 18)

	# --- LineEdit ----------------------------------------------------------
	theme.set_stylebox("normal", "LineEdit", _flat(BG, 8, 1, BORDER, 8))
	theme.set_stylebox("focus", "LineEdit", _flat(BG, 8, 2, ACCENT, 8))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("font_uneditable_color", "LineEdit", MUTED)

	# --- OptionButton (reuse button look) ----------------------------------
	for sb in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(sb, "OptionButton", theme.get_stylebox(sb, "Button"))
	theme.set_color("font_color", "OptionButton", TEXT)
	theme.set_color("font_hover_color", "OptionButton", ACCENT_DK)

	# --- CheckBox ----------------------------------------------------------
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_hover_color", "CheckBox", ACCENT)

	# --- Sliders -----------------------------------------------------------
	theme.set_stylebox("slider", "HSlider", _flat(BG, 4, 1, BORDER, 0))
	theme.set_stylebox("grabber_area", "HSlider", _flat(ACCENT.darkened(0.2), 4, 0, BORDER, 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _flat(ACCENT, 4, 0, BORDER, 0))

	# --- ProgressBar (energy/health bars) ----------------------------------
	theme.set_stylebox("background", "ProgressBar", _flat(BG, 8, 1, BORDER, 0))
	theme.set_stylebox("fill", "ProgressBar", _flat(ACCENT, 8, 0, BORDER, 0))
	theme.set_color("font_color", "ProgressBar", TEXT)

	var err := ResourceSaver.save(theme, "res://assets/ui/theme.tres")
	print("[build_theme] saved theme.tres err=", err)
	quit(0 if err == OK else 1)


func _flat(bg: Color, radius: int, border: int, border_color: Color, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_color
	if pad > 0:
		sb.content_margin_left = pad + 6
		sb.content_margin_right = pad + 6
		sb.content_margin_top = pad
		sb.content_margin_bottom = pad
	return sb
