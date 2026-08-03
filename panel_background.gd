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
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = BORDER_COLOR

	var bg := Panel.new()
	bg.name = "PanelBackground"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never steals clicks from the page
	bg.add_theme_stylebox_override("panel", style)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl.add_child(bg)
	ctrl.move_child(bg, 0)
