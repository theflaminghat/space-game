class_name WikiData

## Content for the in-game encyclopedia (see encyclopedia.gd).
##
## Nothing here restates a number the game already holds.  Every page is generated from the
## tables the simulation itself runs on — BuildingData, RecipeData, the research tree, PlanetData,
## MissionData, DoctrineData, DevConsole.COMMANDS and Game's own constants — so a change to any
## of them shows up in the encyclopedia without anyone having to remember to update it.  The only
## authored prose is the descriptions (BuildingData.DESCRIPTIONS, CompoundData.DESCRIPTIONS, the
## research nodes' own text) and the Mechanics/Controls pages below, which quote the constants
## they describe.
##
## Pages are BBCode for a RichTextLabel.  Cross-references are [url] tags whose meta is an entry
## id, "<Category>|<key>", which the encyclopedia follows when clicked.

const CATEGORIES: Array = ["Buildings", "Items", "Recipes", "Research", "Mechanics", "Console", "Controls"]
const HOME_ID: String = "home"

const COL_HEAD:  String = "#9fc3ff"
const COL_DIM:   String = "#8f9bb3"
const COL_GOOD:  String = "#6fdc8c"
const COL_WARN:  String = "#ffd24a"
const COL_BAD:   String = "#e07a6a"

## Resources that live in the civilisation-wide pools rather than in a world's inventory.
const GLOBAL_POOLS: Array = ["minerals", "energy", "science", "compute"]
const GLOBAL_TITLES: Dictionary = {
	"minerals": "Matter", "energy": "Energy", "science": "Science", "compute": "Compute"}

## Research nodes that open whole systems rather than a building or recipe.  The checks live in
## Game.gd, so this is the one table kept by hand — KEEP IN SYNC with:
##   early_rocketry             Game.LAUNCH_UNLOCK_RESEARCH
##   autonomous_factories       Game.AUTOMATION_UNLOCK_RESEARCH
##   space_power_infrastructure Game.SOLAR_ORBIT_RESEARCH
##   radio_astronomy            Game._telescope_power
##   relativistic_navigation    Game._on_colonize_requested, _has_player_missiles, _vn_unlocked
##   self_replicating_industry  Game._has_berserkers, _vn_unlocked
const FEATURE_UNLOCKS: Dictionary = {
	"early_rocketry": "Opens the Launches panel: surveys, colony ships, supply runs and swarm deployment.",
	"autonomous_factories": "Opens the Automation panel: standing build and launch orders.",
	"space_power_infrastructure": "Opens solar orbit as a build site.",
	"radio_astronomy": "Enables signature detection. Before it, detection power is zero and no alien civilisation can be resolved.",
	"relativistic_navigation": "Enables interstellar colony ships, recon probes and relativistic missiles on the star map.",
	"self_replicating_industry": "Enables berserker seeds and, with Relativistic Navigation, self-replicating von Neumann probes.",
}

const BOOST_TEXT: Dictionary = {
	"research_speed":     "compute (and so science)",
	"science_production": "science produced from compute",
	"energy_production":  "energy output of every generator",
	"matter_production":  "mine and condenser output",
	"detection":          "signature-detection power",
	"heat_management":    "radiating capacity",
}

const MECHANICS: Array = [
	["time", "Time and timescale"],
	["energy", "Energy reserve"],
	["upkeep", "Upkeep and brownout"],
	["heat", "Waste heat"],
	["transmission", "Power transmission"],
	["swarm", "Dyson swarm"],
	["matter", "Matter, mining and storage"],
	["manufacturing", "Manufacturing, farms and labour"],
	["tiers", "Building levels"],
	["belt", "The asteroid belt"],
	["population", "Population and carrying capacity"],
	["food", "Food and famine"],
	["climate", "Climate"],
	["catastrophes", "Catastrophes"],
	["sol", "The Sun's evolution"],
	["interstellar", "Interstellar colonisation"],
	["probes", "von Neumann probes"],
	["aliens", "Alien civilisations"],
	["trade", "Interstellar trade"],
	["doctrine", "Contact doctrine"],
	["deterrence", "Deterrence"],
	["evolution", "Lineage divergence"],
]

# ── Index ─────────────────────────────────────────────────────────────────────

## Every entry: {id, cat, group, key, title, search}.  Ordered by category, group, then title
## (research by lane and column instead, which is how the tree reads).
static func build_index(game: Node) -> Array:
	var out: Array = []
	# Buildings
	for b: Dictionary in BuildingData.BUILDINGS:
		var name: String = str(b["name"])
		var cat: String = str(b.get("category", ""))
		out.append(_entry("Buildings", _category_label(cat), name, name,
			str(BuildingData.DESCRIPTIONS.get(name, "")) + " " + cat))
	# Items
	for key: String in GLOBAL_POOLS:
		out.append(_entry("Items", "Global resources", key, str(GLOBAL_TITLES[key]), key))
	for c: String in item_keys(game):
		var group: String = str(CompoundData.CATEGORY_LABELS.get(CompoundData.CATEGORIES.get(c, "raw"), "Raw Materials"))
		out.append(_entry("Items", group, c, item_name(c),
			c + " " + str(CompoundData.DESCRIPTIONS.get(c, ""))))
	# Recipes
	for r: Dictionary in RecipeData.RECIPES:
		out.append(_entry("Recipes", str(r.get("category", "")).capitalize(), str(r["name"]),
			str(r["name"]), str(r.get("description", ""))))
	# Research, by lane then column
	var nodes: Array = _research_nodes()
	nodes.sort_custom(func(a: ResearchNode, b: ResearchNode) -> bool:
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x)
	for n: ResearchNode in nodes:
		var e: Dictionary = _entry("Research", _lane_name(n), n.id, n.display_name,
			n.id + " " + n.description)
		out.append(e)
	# Mechanics, Console, Controls
	for m: Array in MECHANICS:
		out.append(_entry("Mechanics", "", str(m[0]), str(m[1]), str(m[1])))
	out.append(_entry("Console", "", "_console", "The developer console", "console backtick"))
	for c: Dictionary in DevConsole.COMMANDS:
		out.append(_entry("Console", "Commands", str(c["name"]), str(c["name"]),
			" ".join(c["aliases"]) + " " + str(c["summary"]) + " " + str(c["detail"])))
	out.append(_entry("Controls", "", "controls", "Keyboard and mouse", "keys keyboard mouse"))

	# Stable order: category, then group, then title — except research, which keeps lane order.
	var rank: Dictionary = {}
	for i in range(CATEGORIES.size()):
		rank[CATEGORIES[i]] = i
	var seq: Dictionary = {}
	for i in range(out.size()):
		seq[out[i]["id"]] = i
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["cat"] != b["cat"]:
			return int(rank[a["cat"]]) < int(rank[b["cat"]])
		if a["cat"] in ["Research", "Mechanics", "Console"]:
			return int(seq[a["id"]]) < int(seq[b["id"]])
		if a["group"] != b["group"]:
			return str(a["group"]) < str(b["group"])
		return str(a["title"]).naturalnocasecmp_to(str(b["title"])) < 0)
	return out

static func _entry(cat: String, group: String, key: String, title: String, extra: String) -> Dictionary:
	return {"id": cat + "|" + key, "cat": cat, "group": group, "key": key, "title": title,
		"search": (title + " " + group + " " + extra).to_lower()}

## Every material that can be held in an inventory or is asked for by something: crust and
## atmosphere of every body, recipe inputs and outputs, building bills and fuel, propellants.
static func item_keys(game: Node) -> Array:
	var seen: Dictionary = {}
	for p: String in PlanetData.PLANETS:
		var comp: Dictionary = PlanetData.PLANETS[p].get("composition_g", {})
		for layer: String in ["crust", "atmosphere"]:
			for c: String in (comp.get(layer, {}) as Dictionary):
				seen[c] = true
	if game:
		for c: String in (game.MOON_COMPOSITION.get("crust", {}) as Dictionary):
			seen[c] = true
		for c in game.FOOD_TYPES:
			seen[str(c)] = true
	for r: Dictionary in RecipeData.RECIPES:
		for c: String in (r.get("inputs", {}) as Dictionary):
			seen[c] = true
		for c: String in (r.get("outputs", {}) as Dictionary):
			seen[c] = true
	for b: Dictionary in BuildingData.BUILDINGS:
		for c: String in (b.get("cost", {}) as Dictionary):
			seen[c] = true
		for c: String in (b.get("consumption", {}) as Dictionary):
			seen[c] = true
	for f: Dictionary in MissionData.FUELS:
		seen[str(f["id"])] = true
	for c: String in GLOBAL_POOLS:
		seen.erase(c)
	return seen.keys()

