extends SceneTree

## The game's name, in every place it is written down.
##
## ── What went wrong ──
##
## The rename from the old title swept fifteen files and reported that nothing was left, because
## the check was a case-SENSITIVE search for the title as it appears in prose. The start menu
## spells it in capitals, in a scene file, so the first screen of the game still carried the old
## name after every other reference had moved. The player saw it immediately.
##
## ── What is asserted ──
##
## `application/config/name` in project.godot is the name. It is also what sets `user://`, so it
## is the one copy that cannot be anywhere else. Everything that shows the title either reads it
## from there or is pinned to it here:
##
##   - the start menu's title label, which is text in a scene file and cannot read anything
##   - the run record's header, which reads the setting
##   - the failure achievement named after the title, which is data in a const Array and cannot
##
## And then a scan of the whole tree for the old name, in any case, which is the check that should
## have been run the first time.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

const OLD_TITLE: String = "don't go extinct"
const OLD_SLUG: String = "dont_go_extinct"

## Files that may name the old title: the ones explaining that it used to be the title.
const EXPLAINERS: Array = [
	"res://tests/verify_title.gd",
	"res://tests/verify_achievements.gd",
	"res://save_schema.gd",
	"res://Game.gd",
]


func _run() -> void:
	var title: String = str(ProjectSettings.get_setting("application/config/name"))
	check(title != "", "the project has a name")
	check(title.to_lower().find(OLD_TITLE) < 0, "and it is not the old one: %s" % title)

	# ── The start menu, which is the first thing anyone reads ──
	# Text in a scene file, so it cannot read the setting. Pinned to it instead, and read from the
	# built node rather than the file, so a label moved or renamed in the scene fails here too.
	var menu: Node = (load("res://start_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	var label: Label = menu.get_node_or_null(
		"CenterContainer/MainPanel/MarginContainer/VBoxContainer/TitleLabel") as Label
	check(label != null, "the start menu has a title label")
	if label != null:
		check(label.text == title.to_upper(),
			"and it is the game's name: \"%s\" vs \"%s\"" % [label.text, title.to_upper()])
	menu.queue_free()

	# ── The run record, which is pasted into a comparison between two runs ──
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	check(g.run_summary_text().begins_with(title),
		"the run record's header is the game's name: %s" % g.run_summary_text().substr(0, 40))

	# ── The achievement named after the title ──
	# Its note says "the title", so a rename that moved one and not the other makes the note a lie.
	var ach: Dictionary = AchievementData.by_id("kardashev")
	check(not ach.is_empty(), "the failure achievement is in the catalogue")
	check(str(ach.get("name", "")) == title,
		"and carries the game's name: %s" % str(ach.get("name", "")))
	check(str(ach.get("note", "")).find("the title") >= 0,
		"and still says that is what it is: %s" % str(ach.get("note", "")))
	check(AchievementData.by_id(OLD_SLUG).is_empty(),
		"while the old slug is retired")

	# ── Nothing anywhere still says the old name ──
	# In any case, which is the whole lesson: the one occurrence that was missed was missed by a
	# search for the title as it is written in prose.
	var left: Array = []
	_scan("res://", left)
	check(left.is_empty(), "no file still carries the old title: %s" % str(left))
	# A scan that reached nothing would pass this silently, which is the same failure wearing a
	# different hat: the project is well over a hundred readable files.
	check(_scanned > 100, "and the scan actually read the tree: %d files" % _scanned)

	print("FAILS: %d" % fails)
	quit()


## Every readable file under `dir`, depth first, collecting those naming the old title.
var _scanned: int = 0

func _scan(dir: String, out: Array) -> void:
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	while true:
		var entry: String = d.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var path: String = dir.path_join(entry)
		if d.current_is_dir():
			_scan(path, out)
			continue
		if entry.get_extension() not in ["gd", "tscn", "md", "cfg", "godot", "py", "sh", "json"]:
			continue
		if EXPLAINERS.has(path):
			continue
		_scanned += 1
		var text: String = FileAccess.get_file_as_string(path)
		if text.to_lower().find(OLD_TITLE) >= 0 or text.to_lower().find(OLD_SLUG) >= 0:
			out.append(path)
	d.list_dir_end()
