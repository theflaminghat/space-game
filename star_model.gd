class_name StarModel
extends RefCounted

## Sol's physics, as a pure function of its mass and its age.  Nothing here reads or writes game
## state: SolarSystem holds the star's current mass and calls into this, and everything that asks
## about the Sun — engulfment, the endgame, the swarm's yield, the visuals, the wiki — goes
## through those wrappers.  That indirection is the whole point of stellar engineering: the Sun
## stops being a fixed function of the calendar and becomes a function of what has been done to
## it.
##
## STELLAR AGE vs CALENDAR YEAR.  SUN_STAGES below is a track through the star's own life, and
## until the player touches Sol the two clocks run together.  Lighten the star and its clock
## slows: the same calendar year now finds it younger, which is exactly what buys the extra
## billions of years.  stellar_age() converts one to the other and year_of_age() converts back,
## so "when does the red giant come now?" has an answer the UI can print.
##
## THE SCALINGS.  Only main-sequence relations, applied to the whole track:
##   luminosity  L ∝ M^3.5             — a 1 % lighter Sun burns about 3.4 % dimmer
##   lifetime    t ∝ M / L = M^-2.5    — and lives about 2.5 % longer
##   radius      R ∝ M^0.8
## A real star that had a tenth of its mass lifted away would not follow its old track scaled;
## it would evolve differently in kind.  This keeps the one curve the game already draws and
## moves it in the right direction by the right order of magnitude, which is the honest limit of
## what a civilisation sim needs.  A pristine Sun (exactly 1 M☉) leaves every factor at 1.0, so
## nothing about an untouched run changes.

## The run's reference point: at this year the star's age equals the calendar year whatever its
## mass, so lifting alters the future and never rewrites the past.
const EPOCH_YEAR: float = 2026.0
# ── Fates ─────────────────────────────────────────────────────────────────────
## Two masses decide how the star ENDS, and lifting can carry Sol past both of them.
##
## Above HELIUM_FUSION_MIN the core eventually ignites helium and the authored track runs to its
## end: red giant, helium flash, AGB, ejected envelope, carbon-oxygen white dwarf.  Below it the
## core never gets hot enough — there is no giant branch at all, so Earth is never engulfed and
## no envelope is ever thrown off.  The star simply burns hydrogen for an age and then settles
## as a helium white dwarf.
##
## Below HYDROGEN_FUSION_MIN nothing fuses.  Lift Sol past that line and it is not a star any
## more: the civilisation has put its own sun out.
const HELIUM_FUSION_MIN_MSUN:   float = 0.50
const HYDROGEN_FUSION_MIN_MSUN: float = 0.08
## Lifting stops where fusion does — there is nothing further to do to a star by taking mass off
## it.  (The M^3.5 and M^-2.5 scalings are main-sequence relations and get rough below ~0.3 M☉,
## where stars turn fully convective; they are kept because the alternative is a second authored
## track for a case the player reaches only by choosing to.)
const MIN_MASS_MSUN: float = HYDROGEN_FUSION_MIN_MSUN

## Age at which the authored track leaves the main sequence.  A star that will never fuse helium
## stops here and stays: no subgiant, no giant, no nebula.
const MS_END_AGE: float = 5_400_000_000.0
## The remnants, in solar units.  A white dwarf is Earth-sized and fading; an extinguished star
## is a brown dwarf, warm from contraction and nothing else.
const WD_RADIUS_SOLAR:      float = 0.013
const WD_LUMINOSITY_LSUN:   float = 1.0e-3
const BD_RADIUS_SOLAR:      float = 0.10
const BD_LUMINOSITY_LSUN:   float = 1.0e-5

enum Fate { GIANT_THEN_CO_DWARF, HELIUM_DWARF, EXTINGUISHED }


## What this star is now bound to become.
static func fate(mass_msun: float) -> Fate:
	var m: float = clamp_mass(mass_msun)
	if m < HYDROGEN_FUSION_MIN_MSUN + 1e-9:
		return Fate.EXTINGUISHED
	if m < HELIUM_FUSION_MIN_MSUN:
		return Fate.HELIUM_DWARF
	return Fate.GIANT_THEN_CO_DWARF


## The same, in words, for the Sun's panel and the encyclopedia.
static func fate_text(mass_msun: float) -> String:
	match fate(mass_msun):
		Fate.EXTINGUISHED:
			return "extinguished — no fusion"
		Fate.HELIUM_DWARF:
			return "no giant phase; helium dwarf"
		_:
			return "red giant, then carbon-oxygen dwarf"