static func item_name(c: String) -> String:
	if GLOBAL_TITLES.has(c):
		return str(GLOBAL_TITLES[c])
	return str(CompoundData.NAMES.get(c, c))

# ── Page dispatch ─────────────────────────────────────────────────────────────

static func page(entry: Dictionary, game: Node, index: Array) -> String:
	match str(entry.get("cat", "")):
		"Buildings": return _building_page(str(entry["key"]), game)
		"Items":     return _item_page(str(entry["key"]), game)
		"Recipes":   return _recipe_page(str(entry["key"]), game)
		"Research":  return _research_page(str(entry["key"]), game)
		"Mechanics": return _mechanics_page(str(entry["key"]), game)
		"Console":   return _console_page(str(entry["key"]))
		"Controls":  return _controls_page()
	return home_page(index)

static func home_page(index: Array) -> String:
	var counts: Dictionary = {}
	for e: Dictionary in index:
		counts[e["cat"]] = int(counts.get(e["cat"], 0)) + 1
	var t: String = _h1("Encyclopedia")
	t += _p("Reference for every structure, material, recipe, research node and console command, generated from the tables the simulation runs on. Select an entry on the left, search by name, or follow any underlined name.")
	t += _h2("Contents")
	for cat: String in CATEGORIES:
		t += _li("[b]%s[/b] — %d entries" % [cat, int(counts.get(cat, 0))])
	t += _h2("Start here")
	for m: Array in [["Mechanics", "energy"], ["Mechanics", "manufacturing"], ["Mechanics", "population"],
			["Mechanics", "catastrophes"], ["Controls", "controls"]]:
		t += _li(_link(str(m[0]), str(m[1]), _title_of(index, str(m[0]) + "|" + str(m[1]))))
	return t

static func _title_of(index: Array, id: String) -> String:
	for e: Dictionary in index:
		if e["id"] == id:
			return str(e["title"])
	return id

# ── Buildings ─────────────────────────────────────────────────────────────────

static func _building_page(base: String, game: Node) -> String:
	var tiers: Array = []
	for b: Dictionary in BuildingData.all():
		if str(b.get("base_name", "")) == base:
			tiers.append(b)
	if tiers.is_empty():
		return _h1(_esc(base)) + _p("No such building.")
	tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("level", 1)) < int(b.get("level", 1)))
	var b0: Dictionary = tiers[0]
	var t: String = _h1(_esc(base))
	t += _sub("%s · %s" % [_category_label(str(b0.get("category", ""))),
		_allowed_text(b0.get("allowed_types", []) as Array)])
	var desc: String = str(BuildingData.DESCRIPTIONS.get(base, ""))
	if desc != "":
		t += _p(_esc(desc))

	t += _h2("Availability")
	var req: String = str(BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS.get(base, ""))
	t += _li("Level 1: " + (_research_req(req) if req != "" else "available from the start"))
	var types: Array = b0.get("allowed_types", [])
	t += _li("Built on Earth, on colonised planets and on the moons of either" \
		+ (", and in solar orbit once %s is researched" % _research_link(str(game.SOLAR_ORBIT_RESEARCH)) \
			if game and types.has("star") else "") + ".")
	if types.has("belt"):
		t += _li("Can be built in the %s once it is colonised." % _link("Mechanics", "belt", "asteroid belt"))
	else:
		t += _li("[color=%s]Cannot be built in the %s.[/color]" % [COL_DIM, _link("Mechanics", "belt", "asteroid belt")])
	t += _li("Construction draws on the world's spare " + _link("Mechanics", "manufacturing", "factory capacity") + ".")
	if int(b0.get("min_count", 0)) > 0:
		t += _li("At least %d must remain on each world; the last cannot be demolished." % int(b0["min_count"]))
	if game:
		var standing: int = 0
		for p: String in game.planet_buildings:
			for tier: Dictionary in tiers:
				standing += int(game._count_building(p, str(tier["name"])))
		t += _li("Standing across all worlds, all levels: [b]%d[/b]" % standing)

	for tier: Dictionary in tiers:
		var lv: int = int(tier.get("level", 1))
		var head: String = "Level %d" % lv
		if str(tier["name"]) != base:
			head += " — %s" % _esc(str(tier["name"]))
		t += _h2(head)
		var lreq: String = str(tier.get("level_research", ""))
		if lv > 1:
			t += _li("Requires " + (_research_req(lreq) if lreq != "" else "nothing further"))
		t += _li("Cost: " + _cost_text(tier.get("cost", {}) as Dictionary))
		if game:
			t += _li("Construction work: %s work-units" % _n(float(game._building_work(tier))))
			var upkeep: float = float((game._find_building_def(str(tier["name"])) as Dictionary).get("_upkeep", 0.0))
			t += _li("Running cost: %s while switched on (%s)" % [Units.format_si(upkeep, "W"),
				_link("Mechanics", "upkeep", "upkeep")])
		for line: String in _building_stats(tier, game):
			t += _li(line)
	if tiers.size() > 1:
		t += _p("[color=%s]Upgrading a standing copy to the next level costs the difference in materials and half the construction work; the old structure keeps running until the retrofit completes. See %s.[/color]" % [
			COL_DIM, _link("Mechanics", "tiers", "Building levels")])
	return t

static func _building_stats(b: Dictionary, game: Node) -> Array:
	var out: Array = []
	var prod: Dictionary = b.get("production", {})
	var e: float = float(prod.get("energy", 0.0))
	if e > 0.0:
		var line: String = "Generates %s" % Units.format_si(e, "W")
		if bool(b.get("solar", false)):
			line += " × the Sun's luminosity (now %.2f L☉)" % SolarSystem.sun_luminosity_lsun(
				int(game.year) if game else 1945)
		out.append(line)
		out.append("Generation anywhere but Earth reaches the grid only through the %s." % _link(
			"Mechanics", "transmission", "power-beam network"))
	if float(prod.get("minerals", 0.0)) > 0.0:
		out.append("Extracts %s/day from the crust, divided by the world's Extraction allocation" % _g(float(prod["minerals"])))
	if float(prod.get("compute", 0.0)) > 0.0:
		out.append("Adds %s of compute" % Units.format_si(float(prod["compute"]), "FLOP/s"))
	if float(b.get("atmo_rate", 0.0)) > 0.0:
		out.append("Condenses %s/day from the atmosphere" % _g(float(b["atmo_rate"])))
	var caps: Array = [
		["mc_capacity", "Factory capacity", "manufacturing", " work-units/day"],
		["farm_capacity", "Farm capacity", "manufacturing", " work-units/day"],
		["ranch_capacity", "Ranch capacity", "manufacturing", " work-units/day"],
	]
	for c: Array in caps:
		if float(b.get(str(c[0]), 0.0)) > 0.0:
			out.append("%s +%s%s" % [_link("Mechanics", str(c[2]), str(c[1])), _n(float(b[str(c[0])])), str(c[3])])
	if float(b.get("habitat", 0.0)) > 0.0:
		out.append("Houses %s people (%s)" % [_n(float(b["habitat"])), _link("Mechanics", "population", "carrying capacity")])
	if float(b.get("shelter", 0.0)) > 0.0:
		out.append("Shelters %s people through an asteroid impact or nuclear exchange" % _n(float(b["shelter"])))
	var stor: Dictionary = b.get("storage", {})
	if float(stor.get("minerals", 0.0)) > 0.0:
		out.append("Matter storage +%s" % _g(float(stor["minerals"])))
	if float(stor.get("energy", 0.0)) > 0.0:
		out.append("Energy storage +%s" % Units.format_si(float(stor["energy"]), "J"))
	if float(b.get("radiator_capacity", 0.0)) > 0.0:
		out.append("%s +%s" % [_link("Mechanics", "heat", "Radiating capacity"), Units.format_si(float(b["radiator_capacity"]), "W")])
	if float(b.get("beam_send", 0.0)) > 0.0:
		out.append("%s sending capacity +%s" % [_link("Mechanics", "transmission", "Power-beam"), Units.format_si(float(b["beam_send"]), "W")])
	if float(b.get("beam_recv", 0.0)) > 0.0:
		out.append("%s receiving capacity +%s" % [_link("Mechanics", "transmission", "Power-beam"), Units.format_si(float(b["beam_recv"]), "W")])
	if float(b.get("detection", 0.0)) > 0.0:
		out.append("Signature-detection power +%s (%s)" % [_n(float(b["detection"])), _link("Mechanics", "aliens", "detection")])
	if b.has("launch_cost_mult") or b.has("launch_duration_mult"):
		out.append("Launches from this world: vehicles and propellant ×%.2f, transit time ×%.2f" % [
			float(b.get("launch_cost_mult", 1.0)), float(b.get("launch_duration_mult", 1.0))])
	var burn: Dictionary = b.get("consumption", {})
	for f: String in burn:
		if f == "energy":
			out.append("Draws %s from the energy reserve" % Units.format_si(float(burn[f]), "W"))
		else:
			out.append("Burns %s/day of %s from its world's inventory" % [_g(float(burn[f])), _item_link(f)])
	var co2f: float = float(b.get("co2_per_energy", 0.0))
	if co2f > 0.0 and e > 0.0:
		out.append("Vents %s/day of CO₂ at full output, scaled by the Industrial Intensity policy (%s)" % [
			_g(e * co2f), _link("Mechanics", "climate", "climate")])
	if str(b.get("base_name", "")) == "Orbital Laser":
		out.append("Interception shot: %s from the energy reserve" % Units.format_si(StarMapPanel.laser_energy(0.0), "J"))
	return out

