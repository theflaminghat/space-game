class_name StarChunks
extends RefCounted

## The sky beyond the home cell, generated a chunk at a time.
##
## The original field is 6 000 stars scattered through Sol's Voronoi cell and nothing outside it,
## which was fine while Sol stayed where it started.  Under a Shkadov thruster it does not: the
## star leaves its cell, and everything ahead of it was empty.  This fills that in.
##
## THE ONE IDEA.  Space is cut into fixed cubes in ABSOLUTE coordinates — never relative to Sol —
## and a cube's contents are a pure function of (galaxy seed, cube index).  A cube therefore
## generates identically whenever it is reached, from whatever direction, however many times, and
## whether or not its neighbours have ever been visited.  There is no global list to keep, no
## discovery order to remember and nothing to write into a save.
##
## CANON.  The generator obeys the same numbers the rest of the game is built on:
##   • density — StarMapPanel.galactic_density(p) × STARS_PER_LY3_PER_DENSITY stars per ly³, so
##     the field thickens towards the galactic centre and thins out of the plane on its own.
##   • sampling — the map has never drawn every star.  The home cell renders 6 060 of the
##     ~1.5 million its volume actually holds, so the catalogue is a 1-in-250 sample, and SAMPLE
##     below keeps new sky at exactly that fraction.  Region statistics keep using the true count
##     (StarMapPanel.stars_in_volume); only what is DRAWN is sampled.
##   • types — the PROC_TYPES frequencies, M dwarfs and all.
##   • time — every star carries a formation year and a chunk yields only those already born, so
##     arriving somewhere in deep time shows a sky that has aged.
##
## What it deliberately does NOT do is touch Sol's home cell, which keeps its original field: a
## run in progress has colonies, contacts and names there, and regenerating it would rewrite the
## player's own neighbourhood.

## Cube edge, in light-years.  Small enough that the density law varies little across one, large
## enough that a 450 ly sphere is a few hundred of them rather than a few hundred thousand.
const CHUNK_LY: float = 100.0
## Share of the true stellar population the map draws — measured against the original field.
const SAMPLE: float = 0.004
## Stars are not placed closer to the galactic plane than the catalogue's own inner radius; the
## real catalogue owns everything within this of Sol's ORIGINAL position.
const CATALOGUE_KEEPOUT_LY: float = 20.0
## Chunks held in memory at once.  A 450 ly sphere is ~700 chunks; this leaves room to travel
## without regenerating constantly, and bounds the cost of a long crossing.
const CACHE_LIMIT: int = 4096

## Expected civilisations per cubic light-year, from the setup screen's "within reach" figure:
## six of them inside Sol's 461 ly home ball (410 M ly³).  Applied to sky the original seeding
## never saw, so the crowding the player chose holds wherever they travel.
const CIV_PER_LY3: float = 6.0 / 4.10e8

## chunk key → Array of star dicts, and the keys in the order they were generated (for eviction).
static var _cache: Dictionary = {}
static var _order: Array = []
## The galaxy the cache was built for; a different one invalidates it.
static var _cache_seed: int = -1


## The chunk a position falls in.
static func chunk_of(pos: Vector3) -> Vector3i:
	return Vector3i(floori(pos.x / CHUNK_LY), floori(pos.y / CHUNK_LY), floori(pos.z / CHUNK_LY))


## The centre of a chunk, in light-years.
static func chunk_centre(idx: Vector3i) -> Vector3:
	return (Vector3(idx) + Vector3(0.5, 0.5, 0.5)) * CHUNK_LY


## A chunk's own seed: its index and the galaxy seed, mixed so neighbouring chunks share nothing.
static func _seed_for(idx: Vector3i, galaxy_seed: int) -> int:
	var h: int = galaxy_seed * 0x9E3779B1
	h = (h ^ (idx.x * 0x85EBCA6B)) * 0xC2B2AE35
	h = (h ^ (idx.y * 0x27D4EB2F)) * 0x165667B1
	h = (h ^ (idx.z * 0x2545F491)) * 0x9E3779B1
	return absi(h) & 0x7FFFFFFF


