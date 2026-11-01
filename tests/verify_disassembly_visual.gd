extends SceneTree

## A world being taken apart should stop looking like a world.
##
## Two things change as the excavation goes down, and they are driven from different numbers on
## purpose:
##
##   SIZE follows the MASS left, by the cube root — a planet with half its mass gone is 0.79 of
##     its radius, not half, and the first tenth off it is barely visible. A crust is a skin.
##   APPEARANCE follows the LAYERS reached, not the mass. A core is most of a planet by mass, so
##     a mass-driven look would leave a world untouched long after its crust was gone and then
##     race through the interesting part.
##
## No new art: the surface map stays in play as the body's relief, so a half-eaten Mars reads as
## Mars with its crust off rather than as a billiard ball.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261030)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var DD = load("res://disassembly.gd")


	# ── Size goes as the cube root of the mass left ──
	check(DD.radius_frac(1.0) == 1.0, "an untouched world is its own size")
	check(absf(DD.radius_frac(0.125) - 0.5) < 1.0e-9,
		"an eighth of the mass is half the radius: %s" % str(DD.radius_frac(0.125)))
	check(absf(DD.radius_frac(0.5) - 0.7937) < 0.001,
		"and half the mass is most of the radius: %s" % str(DD.radius_frac(0.5)))
	check(DD.radius_frac(0.0) == 0.0, "nothing left is no size")
	check(DD.radius_frac(0.9) > DD.radius_frac(0.4), "and it only ever shrinks")


	# ── The look ramps through silicate and then iron ──
	var l0: Dictionary = DD.look(0.0)
	check(float(l0["mix"]) == 0.0,
		"an untouched world is not restyled at all: %s" % str(l0["mix"]))
	check(float(l0["glow"]) == 0.0, "and does not glow")
	var mid: Dictionary = DD.look(0.5)
	var deep: Dictionary = DD.look(1.0)
	check(float(mid["mix"]) == 1.0, "past the breach the surface map is fully replaced")
	check(float(mid["glow"]) > float(l0["glow"]), "a breached mantle is incandescent")
	check(float(mid["glow"]) > float(deep["glow"]),
		"and cools as the iron comes up: %s vs %s" % [str(mid["glow"]), str(deep["glow"])])
	check(float(deep["metallic"]) > float(mid["metallic"]),
		"which reads as metal: %s vs %s" % [str(deep["metallic"]), str(mid["metallic"])])
	check(float(deep["metallic"]) > 0.8, "and strongly so at the core: %s" % str(deep["metallic"]))
	check(float(l0["metallic"]) == 0.0, "a crust is not metal")
	# The exposed colour runs hot to cold.
	var c_mid: Color = mid["color"]
	var c_deep: Color = deep["color"]
	check(c_mid.r > c_mid.b, "the mantle is hot-coloured")
	check(c_deep.b >= c_deep.r * 0.9, "and the core is not: %s" % str(c_deep))


	# ── Depth is measured in LAYERS, which is the whole reason it is a separate number ──
	check(g._disassembly_depth("mercury") == 0.0, "an untouched world is at zero depth")
	var comp: Dictionary = g._body_composition("mercury")
	var n_layers: int = 0
	for layer: String in DD.LAYER_ORDER:
		if not (comp.get(layer, {}) as Dictionary).is_empty():
			n_layers += 1
	check(n_layers == 4, "Mercury has four layers: %d" % n_layers)
	# Strip the atmosphere, which is a few hundred tonnes against 3.3e26 g.
	for compound: String in (comp["atmosphere"] as Dictionary):
		g._record_removed("mercury", "atmosphere", compound,
			float((comp["atmosphere"] as Dictionary)[compound]))
	var mass_left: float = g._body_remaining_fraction("mercury")
	var depth_now: float = g._disassembly_depth("mercury")
	check(mass_left > 0.999,
		"losing the air costs essentially no mass: %s" % str(mass_left))
	check(absf(depth_now - 0.25) < 1.0e-6,
		"but it is a quarter of the way down: %s" % str(depth_now))
	# Which is exactly the point: a mass-driven look would still show it untouched.
	check(float(DD.look(depth_now)["mix"]) > float(DD.look(1.0 - mass_left)["mix"]),
		"so the body already looks different, which a mass-driven ramp would not")
	# And the crust.
	for compound: String in (comp["crust"] as Dictionary):
		g._record_removed("mercury", "crust", compound,
			float((comp["crust"] as Dictionary)[compound]))
	check(absf(g._disassembly_depth("mercury") - 0.5) < 1.0e-6,
		"the crust takes it to half: %s" % str(g._disassembly_depth("mercury")))
	# A body with fewer layers divides by its own count, not by four.
	var jcomp: Dictionary = g._body_composition("jupiter")
	var jn: int = 0
	for layer: String in DD.LAYER_ORDER:
		if not (jcomp.get(layer, {}) as Dictionary).is_empty():
			jn += 1
	check(jn == 2, "Jupiter has two layers: %d" % jn)
	for compound: String in (jcomp["atmosphere"] as Dictionary):
		g._record_removed("jupiter", "atmosphere", compound,
			float((jcomp["atmosphere"] as Dictionary)[compound]))
	check(absf(g._disassembly_depth("jupiter") - 0.5) < 1.0e-6,
		"and losing its envelope is half of it, not a quarter: %s"
			% str(g._disassembly_depth("jupiter")))


	# ── The body's own node shows it ──
	var planets := g.get_node_or_null("WorldRoot/Planets")
	check(planets != null, "the planets are in the scene")
	var node = planets.get_node_or_null("venus")
	check(node != null, "and Venus is one of them")
	check(node != null and node.has_method("set_disassembly"),
		"which knows how to be taken apart")
	if node != null:
		var mat := node.material_override as ShaderMaterial
		check(mat != null,
			"its surface is the shader the strip parameters live on: %s"
				% str(node.material_override))
		var intact: Vector3 = node.scale
		check(intact.x > 0.0, "it has a size to begin with: %s" % str(intact))
		node.set_disassembly(0.125, 0.6)
		check(absf(node.scale.x - intact.x * 0.5) < 1.0e-5,
			"an eighth of the mass halves it on screen: %s vs %s" % [
				str(node.scale.x), str(intact.x * 0.5)])
		if mat != null:
			check(float(mat.get_shader_parameter("strip_mix")) == 1.0,
				"the surface map is replaced: %s"
					% str(mat.get_shader_parameter("strip_mix")))
			check(float(mat.get_shader_parameter("strip_glow")) > 0.0,
				"it glows: %s" % str(mat.get_shader_parameter("strip_glow")))
			# Back to intact: the setter has to work in both directions, or a reloaded save
			# shows the last world the node happened to be told about.
			node.set_disassembly(1.0, 0.0)
			check(absf(node.scale.x - intact.x) < 1.0e-5,
				"and an intact world is its own size again: %s" % str(node.scale.x))
			check(float(mat.get_shader_parameter("strip_mix")) == 0.0,
				"with nothing stripped")


	# ── A disassembly tick pushes it, without being asked ──
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	rt.resources["energy"] = 1.0e30
	g.planet_buildings["venus"] = ["Planetary Disassembler"]
	g._mark_prod_dirty("venus")
	g._recompute_production_cache()
	var before_scale: float = (planets.get_node_or_null("venus") as Node3D).scale.x
	# Enough to take a visible bite rather than a rounding error.
	var vcomp: Dictionary = g._body_composition("venus")
	for layer: String in ["atmosphere", "crust"]:
		for compound: String in (vcomp[layer] as Dictionary):
			g._record_removed("venus", layer, compound,
				float((vcomp[layer] as Dictionary)[compound]))
	for compound: String in (vcomp["mantle"] as Dictionary):
		g._record_removed("venus", "mantle", compound,
			float((vcomp["mantle"] as Dictionary)[compound]) * 0.8)
	g._run_disassembly(1.0)
	var vnode := planets.get_node_or_null("venus") as Node3D
	check(vnode.scale.x < before_scale * 0.95,
		"a tick shrinks the body on screen: %s vs %s" % [
			str(vnode.scale.x), str(before_scale)])
	var vmat := (vnode as GeometryInstance3D).material_override as ShaderMaterial
	if vmat != null:
		check(float(vmat.get_shader_parameter("strip_mix")) > 0.5,
			"and it no longer looks like a surface: %s"
				% str(vmat.get_shader_parameter("strip_mix")))

	# ── And a loaded save looks like what it loaded ──
	g.save_game("user://saves/disasm_look.json")
	(planets.get_node_or_null("venus") as Node3D).set_disassembly(1.0, 0.0)
	g.load_game("user://saves/disasm_look.json")
	var after := planets.get_node_or_null("venus") as Node3D
	check(after.scale.x < before_scale * 0.95,
		"a world half taken apart loads half taken apart: %s vs %s" % [
			str(after.scale.x), str(before_scale)])

	print("FAILS: %d" % fails)
	quit()