static func _allowed_text(types: Array) -> String:
	var parts: Array = []
	if types.has("rocky"):
		parts.append("rocky planets and moons")
	if types.has("gas_giant"):
		parts.append("gas giants")
	if types.has("belt"):
		parts.append("the asteroid belt")
	if types.has("star"):
		parts.append("solar orbit")
	if parts.is_empty():
		return "Any body"
	var s: String = ", ".join(parts)
	return s.substr(0, 1).to_upper() + s.substr(1)

static func _category_label(cat: String) -> String:
	return str(BuildingData.CATEGORY_LABELS.get(cat, cat.capitalize()))

# ── Items ─────────────────────────────────────────────────────────────────────

static func _item_page(c: String, game: Node) -> String:
	if GLOBAL_POOLS.has(c):
		return _pool_page(c, game)
	var t: String = _h1(_esc(item_name(c)))
	var cat_key: String = str(CompoundData.CATEGORIES.get(c, "raw"))
	t += _sub("ID [code]%s[/code] · %s" % [_esc(c), str(CompoundData.CATEGORY_LABELS.get(cat_key, cat_key))])
	var desc: String = str(CompoundData.DESCRIPTIONS.get(c, ""))
	if desc != "":
		t += _p(_esc(desc))
	if game:
		t += _li("Held across all worlds: [b]%s[/b]" % _g(float(game._player_item_count(c))))
		if (game.FOOD_TYPES as Array).has(c):
			t += _li("Edible. Each person eats %s per day, drawn in proportion from every food a world holds; foods are interchangeable by mass (%s)." % [
				_g(float(game.FOOD_PER_CAPITA)), _link("Mechanics", "food", "food")])

	# ── Sources
	var src: Array = []
	for p: String in PlanetData.PLANETS:
		var comp: Dictionary = PlanetData.PLANETS[p].get("composition_g", {})
		for layer: String in ["crust", "atmosphere"]:
			var l: Dictionary = comp.get(layer, {})
			if not l.has(c):
				continue
			if p == AsteroidBelt.BODY_NAME:
				src.append("Mined in the %s (%s of it by mass)" % [
					_link("Mechanics", "belt", "asteroid belt"), _frac(float(l[c]) / _sum(l))])
			else:
				src.append("%s from the %s of %s (%s of it by mass)" % [
					"Mined" if layer == "crust" else "Condensed", layer, p.capitalize(), _frac(float(l[c]) / _sum(l))])
	if game:
		var mcrust: Dictionary = (game.MOON_COMPOSITION as Dictionary).get("crust", {})
		if mcrust.has(c):
			src.append("Mined from the regolith of every moon (%s of it by mass)" % _frac(float(mcrust[c]) / _sum(mcrust)))
	if not src.is_empty():
		src.append("Crust is worked by %s and %s; atmospheres by the %s." % [_building_link("Mine"),
			_building_link("Automated Mine"), _building_link("Atmospheric Condenser")])
	for r: Dictionary in RecipeData.RECIPES:
		var outs: Dictionary = r.get("outputs", {})
		if outs.has(c):
			var s: float = RecipeData.scale(r)
			src.append("%s — %s per 1× from %s" % [_recipe_link(str(r["name"])), _g(float(outs[c]) * s),
				_amounts_text(r.get("inputs", {}) as Dictionary, s)])
	t += _h2("Sources")
	t += _list_or(src, "No source: nothing mines, condenses or makes it.")

	# ── Uses
	var uses: Array = []
	for r: Dictionary in RecipeData.RECIPES:
		var ins: Dictionary = r.get("inputs", {})
		if ins.has(c):
			var s2: float = RecipeData.scale(r)
			uses.append("%s — %s per 1×" % [_recipe_link(str(r["name"])), _g(float(ins[c]) * s2)])
	for b: Dictionary in BuildingData.all():
		if int(b.get("level", 1)) != 1:
			continue
		var cost: Dictionary = b.get("cost", {})
		if cost.has(c):
			uses.append("Built into %s — %s at level 1" % [_building_link(str(b["name"])), _g(float(cost[c]))])
		var burn: Dictionary = b.get("consumption", {})
		if burn.has(c):
			uses.append("Burned by %s — %s/day each at level 1" % [_building_link(str(b["name"])), _g(float(burn[c]))])
	for f: Dictionary in MissionData.FUELS:
		if str(f["id"]) == c:
			uses.append("Launch propellant: %s usable per gram, %s m/s² acceleration; requires %s. A launch burns exactly the mass its trajectory's energy requires." % [
				Units.format_si(float(f["energy_density"]), "J"), _n(float(f["accel"])), _research_link(str(f["requires"]))])
	match c:
		"Rocket":
			uses.append("Each launch vehicle is %s; every launch consumes the vehicles its mission and Δv require, plus one per %s of cargo." % [
				_g(MissionData.ROCKET_UNIT_MASS_G), _g(MissionData.CARGO_PER_ROCKET_G)])
		"SolarSatellite":
			uses.append("A Solar Deployment launch carries one collector array (%s) to the Sun. The swarm holds up to %s arrays; see %s." % [
				_g(MissionData.PAYLOAD_MASS_PER_UNIT), str(int(game._swarm_max())) if game else "?",
				_link("Mechanics", "swarm", "Dyson swarm")])
		"Robot":
			if game:
				uses.append("Workforce: every %s of robots counts as %s workers when staffing capacity (%s)." % [
					_g(float(game.ROBOT_MASS_G)), _n(float(game.ROBOT_LABOR_EQUIV)), _link("Mechanics", "manufacturing", "labour")])
		"Missile":
			uses.append("One is consumed per missile fired from the star map, plus its launch energy. Retaliatory doctrines fire them automatically (%s)." % _link("Mechanics", "doctrine", "doctrine"))
			uses.append("Adds to %s once at least one berserker is held." % _link("Mechanics", "deterrence", "deterrence"))
		"Berserker":
			uses.append("One is consumed per seed fired from the star map, plus its launch energy.")
			uses.append("Holding one or more establishes %s." % _link("Mechanics", "deterrence", "deterrence"))
		"VNProbe":
			uses.append("One is consumed per probe launched from the star map (%s)." % _link("Mechanics", "probes", "von Neumann probes"))
	t += _h2("Uses")
	t += _list_or(uses, "Nothing currently uses it.")
	return t