## Draw from a Poisson distribution of mean `mean` — the number of stars in one chunk.  Knuth's
## product method, which is exact and cheap at the means involved here (a few per chunk).  A
## fixed count per chunk would put the field on a lattice; this does not.
static func _poisson(rng: RandomNumberGenerator, mean: float) -> int:
	if mean <= 0.0:
		return 0
	if mean > 30.0:
		# Far into the bulge the mean is large enough that the product underflows; the normal
		# approximation is indistinguishable there and cannot loop.
		return maxi(0, int(round(rng.randfn(mean, sqrt(mean)))))
	var limit: float = exp(-mean)
	var k: int = 0
	var p: float = rng.randf()
	while p > limit and k < 200:
		k += 1
		p *= rng.randf()
	return k


## Pick a spectral type from the catalogue's own frequencies.
static func _pick_type(u: float) -> Array:
	var acc: float = 0.0
	for t: Array in StarMapPanel.PROC_TYPES:
		acc += float(t[1])
		if u <= acc:
			return t
	return StarMapPanel.PROC_TYPES[0]


## Every star in one chunk that exists by `year`.  Pure: the same arguments always give the same
## stars, in the same order, with the same names.
##
## Two populations, in the proportion the original field uses: PROC_STAR_COUNT stars already
## standing to FUTURE_STARS still to form (6 000 : 4 000).  The standing ones get an age drawn
## the way the home-cell generator draws it; the future ones get a birth year on the same
## log-distributed, early-skewed formation curve, and are simply absent until the clock reaches
## them.  That is what lets a chunk be a pure function of the year rather than a thing that has
## to be stepped forward.
static func generate_chunk(idx: Vector3i, galaxy_seed: int, year: float) -> Array:
	# The year only ever ADDS stars, so generation ignores it and the filter happens here.  This
	# is what lets the cache survive a changing clock: keyed on the year, it was thrown away and
	# rebuilt on every tick, which in fast mode is every frame.
	var out: Array = []
	for s: Dictionary in _all_in_chunk(idx, galaxy_seed):
		if float(s.get("born", -INF)) <= year:
			out.append(s)
	return out


