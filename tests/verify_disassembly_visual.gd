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
## The surface map IS the outermost layer — a crust, or a giant's cloud tops — and goes with it: it
## is eaten away exactly as fast as that layer is and is gone once the layer is, with nothing of it
## carried into the rock and iron below.  A rocky world's AIR is not that layer: taking it changes
## nothing you can see.  It used to be a quarter of the look, so Mercury's eight tonnes of
## exosphere, gone in a Disassembler's first day, left it half molten with its crust untouched.
## And Uranus, the one planet with no map, used to keep its plain material and never change colour
## at all.
##
## A GIANT has no surface to breach: under its clouds is more cloud, then fluid, down to the core.
## So it keeps its map and only shrinks while the envelope goes, and turns to bare metal when the
## core is reached — never molten.

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
	var l0: Dictionary = DD.look(0.0, 0.0)
	check(float(l0["mix"]) == 0.0,
		"an untouched world is not restyled at all: %s" % str(l0["mix"]))
	check(float(l0["glow"]) == 0.0, "and does not glow")
	var mid: Dictionary = DD.look(0.5, 1.0)
	var deep: Dictionary = DD.look(1.0, 1.0)
	check(float(mid["mix"]) == 1.0, "with the surface layer gone the map is entirely gone")
	# The map goes exactly as fast as the layer it is: half the layer, half the map.
	check(is_equal_approx(float(DD.look(0.15, 0.5)["mix"]), 0.5),
		"half the surface layer takes half the map: %s" % str(DD.look(0.15, 0.5)["mix"]))
	check(float(DD.look(0.15, 0.0)["mix"]) == 0.0,
		"and none of it takes none, however deep the depth says: %s" % str(DD.look(0.15, 0.0)["mix"]))
	# A giant's look is its core's: metal, cold, at any depth.
	for gd: float in [0.1, 0.5, 0.9]:
		var gl: Dictionary = DD.look(gd, 1.0, true)
		check((gl["color"] as Color).is_equal_approx(DD.METAL_COLOR) and float(gl["glow"]) == 0.0
			and float(gl["metallic"]) > 0.8,
			"a giant shows metal and never magma, at depth %s: %s" % [str(gd), str(gl)])
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
	# But its look has three: the air over a crust is not a layer you can see.
	check(g._look_layers("mercury") == ["crust", "mantle", "core"],
		"and its look is its crust, mantle and core: %s" % str(g._look_layers("mercury")))
	# Strip the atmosphere, which is eight tonnes against 3.3e26 g.
	for compound: String in (comp["atmosphere"] as Dictionary):
		g._record_removed("mercury", "atmosphere", compound,
			float((comp["atmosphere"] as Dictionary)[compound]))
	check(g._body_remaining_fraction("mercury") > 0.999,
		"losing the air costs essentially no mass: %s" % str(g._body_remaining_fraction("mercury")))
	check(g._disassembly_depth("mercury") == 0.0 and g._disassembly_surface_gone("mercury") == 0.0,
		"and changes nothing in the look: depth %s, surface %s" % [
			str(g._disassembly_depth("mercury")), str(g._disassembly_surface_gone("mercury"))])
	check(float(DD.look(g._disassembly_depth("mercury"), g._disassembly_surface_gone("mercury"))["mix"]) == 0.0,
		"so Mercury still looks like Mercury")
	# Half the crust: half the map, a sixth of the way down.
	for compound: String in (comp["crust"] as Dictionary):
		g._record_removed("mercury", "crust", compound,
			float((comp["crust"] as Dictionary)[compound]) * 0.5)
	check(is_equal_approx(g._disassembly_surface_gone("mercury"), 0.5),
		"half the crust is half the surface: %s" % str(g._disassembly_surface_gone("mercury")))
	check(is_equal_approx(g._disassembly_depth("mercury"), 1.0 / 6.0),
		"and a sixth of the way down: %s" % str(g._disassembly_depth("mercury")))
	# And the rest of it.
	for compound: String in (comp["crust"] as Dictionary):
		g._record_removed("mercury", "crust", compound,
			float((comp["crust"] as Dictionary)[compound]) * 0.5)
	var mass_left: float = g._body_remaining_fraction("mercury")
	check(is_equal_approx(g._disassembly_depth("mercury"), 1.0 / 3.0),
		"the crust takes it a third of the way: %s" % str(g._disassembly_depth("mercury")))
	check(g._disassembly_surface_gone("mercury") == 1.0,
		"and the map with it: %s" % str(g._disassembly_surface_gone("mercury")))
	# Which is the point of counting layers: a mass-driven look would barely have started.
	check(1.0 - mass_left < 0.15 and g._disassembly_depth("mercury") > 2.0 * (1.0 - mass_left),
		"a ninth of the mass, a third of the look: %s gone, depth %s" % [
			str(1.0 - mass_left), str(g._disassembly_depth("mercury"))])
	# A body with fewer layers divides by its own count, not by four.
	var jcomp: Dictionary = g._body_composition("jupiter")
	var jn: int = 0
	for layer: String in DD.LAYER_ORDER:
		if not (jcomp.get(layer, {}) as Dictionary).is_empty():
			jn += 1
	check(jn == 2, "Jupiter has two layers: %d" % jn)
	# A giant has no crust, so its clouds are its surface and its envelope is a layer of the look.
	check(g._look_layers("jupiter") == ["atmosphere", "core"],
		"and its envelope is part of its look: %s" % str(g._look_layers("jupiter")))
	# Half the envelope: half of Jupiter, smaller on screen, and its map exactly as it was.
	for compound: String in (jcomp["atmosphere"] as Dictionary):
		g._record_removed("jupiter", "atmosphere", compound,
			float((jcomp["atmosphere"] as Dictionary)[compound]) * 0.5)
	check(g._body_remaining_fraction("jupiter") < 0.6,
		"half the envelope is half of Jupiter: %s left" % str(g._body_remaining_fraction("jupiter")))
	check(g._disassembly_surface_gone("jupiter") == 0.0
		and float(g._disassembly_look("jupiter")["mix"]) == 0.0,
		"and it still looks like Jupiter, only smaller: %s" % str(g._disassembly_look("jupiter")))
	for compound: String in (jcomp["atmosphere"] as Dictionary):
		g._record_removed("jupiter", "atmosphere", compound,
			float((jcomp["atmosphere"] as Dictionary)[compound]) * 0.5)
	check(absf(g._disassembly_depth("jupiter") - 0.5) < 1.0e-6,
		"and losing its envelope is half of it, not a quarter: %s"
			% str(g._disassembly_depth("jupiter")))
	check(g._disassembly_surface_gone("jupiter") == 0.0,
		"all of the envelope, and still its own clouds until the core is touched: %s"
			% str(g._disassembly_surface_gone("jupiter")))
	# The core is hit: the clouds give way to metal over its first CORE_BREACH.
	var jcore: Dictionary = jcomp["core"]
	for compound: String in jcore:
		g._record_removed("jupiter", "core", compound, float(jcore[compound]) * DD.CORE_BREACH * 0.5)
	check(is_equal_approx(g._disassembly_surface_gone("jupiter"), 0.5),
		"half-way through the breach, half the clouds are gone: %s"
			% str(g._disassembly_surface_gone("jupiter")))
	for compound: String in jcore:
		g._record_removed("jupiter", "core", compound, float(jcore[compound]) * DD.CORE_BREACH * 0.5)
	var jl: Dictionary = g._disassembly_look("jupiter")
	check(float(jl["mix"]) == 1.0 and (jl["color"] as Color).is_equal_approx(DD.METAL_COLOR)
		and float(jl["glow"]) == 0.0 and float(jl["metallic"]) > 0.8,
		"and past it Jupiter is bare metal, not magma: %s" % str(jl))
	# An ice giant has a mantle under its envelope, and that is still not a surface.
	var ucomp: Dictionary = g._body_composition("neptune")
	for layer: String in ["atmosphere", "mantle"]:
		for compound: String in (ucomp[layer] as Dictionary):
			g._record_removed("neptune", layer, compound, float((ucomp[layer] as Dictionary)[compound]))
	check(g._body_remaining_fraction("neptune") < 0.5 and g._disassembly_surface_gone("neptune") == 0.0,
		"Neptune down to its core keeps its own colours: %s left, map %s gone" % [
			str(g._body_remaining_fraction("neptune")), str(g._disassembly_surface_gone("neptune"))])
	g._body_removed.erase("neptune")


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
		node.set_disassembly(0.125, DD.look(0.6, 1.0))
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
			node.set_disassembly(1.0, DD.look(0.0, 0.0))
			check(absf(node.scale.x - intact.x) < 1.0e-5,
				"and an intact world is its own size again: %s" % str(node.scale.x))
			check(float(mat.get_shader_parameter("strip_mix")) == 0.0,
				"with nothing stripped")


	# ── Uranus, the one planet with no map, is on the same shader ──
	# It used to keep its plain StandardMaterial3D, where no strip parameter could reach it, and
	# shrank as it was taken apart without ever stopping looking like itself.
	var un = planets.get_node_or_null("uranus")
	var umat := (un as GeometryInstance3D).material_override as ShaderMaterial if un != null else null
	check(umat != null, "Uranus wears the planet shader: %s" % str(un.material_override if un else "no Uranus"))
	if umat != null:
		var utex: Texture2D = umat.get_shader_parameter("albedo_tex")
		check(utex != null and utex.get_width() == 1 and utex.get_image().get_pixel(0, 0) == Color.WHITE,
			"on one white texel, so its colour is its colour: %s" % str(utex))
		var src := un.get_surface_override_material(0) as StandardMaterial3D
		check(src != null and (umat.get_shader_parameter("albedo_color") as Color).is_equal_approx(src.albedo_color),
			"the colour it had: %s" % str(umat.get_shader_parameter("albedo_color")))
		un.set_disassembly(0.1, DD.look(0.95, 1.0, true))
		check(float(umat.get_shader_parameter("strip_mix")) == 1.0
			and float(umat.get_shader_parameter("strip_metallic")) > 0.8,
			"and down to its core it is metal, not Uranus: mix %s" % str(umat.get_shader_parameter("strip_mix")))
		un.set_disassembly(1.0, DD.look(0.0, 0.0, true))

	# ── Nothing of the map is carried below the surface ──
	# What the exposed material looks like is the shader's business, and the dummy renderer the
	# suite runs on draws nothing, so this reads the source: the strip branch may use the map
	# only to fade it out — one blend with `surf` — and never its texels or their brightness.
	var src_text: String = FileAccess.get_file_as_string("res://planet_polar_blur.gdshader")
	var at: int = src_text.find("if (strip_mix <= 0.0)")
	var branch: String = src_text.substr(src_text.find("} else {", at)) if at >= 0 else ""
	check(branch != "", "the shader has a strip branch")
	var reads: Array = []
	for word: String in ["tex", "lum", "relief"]:
		var re := RegEx.new()
		re.compile("\\b%s\\b" % word)
		if re.search(branch) != null:
			reads.append(word)
	check(reads.is_empty(), "the exposed material reads nothing of the map: %s" % str(reads))
	var surf_re := RegEx.new()
	surf_re.compile("\\bsurf\\b")
	var surf_uses: int = surf_re.search_all(branch).size()
	check(surf_uses == 1, "and the map appears once, being faded out: %d" % surf_uses)

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
	(planets.get_node_or_null("venus") as Node3D).set_disassembly(1.0, DD.look(0.0, 0.0))
	g.load_game("user://saves/disasm_look.json")
	var after := planets.get_node_or_null("venus") as Node3D
	check(after.scale.x < before_scale * 0.95,
		"a world half taken apart loads half taken apart: %s vs %s" % [
			str(after.scale.x), str(before_scale)])

	print("FAILS: %d" % fails)
	quit()