static func _pool_page(c: String, game: Node) -> String:
	var t: String = _h1(item_name(c))
	var res: Dictionary = ResearchTree.resources
	match c:
		"minerals":
			t += _sub("Global resource · grams")
			t += _p("The total mass held in every world's inventory — the Matter readout in the top bar. It moves with every gram mined, condensed, crafted, built with, burned, launched or dumped. Recipes are not mass-conserving, so refining loses mass as slag and flue gas.")
			if game:
				t += _li("Now: %s of %s capacity" % [_g(float(res.get("minerals", 0.0))), _g(float(game._cached_storage_caps.get("minerals", 0.0)))])
			t += _li("Capacity: a base allowance per held world plus matter-storage buildings (%s)." % _link("Mechanics", "matter", "Matter, mining and storage"))
		"energy":
			t += _sub("Global resource · watt-days, displayed as J")
			t += _p("One civilisation-wide reserve. Generation (W) is added every game-day, so the stored unit is the watt-day. Building costs, launches, laser shots, messages and interstellar flights are paid from it; upkeep and habitat draws come off generation first. It cannot go below zero.")
			if game:
				t += _li("Now: %s of %s capacity" % [Units.format_si(float(res.get("energy", 0.0)), "J"), Units.format_si(float(game._cached_storage_caps.get("energy", 0.0)), "J")])
				t += _li("Net generation now: %s" % Units.format_si(float(game._get_total_production().get("energy", 0.0)), "W"))
			t += _li("See %s, %s and %s." % [_link("Mechanics", "energy", "Energy reserve"), _link("Mechanics", "upkeep", "Upkeep and brownout"), _link("Mechanics", "heat", "Waste heat")])
		"science":
			t += _sub("Global resource · FLOP")
			t += _p("Accumulated computation. Every game-day, compute (times the science multipliers from policy and research) is added to it, and the active research project draws on it one-for-one until its cost is met. It has no storage cap.")
			if game:
				t += _li("Now: %s; produced %s per game-day" % [Units.format_si(float(res.get("science", 0.0)), "FLOP"), Units.format_si(float(game._get_total_production().get("science", 0.0)), "FLOP")])
		"compute":
			t += _sub("Rate · FLOP/s")
			t += _p("Population times each person's compute (the best evolution node's FLOP/s), plus the fixed compute of labs, data centres and AI hubs; multiplied by research-speed research and by policy, and reduced in proportion during a brownout. It is the source of science.")
			if game:
				t += _li("Now: %s" % Units.format_si(float(game._get_compute_rate()), "FLOP/s"))
	return t

# ── Recipes ───────────────────────────────────────────────────────────────────

static func _recipe_page(name: String, game: Node) -> String:
	var r: Dictionary = {}
	for x: Dictionary in RecipeData.RECIPES:
		if str(x["name"]) == name:
			r = x
			break
	if r.is_empty():
		return _h1(_esc(name)) + _p("No such recipe.")
	var pool: String = str({"agriculture": "Farm capacity", "livestock": "Ranch capacity"}.get(str(r.get("category", "")), "Factory capacity"))
	var t: String = _h1(_esc(name))
	t += _sub("%s · draws on %s" % [str(r.get("category", "")).capitalize(), _link("Mechanics", "manufacturing", pool.to_lower())])
	var req: String = str(r.get("requires", ""))
	t += _li("Requires " + (_research_req(req) if req != "" else "nothing: available from the start"))
	t += _p(_esc(str(r.get("description", ""))))
	var s: float = RecipeData.scale(r)
	t += _h2("Per 1× rate (one gram of output per game-day)")
	t += _li("Inputs: " + _amounts_text(r.get("inputs", {}) as Dictionary, s))
	t += _li("Outputs: " + _amounts_text(r.get("outputs", {}) as Dictionary, s))
	t += _li("Work: %s work-units of %s per day" % [_n(RecipeData.work_per_rate(r)), pool.to_lower()])
	t += _p("[color=%s]Rates are set per world in the Production tab. A job runs as fast as its inputs and its world's capacity allow; capacity is handed out in list order, so jobs higher in the list are served first.[/color]" % COL_DIM)
	if game:
		var running: float = 0.0
		for j in game._production_jobs:
			if str((j as Dictionary).get("recipe", "")) == name:
				running += float((j as Dictionary).get("rate", 0.0))
		if running > 0.0:
			t += _li("Currently scheduled across all worlds: %s×" % _n(running))
	return t

# ── Research ──────────────────────────────────────────────────────────────────

static func _research_nodes() -> Array:
	if not ResearchTree.nodes.is_empty():
		return ResearchTree.nodes.values()
	return ResearchTreeData.build()

static func _research_node(id: String) -> ResearchNode:
	var n: ResearchNode = ResearchTree.get_research_node(id)
	if n != null:
		return n
	for x: ResearchNode in ResearchTreeData.build():
		if x.id == id:
			return x
	return null

static func _lane_name(n: ResearchNode) -> String:
	var key: int = int(round(n.position.y / ResearchTreeData.LANE_ROW_SPACING * 10.0))
	return str(ResearchTreeData.LANE_NAMES.get(key, "Other"))

static func _research_page(id: String, game: Node) -> String:
	var n: ResearchNode = _research_node(id)
	if n == null:
		return _h1(_esc(id)) + _p("No such research node.")
	var t: String = _h1(_esc(n.display_name))
	t += _sub("%s · tier %d · id [code]%s[/code]" % [_lane_name(n), n.tier, n.id])
	t += _p("Status: " + _status_text(n))
	t += _p(_esc(n.description))

	var cost: float = float(n.cost.get("science", 0.0))
	t += _h2("Cost")
	t += _li("%s of science" % Units.format_si(cost, "FLOP"))
	if game:
		var rate: float = float(game._get_total_production().get("science", 0.0))
		if rate > 0.0:
			t += _li("At the current science output (%s per game-day): %s" % [Units.format_si(rate, "FLOP"), _duration(cost / rate)])

	t += _h2("Prerequisites")
	var pre: Array = []
	for p in n.prerequisites:
		pre.append(_research_link(str(p)) + " — " + _status_text(_research_node(str(p))))
	t += _list_or(pre, "None.")
	t += _h2("Leads to")
	var nxt: Array = []
	for u in n.unlocks:
		nxt.append(_research_link(str(u)))
	t += _list_or(nxt, "Nothing further.")

	t += _h2("Effects")
	var fx: Array = []
	for bt: String in n.boosts:
		var v: float = float(n.boosts[bt])
		if bt == "automation":
			fx.append("+%s to the automation factor: multiplies every world's factory, farm and ranch capacity and divides the labour each unit needs (%s)" % [
				_n(v), _link("Mechanics", "manufacturing", "manufacturing")])
		else:
			fx.append("+%d %% %s" % [int(round(v * 100.0)), str(BOOST_TEXT.get(bt, bt))])
	for base: String in BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS:
		if str(BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS[base]) == n.id:
			fx.append("Unlocks the %s" % _building_link(base))
	var lvl: int = BuildingData.LEVEL_RESEARCH.find(n.id)
	if lvl > 0:
		fx.append("Unlocks level %d of every building with levels (%s)" % [lvl + 1, _link("Mechanics", "tiers", "Building levels")])
	for r: Dictionary in RecipeData.RECIPES:
		if str(r.get("requires", "")) == n.id:
			fx.append("Unlocks the recipe %s" % _recipe_link(str(r["name"])))
	for f: Dictionary in MissionData.FUELS:
		if str(f["requires"]) == n.id:
			fx.append("Unlocks %s as a launch propellant" % _item_link(str(f["id"])))
	if FEATURE_UNLOCKS.has(n.id):
		fx.append(str(FEATURE_UNLOCKS[n.id]))
	if game:
		var med: Dictionary = game.MEDICAL_RESEARCH
		if med.has(n.id):
			fx.append("+%s years of life expectancy" % _n(float(med[n.id])))
		if (game.PANDEMIC_BIOTECH as Array).has(n.id):
			fx.append("[color=%s]Raises the probability of an engineered pandemic (%s)[/color]" % [COL_WARN, _link("Mechanics", "catastrophes", "catastrophes")])
	t += _list_or(fx, "No direct effect; required by later research.")
	return t

static func _status_text(n: ResearchNode) -> String:
	if n == null:
		return "unknown"
	match n.state:
		ResearchNode.State.UNLOCKED:
			return "[color=%s]researched[/color]" % COL_GOOD
		ResearchNode.State.RESEARCHING:
			return "[color=%s]in progress (%d %%)[/color]" % [COL_WARN, int(n.progress * 100.0)]
		ResearchNode.State.AVAILABLE:
			var q: int = ResearchTree.research_queue.find(n.id)
			return "[color=%s]available%s[/color]" % [COL_HEAD, "" if q < 0 else ", queued #%d" % (q + 2)]
	var q2: int = ResearchTree.research_queue.find(n.id)
	return "[color=%s]locked%s[/color]" % [COL_DIM, "" if q2 < 0 else ", queued #%d" % (q2 + 2)]