## Whether the star will ever ascend the giant branch.  When it will not, the two dates that end
## a solar system never arrive at all.
static func has_giant_phase(mass_msun: float) -> bool:
	return fate(mass_msun) == Fate.GIANT_THEN_CO_DWARF
const LUMINOSITY_EXP: float = 3.5
const LIFETIME_EXP:   float = -2.5
const RADIUS_EXP:     float = 0.8

## Physical radius of the present-day Sun, in AU.
const SUN_RADIUS_BASE_AU: float = 0.00465

# ── Star lifting ──────────────────────────────────────────────────────────────
## Sol's mass in kilograms, so lifted tonnage can be turned into a change in M☉.
const SUN_MASS_KG: float = 1.989e30
## What it costs to take a kilogram off the Sun, in joules: the gravitational binding energy at
## the photosphere, GM/R = 6.674e-11 × 1.989e30 / 6.957e8.  This is a floor set by physics, not a
## balance knob — no nozzle design gets under it — and it is why lifting is a project measured in
## stellar output and geological time rather than a button.
const LIFT_ENERGY_PER_KG: float = 1.908e11
## Fraction of the energy spent that ends up as lifted mass; the rest is lost in the wind, the
## nozzle fields and the collection.  Generous, but the order of magnitude is the honest part.
const LIFT_EFFICIENCY: float = 0.60


## Mass in kilograms that `joules` of collected energy can lift off the star.
static func mass_lifted_kg(joules: float) -> float:
	return maxf(0.0, joules) * LIFT_EFFICIENCY / LIFT_ENERGY_PER_KG


## The same figure as a fraction of a solar mass — what the star's state is measured in.
static func mass_lifted_msun(joules: float) -> float:
	return mass_lifted_kg(joules) / SUN_MASS_KG


# ── Stellar husbandry ─────────────────────────────────────────────────────────
## Energy to take one year off the star's age, in joules.
##
## Husbandry does not remove mass; it mixes unburnt hydrogen from the envelope down into the
## core, so the core meets fresh fuel it would never otherwise see.  Buying a year of life means
## supplying a year of core fuel — Sol fuses about 6.2e11 kg/s, so 2.0e19 kg a year — driven
## down against a stably stratified envelope into a potential well far deeper than the surface
## one.  Reckoned at about three times the energy it takes to lift the same mass clear of the
## star: 2.0e19 kg × 3 × 1.908e11 J/kg.
##
## Per year of life gained this lands within a factor of two of star lifting, which is the
## intent.  The two are alternatives, not an upgrade path: lifting is crude and pays in hydrogen
## while dimming the star, husbandry is surgical, costs no mass and no light, and gives back
## nothing but time.
const HUSBANDRY_ENERGY_PER_YEAR: float = 1.145e31


## Years of stellar age that `joules` of work can undo.
static func years_rejuvenated(joules: float) -> float:
	return maxf(0.0, joules) / HUSBANDRY_ENERGY_PER_YEAR


# ── Stellar propulsion (the Shkadov thruster) ─────────────────────────────────
## A statite mirror hung on one side of the star reflects its light back, and the star feels the
## recoil.  Nothing is thrown away and nothing is spent: the engine is the star's own radiation,
## so it costs only what the mirrors cost to build, and it pushes for as long as the star burns.
##
## Thrust is the momentum of the light it turns around.  A perfect one-sided mirror would give
## the whole L/c; a real one gives a small fraction of it, because a statite has to hover on the
## same light pressure it is trying to use and can only subtend so much of the sky at an areal
## density that light can hold up.
##
## Published Class A stellar engines come out around 1e-15 m/s² on a star like Sol — against
## L/c ÷ M☉ = 6.4e-13, that is about 0.16 %, which is the figure used here.  It is a slow engine
## by construction: the payoff is measured in light-years across geological time, not in any
## human span.
const MIRROR_THRUST_EFFICIENCY: float = 0.0016
## Solar luminosity in watts at the epoch, for turning L☉ into newtons.
const SOLAR_LUMINOSITY_W: float = 3.828e26
const LIGHT_SPEED_MS: float = 2.998e8
const LY_M: float = 9.4607e15
const SECONDS_PER_YEAR: float = 3.1557e7


