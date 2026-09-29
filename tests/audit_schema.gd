extends SceneTree

## The save file's field table holds Game.gd to it.
##
## Before the table existed, save_game() and load_game() were two hand-written lists three hundred
## lines apart, and a field present in one and missing from the other failed silently — the value
## was written on every save and never read back.  These checks make that a test failure instead.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(25): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")
	var SS_ = load("res://save_schema.gd")

	var path := "user://saves/schema_audit.json"

	# ── 1. The file and the table agree, in both directions ──
	g.save_game(path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary, "the save parses")
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var declared: Array = SS_.all_keys()

	var undeclared: Array = []
	for key: String in data:
		if key == "save_version":
			continue
		if not declared.has(key):
			undeclared.append(key)
	check(undeclared.is_empty(),
		"every key in the file is declared in the table: %s" % str(undeclared))

	var unwritten: Array = []
	for key: String in declared:
		if not data.has(key):
			unwritten.append(key)
	check(unwritten.is_empty(),
		"every key in the table is written to the file: %s" % str(unwritten))
	print("%d keys declared, %d written" % [declared.size(), data.size()])

	check(int(data.get("save_version", -1)) == int(SS_.VERSION),
		"the file stamps its format version: %s" % str(data.get("save_version", null)))

	# ── 2. Every plain field survives a round trip ──
	# Each one is given a value it could not have had by accident, then the game is saved, the
	# field is wrecked, and the save is loaded back.  A field the table declares but load_game
	# never applies shows up here as the wrecked value surviving.
	var plain: Array = SS_.plain_fields()
	print("round-tripping %d plain fields" % plain.size())
	var expect := {}
	var i := 0
	for f: Dictionary in plain:
		i += 1
		var target: Node = ss if str(f.get("on", "game")) == "solar" else g
		var prop: String = SS_.prop_of(f)
		var v: Variant = _distinctive(int(f["kind"]), i)
		if v == null:
			continue          # a kind with nothing distinctive to say
		target.set(prop, v)
		expect[str(f["key"])] = v

	g.save_game(path)

	# Wreck every one of them, so a field that is not read back cannot pass by having been left
	# alone.  The wrecked value is deliberately a different shape from the expected one.
	for f: Dictionary in plain:
		var target: Node = ss if str(f.get("on", "game")) == "solar" else g
		if expect.has(str(f["key"])):
			target.set(SS_.prop_of(f), _wrecked(int(f["kind"])))

	g.load_game(path)

	var lost: Array = []
	for f: Dictionary in plain:
		var key: String = str(f["key"])
		if not expect.has(key):
			continue
		var target: Node = ss if str(f.get("on", "game")) == "solar" else g
		var got: Variant = target.get(SS_.prop_of(f))
		if not _same(got, expect[key]):
			lost.append("%s (wanted %s, got %s)" % [key, str(expect[key]), str(got)])
	check(lost.is_empty(), "every plain field came back: %s" % str(lost))

	# ── 3. A save with nothing in it still loads ──
	# This is what forward compatibility actually rests on: every field has a default, so a file
	# written before the field existed loads with that default rather than erroring.
	var f2 := FileAccess.open("user://saves/schema_empty.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify({"year": 3000}))
	f2.close()
	g.load_game("user://saves/schema_empty.json")
	check(g.year == 3000, "a nearly empty save still loads: year %d" % g.year)
	check(ss.star_drift_ly == Vector3.ZERO, "and missing fields take their defaults")

	print("FAILS: %d" % fails)
	quit()


## A value of the right shape that the game would never produce on its own.
func _distinctive(kind: int, n: int) -> Variant:
	var SS_ = load("res://save_schema.gd")
	match kind:
		SS_.INT:          return 700000 + n
		SS_.FLOAT:        return 900000.0 + float(n)
		SS_.BOOL:         return true
		SS_.STR:          return "probe_%d" % n
		SS_.VEC3:         return Vector3(float(n), float(n) + 0.5, float(n) + 0.25)
		SS_.RAW_DICT:     return {"probe_%d" % n: 1}
		SS_.RAW_ARRAY:    return ["probe_%d" % n]
		SS_.DICT_FLOAT:   return {"probe_%d" % n: 12.5}
		SS_.DICT_INT:     return {"probe_%d" % n: 13}
		SS_.DICT_STR:     return {"probe_%d" % n: "value_%d" % n}
		SS_.DICT_TRUE:    return {"probe_%d" % n: true}
		SS_.DICT_DICT:    return {"probe_%d" % n: {"a": 1}}
		SS_.ARRAY_DICT:   return [{"probe": n}]
		SS_.ARRAY_STR:    return ["probe_%d" % n]
		SS_.NESTED_FLOAT: return {"probe_%d" % n: {"a": 2.5}}
	return null


## Something of the same type but obviously wrong, written over a field after the save.
func _wrecked(kind: int) -> Variant:
	var SS_ = load("res://save_schema.gd")
	match kind:
		SS_.INT:    return -1
		SS_.FLOAT:  return -1.0
		SS_.BOOL:   return false
		SS_.STR:    return "WRECKED"
		SS_.VEC3:   return Vector3(-9, -9, -9)
	return {} if kind != SS_.RAW_ARRAY and kind != SS_.ARRAY_DICT and kind != SS_.ARRAY_STR else []


## JSON turns every number into a float and drops container typing, so compare by content.
func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in b:
			if not (a as Dictionary).has(k):
				return false
			if not _same(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (b as Array).size():
			if not _same(a[i], b[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return a == b