static func _research_req(id: String) -> String:
	return "%s (%s)" % [_research_link(id), _status_text(_research_node(id))]

# ── Console / controls ────────────────────────────────────────────────────────

static func _console_page(key: String) -> String:
	if key == "_console":
		var t: String = _h1("The developer console")
		t += _p("A command line for testing. Open and close it with the backtick key ([code]`[/code]); Escape also closes it. Type a command and press Enter.")
		t += _h2("Commands")
		for c: Dictionary in DevConsole.COMMANDS:
			t += _li("%s — %s" % [_link("Console", str(c["name"]), _usage(c)), _esc(str(c["summary"]))])
		return t
	for c: Dictionary in DevConsole.COMMANDS:
		if str(c["name"]) == key:
			var t2: String = _h1(_esc(_usage(c)))
			t2 += _sub("Console command")
			if not (c["aliases"] as Array).is_empty():
				t2 += _li("Also accepted as: " + ", ".join(c["aliases"]))
			t2 += _p(_esc(str(c["detail"])))
			t2 += _p("[color=%s]Open the console with the backtick key. See %s.[/color]" % [COL_DIM, _link("Console", "_console", "The developer console")])
			return t2
	return _h1(_esc(key)) + _p("No such command.")

static func _usage(c: Dictionary) -> String:
	var u: String = str(c["name"])
	if str(c["args"]) != "":
		u += " " + str(c["args"])
	return u

static func _controls_page() -> String:
	var t: String = _h1("Keyboard and mouse")
	t += _h2("Everywhere")
	for row: Array in [
		["O", "Open or close this encyclopedia (Escape also closes it)"],
		["Space", "Pause or resume the simulation"],
		["Escape", "Pause menu"],
		["` (backtick)", "Developer console"],
		["Speed buttons", "Top-bar row: how much to multiply the base rate by; faster ones unlock as the run reaches their year"],
	]:
		t += _li("[b]%s[/b] — %s" % [_esc(str(row[0])), str(row[1])])
	t += _h2("Solar system view")
	for row2: Array in [
		["W A S D / arrow keys", "Orbit the camera around the focused body"],
		["Mouse wheel", "Zoom"],
		["Left-click a planet, moon or the Sun", "Focus the camera on it and open its panel"],
		["Left-click anywhere on the asteroid belt", "Select the belt: the camera goes to Ceres, its hub"],
	]:
		t += _li("[b]%s[/b] — %s" % [_esc(str(row2[0])), str(row2[1])])
	t += _h2("Star map")
	for row3: Array in [
		["Left-drag", "Rotate the view"],
		["Left-click", "Select a star or cluster"],
		["Right-click", "Recentre on a star or galaxy; right-click empty space to return to Sol"],
		["Mouse wheel", "Zoom"],
	]:
		t += _li("[b]%s[/b] — %s" % [_esc(str(row3[0])), str(row3[1])])
	t += _h2("Galaxy map")
	for row4: Array in [
		["Left-drag / W A S D", "Pan"],
		["Left-click", "Select a region tile"],
		["Mouse wheel", "Zoom"],
	]:
		t += _li("[b]%s[/b] — %s" % [_esc(str(row4[0])), str(row4[1])])
	t += _h2("Research tree")
	for row5: Array in [
		["Mouse wheel", "Scroll horizontally"],
		["Middle-drag", "Pan"],
	]:
		t += _li("[b]%s[/b] — %s" % [_esc(str(row5[0])), str(row5[1])])
	return t

# ── Mechanics ─────────────────────────────────────────────────────────────────

