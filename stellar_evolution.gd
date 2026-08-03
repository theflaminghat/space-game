class_name StellarEvolution
## Single-star evolution — simplified but physically grounded.  Given a star's zero-age
## main-sequence (ZAMS) mass in solar masses and its current age in years, it returns the
## evolutionary phase, luminosity (power output), and current mass at that instant, so a star
## actually marches main sequence → giant/supergiant → remnant across the game's deep-time span.
##
## The whole model keys off ONE parameter, ZAMS mass, via standard relations:
##   • main-sequence lifetime   t ≈ 10 Gyr · (M/M☉)^-2.5   (fuel ∝ M, burn rate ∝ L ∝ M^3.5)
##   • mass–luminosity          L(M)  (piecewise power law)
##   • which death a star dies  (red-dwarf fade / white dwarf / neutron star / black hole)
## Phase boundaries are expressed as multiples of t so the sequence stays self-consistent for
## any mass.  Not a stellar-structure code — it's a believable timeline, not an isochrone fit.

const M_SUN_KG: float = 1.989e30      # one solar mass in kilograms
const L_SUN_W:  float = 3.828e26      # one solar luminosity in watts

## Main-sequence lifetime in years.  t ∝ M / L ≈ 1e10 · (M/M☉)^-2.5.
static func ms_lifetime(mass: float) -> float:
	return 1.0e10 * pow(maxf(mass, 0.05), -2.5)

## Main-sequence luminosity in solar luminosities, from the mass–luminosity relation.
static func ms_luminosity(mass: float) -> float:
	var m: float = maxf(mass, 0.05)
	if m < 0.43:
		return 0.23 * pow(m, 2.3)
	elif m < 2.0:
		return pow(m, 4.0)
	elif m < 55.0:
		return 1.4 * pow(m, 3.5)
	return 32000.0 * m

## Total baryonic mass a civilisation could ever lift from a star, in kilograms — its ZAMS mass.
static func total_usable_mass_kg(mass: float) -> float:
	return maxf(mass, 0.0) * M_SUN_KG

## Compact-remnant mass in solar masses (rough initial–final mass relation).
static func remnant_mass(mass: float) -> float:
	if mass < 0.5:
		return maxf(mass, 0.08)          # helium white dwarf (~its own small mass)
	elif mass < 8.0:
		return clampf(0.4 + 0.1 * mass, 0.5, 1.35)   # carbon/oxygen white dwarf
	elif mass < 20.0:
		return 1.4                       # neutron star (~Chandrasekhar mass)
	return maxf(3.0, mass * 0.15)        # stellar-mass black hole

## The name of the compact remnant this ZAMS mass ends its life as.
static func remnant_kind(mass: float) -> String:
	if mass < 8.0:
		return "White dwarf"
	elif mass < 20.0:
		return "Neutron star"
	return "Black hole"

