class_name PanelBackground

## Opaque backing for the full-area sidebar pages (research, timeline, politics, statistics,
## records, compute).  Those are plain Control nodes, so without a backing panel the 3-D solar
## view reads straight through their text.
##
## The colours are UIPalette's, which is where the whole UI's are now — this was one of the two
## places the look came from (the other is the politics page's effects box), so standardising on
## it changed nothing here and everything elsewhere.

## Insert a full-rect backing panel behind everything already in `ctrl`.  Call it from _ready
## (order doesn't matter — the panel is moved to index 0 so it sits behind the page's content,
## and it covers the FULL rect, so the backing reaches the very top of the page).
static func attach(ctrl: Control) -> void:
	if ctrl == null or ctrl.has_node("PanelBackground"):
		return
	var bg := Panel.new()
	bg.name = "PanelBackground"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never steals clicks from the page
	bg.add_theme_stylebox_override("panel", UIPalette.panel())
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl.add_child(bg)
	ctrl.move_child(bg, 0)