static func _mechanics_page(key: String, game: Node) -> String:
	var title: String = key
	for m: Array in MECHANICS:
		if str(m[0]) == key:
			title = str(m[1])
	var t: String = _h1(title) + _sub("Mechanics")
	if game == null:
		return t + _p("Unavailable outside a running game.")
	var g = game
	match key:
		"time":
			t += _p("The run begins on 1 January 1945. Time runs at one fixed rate — %s real seconds per game-day — for the whole run; how fast a run moves is the player's to choose. The top bar multiplies that rate, and the faster settings are earned by getting there: each unlocks when the run reaches its year." % _n(g.TIMESCALE_BASE))
			for tier: Dictionary in g.SPEED_TIERS:
				var when: String = "from the start" if int(tier["year"]) <= 1945 \
					else "from year %s" % TimelineCanvas.fmt_year(float(tier["year"]))
				t += _li("[b]%s[/b] — %s, %s." % [
					str(tier["label"]), g.speed_pace_text(float(tier["mult"])), when])
			t += _li("Below %s s per day the simulation advances whole years per frame and the calendar shows years only." % _n(g.FAST_THRESHOLD))
			t += _li("Above %sx the planets cross their orbits faster than a frame can show, so the bodies are hidden and each orbit is drawn as a blurred ring instead. Pausing — or slowing back down — brings them back." % _n(SolarSystem.ORBIT_BLUR_ABOVE_MULT))
			t += _li("Every flow — production, burn, growth, decay — is integrated on game-days, so results are the same at any speed.")
		"energy":
			t += _p("Generation is measured in watts and added to one civilisation-wide reserve every game-day, so the stored unit is the watt-day (displayed as J). Building costs, launches, laser shots, transmissions and interstellar flights are paid from the reserve; it cannot go below zero.")
			t += _li("Capacity: %s per held world plus energy-storage buildings." % Units.format_si(float(g._PLANET_BASE_STORAGE["energy"]), "J"))
			t += _li("Fuelled plants run at the share of their fuel their world can supply; out of fuel, they idle.")
			t += _li("Net generation is what is left after the power-beam limit, waste-heat curtailment and upkeep (%s, %s, %s)." % [
				_link("Mechanics", "transmission", "transmission"), _link("Mechanics", "heat", "heat"), _link("Mechanics", "upkeep", "upkeep")])
		"upkeep":
			t += _p("Every switched-on structure draws running power in proportion to its mass: %s per gram of its bill of materials per day, weighted by category." % Units.format_si(float(g.UPKEEP_J_PER_GRAM), "J"))
			var cm: Array = []
			for k: String in g.UPKEEP_CATEGORY_MULT:
				cm.append("%s ×%s" % [_category_label(k), _n(float(g.UPKEEP_CATEGORY_MULT[k]))])
			t += _li("Category weights: " + ", ".join(cm) + "; all others ×1.")
			t += _li("Structures idled with the Active slider neither produce nor draw upkeep.")
			t += _li("If upkeep exceeds generation the grid browns out: net energy is zero, and matter extraction and compute run at the fraction of upkeep that generation covers.")
		"heat":
			t += _p("All power used ends as heat that must be radiated. Radiating capacity = (%s + radiator buildings) × (1 + heat-management research) × √(cosmic expansion factor); as the universe expands and cools, the same radiators shed more." % Units.format_si(float(g.BASE_RADIATOR_W), "W"))
			t += _li("Power drawn beyond capacity is curtailed: usable fraction = √(capacity ÷ load), never below %d %%." % int(round(float(g.THERMAL_EFF_FLOOR) * 100.0)))
			t += _li("The Heat box in the top bar shows load against capacity and turns amber when curtailment is active.")
		"transmission":
			t += _p("Only Earth's own generation is wired straight into the grid. Everything generated on any other world, and everything the Dyson swarm collects, must be sent as a beam and caught.")
			t += _li("Link capacity = %s + the smaller of total sending and total receiving capacity. Building only one side adds nothing." % Units.format_si(float(g.BASE_LINK_W), "W"))
			t += _li("Power offered beyond link capacity is never collected.")
		"swarm":
			t += _p("Solar Deployment launches carry collector arrays to lanes inside Mercury's orbit. Each deployed array is %s collectors; one innermost-lane collector delivers %s at today's solar output, and each lane further out delivers less by the inverse square of its distance." % [
				_n(float(g.SWARM_COLLECTORS_PER_PANEL)), Units.format_si(float(g.SWARM_SAT_POWER), "W")])
			t += _li("Capacity: %d arrays across %d lanes. Deployed now: %d." % [int(g._swarm_max()), int(g.SWARM_LANES), int(g.solar_satellites_deployed)])
			t += _li("Output scales with the Sun's luminosity: larger on the giant branches, almost nothing after the white dwarf forms.")
			t += _li("All of it must cross the %s and be radiated as %s." % [_link("Mechanics", "transmission", "power-beam network"), _link("Mechanics", "heat", "waste heat")])
		"matter":
			t += _p("Each world keeps its own inventory; a moon shares its parent planet's. The Matter total in the top bar is the mass of every inventory combined.")
			t += _li("Mines divide their yield across the crust and condensers across the atmosphere, by the Extraction tab's allocation where it names a compound and by natural abundance otherwise.")
			t += _li("Matter capacity: %s per held world plus matter-storage buildings. Anything above the cap is lost." % _g(float(g._PLANET_BASE_STORAGE["minerals"])))
			t += _li("The Inventory tab can set a standing limit on any compound, discarding the excess as it arrives, or dump a quantity at once.")
		"manufacturing":
			t += _p("Each world has three separate capacity pools, measured in work-units per day: factory capacity (%s base on every world, plus factories), farm capacity and ranch capacity. A recipe draws only on its own pool. Construction uses the factory capacity left over after recipes." % _n(float(g.BASE_MC)))
			t += _li("Automation factor = 1 + automation research. It multiplies every pool and divides the labour each unit needs.")
			t += _li("Labour: one finite workforce staffs all built capacity on every world. A factory work-unit needs %s people and a farm or ranch work-unit %s. Staffing = (population + robots × %s) ÷ labour needed, capped at 100 %%, and scales every pool." % [
				_n(float(g.LABOR_PER_CAP)), _n(float(g.FARM_LABOR_PER_CAP)), _n(float(g.ROBOT_LABOR_EQUIV))])
			t += _li("When demand exceeds capacity, jobs are served in Production-tab list order; lower jobs get what is left.")
			t += _li("Staffing now: %d %%." % int(round(float(g._mc_staffing()) * 100.0)))
		"tiers":
			t += _p("Most buildings have %d levels. Each level costs %s× the one below and yields %s× its output, including fuel burn." % [
				int(BuildingData.LEVEL_COUNT), _n(BuildingData.LEVEL_COST_MULT), _n(BuildingData.LEVEL_OUTPUT_MULT)])
			var lr: Array = []
			for i in range(1, BuildingData.LEVEL_RESEARCH.size()):
				lr.append("level %d: %s" % [i + 1, _research_link(str(BuildingData.LEVEL_RESEARCH[i]))])
			t += _li("Research gates: " + "; ".join(lr) + ".")
			t += _li("Upgrading a standing copy costs the difference in materials between the two levels and half the new level's construction work. The old structure keeps working until the retrofit completes.")
		"population":
			t += _p("Each inhabited world grows logistically toward its own carrying capacity at %s %% a year (times policy)." % _n(float(g.POP_GROWTH_PER_YEAR) * 100.0))
			t += _li("Earth: a natural capacity of %s, reduced by atmospheric CO₂ (%s)." % [_n(float(g.EARTH_NATURAL_K)), _link("Mechanics", "climate", "climate")])
			t += _li("Other worlds in the Sol system have no biosphere: capacity is only the habitat built there, scaled by the world's own generation up to %s (never below 5 %%)." % Units.format_si(float(g.COLONY_FULL_POWER), "W"))
			t += _li("Interstellar colonies are modelled as self-sufficient, with a capacity of %s, and do not draw food from any inventory." % _n(float(g.COLONY_HABITAT_K)))
			t += _li("New colonies start with %s people. An emptied world with capacity is resettled while the species survives anywhere." % _n(float(g.COLONY_SEED_POP)))
			t += _li("Life expectancy: %s years, plus medical research and policy, minus up to %s years for a fossil-fuelled grid; never below %s." % [
				_n(float(g.BASE_LIFE_EXPECTANCY)), _n(float(g.POLLUTION_LE_PENALTY)), _n(float(g.MIN_LIFE_EXPECTANCY))])
			t += _li("The run ends when no humans remain anywhere, including the statistical galaxy regions.")
		"food":
			t += _p("Every person on a world in the Sol system eats %s a day, drawn from that world's inventory in proportion to each food held. All foods are interchangeable by mass; they differ in what they cost to grow." % _g(float(g.FOOD_PER_CAPITA)))
			var foods: Array = []
			for f in g.FOOD_TYPES:
				foods.append(_item_link(str(f)))
			t += _li("Foods: " + ", ".join(foods) + ".")
			t += _li("The unfed fraction of a population dies at a rate of %s per year (about seven weeks without food)." % _n(float(g.STARVATION_RATE)))
			t += _li("Colony ships land %s of %s rations for the founding population." % [
				Units.format_si(float(g.COLONY_SEED_FOOD) / (float(g.COLONY_SEED_POP) * float(g.FOOD_PER_CAPITA)) / 365.25, "yr"),
				_item_link("Algae")])
		"climate":
			t += _p("Combustion plants vent CO₂ in proportion to the energy they generate (scaled by the Industrial Intensity policy). CO₂ accumulates in the world's atmosphere and is sequestered naturally with a time constant of %s days (half-life about %d years)." % [
				_n(float(g.CO2_SEQUESTRATION_DAYS)), int(round(float(g.CO2_SEQUESTRATION_DAYS) * 0.6931 / 365.25))])
			t += _li("Earth's natural carrying capacity is divided by (1 + CO₂ ÷ %s), floored at 5 %%. The divisor is set by the Climate option chosen for the run." % _g(float(g.CO2_K_HALF) * float(g.setup_climate)))
			t += _li("A CO₂-emitting grid also shortens life expectancy.")
		"catastrophes":
			t += _li("[b]Asteroid impact[/b] — every %s–%s years. Strikes Earth or a colony in the Sol system: %s of its population, divided by the number of inhabited worlds in the system, dies; every structure except bunkers and one Biomass Burner is destroyed. The simulation pauses first and offers an Orbital Laser shot if one stands and the reserve can pay." % [
				_n(float(g.IMPACT_GAP_MIN)), _n(float(g.IMPACT_GAP_MAX)), "50–85 %"])
			t += _li("[b]Engineered pandemic[/b] — rolled every %s–%s years once any bioengineering research is done. Probability rises with that research, with AI autonomy and with poor life expectancy, and falls as humanity spreads across worlds. Kills 70–95 %% of the Sol system's population, divided by the number of inhabited worlds; interstellar colonies are untouched." % [
				_n(float(g.PANDEMIC_GAP_MIN)), _n(float(g.PANDEMIC_GAP_MAX))])
			t += _li("[b]Nuclear war[/b] — rolled every %s–%s years. Risk = geopolitical tension × means. Tension is highest with humanity on one world under crowding and high military spending; each colonised planet dilutes it and each interstellar colony twice as much. Means = military spending plus latent capability from Nuclear Plants. Kills 55–90 %% of Earth's population, divided by the number of inhabited worlds, and destroys about half of Earth's structures; bunkers survive." % [
				_n(float(g.NUCLEAR_GAP_MIN)), _n(float(g.NUCLEAR_GAP_MAX))])
			t += _li("[b]Relativistic strikes[/b] — hostile civilisations fire lasers (light speed), missiles (%s c) and berserker swarms at human worlds. A hit on a colony destroys it; a hit on Earth kills everyone there and destroys about a third of its structures. Missiles and swarms can be shot down on arrival by an Orbital Laser; lasers cannot." % _n(float(g.RKKV_BETA)))
			t += _li("%s guarantee survivors in impacts and nuclear war." % _building_link("Bunker"))
		"sol":
			# Both figures follow the star's current state: a lightened Sol swells less, and
			# reaches each stage later.
			var peak: float = 0.0
			var peak_age: float = 0.0
			for s: Array in Planet.SUN_STAGES:
				var r: float = float(g.SUN_RADIUS_BASE_AU) * float(s[4]) \
					* StarModel.radius_mult(SolarSystem.star_mass_msun)
				if r > peak:
					peak = r
					peak_age = float(s[0])
			t += _p("Sol follows one evolutionary track: slow brightening on the main sequence, then the red-giant branch, helium flash, horizontal branch and asymptotic giant branch, then envelope ejection. Where the star sits on that track depends on its mass, which is the one thing a civilisation can change about it.")
			if SolarSystem.star_is_engineered():
				t += _li("[b]Sol has been altered.[/b] %.4f M☉ remain, %.1f %% of the original. It burns at %s of its old light and ages at %.3f× the calendar, which is what moves the dates below." % [
					SolarSystem.star_mass_msun, SolarSystem.star_mass_msun * 100.0,
					("%.3f" % StarModel.luminosity_mult(SolarSystem.star_mass_msun)),
					1.0 / StarModel.lifetime_stretch(SolarSystem.star_mass_msun)])
			t += _li("Any planet whose orbit lies inside the photosphere is destroyed with its moons, structures and people. The photosphere peaks at %.3f AU around year %s (Earth orbits at 1.000 AU)." % [
				peak, _n(SolarSystem.star_year_of_age(peak_age))])
			t += _li("In year %s Sol ejects its envelope; ultraviolet flux ends all life remaining in the system." % _n(float(g.sun_nebula_year())))
			t += _li("[b]Star lifting.[/b] %s built on the Sun drive a controlled wind off it and catch what comes away. Each kilogram removed costs the binding energy of the material, %s J/kg — a floor set by physics — and the lifters draw that from the civilisation's reserve, banked energy included. What comes off is hydrogen, and it lands in the Sun's inventory." % [
				_building_link("Star Lifter"), _n(StarModel.LIFT_ENERGY_PER_KG)])
			t += _li("[b]Fate.[/b] Mass decides how Sol ends, and lifting can carry it past two thresholds. Above %s M☉ the track above runs to its end. Below that the core never ignites helium: there is no giant branch, Earth is never engulfed, no envelope is ever ejected, and the star settles as a helium dwarf — the two dates simply stop existing. Below %s M☉ nothing fuses at all and the Sun is out. Sol is currently bound to be: [b]%s[/b]." % [
				_n(StarModel.HELIUM_FUSION_MIN_MSUN), _n(StarModel.HYDROGEN_FUSION_MIN_MSUN),
				SolarSystem.sun_fate_text()])
			t += _li("[b]The cost of a dimmer sun.[/b] Earth's ceiling answers to the light that reaches it, whether the shades took it or the star stopped making it. A quarter of Sol lifted away leaves the biosphere about a third of its sunlight, which is a climate catastrophe in the cold direction — buying billions of years this way means having somewhere else to live, or a warmed world to spend.")
			t += _li("A lighter star burns dimmer and lives longer: luminosity follows M^%s and lifetime M^%s, so lifting 1 %% of Sol costs about a tenth of its remaining light-budget in effort and buys roughly 190 million years. Mass cannot be added, and lifting stops at %s M☉." % [
				_n(StarModel.LUMINOSITY_EXP), _n(absf(StarModel.LIFETIME_EXP)), _n(StarModel.MIN_MASS_MSUN)])
			t += _li("[b]Sunshades.[/b] %s do nothing to the star: they stand between it and the planets. Shading offsets greenhouse warming in the same balance, so a warmed Earth recovers — but shading past what the CO₂ is doing chills it, and every solar collector on a shaded world makes proportionally less. At most %s %% of the light can be intercepted." % [
				_building_link("Sunshade Constellation"), _n(StarModel.MAX_SHADE_FRACTION * 100.0)])
			t += _li("[b]Stellar husbandry.[/b] %s mix unburnt hydrogen from the envelope into the core, taking years off the star's clock at %s J a year — far cheaper per year than lifting, and it costs no mass and no light. It cannot wind Sol back past the year the run began." % [
				_building_link("Core Mixing Array"), _n(StarModel.HUSBANDRY_ENERGY_PER_YEAR)])
			t += _li("[b]Stellar propulsion.[/b] %s hung to one side of the Sun reflect its light back, and the star feels the recoil — a Shkadov thruster. It spends nothing: the engine is the star, and the mirrors only have to stand. Thrust is %s of the star's light-momentum against its whole mass, so the answer comes in millimetres per second per century and light-years over geological time. Aim it at a star from the star map; every distance the game measures from Sol moves with it." % [
				_building_link("Shkadov Mirror"), "%d %%" % int(round(StarModel.MIRROR_THRUST_EFFICIENCY * 100.0))])
			t += _li("The run survives the loss of the Sol system only if the species holds something beyond it: an interstellar colony, a share of a star cluster, or a settled galaxy region.")
			t += _li("Sun's luminosity now: %.2f L☉." % SolarSystem.sun_luminosity_lsun(int(g.year)))
		"interstellar":
			t += _p("With %s researched, the star map can launch colony ships. A flight accelerates to the chosen speed, coasts and decelerates; its energy is the relativistic kinetic energy of a %s kg ship, paid twice." % [
				_research_link("relativistic_navigation"), _n(StarMapPanel.SHIP_MASS)])
			t += _li("Arrivals within %s ly of Sol become individually simulated colonies. Farther arrivals fold into the statistical region model, which then fills and spreads on its own." % _n(float(g.DETAILED_RADIUS_LY)))
			t += _li("A star cluster needs one probe and no more. The landing puts a foothold on a single star — the cluster reads 0 %% settled that day — and it spreads on its own from there at %s of the cluster a year, the same rate a region of the galaxy fills its own stars, so a cluster takes about %s years to settle completely. Sending further probes to it achieves nothing." % [
				_n(float(g.CLUSTER_SATURATE_RATE)), _n(1.0 / float(g.CLUSTER_SATURATE_RATE))])
			t += _li("A system known to be inhabited cannot be targeted by colony ships or colonising probes; an unknown inhabited one is discovered on arrival and nothing is founded.")
			t += _li("Colonies develop their own Dyson swarm, telescopes and lasers over time; their telescopes extend how far stars can be resolved.")
		"probes":
			t += _p("A crafted %s launched from the star map settles, surveys or listens at its target, then builds %d copies that leave for the nearest unclaimed stars. Orders travel with every copy. Requires %s and %s." % [
				_item_link("VNProbe"), int(g.VN_REPLICATE_COUNT), _research_link("relativistic_navigation"), _research_link("self_replicating_industry")])
			for m: Dictionary in DoctrineData.PROBE_MISSIONS:
				t += _li("[b]%s[/b] — %s Launch energy ×%s of a colony ship's; %s." % [str(m["name"]), _esc(str(m["desc"])),
					_n(float(m["mass_frac"])), "claims the system" if bool(m["claims"]) else "claims nothing"])
			t += _li("At most %d probes are in flight at once; existing lineages retry every %s years, so a stalled frontier resumes on its own. Each launch is paid from the energy reserve." % [
				int(g.VN_MAX_INFLIGHT), _n(float(g.VN_RESUME_INTERVAL))])
		"aliens":
			t += _p("A number of civilisations, set by the Neighbours option, occupy stars near Sol. Each is hidden until detected, and its alignment (aggressive or peaceful) is unknown until contact.")
			t += _li("A civilisation can be detected only once its light has reached Sol. Each year the chance is %s × detection power ÷ distance in ly." % _n(float(g.ALIEN_DETECT_BASE)))
			t += _li("Detection power = (1 + detection buildings) × (1 + detection research) × (1 + %s per communication relay); zero before %s." % [_n(float(g.RELAY_DETECT_GAIN)), _research_link("radio_astronomy")])
			t += _li("What is seen is light-delayed; a recon probe returns the current state.")
			t += _li("Civilisations spread to nearby stars. Aggressive ones build lasers, missiles and berserkers as they age and fire them at human worlds; peaceful ones do not.")
			t += _li("Messages travel at light speed and the reply returns after twice the distance in years. Contact reveals alignment; peaceful systems accept alliance, and an alliance overture to a hostile provokes open war. Trade is proposed through the trade panel (%s)." % _link("Mechanics", "trade", "Interstellar trade"))
			t += _li("Strike rate scales with the Hostility option, the %s and %s." % [_link("Mechanics", "doctrine", "contact doctrine"), _link("Mechanics", "deterrence", "deterrence")])
		"trade":
			t += _p("The Trade button on the star map opens a proposal to a detected civilisation. Both sides can hold energy, science and any material; the goods offered come from, and the goods received go to, the Sol-system world chosen in the panel. The proposal travels at light speed and the reply returns after twice the distance in years; one message to a system can be in transit at a time. Transmission costs %s." % Units.format_si(float(g.MSG_ALLY_ENERGY), "J"))
			t += _li("Offered goods leave their stores when the proposal is sent. If it is refused they are returned; if accepted, the request arrives with the reply. Energy above storage capacity is lost.")
			t += _li("Goods are valued as embodied energy: energy at face value; science at %s per FLOP (the energy of computing it); raw materials at %s per gram × abundance^-%s, abundance being the mass fraction in the richest mineable layer anywhere; manufactured goods at the inputs plus energy of their cheapest recipe, per gram of output." % [
				Units.format_si(TradeData.SCIENCE_VALUE_PER_FLOP, "J"), Units.format_si(TradeData.RAW_VALUE_PER_G, "J"), _n(TradeData.RAW_SCARCITY_POW)])
			var ratios: Array = []
			for st: String in ["allied", "trading", "contact", ""]:
				ratios.append("%s %d %%" % [st if st != "" else "no prior contact", int(round(float(TradeData.ACCEPT_RATIO[st]) * 100.0))])
			t += _li("A peaceful civilisation accepts when the offer's value is at least a share of the request's that depends on standing: " + ", ".join(ratios) + ". A proposal that asks for nothing is a gift and is always accepted.")
			t += _li("It can supply at most one year of its own output per proposal: from %s with no Dyson swarm up to %s with a complete one. The panel's estimate uses light-delayed intel; the civilisation decides on its actual state when the proposal arrives." % [
				Units.format_si(TradeData.PRE_SWARM_POWER_W, "W"), Units.format_si(TradeData.FULL_SWARM_POWER_W, "W")])
			t += _li("Hostile civilisations, and any at war with this one, refuse every proposal. An accepted trade sets the standing to trading, unless already allied.")
		"doctrine":
			t += _p("The standing rule for answering attacks, chosen at the start of a run and changeable in the Automation panel. Retaliation fires crafted %s at the attacker automatically." % _item_link("Missile"))
			for d: Dictionary in DoctrineData.DOCTRINES:
				t += _li("[b]%s[/b] — hostile strike rate ×%s; answers each attack with %d missile%s; %s; %s." % [
					str(d["name"]), _n(float(d["provocation"])), int(d["retaliate"]), "" if int(d["retaliate"]) == 1 else "s",
					("fires first on every detected civilisation except allies, and a peaceful one struck is at war" if str(d.get("targets", "hostile")) == "all"
						else "fires first on any detected hostile") if bool(d["first_strike"]) else "never fires first",
					"stops once answered" if bool(d["forgives"]) else "never stops answering"])
		"deterrence":
			t += _p("Holding at least one crafted %s establishes deterrence. Strength = berserkers + %s × stockpiled missiles." % [_item_link("Berserker"), _n(float(g.MISSILE_DETER_WEIGHT))])
			t += _li("Hostile strike rate is multiplied by %s × %s^(strength − 1), never below %s." % [_n(float(g.DETERRENCE_MULT)), _n(float(g.DETERRENCE_STACK)), _n(float(g.DETERRENCE_FLOOR))])
			t += _li("Deterrence lapses when the berserker stockpile reaches zero.")
		"belt":
			t += _p("The main asteroid belt, between %s and %s AU, is played as a world of its own. Its hub is Ceres, the largest body in it: launches arrive there and the camera focuses on it. Orbital structures built in the belt orbit the Sun among the asteroids, each type on its own lane across the band. Hovering anywhere on the band outlines the belt; clicking selects it." % [
				_n(AsteroidBelt.BELT_INNER_AU), _n(AsteroidBelt.BELT_OUTER_AU)])
			t += _li("Settled like a planet: a Colony Ship to the Asteroid Belt founds a colony, and from then on it can be built on.")
			t += _li("Its mines work the whole belt's bulk chemistry, weighted by mass: mostly carbonaceous material (hydrated clays, water, magnetite, carbonates, sulfates and organic carbon), stony material with troilite and free iron-nickel — mined as metal, not ore — and a few percent of metallic bodies. There is no coal: %s turns its organic carbon into char for smelting. It has no atmosphere." % _recipe_link("Organic Carbon Pyrolysis"))
			t += _li("It has no biosphere: its population is whatever habitat is built for it.")
			t += _li("Asteroid impacts never target it.")
			t += _li("It lies beyond the Sun's largest photosphere; it is lost only when the Sun ejects its envelope.")
			var yes: Array = []
			var no: Array = []
			for b: Dictionary in BuildingData.BUILDINGS:
				if (b.get("allowed_types", []) as Array).has("belt"):
					yes.append(_building_link(str(b["name"])))
				else:
					no.append(_building_link(str(b["name"])))
			t += _h2("Buildable here (%d)" % yes.size())
			t += _p(", ".join(yes))
			t += _h2("Not buildable here (%d)" % no.size())
			t += _p("Structures that need an atmosphere, weather, open ground, a water cycle or a gravity well: " + ", ".join(no) + ".")
		"evolution":
			t += _p("A population reproductively isolated on one world for 0.5–1 million years diverges into a distinct lineage, H. sapiens <world>. Earth's clock starts in 1945; each colony's at its founding. A colony's lineage descends from the lineage of the world that settled it, if that world had already diverged. Lineages appear in the Evolution panel.")
	return t