## Thrust in newtons from a mirror covering `coverage` of the sky around a star of `lum` L☉.
## The brighter the star, the harder it pushes — a red giant is a far better engine than a
## main-sequence sun, and a star lifted down to a dwarf is a far worse one.
static func shkadov_thrust_n(coverage: float, luminosity_lsun: float) -> float:
	return maxf(coverage, 0.0) * MIRROR_THRUST_EFFICIENCY \
		* maxf(luminosity_lsun, 0.0) * SOLAR_LUMINOSITY_W / LIGHT_SPEED_MS


## The acceleration that thrust gives a star of `mass_msun`, in m/s².  Lifting mass away makes
## the star easier to push as well as dimmer; the two pull against each other.
static func shkadov_accel_ms2(coverage: float, luminosity_lsun: float, mass_msun: float) -> float:
	return shkadov_thrust_n(coverage, luminosity_lsun) / maxf(mass_msun * SUN_MASS_KG, 1.0)


# ── Shading ───────────────────────────────────────────────────────────────────
## Largest fraction of the Sun's light the shades may intercept.  Past this the inner system is
## dark whatever the player intended, and the model has nothing sensible to say.
const MAX_SHADE_FRACTION: float = 0.90
## How much warming one unit of dimming offsets, in the climate model's own units — where 1.0 is
## the CO₂ load that halves Earth's ceiling (Game.CO2_K_HALF).
##
## Calibrated so the two sides of the balance are the same physics.  CO2_K_HALF is about six
## times the CO₂ the atmosphere holds today, near 2.5 doublings, so one unit of the game's
## warming is roughly 9 W/m² of forcing.  Intercepting 1 % of the sunlight takes about 2.4 W/m²
## out of the absorbed budget — 0.27 of a unit.  Hence 27 per unit of dimming, and shading 3.7 %
## of the light exactly cancels a ceiling-halving CO₂ load.
##
## It cuts both ways, which is the point: a star dimmed by lifting is felt by the biosphere on
## the same scale, so a civilisation cannot quietly take a quarter of its sun away and go on
## living on Earth.
const SHADE_OFFSET_PER_FRACTION: float = 27.0


## Ages (not calendar years) of the two moments that end a solar system.  What year each falls in
## depends on the star's mass — see SolarSystem.sun_red_giant_year() / sun_nebula_year().
const RED_GIANT_AGE: float = 7_590_000_000.0
const NEBULA_AGE:    float = 8_210_000_000.0
## The HUD starts warning this long before the red-giant tip.
const WARNING_LEAD_YEARS: float = 1_000_000.0

const SUN_STAGES: Array = [
	# Each entry: [year, color, visual_mult, emiss_mult, solar_radii, luminosity_Lsun]
	#
	# luminosity_Lsun — physically accurate power output in solar luminosities (see
	#                sun_luminosity_lsun()).  1 L☉ today, +10% per Gyr on the main sequence,
	#                soaring to ~2700 L☉ at the red-giant tip and ~4000 L☉ on the AGB before
	#                the envelope is ejected.  emiss_mult (the display glow) is a log-compressed
	#                image of this curve so the render brightens hugely at the giant tips
	#                without blowing the frame out to pure white.
	#
	# visual_mult  — multiplied by _sun_base_scale (= log(16) ≈ 2.773) for display.
	#                _sun_base_scale × visual_mult × sphere_radius (0.5) = game-unit radius.
	#                Calibrated so visual_mult 16.0 = Earth orbit ring (22.18 game units).
	#                Proportional formula: visual_mult ≈ solar_radii × (16.0 / 215).
	#
	# Orbit ring radii and visual_mult needed to reach them:
	#   Mercury 10.47 game units → 7.55×    Venus 17.42 → 12.57×
	#   Earth   22.18 game units → 16.00×   Mars  29.63 → 21.37× (NOT reached — AGB only ~12.6×)
	#
	# solar_radii  — AU-radius physics only (Game.gd/_get_sun_radius_au).
	#
	# Timeline notes:
	#   RGB tip (7.59B): peak expansion, Earth engulfed.
	#   Helium flash (7.591B): rapid collapse back to ~10 solar radii — still 3.5× modern sun,
	#     NOT tiny.  The 1 M yr window between RGB tip and CHeB represents the flash + settling.
	#   AGB tip (8.2B): second expansion peaks at ~170 solar radii (~0.79 AU).
	#     Mars at 1.524 AU is NOT engulfed.  Outer-system colonies survive until the
	#     planetary nebula fires at PLANETARY_NEBULA_YEAR (8.21B), which sterilises everything
	#     via intense UV/X-ray radiation regardless of orbital distance.
	[0,              Color(1.00, 0.95, 0.80),   1.00,  0.90,   1.0,      1.0],  # modern Sun
	[1_000_000_000,  Color(1.00, 0.92, 0.72),   1.00,  0.95,   1.05,     1.1],  # brightening MS — imperceptible change
	[5_400_000_000,  Color(1.00, 0.84, 0.45),   1.15,  1.10,   1.5,      1.8],  # subgiant begins
	[7_000_000_000,  Color(1.00, 0.60, 0.18),   3.50,  3.50,  10.0,     50.0],  # lower RGB (≈10 SR)
	[7_500_000_000,  Color(1.00, 0.32, 0.06),   9.50,  9.90, 100.0,   1200.0],  # upper RGB — past Mercury, near Venus
	[7_590_000_000,  Color(0.96, 0.18, 0.04),  16.00, 14.00, 215.0,   2700.0],  # RGB tip — Earth orbit, ~2700 L☉
	[7_591_000_000,  Color(0.60, 0.82, 1.00),   3.50,  3.50,  10.0,     50.0],  # helium flash — shrinks, turns blue-white, dims
	[7_700_000_000,  Color(0.90, 0.88, 0.80),   3.50,  3.80,  11.0,     60.0],  # CHeB stable (~100 M yr, ~11 SR)
	[8_000_000_000,  Color(1.00, 0.58, 0.20),   5.50,  7.80,  50.0,    500.0],  # early AGB — past Mercury again
	[8_200_000_000,  Color(0.94, 0.14, 0.03),  12.60, 16.00, 170.0,   4000.0],  # AGB tip (~170 SR = 0.79 AU), ~4000 L☉
	[8_210_000_000,  Color(0.62, 0.80, 1.00),   0.05, 12.00,   0.05,  3000.0],  # planetary nebula → white dwarf
]


