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
# A planet being taken apart should not look like a planet. The crust is the only part anybody
# ever sees from orbit, and once it is gone what is under it is hot silicate and then iron —
# neither of which looks anything like a surface.
#
# Driven off ONE number, `depth`: how far through the layers the excavation has reached, 0 at an
# untouched world and 1 at the last of the core. Game works it out from the layer being removed
# and how much of that layer is left (see _disassembly_depth), so the look follows the same
# ledger the simulation does rather than a second idea of progress.
#
# No new art. The surface map stays in play as the body's STRUCTURE — its own light and dark is
# what the molten and metal passes are modulated by — so a half-eaten Mars still reads as Mars
# with its crust off, rather than as a billiard ball. See planet_polar_blur.gdshader.

## Hot silicate: what is under a crust.
const MOLTEN_COLOR: Color = Color(0.98, 0.42, 0.10)
## Iron-nickel: what is under that.
const METAL_COLOR: Color = Color(0.60, 0.63, 0.70)

## Depth at which the surface map has been entirely replaced by what is beneath it.
const LOOK_BREACH: float = 0.45
## Depth over which molten gives way to metal.
const LOOK_CORE_IN: float = 0.50
const LOOK_CORE_FULL: float = 0.95


## How the body is shaded at this excavation depth.
##
##   mix       how much of the surface map is replaced by the exposed material
##   color     the exposed material's own colour
##   glow      self-light: a breached mantle is incandescent, a core is not
##   metallic  iron reads as metal and silicate does not
static func look(depth: float) -> Dictionary:
	var d: float = clampf(depth, 0.0, 1.0)
	var to_core: float = smoothstep(LOOK_CORE_IN, LOOK_CORE_FULL, d)
	return {
		"mix": smoothstep(0.0, LOOK_BREACH, d),
		"color": MOLTEN_COLOR.lerp(METAL_COLOR, to_core),
		# Brightest just after the crust goes, and cooling as the iron comes up.
		"glow": 0.45 * smoothstep(0.0, LOOK_BREACH, d) * (1.0 - to_core),
		"metallic": 0.90 * to_core,
	}


## Visual radius against an untouched body, for `remaining` of its mass left.
##
## The CUBE ROOT, because mass goes as the cube of the radius at constant density: a world with
## half its mass gone is not half the size, it is 0.79 of it. Taking the first tenth off a planet
## is barely visible and that is correct — the crust is a skin.
static func radius_frac(remaining: float) -> float:
	return pow(clampf(remaining, 0.0, 1.0), 1.0 / 3.0)
