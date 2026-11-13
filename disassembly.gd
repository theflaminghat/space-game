class_name DisassemblyData

## Taking a planet apart.
##
## A civilisation that has built a swarm needs mass more than it needs anywhere to stand, and
## the planets are where the mass is. This is the other half of stellar engineering: Star
## Lifting takes the Sun apart from the outside, and this takes everything else apart.
##
## ── Why the cost is binding energy, and why it is not the limit ──
##
## Lifting a kilogram off a body costs, at minimum, the energy holding it there. For a roughly
## uniform sphere that is (3/5)GM²/R over the whole body, so (3/5)GM/R per kilogram averaged —
## a floor set by physics in the same way StarModel.LIFT_ENERGY_PER_KG is, and for the same
## reason. No lift geometry gets under it.
##
##   Sol, at the photosphere   1.91e11 J/kg
##   Earth                     3.75e7  J/kg      2.24e32 J for the whole planet
##   Mercury                   5.42e6  J/kg      1.79e30 J for the whole planet
##
## A planet is four to five ORDERS OF MAGNITUDE cheaper per kilogram than its star, which is
## the honest reason a civilisation eats the planets first — and it falls out of the physics
## rather than being a decision anybody made.
##
## It also means energy cannot be what limits this. Mercury's entire binding energy is about
## five days of a complete Dyson swarm; gate on energy alone and taking a planet apart is a
## button. What actually limits it is moving 3.3e26 grams, so the RATE comes from installed
## machinery (Planetary Disassembler, in grams per day) and the energy is a floor that stops it
## being free in 1960. Build more, go faster; the bill per gram never moves.
##
## ── Outside in ──
##
## Layers are consumed in LAYER_ORDER, which is the order they are reachable in: you cannot mine
## a core through a mantle. That is what makes a half-eaten planet a different proposition from
## a fresh one — the crust is the interesting thin layer, the mantle is bulk silicate feedstock,
## and the iron-nickel core a swarm actually wants is the last thing you reach. On a gas giant
## the envelope IS the planet, so Jupiter is a hydrogen reservoir with a small rocky prize at
## the bottom of it.

## Gravitational constant, m³ kg⁻¹ s⁻².
const G: float = 6.674e-11

## Outermost first. A layer absent from a body's composition is simply skipped — a gas giant has
## no crust and Mercury's atmosphere is a few hundred tonnes of sodium.
const LAYER_ORDER: Array[String] = ["atmosphere", "crust", "mantle", "core"]

## Human-readable, for the readout.
const LAYER_LABEL: Dictionary = {
	"atmosphere": "Atmosphere",
	"crust":      "Crust",
	"mantle":     "Mantle",
	"core":       "Core",
}

## Mean binding energy per kilogram for a uniform sphere: (3/5)GM/R.
##
## Uniform, deliberately. A real planet is centrally condensed and its true binding energy is
## some tens of percent higher, but the mass distribution that would fix that is not in
## PlanetData and the order of magnitude — which is the part that matters here — is the same.
static func binding_j_per_kg(mass_kg: float, radius_km: float) -> float:
	if mass_kg <= 0.0 or radius_km <= 0.0:
		return 0.0
	return 0.6 * G * mass_kg / (radius_km * 1000.0)


## The same figure per GRAM, which is the unit every mass in this game is kept in.
static func binding_j_per_gram(mass_kg: float, radius_km: float) -> float:
	return binding_j_per_kg(mass_kg, radius_km) * 1.0e-3


## What it costs to take `grams` off a body with this mass and radius, in joules.
static func lift_cost_j(grams: float, mass_kg: float, radius_km: float) -> float:
	return maxf(grams, 0.0) * binding_j_per_gram(mass_kg, radius_km)


## How many grams `joules` will pay to lift off a body — the inverse, for a tick that is short
## of energy and has to scale back what it takes.
static func grams_for_energy(joules: float, mass_kg: float, radius_km: float) -> float:
	var per: float = binding_j_per_gram(mass_kg, radius_km)
	if per <= 0.0:
		return 0.0
	return maxf(joules, 0.0) / per


static func layer_label(layer: String) -> String:
	return str(LAYER_LABEL.get(layer, layer.capitalize()))


# ── What a half-eaten world looks like ────────────────────────────────────────
#
# A planet being taken apart should not look like a planet. Its surface map IS its outermost
# layer — the crust, or a giant's cloud tops — and it goes with that layer: eaten away in patches
# as the layer comes off, and gone entirely once it has. What is under it is hot silicate and then
# iron, neither of which looks anything like a surface, and nothing of the map is carried down
# into them. The shader gives them a structure of their own (planet_polar_blur.gdshader).
#
# Driven off two numbers Game works out from the removal ledger, so the look follows the same
# account the simulation keeps rather than a second idea of progress:
#
#   depth         how far through the layers that make up what you SEE the excavation has
#                 reached, 0 untouched to 1 at the last of the core (Game._disassembly_depth)
#   surface_gone  how much of the map has been taken away, 0 to 1 (Game._disassembly_surface_gone)
#
# A GIANT is different, and simpler. Its map is its cloud tops, and under them is more of the same
# gas, and then fluid, all the way down: there is no surface to breach and nothing molten to show.
# So it keeps its map and only gets smaller while its envelope goes, and when the core is reached
# the clouds give way to bare metal (over the first CORE_BREACH of the core, so the change spreads
# in patches rather than flipping in one frame).

## Hot silicate: what is under a crust.
const MOLTEN_COLOR: Color = Color(0.98, 0.42, 0.10)
## Iron-nickel: what is under that.
const METAL_COLOR: Color = Color(0.60, 0.63, 0.70)

## Share of a giant's core over which its clouds give way to the metal under them.
const CORE_BREACH: float = 0.10

## Depth over which molten gives way to metal.  A rocky world's look has three layers (its air is
## not one, see Game._look_layers), so this runs from half-way down its mantle to early in its
## core; a giant's two put it across the top of the core.
const LOOK_CORE_IN: float = 0.50
const LOOK_CORE_FULL: float = 0.80


## How the body is shaded.
##
##   mix       how much of the surface map has been taken away — exactly `surface_gone`
##   color     the exposed material's own colour
##   glow      self-light: a breached mantle is incandescent, a core is not
##   metallic  iron reads as metal and silicate does not
##
## `giant`: what is exposed is the core and nothing else — metal, cold, from the first patch.
static func look(depth: float, surface_gone: float, giant: bool = false) -> Dictionary:
	var d: float = clampf(depth, 0.0, 1.0)
	var s: float = clampf(surface_gone, 0.0, 1.0)
	if giant:
		return {"mix": s, "color": METAL_COLOR, "glow": 0.0, "metallic": 0.90}
	var to_core: float = smoothstep(LOOK_CORE_IN, LOOK_CORE_FULL, d)
	return {
		"mix": s,
		"color": MOLTEN_COLOR.lerp(METAL_COLOR, to_core),
		# Brightest as the surface goes, and cooling as the iron comes up.
		"glow": 0.45 * s * (1.0 - to_core),
		"metallic": 0.90 * to_core,
	}


## Visual radius against an untouched body, for `remaining` of its mass left.
##
## The CUBE ROOT, because mass goes as the cube of the radius at constant density: a world with
## half its mass gone is not half the size, it is 0.79 of it. Taking the first tenth off a planet
## is barely visible and that is correct — the crust is a skin.
static func radius_frac(remaining: float) -> float:
	return pow(clampf(remaining, 0.0, 1.0), 1.0 / 3.0)