## Every star the chunk will ever hold, born or not.  Pure in (index, seed).
static func _all_in_chunk(idx: Vector3i, galaxy_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(idx, galaxy_seed)
	var centre: Vector3 = chunk_centre(idx)
	var density: float = StarMapPanel.galactic_density(centre)
	if density <= 0.0:
		return []
	var volume: float = CHUNK_LY * CHUNK_LY * CHUNK_LY
	# The sampled standing population, and the yet-to-form tail on top of it.
	var mean_standing: float = density * StarMapPanel.STARS_PER_LY3_PER_DENSITY * volume * SAMPLE
	var future_share: float = float(StarMapPanel.FUTURE_STARS) / float(StarMapPanel.PROC_STAR_COUNT)
	var count: int = _poisson(rng, mean_standing * (1.0 + future_share))
	# One civilisation per CIV_PER_LY3 of volume, spread across the STANDING stars of the chunk:
	# the frequency the setup screen chose, applied to sky the original seeding never reached.
	var civ_chance: float = 0.0 if mean_standing <= 0.0 \
		else CIV_PER_LY3 * volume / mean_standing
	var out: Array = []
	for i in range(count):
		var pos := Vector3(
			(float(idx.x) + rng.randf()) * CHUNK_LY,
			(float(idx.y) + rng.randf()) * CHUNK_LY,
			(float(idx.z) + rng.randf()) * CHUNK_LY)
		# The real catalogue owns the inner sphere around Sol's starting point; nothing invented
		# is placed there, however far Sol has since travelled.
		if pos.length() < CATALOGUE_KEEPOUT_LY:
			continue
		# Thin to the density at the point rather than the chunk's centre, so a chunk straddling
		# the disk edge fades across itself instead of stepping.
		if rng.randf() * density > StarMapPanel.galactic_density(pos):
			continue
		var t: Array = _pick_type(rng.randf())
		var star := {
			"name": "chunk%d.%d.%d-%d" % [idx.x, idx.y, idx.z, i],
			"pos": pos,
			"dist": pos.length(),
			"spectral": str(t[0]),
			"color": t[3],
			"mass": float(t[2]) * rng.randf_range(0.7, 1.3),
			"procedural": true,
			"chunked": true,
			"civ": false,
		}
		# Draws happen in a fixed order whatever branch is taken, so a star's identity does not
		# depend on the year the chunk was asked for.
		var is_future: bool = rng.randf() < future_share / (1.0 + future_share)
		var u: float = pow(rng.randf(), StarMapPanel.BIRTH_SKEW)
		var standing_age: float = rng.randf_range(0.4, 9.0)
		var civ_roll: float = rng.randf()
		if is_future:
			var born: float = StarMapPanel.STAR_FORMATION_START_YEAR \
				* pow(StarMapPanel.STAR_FORMATION_END_YEAR / StarMapPanel.STAR_FORMATION_START_YEAR, u)
			# Kept whatever the clock says; stars_near() and generate_chunk() drop the ones not
			# yet formed.  Same convention the home cell uses: a seed age that reads as "born in
			# that year" once _star_age_now adds the elapsed time to it.
			star["age"] = (float(StarMapPanel.STELLAR_EPOCH) - born) / 1.0e9
			star["born"] = born
		else:
			star["age"] = standing_age
			star["civ"] = civ_roll < civ_chance
		out.append(star)
	return out


## A chunk's full population, cached.  Only a different galaxy turns the cache over — the year
## does not, because it changes which stars are VISIBLE rather than which exist.
static func cached_chunk(idx: Vector3i, galaxy_seed: int) -> Array:
	if galaxy_seed != _cache_seed:
		_cache.clear()
		_order.clear()
		_cache_seed = galaxy_seed
	if _cache.has(idx):
		return _cache[idx]
	var stars: Array = _all_in_chunk(idx, galaxy_seed)
	_cache[idx] = stars
	_order.append(idx)
	if _order.size() > CACHE_LIMIT:
		var drop: Vector3i = _order.pop_front()
		_cache.erase(drop)
	return stars


## A chunk's stars as of `year`.
static func chunk(idx: Vector3i, galaxy_seed: int, year: float) -> Array:
	var out: Array = []
	for s: Dictionary in cached_chunk(idx, galaxy_seed):
		if float(s.get("born", -INF)) <= year:
			out.append(s)
	return out


## Every generated star within `radius` of `centre`, for the sky around a travelling Sol.
static func stars_near(centre: Vector3, radius: float, galaxy_seed: int, year: float) -> Array:
	var out: Array = []
	if radius <= 0.0:
		return out
	var lo: Vector3i = chunk_of(centre - Vector3.ONE * radius)
	var hi: Vector3i = chunk_of(centre + Vector3.ONE * radius)
	var r2: float = radius * radius
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				for s: Dictionary in cached_chunk(Vector3i(x, y, z), galaxy_seed):
					if float(s.get("born", -INF)) > year:
						continue                  # not formed yet at this date
					if (s["pos"] as Vector3).distance_squared_to(centre) <= r2:
						out.append(s)
	return out


## One star by name, without knowing where it is: the name carries its chunk and its ordinal, so
## a chunk star can be looked up the way a catalogued one can.  Returns {} for a name that is not
## a chunk star, or one whose star has not formed yet.
##
## This is what makes a generated star addressable — a colony, a message or a trade route names
## a star, and the lookup has to work whether or not that part of the sky happens to be loaded.
static func star_by_name(star_name: String, galaxy_seed: int, year: float) -> Dictionary:
	if not star_name.begins_with("chunk"):
		return {}
	var dash: int = star_name.rfind("-")
	if dash < 0:
		return {}
	var coords: PackedStringArray = star_name.substr(5, dash - 5).split(".")
	if coords.size() != 3:
		return {}
	var idx := Vector3i(int(coords[0]), int(coords[1]), int(coords[2]))
	for s: Dictionary in chunk(idx, galaxy_seed, year):
		if str(s["name"]) == star_name:
			return s
	return {}


## Drop everything held.  Called when the run changes underneath the cache (a new game, a load).
static func clear_cache() -> void:
	_cache.clear()
	_order.clear()
	_cache_seed = -1