# ── Formatting helpers ────────────────────────────────────────────────────────

static func _h1(s: String) -> String:
	return "[font_size=26][b]%s[/b][/font_size]\n" % s

static func _h2(s: String) -> String:
	return "\n[font_size=18][color=%s][b]%s[/b][/color][/font_size]\n" % [COL_HEAD, s]

static func _sub(s: String) -> String:
	return "[color=%s]%s[/color]\n\n" % [COL_DIM, s]

static func _p(s: String) -> String:
	return s + "\n"

static func _li(s: String) -> String:
	return "  •  " + s + "\n"

static func _list_or(lines: Array, empty: String) -> String:
	if lines.is_empty():
		return _li("[color=%s]%s[/color]" % [COL_DIM, empty])
	var t: String = ""
	for l in lines:
		t += _li(str(l))
	return t

## Escape authored text for BBCode: a literal "[" would otherwise start a tag.
static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")

static func _link(cat: String, key: String, text: String) -> String:
	return "[url=%s|%s]%s[/url]" % [cat, key, _esc(text)]

static func _building_link(name: String) -> String:
	var def: Dictionary = {}
	for b: Dictionary in BuildingData.all():
		if str(b["name"]) == name:
			def = b
			break
	return _link("Buildings", str(def.get("base_name", name)), name)

