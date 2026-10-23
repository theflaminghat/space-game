extends SceneTree

## The lanes that draw a MODELLED mesh instead of a placeholder primitive, and the contract
## those models have to meet.  Twenty-one: every lane in INFRA_LANES, with no primitive
## stand-ins left anywhere in the band.
##
## None of these constraints is visible from looking at the model, which is why they are
## pinned here rather than left to whoever next opens Blender:
##
##   ONE SURFACE, NO TEXTURE - the lane sets mmi.material_override, which replaces every
##       surface's material.  A second surface would render identically to the first, so an
##       exporter that split the mesh by material would cost draw calls for nothing.
##   UVs - the override's albedo_texture is sampled with them.  A mesh without UVs reads as
##       flat colour.
##   GREYSCALE MAP - the lane sets albedo_color and the texture multiplies through it.  Hue
##       baked into the map would fight the lane palette, so the bake carries value only.
##   SIZE - the lanes sit 0.04 apart in radius around a body.  Much over ~0.3 units and a
##       hull reaches into its neighbours; the box these replaced was 0.18.
##   RADIAL AXIS IS +Y - _update_infra() builds Basis(t1, radial, t2), so each model's +Y
##       points away from the body.  The glTF export relies on Blender's +Z mapping to it.
##
## Checked against the SUN, not a planet: it is not Type.ROCKY, so it is the one body that
## gets every lane including the "ground" ones, and the storage ring is a ground structure
## anywhere there is ground to stand on.
##
## The fallbacks are deliberately NOT exercised: a run where a .glb or .png failed to import
## should fail this test rather than quietly pass on a box and a checker.

