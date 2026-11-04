class_name PanelBackground

## Opaque backing for the full-area sidebar pages (research, timeline, politics, statistics).
## Those are plain Control nodes, so without a backing panel the 3-D solar view reads straight
## through their text.  Styling matches the top/side bars in Game._setup_bar_backgrounds so the
## whole UI reads as one surface.
const BG_COLOR:     Color = Color(0.05, 0.06, 0.10, 1.0)
const BORDER_COLOR: Color = Color(0.35, 0.45, 0.65, 1.0)

## Insert a full-rect backing panel behind everything already in `ctrl`.  Call it from _ready
## (order doesn't matter — the panel is moved to index 0 so it sits behind the page's content,
## and it covers the FULL rect, so the backing reaches the very top of the page).
static func attach(ctrl: Control) -> void:
	if ctrl == null or ctrl.has_node("PanelBackground"):
		return
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	# SQUARE, like the bars. See sharpen() for the rest of the menu panels.
	style.set_corner_radius_all(0)
	style.set_border_width_all(1)
	style.border_color = BORDER_COLOR

	var bg := Panel.new()
	bg.name = "PanelBackground"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never steals clicks from the page
	bg.add_theme_stylebox_override("panel", style)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl.add_child(bg)
	ctrl.move_child(bg, 0)


## Square the corners of whatever panel `ctrl` already draws for itself.
##
## attach() is no help to a PanelContainer or a TabContainer: those take their backing from the
## theme and draw it behind their own children, so a backing added underneath is covered. Godot's
## default theme rounds it by 3px, which is what this overrides.
##
## On a DUPLICATE of the stylebox, as an override on this one control. The stylebox the theme
## hands back is shared by every PanelContainer in the game, including the ones inside panels —
## row backings, badges, the dialogs — and squaring it in place would square all of them at once
## from whichever panel happened to ask first.
##
## Colours are left exactly as they were. The panels are not uniform (an attached backing is
## opaque midnight blue with a light border, the themed ones are a translucent grey) and making
## them so is a separate decision from the corners.
static func sharpen(ctrl: Control, what: String = "panel") -> void:
	if ctrl == null:
		return
	var flat := ctrl.get_theme_stylebox(what) as StyleBoxFlat
	if flat == null:
		return
	var own := flat.duplicate() as StyleBoxFlat
	own.set_corner_radius_all(0)
	ctrl.add_theme_stylebox_override(what, own)