# ── Mass scalings ─────────────────────────────────────────────────────────────

## Mass a star may actually have here: lifting only ever removes mass, and never past the floor.
static func clamp_mass(mass_msun: float) -> float:
	return clampf(mass_msun, MIN_MASS_MSUN, 1.0)


## How bright the star is, against the stage table's figure.
static func luminosity_mult(mass_msun: float) -> float:
	return pow(clamp_mass(mass_msun), LUMINOSITY_EXP)


## How big it is, against the stage table's figure.
static func radius_mult(mass_msun: float) -> float:
	return pow(clamp_mass(mass_msun), RADIUS_EXP)


## How much longer the whole track takes.  1.0 for a pristine star; above 1.0 once lightened.
static func lifetime_stretch(mass_msun: float) -> float:
	return pow(clamp_mass(mass_msun), LIFETIME_EXP)


# ── The two clocks ────────────────────────────────────────────────────────────

## The star's own age at a calendar year.  A lighter star ages more slowly, so this falls behind
## the calendar once mass has been lifted.
static func stellar_age(year: float, mass_msun: float, age_offset: float = 0.0) -> float:
	return EPOCH_YEAR + (year - EPOCH_YEAR) / maxf(lifetime_stretch(mass_msun), 1e-6) - age_offset


## The calendar year at which the star reaches an age — the inverse of stellar_age(), and what
## the UI needs to say when the red giant is now due.
static func year_of_age(age: float, mass_msun: float, age_offset: float = 0.0) -> float:
	return EPOCH_YEAR + (age + age_offset - EPOCH_YEAR) * lifetime_stretch(mass_msun)


# ── Reading the track ─────────────────────────────────────────────────────────

## The pair of stages bracketing an age, and how far between them it sits: [lo, hi, t].
static func _bracket(age: float) -> Array:
	var last: Array = SUN_STAGES[SUN_STAGES.size() - 1]
	if age >= float(last[0]):
		return [last, last, 0.0]
	var lo: Array = SUN_STAGES[0]
	var hi: Array = SUN_STAGES[1]
	for i in range(SUN_STAGES.size() - 1):
		if age >= float(SUN_STAGES[i][0]) and age < float(SUN_STAGES[i + 1][0]):
			lo = SUN_STAGES[i]
			hi = SUN_STAGES[i + 1]
			break
	var span: float = float(hi[0]) - float(lo[0])
	var t: float = 0.0 if span <= 0.0 else clampf((age - float(lo[0])) / span, 0.0, 1.0)
	return [lo, hi, t]


