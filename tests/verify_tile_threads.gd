extends SceneTree

## The cluster tiles of a patch are generated on worker threads, and must come out EXACTLY what
## generating them one after another gives.
##
## A patch is seven tiles and each is a rejection-sampling run, so a cold patch was a second of
## wall time on the thread that also has to draw the first frame — a third of the scene load, and
## paid again at every tile border the Shkadov thruster crosses.  _generate_tile is a pure
## function of the tile and the galaxy seed, which is what makes it safe to run seven at once.
##
## "Pure" is the whole claim, so it is the whole test.  A generator that were only MOSTLY
## deterministic would be far worse than a slow one: cluster names are what saves bind to, and
## the INDEX into the patch is identity for the focus set and the selection, so a tile landing in
## a different order or a seed landing in a different place would move a player's colonies.
##
## The lazy galactic-basis cache is the one piece of shared state the workers read, and it is
## filled on the main thread before they start.  The adversarial case — a cold cache and a
## parallel build — is run here deliberately, because it is the one that would race.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## Every field of every cluster, in patch order, as one comparable value.
func _fingerprint(clusters: Array) -> Array:
	var out: Array = []
	for c: Dictionary in clusters:
		out.append([str(c["name"]), c["pos"], c["lp"], float(c["dist"]), int(c["stars"]),
			float(c["volume"]), c["color"], c["tile"], bool(c.get("is_home", false))])
	return out

func _run() -> void:
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var SM = g.sidebar.star_map
	var tiles: Array = (SM.loaded_tiles() as Array).duplicate()
	check(tiles.size() == 7, "the patch is seven tiles: %d" % tiles.size())
	check(SM.CLUSTER_COUNT > 100, "and each holds a roster worth threading: %d" % SM.CLUSTER_COUNT)

	# ── The reference: every tile, one after another, on this thread ──
	#
	# Built as a whole PATCH and not as seven loose tiles, because _build_cluster_cells writes
	# the true carved volume back over the estimate for the cells it carves — and it writes it
	# into the tile cache's own dictionaries.  A reference taken straight from _generate_tile
	# would therefore differ from any patch by exactly those cells, which says nothing about
	# threading.  Pre-filling the cache makes _ensure_patch take its serial path: there is
	# nothing left for it to generate, so the pool is never used.
	var serial: Dictionary = {}
	for t: Vector2i in tiles:
		serial[t] = SM._generate_tile(t)

	# ── The same tile twice in a row is the same tile ──
	# Determinism on one thread first: if this failed, nothing below would mean anything.
	check(_fingerprint(SM._generate_tile(tiles[0] as Vector2i))
			== _fingerprint(serial[tiles[0]] as Array),
		"one tile generated twice is identical")

	SM._tile_cache.clear()
	for t: Vector2i in tiles:
		SM._tile_cache[t] = serial[t]
	SM._loaded_centre = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	SM._ensure_patch(tiles[0] as Vector2i)
	var serial_patch: Array = SM.star_clusters()
	check(serial_patch.size() > 7 * 100, "there is a patch to compare: %d" % serial_patch.size())
	var want: Array = _fingerprint(serial_patch)

	# ── The threaded patch, five times over ──
	# Repeated because a race does not have to fire: five cold builds of seven tiles is
	# thirty-five chances for one to land out of order or read a half-written basis.
	for round_i in range(5):
		SM._tile_cache.clear()
		SM._loaded_centre = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
		if round_i == 2:
			# The adversarial round: the galactic basis cache cold, so the warm-up in
			# _ensure_patch is the only thing standing between seven workers and a race on it.
			SM._basis_cache.clear()
		SM._ensure_patch(tiles[0] as Vector2i)
		var got: Array = SM.star_clusters()
		check((SM.loaded_tiles() as Array) == tiles,
			"round %d: the patch holds the same tiles" % round_i)
		check(got.size() == serial_patch.size(),
			"round %d: and the same number of clusters: %d vs %d" % [
				round_i, got.size(), serial_patch.size()])
		check(_fingerprint(got) == want,
			"round %d: threaded == serial, cluster for cluster, in order" % round_i)

	# ── A tile already in the cache is not regenerated ──
	# The parallel path only covers tiles the patch is MISSING; crossing a border reuses the
	# three that still border, and reusing them must not disturb the order either.
	var before: Array = _fingerprint(SM.star_clusters())
	SM._loaded_centre = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	SM._ensure_patch(tiles[0] as Vector2i)
	check(_fingerprint(SM.star_clusters()) == before,
		"a patch rebuilt entirely from cache is unchanged")

	# One missing tile takes the single-tile path rather than the pool, which is a different
	# branch (want.size() > 1) and has to agree too.
	SM._tile_cache.erase(tiles[3])
	SM._loaded_centre = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	SM._ensure_patch(tiles[0] as Vector2i)
	check(_fingerprint(SM.star_clusters()) == want,
		"and so does a patch with exactly one tile to regenerate")

	# ── The home cluster is still the first entry of the home tile ──
	# It is seeded at the origin ahead of the dart thrower, and the focus carve finds it by
	# scanning for is_home — but the patch order is what _focus_index means.
	var home_at: int = -1
	var homes: int = 0
	var all_: Array = SM.star_clusters()
	for i in range(all_.size()):
		if bool((all_[i] as Dictionary).get("is_home", false)):
			homes += 1
			if home_at < 0:
				home_at = i
	check(homes == 1, "exactly one home cluster in the patch: %d" % homes)
	check(SM.sol_cluster_index() >= 0, "and Sol is inside one of them")

	# ── The separation the sampler was asked for is actually delivered ──
	# The constant was stepped back from 0.86 to 0.80 because the last tenth of the seeds was
	# costing 58 % of the darts.  What it buys is even cell volumes, so the minimum separation
	# has to hold: a seed closer than that to another is a cell much smaller than mean_vol says.
	var mean_spacing: float = pow(
		(1.5 * SM.SQRT3 * SM.HEX_SIZE * SM.HEX_SIZE * SM.HEX_HEIGHT_LY)
		/ float(SM.CLUSTER_COUNT), 1.0 / 3.0)
	var sep: float = SM.CLUSTER_SEP_FRAC * mean_spacing
	var one_tile: Array = SM._tile_cache[tiles[0]] as Array
	var worst: float = INF
	for i in range(one_tile.size()):
		for j in range(i + 1, one_tile.size()):
			worst = minf(worst, ((one_tile[i] as Dictionary)["lp"] as Vector3)
				.distance_to((one_tile[j] as Dictionary)["lp"] as Vector3))
	check(worst >= sep * 0.999,
		"no two seeds in a tile are closer than the separation: %.1f vs %.1f ly" % [worst, sep])
	print("tile of %d seeds, closest pair %.0f ly, separation asked %.0f ly" % [
		one_tile.size(), worst, sep])

	print("FAILS: %d" % fails)
	quit()