static func _item_link(c: String) -> String:
	return _link("Items", c, item_name(c))

static func _recipe_link(name: String) -> String:
	return _link("Recipes", name, name)

static func _research_link(id: String) -> String:
	var n: ResearchNode = _research_node(id)
	return _link("Research", id, n.display_name if n else id)

static func _g(v: float) -> String:
	return Units.format_si(v, "g")

static func _n(v: float) -> String:
	if absf(v) < 1000.0 and absf(v) >= 0.01:
		var s: String = ("%.2f" % v).rstrip("0").rstrip(".")
		return s
	return Units.format_si(v, "").strip_edges()

static func _sum(d: Dictionary) -> float:
	var t: float = 0.0
	for k in d:
		t += float(d[k])
	return maxf(t, 1.0e-30)

static func _frac(f: float) -> String:
	if f >= 0.001:
		return "%s %%" % _n(f * 100.0)
	if f >= 1.0e-6:
		return "%s ppm" % _n(f * 1.0e6)
	return "%s ppb" % _n(f * 1.0e9)

static func _duration(days: float) -> String:
	if days < 1.0:
		return "under a game-day"
	if days < 365.25:
		return "%d game-days" % int(round(days))
	return Units.format_si(days / 365.25, "yr")

static func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for k: String in cost:
		if k == "energy":
			parts.append(Units.format_si(float(cost[k]), "J") + " energy")
		elif k == "minerals":
			parts.append(_g(float(cost[k])) + " matter")
		else:
			parts.append("%s %s" % [_g(float(cost[k])), _item_link(k)])
	return ", ".join(parts) if not parts.is_empty() else "free"

## A recipe side scaled to one unit of rate: "3 g Hematite, 50 J energy".
static func _amounts_text(amounts: Dictionary, s: float) -> String:
	var parts: Array = []
	for k: String in amounts:
		var v: float = float(amounts[k]) * s
		if k == "energy":
			parts.append(Units.format_si(v, "J") + " energy")
		elif k == "minerals":
			parts.append(_g(v) + " matter")
		else:
			parts.append("%s %s" % [_g(v), _item_link(k)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"