## Luminosity in L☉ at a stellar age, before the mass scaling.  Interpolated in LOG space so the
## enormous RGB/AGB swings read smoothly.
static func luminosity_at_age(age: float) -> float:
	var b: Array = _bracket(age)
	var l0: float = maxf(float((b[0] as Array)[5]), 1.0e-6)
	var l1: float = maxf(float((b[1] as Array)[5]), 1.0e-6)
	return exp(lerpf(log(l0), log(l1), float(b[2])))


## Radius in solar radii at a stellar age, before the mass scaling.
static func radius_solar_at_age(age: float) -> float:
	var b: Array = _bracket(age)
	return lerpf(float((b[0] as Array)[4]), float((b[1] as Array)[4]), float(b[2]))


# ── The star as it actually is ────────────────────────────────────────────────
# The three functions above read the AUTHORED TRACK, which describes a 1 M☉ star.  These three
# are what the game asks: the track where it still applies, the mass scalings on top, and the
# other two fates substituted where the track has nothing to say.

## Luminosity in L☉ of a star of this mass at this age.
static func luminosity_at(age: float, mass_msun: float) -> float:
	match fate(mass_msun):
		Fate.EXTINGUISHED:
			return BD_LUMINOSITY_LSUN
		Fate.HELIUM_DWARF:
			if age >= RED_GIANT_AGE:
				return WD_LUMINOSITY_LSUN          # hydrogen spent; a fading remnant
			return luminosity_at_age(minf(age, MS_END_AGE)) * luminosity_mult(mass_msun)
		_:
			return luminosity_at_age(age) * luminosity_mult(mass_msun)


## Radius in solar radii of a star of this mass at this age.
static func radius_solar_at(age: float, mass_msun: float) -> float:
	match fate(mass_msun):
		Fate.EXTINGUISHED:
			return BD_RADIUS_SOLAR
		Fate.HELIUM_DWARF:
			if age >= RED_GIANT_AGE:
				return WD_RADIUS_SOLAR
			return radius_solar_at_age(minf(age, MS_END_AGE)) * radius_mult(mass_msun)
		_:
			return radius_solar_at_age(age) * radius_mult(mass_msun)


## How a star of this mass looks at this age: { color, visual_mult, emiss_mult }.  visual_mult is
## in the same units the authored track uses (about solar_radii × 16/215), so the drawn disc and
## the physical radius stay in step.
static func appearance_at(age: float, mass_msun: float) -> Dictionary:
	var f: Fate = fate(mass_msun)
	if f == Fate.GIANT_THEN_CO_DWARF:
		var look: Dictionary = appearance_at_age(age)
		look["visual_mult"] = float(look["visual_mult"]) * radius_mult(mass_msun)
		return look
	var radius: float = radius_solar_at(age, mass_msun)
	var vis: float = radius * (16.0 / 215.0)
	if f == Fate.EXTINGUISHED:
		# Not a star: a dim, barely-warm body.  Drawn small and almost unlit.
		return {"color": Color(0.45, 0.20, 0.16), "visual_mult": vis, "emiss_mult": 0.06}
	if age >= RED_GIANT_AGE:
		# Helium white dwarf: small, hot, and fading.
		return {"color": Color(0.80, 0.88, 1.00), "visual_mult": vis, "emiss_mult": 0.40}
	# A lightened star still on the main sequence: cooler and redder the lighter it is.
	var t: float = clampf((clamp_mass(mass_msun) - HYDROGEN_FUSION_MIN_MSUN)
		/ (HELIUM_FUSION_MIN_MSUN - HYDROGEN_FUSION_MIN_MSUN), 0.0, 1.0)
	return {
		"color": Color(1.00, 0.55, 0.35).lerp(Color(1.00, 0.85, 0.62), t),
		"visual_mult": vis,
		"emiss_mult": lerpf(0.35, 0.80, t),
	}


## Appearance at a stellar age: { color, visual_mult, emiss_mult } for the rendered Sun.
static func appearance_at_age(age: float) -> Dictionary:
	var b: Array = _bracket(age)
	var lo: Array = b[0]
	var hi: Array = b[1]
	var t: float = float(b[2])
	return {
		"color":       (lo[1] as Color).lerp(hi[1] as Color, t),
		"visual_mult": lerpf(float(lo[2]), float(hi[2]), t),
		"emiss_mult":  lerpf(float(lo[3]), float(hi[3]), t),
	}