const MODELS := [
	{
		"type": "Orbital Vault", "kind": "depot",
		"model": "res://models/orbital_depot.glb",
		"texture": "res://models/orbital_depot_albedo.png",
		# A satellite bus: its body runs along the radial axis.
		"y_is": "long",
	},
	{
		"type": "Orbital Battery", "kind": "battery",
		"model": "res://models/orbital_battery.glb",
		"texture": "res://models/orbital_battery_albedo.png",
		# A rack of cell slabs: it stacks along the radial axis.
		"y_is": "long",
	},
	{
		"type": "Core Mixing Array", "kind": "core_mixer",
		"model": "res://models/orbital_core_mixer.glb",
		"texture": "res://models/orbital_core_mixer_albedo.png",
		# A bundle of lances hung below a shield: it reaches along the radial axis, inward.
		"y_is": "long",
	},
	{
		"type": "Microwave Uplink", "kind": "uplink",
		"model": "res://models/orbital_uplink.glb",
		"texture": "res://models/orbital_uplink_albedo.png",
		# A flat emitter face on a short mast: broader across than deep.
		"y_is": "shallow",
	},
	{
		"type": "Orbital Construction Station", "kind": "station",
		"model": "res://models/orbital_construction_station.glb",
		"texture": "res://models/orbital_construction_station_albedo.png",
		# A keel with dock hoops stacked up it: it runs along the radial axis.
		"y_is": "long",
	},
	{
		"type": "Orbital Habitat", "kind": "habitat",
		"model": "res://models/orbital_habitat.glb",
		"texture": "res://models/orbital_habitat_albedo.png",
		# A spun cylinder stood end-on: its drum runs along the radial axis.
		"y_is": "long",
	},
	{
		"type": "Orbital Laser", "kind": "laser",
		"model": "res://models/orbital_laser.glb",
		"texture": "res://models/orbital_laser_albedo.png",
		# A gun aimed outward: its barrel runs along the radial axis.
		"y_is": "long",
	},
	{
		"type": "Orbital Power Grid", "kind": "grid",
		"model": "res://models/orbital_power_grid.glb",
		"texture": "res://models/orbital_power_grid_albedo.png",
		# A rectenna face with dishes over it: broader across than deep.
		"y_is": "shallow",
	},
	{
		"type": "Orbital Radiator Array", "kind": "radiator",
		"model": "res://models/orbital_radiator_array.glb",
		"texture": "res://models/orbital_radiator_array_albedo.png",
		# Fins on a spine, and the spine runs along the radial axis.
		"y_is": "long",
	},
	{
		"type": "Orbital Rectenna", "kind": "rectenna",
		"model": "res://models/orbital_rectenna.glb",
		"texture": "res://models/orbital_rectenna_albedo.png",
		# A canted collector dish: wider across than deep.
		"y_is": "shallow",
	},
	{
		"type": "Orbital Ring Store", "kind": "ring_store",
		"model": "res://models/orbital_ring_store.glb",
		"texture": "res://models/orbital_ring_store_albedo.png",
		# A bare hoop: it lies across the radial axis, like the storage ring it must not be
		# mistaken for.
		"y_is": "flat",
	},
	{
		"type": "Power Relay Satellite", "kind": "relay",
		"model": "res://models/orbital_relay_sat.glb",
		"texture": "res://models/orbital_relay_sat_albedo.png",
		# A deck with a mirror canted over it: a platform, not a spire.
		"y_is": "shallow",
	},
	{
		"type": "Space Telescope", "kind": "telescope",
		"model": "res://models/orbital_telescope.glb",
		"texture": "res://models/orbital_telescope_albedo.png",
		# Optics on a mast over a sunshield: it stands along the radial axis, looking out.
		"y_is": "long",
	},
	{
		"type": "Swarm Relay Network", "kind": "swarm_relay",
		"model": "res://models/orbital_swarm_relay.glb",
		"texture": "res://models/orbital_swarm_relay_albedo.png",
		# Apertures strung along a tether: the most elongated thing in the band.
		"y_is": "long",
	},
	{
		"type": "Star Lifter", "kind": "lifter",
		"model": "res://models/orbital_star_lifter.glb",
		"texture": "res://models/orbital_star_lifter_albedo.png",
		# A nozzle: its mouth is wider than the nozzle is deep, so it presents an aperture
		# rather than a spike - but it is a bell, not a disc.
		"y_is": "shallow",
	},
	{
		"type": "Superconducting Storage Ring", "kind": "sc_ring",
		"model": "res://models/orbital_storage_ring.glb",
		"texture": "res://models/orbital_storage_ring_albedo.png",
		# A ring: it lies in the plane across the radial axis, so it is seen face-on.
		"y_is": "flat",
	},
	{
		"type": "Radiator Swarm", "kind": "rad_swarm",
		"model": "res://models/orbital_radiator_swarm.glb",
		"texture": "res://models/orbital_radiator_swarm_albedo.png",
		"y_is": "flat",
	},
	{
		"type": "Shkadov Mirror", "kind": "shkadov",
		"model": "res://models/orbital_shkadov.glb",
		"texture": "res://models/orbital_shkadov_albedo.png",
		"y_is": "flat",
	},
	{
		"type": "Stellar Rectenna Grid", "kind": "rect_grid",
		"model": "res://models/orbital_rectenna_grid.glb",
		"texture": "res://models/orbital_rectenna_grid_albedo.png",
		"y_is": "flat",
	},
	{
		"type": "Sunshade Constellation", "kind": "sunshade",
		"model": "res://models/orbital_sunshade.glb",
		"texture": "res://models/orbital_sunshade_albedo.png",
		"y_is": "flat",
	},
	{
		"type": "Thermal Radiator", "kind": "thermal",
		"model": "res://models/orbital_thermal_radiator.glb",
		"texture": "res://models/orbital_thermal_radiator_albedo.png",
		"y_is": "flat",
	},
]

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var P = load("res://planet.gd")

	# Every lane's mesh kind must be one something actually handles.
	#
	# _infra_mesh() ends in a `_:` branch returning a plain box, so a kind nobody implements
	# does not error - it silently draws a box, which looks enough like real infrastructure
	# that it could sit there for a long time unnoticed.  This is the check that makes a typo
	# or a retired primitive loud, and it is why the cylinder, the torus and the rod could be
	# deleted at all: the lanes that used them are named below, so a removal cannot pass quietly.
	#
	# PRIMITIVES is empty, and that is the point: every lane in the table now names a model,
	# so anything NOT in LANE_MODELS is a mistake.  The list stays rather than being folded
	# into the LANE_MODELS test, because a future lane may legitimately want a primitive
	# again - and if one does, adding it here should be a deliberate line in a diff.
	const PRIMITIVES: Array[String] = []
	for spec: Dictionary in P.INFRA_LANES:
		var kind: String = str(spec["mesh"])
		check(P.LANE_MODELS.has(kind) or PRIMITIVES.has(kind),
			"%s asks for a mesh kind something implements: \"%s\"" % [str(spec["type"]), kind])

	# The two primitives whose last users were given models, and which were then deleted.
	for gone: String in ["cyl", "dish", "flat", "ring", "rod"]:
		var users: Array[String] = []
		for spec: Dictionary in P.INFRA_LANES:
			if str(spec["mesh"]) == gone:
				users.append(str(spec["type"]))
		check(users.is_empty(),
			"the retired \"%s\" primitive has no lanes left asking for it: %s"
				% [gone, str(users)])

	var meshes := {}
	var textures := {}

	for entry: Dictionary in MODELS:
		var what: String = str(entry["type"])
		var kind: String = str(entry["kind"])

		var spec: Dictionary = {}
		for s: Dictionary in P.INFRA_LANES:
			if str(s["type"]) == what:
				spec = s
		check(not spec.is_empty(), "%s has a lane at all" % what)
		if spec.is_empty():
			continue

		check(str(spec["mesh"]) == kind,
			"%s asks for its model, not a primitive: got %s" % [what, str(spec["mesh"])])
		check(str(spec.get("texture", "")) == str(entry["texture"]),
			"%s names its baked map: got %s" % [what, str(spec.get("texture", "(none)"))])
		check(ResourceLoader.exists(str(entry["model"])),
			"%s is imported (run Godot once on a fresh checkout)" % str(entry["model"]))

		# ── Mesh ──────────────────────────────────────────────────────────────────────────
		var mesh: Mesh = P._model_mesh(kind)
		check(mesh != null, "%s: a mesh came back" % what)
		if mesh == null:
			continue
		meshes[kind] = mesh
		check(not (mesh is BoxMesh), "%s: got the model, not its box fallback" % what)
		check(mesh.get_surface_count() == 1,
			"%s: one surface, because material_override replaces them all: %d"
				% [what, mesh.get_surface_count()])

		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		check(uvs != null and uvs.size() == verts.size(),
			"%s: every vertex is unwrapped" % what)

		# The .glb carries no materials, but Godot's glTF importer synthesises a default
		# StandardMaterial3D for a surface that has none.  So the assertion is not "no
		# material", it is "nothing authored that anyone could expect to see".
		for i in range(mesh.get_surface_count()):
			var sm: Material = mesh.surface_get_material(i)
			if sm == null:
				continue
			var std_m := sm as StandardMaterial3D
			check(std_m != null, "%s: surface %d carries only the importer's default" % [what, i])
			if std_m != null:
				check(std_m.albedo_texture == null,
					"%s: surface %d brings no texture — the lane supplies it" % [what, i])

		var aabb: AABB = mesh.get_aabb()
		var size: Vector3 = aabb.size
		check(size.length() > 0.0, "%s: non-degenerate bounds" % what)
		var longest: float = maxf(size.x, maxf(size.y, size.z))
		check(longest < 0.34,
			"%s: stays inside the envelope its neighbours leave it: longest %.3f"
				% [what, longest])
		check(aabb.get_center().length() < 0.02,
			"%s: origin-centred, so it rides its lane radius: %.3f off"
				% [what, aabb.get_center().length()])

		match str(entry["y_is"]):
			"long":
				check(size.y > size.z,
					"%s: its body runs along +Y, the radial axis: y %.3f vs z %.3f"
						% [what, size.y, size.z])
			"flat":
				check(size.y < size.x * 0.5 and size.y < size.z * 0.5,
					"%s: it lies across +Y, so it is seen face-on: y %.3f vs x %.3f, z %.3f"
						% [what, size.y, size.x, size.z])
			"shallow":
				# Between the two: wider than it is deep, but not a disc.  A bell.
				check(size.y < size.x and size.y < size.z,
					"%s: wider across than it is deep along +Y: y %.3f vs x %.3f, z %.3f"
						% [what, size.y, size.x, size.z])

		# ── Texture ───────────────────────────────────────────────────────────────────────
		var tpath: String = str(entry["texture"])
		check(ResourceLoader.exists(tpath), "%s is imported" % tpath)
		var tex: Texture2D = P._lane_texture(tpath)
		check(tex != null, "%s: the texture loaded" % what)
		check(tex != P._get_placeholder_tex(),
			"%s: got its baked map, not the checker fallback" % what)
		if tex != null:
			textures[kind] = tex
			var img: Image = tex.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				var worst := 0.0
				var step: int = maxi(1, img.get_width() / 48)
				for y in range(0, img.get_height(), step):
					for x in range(0, img.get_width(), step):
						var c: Color = img.get_pixel(x, y)
						worst = maxf(worst,
							maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)))
				check(worst < 0.02,
					"%s: the map is greyscale, so the lane's colour is the only hue: worst "
						% what + "channel spread %.4f" % worst)
				print("%s: %d verts, bounds %.3f x %.3f x %.3f, tex %dx%d spread %.4f" % [
					what, verts.size(), size.x, size.y, size.z,
					img.get_width(), img.get_height(), worst])

	# ── Normal maps ───────────────────────────────────────────────────────────────────────
	#
	# Baked beside the albedo by the same script, under a naming convention planet.gd
	# relies on.  Not every model has one yet, so this checks the ones that do and says how
	# many that is; a model without simply goes without relief.
	#
	# The sRGB check is the one that matters.  A normal map holds directions, and a texture
	# pipeline that treats it as colour pushes 0.5 to about 0.735 - which lights the model
	# wrongly in a way that looks like bad modelling, not bad colour management.  Nothing
	# about the file or its thumbnail gives it away.
	var with_normals := 0
	for entry: Dictionary in MODELS:
		var nwhat: String = str(entry["type"])
		var npath: String = str(entry["texture"]).replace("_albedo.png", "_normal.png")
		if not ResourceLoader.exists(npath):
			continue
		with_normals += 1
		var ntex: Texture2D = P._lane_normal(str(entry["texture"]))
		check(ntex != null, "%s: its normal map loaded" % nwhat)
		if ntex == null:
			continue
		var nimg: Image = ntex.get_image()
		if nimg == null:
			continue
		if nimg.is_compressed():
			nimg.decompress()
		var sr := 0.0
		var sg := 0.0
		var sb := 0.0
		var spread := 0.0
		var n := 0
		var nstep: int = maxi(1, nimg.get_width() / 48)
		for y in range(0, nimg.get_height(), nstep):
			for x in range(0, nimg.get_width(), nstep):
				var c: Color = nimg.get_pixel(x, y)
				sr += c.r
				sg += c.g
				sb += c.b
				spread = maxf(spread, absf(c.r - 0.5))
				n += 1
		if n == 0:
			continue
		sr /= n
		sg /= n
		sb /= n
		check(absf(sr - 0.5) < 0.06 and absf(sg - 0.5) < 0.06,
			"%s: the normal map is non-colour data — mean R %.3f G %.3f, which would read "
				% [nwhat, sr, sg] + "about 0.735 if sRGB had been applied to it")
		check(sb > 0.90, "%s: normals mostly point out of the surface: mean B %.3f" % [nwhat, sb])
		check(spread > 0.02,
			"%s: the map carries actual relief rather than being flat — a flat tangent-space "
				% nwhat + "map has exactly this mean and tells you nothing: spread %.3f" % spread)

	print("normal maps: %d of %d models" % [with_normals, MODELS.size()])

	# ── What a real body actually builds ──────────────────────────────────────────────────
	#
	# Everything above tests the loaders in isolation.  This is the part that would be
	# noticed if it broke: a body's lane handing its MultiMesh the modelled hull and the
	# baked map rather than a primitive and a checker.
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var sun: Node3D = current_scene.get_node("WorldRoot/Planets/sun")
	check(sun._infra.size() > 0, "the sun built its lanes: %d" % sun._infra.size())

	for entry: Dictionary in MODELS:
		var what: String = str(entry["type"])
		var kind: String = str(entry["kind"])
		var lane: Dictionary = {}
		for l: Dictionary in sun._infra:
			if str(l["type"]) == what:
				lane = l
		check(not lane.is_empty(), "the sun has a %s lane" % what)
		if lane.is_empty():
			continue

		check((lane["mm"] as MultiMesh).mesh == meshes.get(kind),
			"%s: that lane's MultiMesh carries the modelled mesh — the same cached resource, "
				% what + "so every body and lane shares one")
		var std_m := (lane["mmi"] as MultiMeshInstance3D).material_override as StandardMaterial3D
		check(std_m != null, "%s: the lane has a StandardMaterial3D override" % what)
		if std_m != null:
			check(std_m.albedo_texture == textures.get(kind),
				"%s: the override samples the baked map, shared across bodies" % what)
			var want: Color = Color.BLACK
			for s: Dictionary in P.INFRA_LANES:
				if str(s["type"]) == what:
					want = s["color"]
			check(std_m.albedo_color == want,
				"%s: and still tints it with the lane's own colour: %s vs %s"
					% [what, str(std_m.albedo_color), str(want)])
			var np2: String = str(entry["texture"]).replace("_albedo.png", "_normal.png")
			if ResourceLoader.exists(np2):
				check(std_m.normal_enabled and std_m.normal_texture != null,
					"%s: the lane's override actually uses the baked normal map" % what)

	print("sun: %d lanes" % sun._infra.size())
	print("FAILS: %d" % fails)
	quit()