## Full state of the star at `age` years:
##   { phase, lum_lsun, lum_w, mass_msun (current), color, remnant (bool), ms_life (yr) }.
## `ms_color` is the star's catalogue colour, reused for supergiants so a red supergiant stays
## red and a blue one stays blue (their spectral type already encodes it).
static func state(mass: float, age: float, ms_color: Color) -> Dictionary:
	var t: float = ms_lifetime(mass)
	var base_l: float = ms_luminosity(mass)
	var phase: String = "Main sequence"
	var lum: float = base_l
	var cur_mass: float = mass
	var color: Color = ms_color
	var remnant: bool = false

	if mass < 0.5:
		# Red dwarf: fully convective, burns nearly all its hydrogen — a main-sequence life of
		# hundreds of billions to trillions of years, then it fades straight to a helium white
		# dwarf with no giant phase at all.
		if age < t:
			lum = base_l * lerpf(1.0, 3.0, clampf(age / t, 0.0, 1.0))   # slowly brightens
		else:
			phase = "White dwarf"
			cur_mass = remnant_mass(mass)
			color = Color(0.85, 0.9, 1.0)
			lum = _wd_luminosity(age - t)
			remnant = true
	elif mass < 8.0:
		# Sun-like to intermediate: main sequence → subgiant → red giant → helium (horizontal
		# branch) → asymptotic giant → planetary nebula → white dwarf.
		var t_sub: float = t * 1.05
		var t_rgb: float = t * 1.15
		var t_hb:  float = t * 1.22
		var t_agb: float = t * 1.27
		var t_pn:  float = t_agb + 1.0e5      # the planetary nebula is astronomically fleeting
		if age < t:
			lum = base_l * lerpf(0.7, 1.6, clampf(age / t, 0.0, 1.0))   # ~2× over its life
		elif age < t_sub:
			phase = "Subgiant"
			lum = base_l * lerpf(1.6, 3.0, _frac(age, t, t_sub))
			color = Color(1.0, 0.9, 0.7)
		elif age < t_rgb:
			phase = "Red giant"
			lum = lerpf(3.0 * base_l, maxf(1000.0, 500.0 * mass), _frac(age, t_sub, t_rgb))
			color = Color(1.0, 0.55, 0.35)
		elif age < t_hb:
			phase = "Horizontal branch"     # steady helium-core burning
			lum = maxf(40.0, 30.0 * mass)
			color = Color(1.0, 0.85, 0.55)
		elif age < t_agb:
			phase = "Asymptotic giant"
			lum = lerpf(maxf(40.0, 30.0 * mass), maxf(3000.0, 1500.0 * mass), _frac(age, t_hb, t_agb))
			color = Color(1.0, 0.5, 0.3)
			cur_mass = lerpf(mass, remnant_mass(mass), _frac(age, t_hb, t_agb))   # heavy mass loss
		elif age < t_pn:
			phase = "Planetary nebula"
			lum = maxf(2000.0, 1000.0 * mass)
			color = Color(0.7, 0.9, 1.0)
			cur_mass = remnant_mass(mass)
		else:
			phase = "White dwarf"
			cur_mass = remnant_mass(mass)
			color = Color(0.85, 0.9, 1.0)
			lum = _wd_luminosity(age - t_pn)
			remnant = true
	else:
		# Massive: main sequence → supergiant → core-collapse supernova → neutron star or black
		# hole.  Everything happens fast — the whole life is a few to tens of millions of years.
		var t_sg: float = t * 1.10
		if age < t:
			lum = base_l
		elif age < t_sg:
			phase = "Supergiant"
			lum = base_l * lerpf(1.0, 2.0, _frac(age, t, t_sg))
			color = ms_color                # keep red/blue supergiant colour from spectral type
		else:
			# Post-supernova compact remnant.
			cur_mass = remnant_mass(mass)
			remnant = true
			if mass < 20.0:
				phase = "Neutron star"
				color = Color(0.85, 0.9, 1.0)
				lum = _wd_luminosity(age - t_sg) * 0.1
			else:
				phase = "Black hole"
				color = Color(0.12, 0.10, 0.16)
				lum = 0.0

	return {
		"phase": phase, "lum_lsun": lum, "lum_w": lum * L_SUN_W,
		"mass_msun": cur_mass, "color": color, "remnant": remnant, "ms_life": t,
	}

## Convenience: just the power output in watts at a given age.
static func luminosity_w(mass: float, age: float) -> float:
	return float(state(mass, age, Color.WHITE)["lum_w"])

## Linear 0→1 progress of `x` through the interval [a, b].
static func _frac(x: float, a: float, b: float) -> float:
	return clampf((x - a) / maxf(b - a, 1.0), 0.0, 1.0)

## White-dwarf / neutron-star cooling: luminosity falls off steeply as residual heat radiates
## away.  Bright (~0.1 L☉) at formation, fading below a millionth of the Sun over ~10 Gyr.
static func _wd_luminosity(age_since: float) -> float:
	var a: float = maxf(age_since, 1.0e5)
	return clampf(0.1 * pow(a / 1.0e7, -1.3), 1.0e-6, 0.1)
