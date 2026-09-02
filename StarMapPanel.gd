extends Control
class_name StarMapPanel

## A 3D map of nearby stars centred on the Sun, projected orthographically to 2D.
## Drag the mouse to rotate the view about the Sun, scroll to zoom, and click a star
## to select it.  Star positions are real (equatorial cartesian, in light-years).

## Emitted when the player clicks a star (or empty space → "").
signal star_selected(star_name: String)
## Emitted when the player commits an interstellar colony mission to a star at a chosen
## max Lorentz factor γ (cruise speed) and max acceleration (m/s²).  Game validates
## energy + launches.
signal colonize_requested(star_name: String, gamma_max: float, accel: float)
## Fire the orbital laser at a star system (a light-speed white pulse crosses to it).
## `power` is the energy multiplier the player dialled in (≥1).
signal laser_requested(star_name: String, power: float)
## Launch `count` von Neumann berserker seeds at a star system, at a chosen max γ / acceleration
## (same flight model as a colony ship).
signal berserker_requested(star_name: String, gamma_max: float, accel: float, count: int)
## Fire `count` relativistic kinetic missiles at a star system, at a chosen max γ / acceleration.
signal missile_requested(star_name: String, gamma_max: float, accel: float, count: int)
## Send a lightweight recon probe to a star at a chosen max γ / acceleration (like a colony
## ship, but it gathers full intel on arrival instead of settling).
signal probe_requested(star_name: String, gamma_max: float, accel: float)
## Send a crafted von Neumann Probe to seed a star.  Unlike a colony ship this one replicates
## on arrival and keeps going, so it is a decision about the whole galaxy, not one system.
signal vn_probe_requested(star_name: String, gamma_max: float, accel: float,
		mission: String, doctrine: String)
## Transmit a diplomatic message to a detected alien system.
## kind ∈ {"contact", "ally", "trade", "war"}.
signal message_requested(star_name: String, kind: String)

## Laser cost is a FLAT base energy (independent of distance) — scaled only by the power
## multiplier the player dials in.  Shared with Game for the cost readout.
const LASER_BASE_ENERGY: float = 1.0e9
## Berserker swarm cruise speed (fraction of c) — slow, but self-replicating on arrival.
const BERSERKER_BETA: float = 0.3

static func laser_energy(_dist_ly: float) -> float:
	return LASER_BASE_ENERGY

# ── Relativistic flight model (shared with Game so cost/time match what's shown) ──
# A colony ship accelerates at its chosen max acceleration `a` up to its max speed β,
# coasts, then decelerates to arrive at rest.  Over short interstellar hops a low
# acceleration may run out of distance before reaching β — then it peaks lower.  The
# energy is the ship's relativistic kinetic energy, paid twice (speed up + slow down).
const C_MS: float    = 2.998e8      # m/s
const LY_M: float    = 9.4607e15    # metres per light-year
const YEAR_S: float  = 3.1557e7     # seconds per year
## Speed is parameterised by the Lorentz factor γ (not β) for precision near c.  The cruise
## speed is capped at 99.99% c (γ ≈ 70.71) — the top of the speed slider.
const MAX_BETA:  float = 0.9999
const MAX_GAMMA: float = 70.7127   # 1 / sqrt(1 − 0.9999²)
## Standard colony-ship rest mass (kg) and the factor converting real joules to the
## game's energy units — both tuned so a near-c dash needs a built-out grid's reserves.
const SHIP_MASS: float           = 2.0e7
const ENERGY_GAME_PER_JOULE: float = 5.0e-17
## Rest-mass fractions (vs a colony ship) of the craft that share the colony flight model,
## so their relativistic-KE energy cost scales with how heavy they are.
const MISSILE_MASS_FRAC:   float = 0.15
const BERSERKER_MASS_FRAC: float = 0.02
const PROBE_MASS_FRAC:     float = 0.004
## A colony seed is heavier than a survey probe — it has to carry a factory.
const VN_PROBE_MASS_FRAC:  float = 0.03

## Relativistic launch-energy for a craft of the given mass fraction, via the shared flight
## model — same speed/accel logic as a colony ship, just scaled by rest mass.
static func projectile_energy(dist_ly: float, gamma_max: float, accel: float, mass_frac: float) -> float:
	return float(plan_flight(dist_ly, gamma_max, accel)["energy"]) * mass_frac

## β (fraction of c) for a Lorentz factor γ.  Saturates to 1.0 in float for huge γ.
static func beta_from_gamma(g: float) -> float:
	return sqrt(maxf(1.0 - 1.0 / (g * g), 0.0))

## "% c" speed string for a Lorentz factor γ (shared with Game for launch/impact notices).
static func fmt_beta(g: float) -> String:
	return "%.2f%% c" % (beta_from_gamma(g) * 100.0)

## Plan a flight of `dist_ly` light-years with max Lorentz factor γ (cruise speed) and
## max acceleration `a` (m/s²): accelerate to γ, coast, decelerate to rest.  Returns the
## game-energy required, Sol-frame travel time (years), the peak β/γ actually reached,
## and whether the requested γ was hit (short hops at low accel fall short).
static func plan_flight(dist_ly: float, gamma_max: float, accel: float) -> Dictionary:
	var dist_m: float = maxf(dist_ly, 1.0e-4) * LY_M
	var a: float = maxf(accel, 1.0e-4)
	var gv: float = clampf(gamma_max, 1.0001, MAX_GAMMA)
	# Relativistic distance to reach γ from rest at constant proper accel: (c²/a)(γ−1).
	var d_accel: float = (C_MS * C_MS / a) * (gv - 1.0)
	var reaches: bool = (2.0 * d_accel) <= dist_m
	var g_peak: float
	var coast_m: float = 0.0
	if reaches:
		g_peak = gv
		coast_m = dist_m - 2.0 * d_accel
	else:
		# Distance-limited: accelerate over half the trip, decelerate over the other.
		g_peak = 1.0 + a * (dist_m * 0.5) / (C_MS * C_MS)
	var b_peak: float = beta_from_gamma(g_peak)
	# Energy is the drive's rating for the COMMANDED cruise γ (relativistic KE for the burn
	# plus the matching deceleration), so it scales smoothly with the speed slider across its
	# whole range.  Using g_peak instead made the cost plateau the moment a short/low-accel hop
	# became range-limited — the "energy stops changing near 60% c" behaviour.  Reachability
	# only affects the actual peak reached and the arrival time (see "reaches" below).
	var joules: float = 2.0 * (gv - 1.0) * SHIP_MASS * C_MS * C_MS
	var energy: float = joules * ENERGY_GAME_PER_JOULE
	# Coordinate-frame time: each constant-accel leg takes (c/a)·γ·β; plus any coast.
	var t_leg: float = (C_MS / a) * g_peak * b_peak           # one accel/decel leg
	var d_leg: float = d_accel if reaches else dist_m * 0.5   # distance of one leg
	var t_coast: float = coast_m / (b_peak * C_MS) if (coast_m > 0.0 and b_peak > 0.0) else 0.0
	var t: float = 2.0 * t_leg + t_coast
	return {
		"energy":     energy,
		"years":      t / YEAR_S,
		"peak_beta":  b_peak,
		"peak_gamma": g_peak,
		"reaches":    reaches,
		# Fractions of the total trip the accel leg occupies, for an accel→coast→decel
		# position profile (so the ship visibly speeds up then slows to arrive at rest).
		"accel_time_frac": (t_leg / t) if t > 0.0 else 0.5,
		"accel_dist_frac": (d_leg / dist_m) if dist_m > 0.0 else 0.5,
	}

## Distance fraction (0..1) covered at time fraction `tf` for a symmetric accel→coast→
## decel profile — quadratic ramps at each end (slowing into the target), linear coast.
static func flight_progress(tf: float, accel_time_frac: float, accel_dist_frac: float) -> float:
	var tfc := clampf(tf, 0.0, 1.0)
	var ta := clampf(accel_time_frac, 0.0, 0.5)
	var fa := clampf(accel_dist_frac, 0.0, 0.5)
	if ta <= 0.0:
		return tfc
	if tfc <= ta:
		return fa * (tfc / ta) * (tfc / ta)                       # accelerating
	if tfc >= 1.0 - ta:
		var r := (1.0 - tfc) / ta
		return 1.0 - fa * r * r                                   # decelerating into target
	# Coasting at constant speed.
	var span_t := 1.0 - 2.0 * ta
	return fa + (1.0 - 2.0 * fa) * ((tfc - ta) / span_t) if span_t > 0.0 else 0.5

# ── Nearby stars within ~20 ly (real coordinates, light-years, Sun at origin) ──────
const STARS: Array = [
	{"name": "Proxima Centauri", "pos": Vector3(-1.55, -1.18, -3.77), "dist": 4.25, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.122, "age": 4.85},
	{"name": "Alpha Centauri A", "pos": Vector3(-1.63, -1.36, -3.81), "dist": 4.37, "spectral": "G", "color": Color(1.0, 0.93, 0.66), "mass": 1.079, "age": 5.3},
	{"name": "Alpha Centauri B", "pos": Vector3(-1.63, -1.36, -3.81), "dist": 4.37, "spectral": "K", "color": Color(1.0, 0.8, 0.55), "mass": 0.909, "age": 5.3},
	{"name": "Barnard's Star", "pos": Vector3(-0.06, -5.94, 0.49), "dist": 5.96, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.144, "age": 10},
	{"name": "Wolf 359", "pos": Vector3(-7.50, 2.13, 0.96), "dist": 7.86, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.09, "age": 0.5},
	{"name": "Lalande 21185", "pos": Vector3(-6.52, 1.65, 4.88), "dist": 8.31, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.39, "age": 7},
	{"name": "Sirius", "pos": Vector3(-1.62, 8.13, -2.49), "dist": 8.66, "spectral": "A", "color": Color(0.82, 0.88, 1.0), "mass": 2.063, "age": 0.24},
	{"name": "Luyten 726-8", "pos": Vector3(7.54, 3.48, -2.69), "dist": 8.73, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.1, "age": 5},
	{"name": "Ross 154", "pos": Vector3(1.91, -8.66, -3.92), "dist": 9.69, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.17, "age": 0.9},
	{"name": "Ross 248", "pos": Vector3(7.37, -0.58, 7.18), "dist": 10.30, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.136, "age": 10},
	{"name": "Epsilon Eridani", "pos": Vector3(6.18, 8.28, -1.72), "dist": 10.47, "spectral": "K", "color": Color(1.0, 0.8, 0.55), "mass": 0.82, "age": 0.6},
	{"name": "Lacaille 9352", "pos": Vector3(8.46, -2.04, -6.29), "dist": 10.74, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.49, "age": 5},
	{"name": "Ross 128", "pos": Vector3(-10.98, 0.59, 0.15), "dist": 11.00, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.168, "age": 9.4},
	{"name": "61 Cygni", "pos": Vector3(6.47, -6.09, 7.14), "dist": 11.40, "spectral": "K", "color": Color(1.0, 0.8, 0.55), "mass": 0.7, "age": 6},
	{"name": "Procyon", "pos": Vector3(-4.79, 10.36, 1.04), "dist": 11.46, "spectral": "F", "color": Color(1.0, 1.0, 0.94), "mass": 1.5, "age": 1.9},
	{"name": "Epsilon Indi", "pos": Vector3(5.68, -3.17, -9.93), "dist": 11.87, "spectral": "K", "color": Color(1.0, 0.8, 0.55), "mass": 0.75, "age": 4},
	{"name": "Tau Ceti", "pos": Vector3(10.29, 5.02, -3.27), "dist": 11.91, "spectral": "G", "color": Color(1.0, 0.93, 0.66), "mass": 0.783, "age": 5.8},
	{"name": "Gliese 581", "pos": Vector3(-13.03, -15.45, -2.74), "dist": 20.40, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.31, "age": 8},
	# ── More nearby red dwarfs ────────────────────────────────────────────────
	{"name": "40 Eridani", "pos": Vector3(7.14, 14.53, -2.18), "dist": 16.34, "spectral": "K", "color": Color(1.0, 0.80, 0.55), "mass": 0.78, "age": 5.6},
	{"name": "Kapteyn's Star", "pos": Vector3(1.90, 8.87, -9.07), "dist": 12.83, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.28, "age": 11.5},
	{"name": "Lacaille 8760", "pos": Vector3(7.44, -6.80, -8.13), "dist": 12.95, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.6, "age": 5},
	{"name": "Kruger 60", "pos": Vector3(6.47, -2.75, 11.11), "dist": 13.15, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.27, "age": 5},
	# ── Local neighbourhood — more real stars within ~20 ly ───────────────────
	{"name": "Groombridge 34", "pos": Vector3(8.33, 0.67, 8.07), "dist": 11.62, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.38, "age": 8},
	{"name": "EZ Aquarii", "pos": Vector3(10.19, -3.78, -2.97), "dist": 11.27, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.11, "age": 5},
	{"name": "Struve 2398", "pos": Vector3(1.08, -5.71, 9.91), "dist": 11.49, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.33, "age": 5},
	{"name": "DX Cancri", "pos": Vector3(-6.34, 8.28, 5.26), "dist": 11.68, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.09, "age": 5},
	{"name": "YZ Ceti", "pos": Vector3(11.02, 3.61, -3.54), "dist": 12.13, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.13, "age": 3.8},
	{"name": "Luyten's Star", "pos": Vector3(-4.58, 11.42, 1.13), "dist": 12.36, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.26, "age": 9},
	{"name": "Teegarden's Star", "pos": Vector3(8.71, 8.20, 3.63), "dist": 12.50, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.09, "age": 8},
	{"name": "Gliese 1061", "pos": Vector3(5.05, 6.95, -8.44), "dist": 12.04, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.12, "age": 7},
	{"name": "SCR 1845-6357", "pos": Vector3(1.08, -5.41, -11.29), "dist": 12.57, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.07, "age": 5},
	{"name": "Van Maanen's Star", "pos": Vector3(13.69, 2.98, 1.32), "dist": 14.07, "spectral": "D", "color": Color(0.90, 0.95, 1.0), "mass": 2.6, "age": 4.493},
	{"name": "Gliese 1", "pos": Vector3(11.29, 0.27, -8.61), "dist": 14.20, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.45, "age": 10},
	{"name": "Wolf 1061", "pos": Vector3(-5.23, -12.67, -3.08), "dist": 14.05, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.29, "age": 5},
	{"name": "Wolf 424", "pos": Vector3(-13.98, -2.05, 2.24), "dist": 14.31, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.14, "age": 0.3},
	{"name": "Gliese 876", "pos": Vector3(14.15, -4.24, -3.75), "dist": 15.24, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.37, "age": 5},
	{"name": "AD Leonis", "pos": Vector3(-13.79, 6.46, 5.50), "dist": 16.19, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.42, "age": 0.3},
	{"name": "Gliese 832", "pos": Vector3(8.51, -6.32, -12.20), "dist": 16.16, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.45, "age": 5},
	{"name": "Gliese 570", "pos": Vector3(-12.83, -12.55, -7.04), "dist": 19.28, "spectral": "K", "color": Color(1.0, 0.8, 0.55), "mass": 0.8, "age": 3},
	{"name": "82 Eridani", "pos": Vector3(9.26, 11.03, -13.46), "dist": 19.71, "spectral": "G", "color": Color(1.0, 0.93, 0.66), "mass": 0.85, "age": 6},
	{"name": "Delta Pavonis", "pos": Vector3(4.28, -6.81, -18.22), "dist": 19.92, "spectral": "G", "color": Color(1.0, 0.93, 0.66), "mass": 0.99, "age": 7},
	# ── Notable exoplanet host systems (famous colonisation targets) ──────────
	{"name": "Gliese 667 C", "pos": Vector3(-3.45, -19.04, -13.54), "dist": 23.62, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.33, "age": 5},
	{"name": "TRAPPIST-1", "pos": Vector3(39.40, -9.37, -3.57), "dist": 40.66, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.089, "age": 7.6},
	{"name": "LHS 1140", "pos": Vector3(46.30, 9.19, -12.89), "dist": 48.93, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 0.18, "age": 5},
	# ── Bright naked-eye stars (tens to hundreds of ly) ───────────────────────
	{"name": "Altair", "pos": Vector3(7.68, -14.64, 2.58), "dist": 16.73, "spectral": "A", "color": Color(0.85, 0.90, 1.0), "mass": 1.79, "age": 1},
	{"name": "Vega", "pos": Vector3(3.13, -19.27, 15.68), "dist": 25.04, "spectral": "A", "color": Color(0.85, 0.90, 1.0), "mass": 2.14, "age": 0.45},
	{"name": "Fomalhaut", "pos": Vector3(21.04, -5.87, -12.42), "dist": 25.13, "spectral": "A", "color": Color(0.85, 0.90, 1.0), "mass": 1.92, "age": 0.44},
	{"name": "Pollux", "pos": Vector3(-13.23, 26.73, 15.87), "dist": 33.78, "spectral": "K", "color": Color(1.0, 0.80, 0.55), "mass": 1.91, "age": 2.202},
	{"name": "Arcturus", "pos": Vector3(-28.73, -19.32, 12.05), "dist": 36.66, "spectral": "K", "color": Color(1.0, 0.80, 0.55), "mass": 1.08, "age": 9.157},
	{"name": "Capella", "pos": Vector3(5.60, 29.29, 30.87), "dist": 42.92, "spectral": "G", "color": Color(1.0, 0.93, 0.66), "mass": 2.57, "age": 1.048},
	{"name": "Castor", "pos": Vector3(-17.37, 39.67, 26.94), "dist": 51.0, "spectral": "A", "color": Color(0.85, 0.90, 1.0), "mass": 2.2, "age": 0.37},
	{"name": "Aldebaran", "pos": Vector3(22.43, 58.38, 18.54), "dist": 65.23, "spectral": "K", "color": Color(1.0, 0.80, 0.55), "mass": 1.16, "age": 7.659},
	{"name": "Regulus", "pos": Vector3(-68.55, 36.31, 16.44), "dist": 79.3, "spectral": "B", "color": Color(0.80, 0.87, 1.0), "mass": 3.8, "age": 0.25},
	{"name": "Mizar", "pos": Vector3(-44.48, -17.06, 67.85), "dist": 82.9, "spectral": "A", "color": Color(0.85, 0.90, 1.0), "mass": 2.2, "age": 0.37},
	{"name": "Spica", "pos": Vector3(-228.52, -89.09, -48.39), "dist": 250.0, "spectral": "B", "color": Color(0.80, 0.87, 1.0), "mass": 11.4, "age": 0.0125},
	{"name": "Polaris", "pos": Vector3(4.39, 3.42, 432.96), "dist": 433.0, "spectral": "F", "color": Color(1.0, 1.0, 0.94), "mass": 5.4, "age": 0.1638},
	{"name": "Betelgeuse", "pos": Vector3(11.45, 543.31, 70.65), "dist": 548.0, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 18, "age": 0.007857},
	{"name": "Antares", "pos": Vector3(-189.65, -454.53, -244.82), "dist": 550.0, "spectral": "M", "color": Color(1.0, 0.62, 0.46), "mass": 12, "age": 0.02165},
	{"name": "Rigel", "pos": Vector3(167.74, 834.51, -122.69), "dist": 860.0, "spectral": "B", "color": Color(0.80, 0.87, 1.0), "mass": 21, "age": 0.005196},
	{"name": "Deneb", "pos": Vector3(1191.51, -1402.13, 1858.11), "dist": 2615.0, "spectral": "A", "color": Color(0.85, 0.90, 1.0), "mass": 19, "age": 0.006673},
]

# ── Procedurally-generated stars distributed across the galaxy ─────────────────
# In addition to the real catalogue, a large set of invented stars is seeded across the whole
# galactic disk + bulge from a fixed seed.  They're named procedural1, procedural2, … and are
# full-fledged stars — selectable, colonisable, and eligible to host alien civilisations —
# sharing the STARS dictionary shape.  But only those within the player's OBSERVATION RANGE (a
# radius from Sol that grows with telescopes/colonies) are resolvable; the rest stay hidden in
# the anonymous field until the frontier reaches them.  Seed-deterministic + static, so the set
# is identical every session and consistent between the star map and Game.
const PROC_STAR_COUNT:   int   = 10000
const PROC_SEED:         int   = 0x57A6_5EED

# ── Star formation ────────────────────────────────────────────────────────────
## The galaxy is not a fixed cast.  Stars die — StellarEvolution already takes them off the
## main sequence and leaves white dwarfs, neutron stars and black holes behind — and until now
## nothing replaced them, so the sky could only ever get emptier.
##
## New stars are NOT generated at runtime.  The whole future population is drawn once from the
## same seed with a BIRTH YEAR attached, and each one joins the catalogue when the clock reaches
## it.  That keeps the galaxy deterministic (the same run always sees the same sky), keeps
## generation off the frame budget entirely, and means a save restores the right stars simply by
## restoring the year.
const FUTURE_STARS:      int   = 4000
## Star formation ends here.  The Milky Way's gas reservoir is finite and is not replenished
## faster than it is locked into remnants; by ~1e14 years there is nothing left to collapse and
## the last stars ever to exist have already been born.
const STAR_FORMATION_END_YEAR: float = 1.0e14
## First year a newly-formed star can appear.  Birth years are drawn log-uniformly between the
## two bounds and then skewed early (BIRTH_SKEW > 1), so formation is fastest at the start and
## thins out across the decades rather than arriving all at once at the end.
const STAR_FORMATION_START_YEAR: float = 1.0e6
const BIRTH_SKEW:        float = 1.6
const PROC_BASE_RANGE_LY: float = 4000.0   # naked-eye / early-telescope reach (always visible)
## [spectral, weight, base-mass M☉, colour] — weights skew heavily toward M dwarfs, as reality does.
const PROC_TYPES: Array = [
	["M", 0.74, 0.25, Color(1.0, 0.62, 0.46)],
	["K", 0.12, 0.70, Color(1.0, 0.80, 0.55)],
	["G", 0.08, 1.00, Color(1.0, 0.93, 0.66)],
	["F", 0.04, 1.40, Color(1.0, 1.00, 0.94)],
	["A", 0.02, 2.00, Color(0.85, 0.90, 1.00)],
]

## Static catalogue: the full galaxy-wide procedural set (built once) and the currently-visible
## list = real STARS + procedural stars within the observation range (rebuilt when it grows).
static var _proc_stars:   Array = []
static var _all_stars:    Array = []
static var _all_full:     Array = []   # real + EVERY procedural star, ignoring range (debug view)
static var _obs_range_ly: float = PROC_BASE_RANGE_LY
## Stars not yet born, sorted by birth year, plus how many of them have joined the catalogue.
static var _future:       Array = []
static var _born_count:   int = 0
static var _born_year:    float = 0.0
static var _stars_dirty:  bool  = true

## The complete star catalogue — real STARS + ALL procedural stars, regardless of observation
## range.  Used by the galaxy debug map to render the whole seed-generated distribution.
static func all_stars_full() -> Array:
	if _all_full.is_empty():
		if _proc_stars.is_empty():
			_proc_stars = _generate_procedural_stars()
		_all_full = STARS.duplicate()
		_all_full.append_array(_proc_stars)
	return _all_full

## The stars the player can currently resolve = real STARS + procedural stars inside the
## observation range.  Cached; rebuilt only when the range expands.
static func all_stars() -> Array:
	if _stars_dirty or _all_stars.is_empty():
		if _proc_stars.is_empty():
			_proc_stars = _generate_procedural_stars()
		_all_stars = STARS.duplicate()
		for s: Dictionary in _proc_stars:
			if float(s["dist"]) <= _obs_range_ly:
				_all_stars.append(s)
		_stars_dirty = false
	return _all_stars

## Expand how far the player can resolve individual stars (ly from Sol).  MONOTONIC — a star,
## once in range, stays visible — so call it as telescopes/colonies push the frontier outward.
static func set_observation_range(ly: float) -> void:
	if ly > _obs_range_ly + 0.5:
		_obs_range_ly = ly
		_stars_dirty = true

static func observation_range() -> float:
	return _obs_range_ly

## Seed-deterministic invented stars across the galactic disk + bulge (same distribution the
## field uses), each a full star dict named "proceduralN".
## The stars that do not exist yet.  Same generator as the standing population, but each entry
## carries the year it forms; `age` is 0 at birth because it is born then.
static func _generate_future_stars() -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = PROC_SEED ^ 0x5748_0000
	for i in range(FUTURE_STARS):
		# Births are spread LOGARITHMICALLY across the decades, not linearly across the span:
		# a linear draw over 1e6..1e14 puts almost everything in the final decade, which is the
		# opposite of how star formation behaves.  The skew then weights the early decades, so
		# the rate visibly declines — half the remaining stars are born in the first few
		# hundred million years and the last ones trickle in over the following trillions.
		var u: float = pow(rng.randf(), BIRTH_SKEW)
		var born: float = STAR_FORMATION_START_YEAR * pow(STAR_FORMATION_END_YEAR / STAR_FORMATION_START_YEAR, u)
		var st: Dictionary = _proc_star_at(rng, "newborn%d" % (i + 1))
		if st.is_empty():
			continue
		# _star_age_now computes age*1e9 + (year - STELLAR_EPOCH), so to make a star exactly
		# (year - born) old we store a NEGATIVE seed age.  It reads as "not yet formed" until
		# the clock passes its birth year, then ages from zero like any other star.
		st["age"] = (float(STELLAR_EPOCH) - born) / 1.0e9
		st["born"] = born
		out.append(st)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["born"]) < float(b["born"]))
	return out

## Advance the catalogue to `y`, admitting every star whose formation year has arrived.  Cheap:
## the pool is sorted, so this is a pointer walk that almost always does nothing.
static func advance_star_formation(y: float) -> void:
	if _future.is_empty():
		_future = _generate_future_stars()
	_born_year = y
	var added: bool = false
	while _born_count < _future.size() and float(_future[_born_count]["born"]) <= y:
		_proc_stars.append(_future[_born_count])
		_born_count += 1
		added = true
	if added:
		_all_full.clear()      # force the catalogue views to rebuild with the new stars
		_all_stars.clear()
		_stars_dirty = true

## How many stars have yet to form, and when the next one does — for the galaxy readout.
static func pending_star_formation() -> Dictionary:
	if _future.is_empty():
		_future = _generate_future_stars()
	return {
		"pending": _future.size() - _born_count,
		"next_year": float(_future[_born_count]["born"]) if _born_count < _future.size() else -1.0,
		"ended": _born_count >= _future.size() or _born_year >= STAR_FORMATION_END_YEAR,
	}

## One procedurally-placed star (disk or bulge), or {} if the draw fell outside the disk.
static func _proc_star_at(rng: RandomNumberGenerator, star_name: String) -> Dictionary:
	var basis: Array = _galactic_basis()
	var gx: Vector3 = basis[0]
	var gy: Vector3 = basis[1]
	var gz: Vector3 = basis[2]
	var gc: Vector3 = gx * SOL_GC_LY
	var pos: Vector3
	if rng.randf() < BULGE_FRAC:
		pos = gc + _proc_rand_unit(rng) * absf(rng.randfn(0.0, BULGE_LY * 0.6))
	else:
		var radius: float = -DISK_SCALE_LY * (log(maxf(rng.randf(), 1e-6)) + log(maxf(rng.randf(), 1e-6)))
		if radius > DISK_MAX_LY:
			return {}
		var phi: float = rng.randf() * TAU
		var z: float = rng.randfn(0.0, DISK_H_LY)
		pos = gc + (gx * (radius * cos(phi))) + (gy * (radius * sin(phi))) + (gz * z)
	var dist: float = pos.length()
	if dist < 1.0:
		return {}
	var t: Array = _proc_pick_type(rng.randf())
	return {
		"name": star_name, "pos": pos, "dist": dist,
		"spectral": str(t[0]), "color": t[3],
		"mass": float(t[2]) * rng.randf_range(0.7, 1.3),
		"age": rng.randf_range(0.4, 9.0),
		"procedural": true,
	}

static func _generate_procedural_stars() -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = PROC_SEED
	var basis: Array = _galactic_basis()
	var gx: Vector3 = basis[0]
	var gy: Vector3 = basis[1]
	var gz: Vector3 = basis[2]
	var gc: Vector3 = gx * SOL_GC_LY
	var guard: int = 0
	while out.size() < PROC_STAR_COUNT and guard < PROC_STAR_COUNT * 6:
		guard += 1
		var pos: Vector3
		if rng.randf() < BULGE_FRAC:
			pos = gc + _proc_rand_unit(rng) * absf(rng.randfn(0.0, BULGE_LY * 0.6))
		else:
			var radius: float = -DISK_SCALE_LY * (log(maxf(rng.randf(), 1e-6)) + log(maxf(rng.randf(), 1e-6)))
			if radius > DISK_MAX_LY:
				continue
			var phi: float = rng.randf() * TAU
			var z: float = rng.randfn(0.0, DISK_H_LY)
			pos = gc + (gx * (radius * cos(phi))) + (gy * (radius * sin(phi))) + (gz * z)
		var dist: float = pos.length()
		if dist < 1.0:
			continue   # essentially at Sol
		var t: Array = _proc_pick_type(rng.randf())
		out.append({
			"name":     "procedural%d" % (out.size() + 1),
			"pos":      pos,
			"dist":     dist,
			"spectral": str(t[0]),
			"color":    t[3],
			"mass":     float(t[2]) * rng.randf_range(0.7, 1.3),
			"age":      rng.randf_range(0.4, 9.0),
			"procedural": true,
		})
	return out

## Orthonormal galactic basis [gx→centre, gy→l=90, gz→pole] in the equatorial frame — a static
## copy of _build_galaxy's basis, so procedural stars can be distributed during static generation.
static func _galactic_basis() -> Array:
	var gx: Vector3 = _eq_dir(GC_RA_H, GC_DEC)
	var gz: Vector3 = _eq_dir(NGP_RA_H, NGP_DEC)
	gz = (gz - gx * gz.dot(gx)).normalized()
	var gy: Vector3 = gz.cross(gx).normalized()
	return [gx, gy, gz]

## Public galactic basis [gx→centre, gy→l=90, gz→pole] in the equatorial frame, so Game can
## tile its hex regions in the galactic plane rather than the tilted equatorial one.
static func galactic_basis() -> Array:
	return _galactic_basis()

static func _eq_dir(ra_h: float, dec_deg: float) -> Vector3:
	var ra: float = deg_to_rad(ra_h * 15.0)
	var dec: float = deg_to_rad(dec_deg)
	return Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec)).normalized()

## Relative stellar density (~0..3) of the disk+bulge model at a Sol-relative position (ly).  Used
## by Game to weight how many colonisable stars a statistical region cell represents, so the
## galaxy's aggregate colonisation follows the real disk/arm/bulge shape rather than filling voids.
static func galactic_density(pos: Vector3) -> float:
	var basis: Array = _galactic_basis()
	var gx: Vector3 = basis[0]
	var gy: Vector3 = basis[1]
	var gz: Vector3 = basis[2]
	var rel: Vector3 = pos - gx * SOL_GC_LY               # galactocentric
	var rp: float = Vector2(rel.dot(gx), rel.dot(gy)).length()   # in-plane radius
	var zz: float = rel.dot(gz)                                   # height above the plane
	if rp > DISK_MAX_LY:
		return 0.0
	var disk: float = exp(-rp / DISK_SCALE_LY) * exp(-absf(zz) / DISK_H_LY)
	var bulge: float = 2.0 * exp(-rel.length() / BULGE_LY)
	return clampf(disk + bulge, 0.0, 3.0)

## A uniformly-distributed unit direction (static so it's usable during static generation).
static func _proc_rand_unit(rng: RandomNumberGenerator) -> Vector3:
	var z: float = rng.randf_range(-1.0, 1.0)
	var t: float = rng.randf() * TAU
	var r: float = sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(r * cos(t), r * sin(t), z)

## Weighted pick from PROC_TYPES by a 0..1 roll.
static func _proc_pick_type(roll: float) -> Array:
	var total: float = 0.0
	for t: Array in PROC_TYPES:
		total += float(t[1])
	var r: float = roll * total
	var acc: float = 0.0
	for t: Array in PROC_TYPES:
		acc += float(t[1])
		if r <= acc:
			return t
	return PROC_TYPES[PROC_TYPES.size() - 1]

# ── Nearby galaxies (and the Milky Way's own centre) ───────────────────────────
# Stored as equatorial coordinates + distance; _build_galaxies() converts them to the
# same cartesian frame the stars use (x = d·cosδ·cosα, y = d·cosδ·sinα, z = d·sinδ,
# α = RA hours × 15°).  Distances in light-years.  They populate the map's outer
# decades — the first hint that "nearby" spans a hundred-million-fold range.
const GALAXIES: Array = [
	{"name": "Galactic Centre (Sgr A*)", "ra_h": 17.761, "dec_deg": -28.94, "dist": 2.6e4,  "kind": "core",   "color": Color(1.0, 0.85, 0.55)},
	{"name": "Large Magellanic Cloud",   "ra_h":  5.392, "dec_deg": -69.76, "dist": 1.63e5, "kind": "irr",    "color": Color(0.88, 0.92, 1.0)},
	{"name": "Small Magellanic Cloud",   "ra_h":  0.873, "dec_deg": -72.80, "dist": 2.0e5,  "kind": "irr",    "color": Color(0.88, 0.92, 1.0)},
	{"name": "Andromeda (M31)",          "ra_h":  0.712, "dec_deg":  41.27, "dist": 2.537e6,"kind": "spiral", "color": Color(0.80, 0.86, 1.0)},
	{"name": "Triangulum (M33)",         "ra_h":  1.564, "dec_deg":  30.66, "dist": 2.73e6, "kind": "spiral", "color": Color(0.80, 0.86, 1.0)},
	{"name": "Sculptor (NGC 253)",       "ra_h":  0.793, "dec_deg": -25.29, "dist": 1.14e7, "kind": "spiral", "color": Color(0.82, 0.88, 1.0)},
	{"name": "Bode's Galaxy (M81)",      "ra_h":  9.926, "dec_deg":  69.07, "dist": 1.18e7, "kind": "spiral", "color": Color(0.82, 0.88, 1.0)},
	{"name": "Centaurus A",              "ra_h": 13.424, "dec_deg": -43.02, "dist": 1.2e7,  "kind": "ell",    "color": Color(1.0, 0.90, 0.74)},
	{"name": "Pinwheel (M101)",          "ra_h": 14.053, "dec_deg":  54.35, "dist": 2.1e7,  "kind": "spiral", "color": Color(0.82, 0.88, 1.0)},
	{"name": "Whirlpool (M51)",          "ra_h": 13.498, "dec_deg":  47.20, "dist": 2.3e7,  "kind": "spiral", "color": Color(0.82, 0.88, 1.0)},
	{"name": "Sombrero (M104)",          "ra_h": 12.667, "dec_deg": -11.62, "dist": 2.93e7, "kind": "ell",    "color": Color(1.0, 0.90, 0.74)},
	{"name": "Virgo A (M87)",            "ra_h": 12.514, "dec_deg":  12.39, "dist": 5.35e7, "kind": "ell",    "color": Color(1.0, 0.90, 0.74)},
	# More Local Group + nearby galaxies
	{"name": "IC 10",                    "ra_h":  0.340, "dec_deg":  59.29, "dist": 2.2e6,  "kind": "irr",    "color": Color(0.88, 0.92, 1.0)},
	{"name": "Barnard's Galaxy (NGC 6822)", "ra_h": 19.750, "dec_deg": -14.80, "dist": 1.6e6, "kind": "irr", "color": Color(0.88, 0.92, 1.0)},
	{"name": "NGC 300",                  "ra_h":  0.915, "dec_deg": -37.68, "dist": 6.07e6, "kind": "spiral", "color": Color(0.82, 0.88, 1.0)},
	# Nearby bright galaxies (tens of Mly)
	{"name": "Southern Pinwheel (M83)",  "ra_h": 13.617, "dec_deg": -29.87, "dist": 1.5e7,  "kind": "spiral", "color": Color(0.82, 0.88, 1.0)},
	{"name": "Black Eye (M64)",          "ra_h": 12.945, "dec_deg":  21.68, "dist": 1.7e7,  "kind": "spiral", "color": Color(0.82, 0.88, 1.0)},
	{"name": "Cetus A (M77)",            "ra_h":  2.711, "dec_deg":  -0.01, "dist": 4.7e7,  "kind": "spiral", "color": Color(0.82, 0.88, 1.0)},
	{"name": "M49",                      "ra_h": 12.497, "dec_deg":   8.00, "dist": 5.6e7,  "kind": "ell",    "color": Color(1.0, 0.90, 0.74)},
	# Distant cluster + a quasar, far out toward the horizon
	{"name": "Coma Cluster (NGC 4889)",  "ra_h": 13.002, "dec_deg":  27.98, "dist": 3.21e8, "kind": "ell",    "color": Color(1.0, 0.88, 0.78)},
	{"name": "Quasar 3C 273",            "ra_h": 12.485, "dec_deg":   2.05, "dist": 2.4e9,  "kind": "quasar", "color": Color(0.70, 0.95, 1.0)},
]

# ── The Milky Way: procedural star field + named large-scale structure ─────────
# The galactic disk holds hundreds of billions of stars over ~100 000 ly — far too many to
# enumerate like the nearby-star catalogue.  Instead we SAMPLE it: a deterministic point cloud
# drawn from the real structure (exponential disk + central bulge + logarithmic spiral arms),
# so the map shows the galaxy as a field of faint stars filling the gap between the named stars
# (out to ~2 600 ly) and the extragalactic layer.  Seeded, so it's identical every session.
const GALAXY_SEED:    int   = 0x5EED_1A11
const FIELD_STARS:    int   = 1700
const FIELD_MIN_LY:   float = 1800.0    # cull points nearer than this (the named-star domain)
const SOL_GC_LY:      float = 26000.0   # Sun's galactocentric distance (~8 kpc)
const DISK_SCALE_LY:  float = 9000.0    # radial scale length of the exponential disk
const DISK_MAX_LY:    float = 60000.0   # visible disk edge
const DISK_H_LY:      float = 900.0     # disk scale height (thickness)
const BULGE_LY:       float = 3500.0    # central bulge scale radius
const BULGE_FRAC:     float = 0.16      # fraction of field stars in the bulge
const ARM_COUNT:      int   = 4
const ARM_PITCH_RAD:  float = 0.218     # ~12.5° spiral pitch angle
const ARM_WIDTH_RAD:  float = 0.55      # angular half-width of an arm's overdensity
# Galactic frame anchors (J2000): the galactic centre (Sgr A*) and the North Galactic Pole.
const GC_RA_H:   float = 17.7603
const GC_DEC:    float = -28.936
const NGP_RA_H:  float = 12.85730
const NGP_DEC:   float =  27.12825

## Named intra-galactic landmarks (clusters, nebulae) with real equatorial coords + distance —
## the mid-scale features that give the galaxy a sense of size between the nearby stars and the
## other galaxies.  kind ∈ {"cluster", "nebula"}.
const LANDMARKS_EQ: Array = [
	{"name": "Hyades",            "ra_h":  4.483, "dec_deg":  15.87, "dist":   153.0, "kind": "cluster", "color": Color(1.00, 0.95, 0.80)},
	{"name": "Pleiades (M45)",    "ra_h":  3.790, "dec_deg":  24.12, "dist":   444.0, "kind": "cluster", "color": Color(0.75, 0.85, 1.00)},
	{"name": "Beehive (M44)",     "ra_h":  8.670, "dec_deg":  19.67, "dist":   577.0, "kind": "cluster", "color": Color(0.90, 0.93, 1.00)},
	{"name": "Orion Nebula (M42)","ra_h":  5.588, "dec_deg":  -5.39, "dist":  1344.0, "kind": "nebula",  "color": Color(1.00, 0.60, 0.68)},
	{"name": "Lagoon Nebula (M8)","ra_h": 18.060, "dec_deg": -24.38, "dist":  4100.0, "kind": "nebula",  "color": Color(1.00, 0.55, 0.62)},
	{"name": "Rosette Nebula",    "ra_h":  6.538, "dec_deg":   4.95, "dist":  5200.0, "kind": "nebula",  "color": Color(1.00, 0.56, 0.62)},
	{"name": "Eagle Nebula (M16)","ra_h": 18.313, "dec_deg": -13.79, "dist":  7000.0, "kind": "nebula",  "color": Color(0.95, 0.60, 0.70)},
	{"name": "Double Cluster",    "ra_h":  2.330, "dec_deg":  57.14, "dist":  7500.0, "kind": "cluster", "color": Color(0.80, 0.87, 1.00)},
	{"name": "Carina Nebula",     "ra_h": 10.752, "dec_deg": -59.87, "dist":  8500.0, "kind": "nebula",  "color": Color(1.00, 0.60, 0.66)},
	{"name": "47 Tucanae",        "ra_h":  0.401, "dec_deg": -72.08, "dist": 13000.0, "kind": "cluster", "color": Color(1.00, 0.90, 0.78)},
	{"name": "Omega Centauri",    "ra_h": 13.446, "dec_deg": -47.48, "dist": 17000.0, "kind": "cluster", "color": Color(1.00, 0.90, 0.75)},
	{"name": "M13 (Hercules)",    "ra_h": 16.695, "dec_deg":  36.46, "dist": 22000.0, "kind": "cluster", "color": Color(1.00, 0.92, 0.80)},
]

const ROT_SENS:  float = 0.01    # radians of rotation per pixel dragged
const MIN_PITCH: float = -1.45   # ~ ±83° — stop short of gimbal flip at the poles
const MAX_PITCH: float =  1.45
const ZOOM_STEP: float = 1.12
const ZOOM_MIN:  float = 0.4
const ZOOM_MAX:  float = 80.0    # deep zoom needed: the scale spans ~10 decades of ly
const PICK_PX:   float = 16.0    # click tolerance for selecting a star
const FRAME_PICK_PX: float = 26.0   # right-click tolerance for landmark/galaxy reference frames
# Stars nearer than this always draw (the local catalogue); farther ones draw only when in the
# current zoom band — the perf gate that lets ~10 000 galaxy stars coexist with the neighbourhood.
const STAR_ALWAYS_LY: float = 3500.0
# Hard render cutoff: stars farther than this from the CURRENT REFERENCE FRAME are never drawn
# (unless selected/alien/colonised), so the outer galaxy doesn't clutter the map or cost draw
# time.  Measured from the frame origin, so recentring reveals a different bubble of stars.
const STAR_RENDER_MAX_LY: float = 1000.0

# ── Star clusters ─────────────────────────────────────────────────────────────
## Individual stars stop resolving past STAR_RENDER_MAX_LY, which used to leave the map simply
## empty out there.  These fill that shell: seed-generated open clusters scattered through the
## volume the player cannot see star-by-star, each a colonisable target in its own right.  You
## do not settle a star out here — you settle a cluster, and what you get is however many
## thousand suns came with it.
const CLUSTER_COUNT:   int   = 140
const CLUSTER_SEED:    int   = 0x0C1_5EED
const CLUSTER_MIN_LY:  float = 1100.0     # just past the individual-star horizon
const CLUSTER_MAX_LY:  float = 9000.0
## Stars a cluster holds — real open clusters run from a few hundred to a few thousand.
const CLUSTER_STARS_MIN: int = 250
const CLUSTER_STARS_MAX: int = 6000
const CLUSTER_PICK_PX: float = 16.0

static var _clusters: Array = []

## The generated cluster shell.  Deterministic from CLUSTER_SEED, so it is identical every
## session and both the map and Game agree on where everything is.
static func star_clusters() -> Array:
	if _clusters.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = CLUSTER_SEED
		for i in range(CLUSTER_COUNT):
			# Uniform in VOLUME rather than in radius, so the shell looks evenly populated
			# instead of crowding toward the inner edge.
			var lo: float = pow(CLUSTER_MIN_LY, 3.0)
			var hi: float = pow(CLUSTER_MAX_LY, 3.0)
			var d: float = pow(lo + rng.randf() * (hi - lo), 1.0 / 3.0)
			var dir: Vector3 = _proc_rand_unit(rng)
			var n_stars: int = CLUSTER_STARS_MIN + rng.randi() % (CLUSTER_STARS_MAX - CLUSTER_STARS_MIN)
			# Richer clusters read hotter/bluer; sparse ones dimmer.
			var t: float = float(n_stars - CLUSTER_STARS_MIN) / float(CLUSTER_STARS_MAX - CLUSTER_STARS_MIN)
			_clusters.append({
				"name":     "Cluster C-%03d" % (i + 1),
				"pos":      dir * d,
				"dist":     d,
				"stars":    n_stars,
				"is_cluster": true,
				"color":    Color(0.72, 0.80, 1.00).lerp(Color(1.00, 0.94, 0.82), 1.0 - t),
			})
	return _clusters
## Labels + drop-lines are gated on the object's distance from Sol relative to the
## current VIEW RADIUS (the distance the zoom level reaches — max_display_radius / zoom),
## not its position on screen.  An object is named when its own log-distance is within
## [LABEL_INNER_FRAC × view_radius, view_radius]: i.e. it's inside the current view and
## not tiny relative to its scale.  Because this keys off world distance, every object at
## a given distance is named together — zoom out to galaxy scale and ALL galaxies get
## names, not just the ones near screen centre.  It's also monotonic (each object has one
## contiguous zoom band), so nothing reappears as you keep zooming out.  Selected exempt.
## Naming band as fractions of the current view radius: an object is named when its
## log-distance is within [LABEL_INNER_FRAC, LABEL_OUTER_FRAC] × view_radius.
const LABEL_INNER_FRAC: float = 0.1   # inner edge (× view radius) — small central hole
const LABEL_OUTER_FRAC: float = 3.6   # outer edge (× view radius) — names reach past the rim
## Fraction of the naming band over which names + lines fade in (inner edge) and out
## (outer edge), instead of popping on/off.
const LABEL_FADE: float = 0.25

## Hubble horizon — the radius of the observable universe (c / H₀ ≈ 14.4 Gly).  The map
## scales all the way out to it, so the nearest stars are a speck beside the void and
## the decade rings march off toward the edge of everything.
const HUBBLE_HORIZON_LY: float = 1.44e10

## Cosmic expansion: galaxies outside the gravitationally-bound Local Group recede as
## space expands (the scale factor is pushed from Game over deep time).  Within this
## radius structures are bound and hold together; beyond it, they drift outward until
## they pass the Hubble horizon and wink out — the observable universe slowly emptying.
const LOCAL_GROUP_LY: float = 4.0e6

## Superscript digits for "10ⁿ ly" ring labels (orders of magnitude).
const SUPERSCRIPT: Array = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
const HORIZON_COLOR: Color = Color(0.70, 0.45, 0.55, 0.45)

const BG_COLOR:    Color = Color(0.0, 0.0, 0.0, 1.0)
const RING_COLOR:  Color = Color(0.30, 0.45, 0.65, 0.20)
const RING_LABEL:  Color = Color(0.42, 0.56, 0.78, 0.55)
const DROP_COLOR:  Color = Color(0.45, 0.60, 0.85, 0.12)

var _yaw:   float = 0.6
var _pitch: float = 0.95   # default tilt to look down onto the galactic plane (now the map plane)
var _zoom:  float = 1.0
var _selected: int = -1
## Index into star_clusters() of the selected cluster, or -1.  Stars and clusters are picked
## from the same click, and selecting one clears the other.
var _selected_cluster: int = -1

var _dragging:   bool = false
var _drag_moved: bool = false
var _last_mouse: Vector2 = Vector2.ZERO

var _font: Font

## GALAXIES with their equatorial coords resolved to cartesian "pos" (built in _ready).
var _galaxies: Array = []
## Procedural Milky-Way star field: [{pos: Vector3 (ly), col: Color, r: float}], built once.
var _field: Array = []
## Named intra-galactic landmarks resolved to cartesian: [{name, pos, kind, color}].
var _landmarks: Array = []
## Reference frame: the world position placed at the centre of the map (Sol by default).  Every
## object is drawn at log(pos − _ref_pos), so switching frames re-lays-out the whole log-scaled
## map around a different origin.  Right-click a star to recentre, empty space to reset.
var _ref_pos:  Vector3 = Vector3.ZERO
var _ref_name: String  = "Sol"
## Orthonormal galactic basis in the equatorial frame + the galactic-centre position (ly).
var _g_x: Vector3 = Vector3.RIGHT   # toward the galactic centre (l=0, b=0)
var _g_y: Vector3 = Vector3.FORWARD # toward l=90 (direction of galactic rotation)
var _g_z: Vector3 = Vector3.UP      # toward the North Galactic Pole (b=90)
var _gc_pos: Vector3 = Vector3.ZERO # galactic centre, relative to Sol

## Interstellar state pushed by Game.gd.
var _colonized: Dictionary = {}      # star name → true
var _factions: Dictionary = {}       # star name → "aggressive" | "peaceful"
var _missions: Array = []            # [{ target, progress, origin, kind: "colony"|"vn", mission }]
var _avail_energy: float = 0.0       # current energy, for the launch affordability readout
var _dash_phase: float = 0.0         # animates the travel-line dashes
var _cosmic_scale: float = 1.0       # proper-distance multiplier for unbound galaxies (≥1)
var _year: float = 2026.0            # current game year, so stars can be shown at their evolved state
const STELLAR_EPOCH: float = 2026.0  # the game's start year; a star's "age" field is its age then
var _attacks: Array = []             # [{ "target": name, "progress": 0..1, "kind": "laser"|"berserker" }]
var _incoming: Array = []            # [{ "source": name, "target": "sol"|name, "progress": 0..1 }]
var _can_laser: bool = false         # an Orbital Laser is built
var _can_berserker: bool = false     # von Neumann (self-replicating industry) researched
var _can_missile: bool = false       # relativistic missiles/probes (Relativistic Navigation)
var _missile_stock: int = 0          # crafted Missile units in the player's inventory
var _berserker_stock: int = 0        # crafted Berserker seeds in the player's inventory
var _can_colonize: bool = false      # Relativistic Navigation researched (interstellar flight)
var _intel: Dictionary = {}          # star → {alignment, dyson, telescopes, lasers, detail, diplo, probed}
var _colony_intel: Dictionary = {}   # colonised star → {dyson, telescopes, lasers} (own infrastructure)
var _missile_btn: Button = null
var _probe_btn: Button = null
var _vn_btn:         Button = null
var _dlg_mission_row:  HBoxContainer = null
var _dlg_doctrine_row: HBoxContainer = null
var _contact_btn: Button = null
var _ally_btn: Button = null
var _trade_btn: Button = null
var _war_btn: Button = null

## Launch sub-panel (built in _ready, shown when a colonisable star is selected).
var _launch_ui:     PanelContainer = null
var _launch_title:  Label   = null
var _intel_label:   Label   = null   # known infrastructure of a detected alien system
var _speed_slider:  HSlider = null
var _accel_slider:  HSlider = null   # log₁₀ of max acceleration in m/s²
var _launch_info:   Label   = null
var _launch_btn:    Button  = null
var _laser_power_slider: HSlider = null   # laser energy multiplier (≥1)
var _laser_btn:     Button  = null
var _berserker_btn: Button  = null

## Modal configuration dialog — a launchable/laser button opens it to edit speed, acceleration,
## number to send (weapons) or energy output (laser), with a live cost readout and a confirm.
var _dialog_backdrop: ColorRect      = null   # dims the map + eats clicks while the dialog is up
var _action_dialog:  PanelContainer  = null
var _dlg_kind:       String          = ""     # "colonize" | "probe" | "vnprobe" | "berserker" | "missile" | "laser"
var _dlg_title:      Label           = null
var _dlg_speed_row:  HBoxContainer    = null
var _dlg_accel_row:  HBoxContainer    = null
var _dlg_count_row:  HBoxContainer    = null
var _dlg_energy_row: HBoxContainer    = null
var _dlg_speed_val:  Label            = null
var _dlg_accel_val:  Label            = null
var _dlg_energy_val: Label            = null
var _dlg_count:      SpinBox          = null
var _dlg_info:       Label            = null
var _dlg_confirm:    Button           = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL
	# Clip all drawing (stars/labels/lines projected beyond the edges) to the panel rect
	# so nothing bleeds outside the star map into the rest of the UI.
	clip_contents = true
	_font = ThemeDB.fallback_font
	_build_galaxies()
	_build_galaxy()   # galactic basis + procedural star field + intra-galactic landmarks
	_build_launch_ui()
	resized.connect(queue_redraw)

## Build the bottom-docked launch sub-panel (speed slider + Launch button).
func _build_launch_ui() -> void:
	_launch_ui = PanelContainer.new()
	# Docked bottom-right and lifted off the bottom edge, clear of the bottom-left planet
	# column and the lower edge of the panel.
	_launch_ui.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	# Fixed width so the info text (which wraps) can't resize the panel horizontally.
	_launch_ui.custom_minimum_size = Vector2(384, 0)
	_launch_ui.offset_left = -540
	_launch_ui.offset_right = -156
	# Raised well off the bottom edge (it grows upward from offset_bottom as content is added).
	_launch_ui.offset_top = -420
	_launch_ui.offset_bottom = -220
	_launch_ui.hide()
	add_child(_launch_ui)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	var mc := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(m, 8)
	mc.add_child(vb)
	_launch_ui.add_child(mc)

	_launch_title = Label.new()
	_launch_title.add_theme_font_size_override("font_size", 13)
	_launch_title.modulate = Color(0.9, 0.95, 1.0)
	vb.add_child(_launch_title)

	# Known infrastructure of a detected alien system (multi-line list; hidden otherwise).
	_intel_label = Label.new()
	_intel_label.add_theme_font_size_override("font_size", 11)
	_intel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intel_label.custom_minimum_size = Vector2(360, 0)
	_intel_label.modulate = Color(0.85, 0.80, 0.62)
	_intel_label.hide()
	vb.add_child(_intel_label)

	_launch_info = Label.new()
	_launch_info.add_theme_font_size_override("font_size", 11)
	_launch_info.modulate = Color(0.75, 0.82, 0.95)
	# Wrap within a fixed width so long flight/intel text can't stretch the panel horizontally.
	_launch_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_launch_info.custom_minimum_size = Vector2(360, 0)
	_launch_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_launch_info)

	# Each action button opens the configuration dialog for that action (speed / acceleration /
	# number to send, or laser output) with a live cost readout and a confirm — nothing fires on
	# the button press itself.
	_launch_btn = Button.new()
	_launch_btn.text = "Launch colony ship…"
	_launch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_btn.pressed.connect(func(): _open_action_dialog("colonize"))
	vb.add_child(_launch_btn)

	_probe_btn = Button.new()
	_probe_btn.text = "Send recon probe…"
	_probe_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_probe_btn.add_theme_color_override("font_color", Color(0.7, 0.9, 0.85))
	_probe_btn.pressed.connect(func(): _open_action_dialog("probe"))

	vb.add_child(_probe_btn)

	_vn_btn = Button.new()
	_vn_btn.text = "Seed von Neumann probe…"
	_vn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vn_btn.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_vn_btn.tooltip_text = "Send a crafted von Neumann Probe. It colonises the star and builds fresh probes there, which leave for the next systems on their own — one launch eventually reaches everything."
	_vn_btn.pressed.connect(func(): _open_action_dialog("vnprobe"))
	vb.add_child(_vn_btn)

	_berserker_btn = Button.new()
	_berserker_btn.text = "Send berserkers…"
	_berserker_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_berserker_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	_berserker_btn.pressed.connect(func(): _open_action_dialog("berserker"))
	vb.add_child(_berserker_btn)

	_missile_btn = Button.new()
	_missile_btn.text = "Fire missile…"
	_missile_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_missile_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.55))
	_missile_btn.pressed.connect(func(): _open_action_dialog("missile"))
	vb.add_child(_missile_btn)

	_laser_btn = Button.new()
	_laser_btn.text = "Fire laser…"
	_laser_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_laser_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.9))
	_laser_btn.pressed.connect(func(): _open_action_dialog("laser"))
	vb.add_child(_laser_btn)

	var diplo := HBoxContainer.new()
	diplo.add_theme_constant_override("separation", 6)
	_contact_btn = _diplo_button("Contact", func(): _emit_message("contact"))
	_ally_btn    = _diplo_button("Alliance", func(): _emit_message("ally"))
	_trade_btn   = _diplo_button("Trade", func(): _emit_message("trade"))
	_war_btn     = _diplo_button("Declare war", func(): _emit_message("war"))
	diplo.add_child(_contact_btn)
	diplo.add_child(_ally_btn)
	diplo.add_child(_trade_btn)
	diplo.add_child(_war_btn)
	vb.add_child(diplo)

	_build_action_dialog()

func _diplo_button(label: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(handler)
	return b

func _emit_message(kind: String) -> void:
	var n := selected_star()
	if n != "":
		message_requested.emit(n, kind)

# ── Action configuration dialog ────────────────────────────────────────────────

## Build the modal dialog (hidden) that a launchable/laser button opens.  It holds every
## editable control; rows are shown/hidden per action in _open_action_dialog.
func _build_action_dialog() -> void:
	_dialog_backdrop = ColorRect.new()
	_dialog_backdrop.color = Color(0.0, 0.0, 0.0, 0.5)   # dims the map behind the dialog
	_dialog_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP   # modal — eats clicks behind it
	_dialog_backdrop.hide()
	_dialog_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_dialog_backdrop)

	_action_dialog = PanelContainer.new()
	_action_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_action_dialog.custom_minimum_size = Vector2(380, 0)
	_action_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog_backdrop.add_child(_action_dialog)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var mc := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(m, 14)
	mc.add_child(vb)
	_action_dialog.add_child(mc)

	_dlg_title = Label.new()
	_dlg_title.add_theme_font_size_override("font_size", 15)
	_dlg_title.modulate = Color(0.95, 0.97, 1.0)
	vb.add_child(_dlg_title)

	# Max speed (γ) — log slider, identical range to the old inline control.
	_dlg_speed_row = _dlg_slider_row("Max speed", -3.0, log(MAX_GAMMA - 1.0) / log(10.0), 0.02, -1.0)
	_speed_slider = _dlg_speed_row.get_meta("slider")
	_dlg_speed_val = _dlg_speed_row.get_meta("value")
	vb.add_child(_dlg_speed_row)

	# Max acceleration — log slider (m/s²).
	_dlg_accel_row = _dlg_slider_row("Max accel", -3.0, 4.0, 0.05, -1.0)
	_accel_slider = _dlg_accel_row.get_meta("slider")
	_dlg_accel_val = _dlg_accel_row.get_meta("value")
	vb.add_child(_dlg_accel_row)

	# Number to send (weapons only) — a spinbox capped at the crafted stock on hand.
	_dlg_count_row = HBoxContainer.new()
	_dlg_count_row.add_theme_constant_override("separation", 8)
	var cl := Label.new()
	cl.text = "Number to send"
	cl.custom_minimum_size = Vector2(120, 0)
	cl.add_theme_font_size_override("font_size", 11)
	_dlg_count_row.add_child(cl)
	_dlg_count = SpinBox.new()
	_dlg_count.min_value = 1
	_dlg_count.max_value = 1
	_dlg_count.step = 1
	_dlg_count.value = 1
	_dlg_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dlg_count.value_changed.connect(func(_v): _update_dialog_info())
	_dlg_count_row.add_child(_dlg_count)
	vb.add_child(_dlg_count_row)

	# Energy output (laser only) — the flat-cost power multiplier.
	_dlg_energy_row = _dlg_slider_row("Energy output", 1.0, 10.0, 0.5, 1.0)
	_laser_power_slider = _dlg_energy_row.get_meta("slider")
	_dlg_energy_val = _dlg_energy_row.get_meta("value")
	vb.add_child(_dlg_energy_row)

	# Probe orders (von Neumann only): what it does on arrival, and how it treats what it finds.
	_dlg_mission_row  = _make_option_row(vb, "Mission", DoctrineData.PROBE_MISSIONS)
	_dlg_doctrine_row = _make_option_row(vb, "Doctrine", DoctrineData.DOCTRINES)

	_dlg_info = Label.new()
	_dlg_info.add_theme_font_size_override("font_size", 11)
	_dlg_info.modulate = Color(0.78, 0.85, 0.97)
	_dlg_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlg_info.custom_minimum_size = Vector2(340, 0)
	vb.add_child(_dlg_info)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	_dlg_confirm = Button.new()
	_dlg_confirm.text = "Confirm"
	_dlg_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dlg_confirm.pressed.connect(_on_dialog_confirm)
	btn_row.add_child(_dlg_confirm)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_close_action_dialog)
	btn_row.add_child(cancel)
	vb.add_child(btn_row)

## Build a labelled slider row with a right-aligned value readout; the HSlider and value Label
## are stashed as metadata so the caller can wire them up.
func _dlg_slider_row(label: String, lo: float, hi: float, step: float, val: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(96, 0)
	l.add_theme_font_size_override("font_size", 11)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(_v): _update_dialog_info())
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(104, 0)
	v.add_theme_font_size_override("font_size", 11)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	row.set_meta("slider", s)
	row.set_meta("value", v)
	return row

## An option row for the dialog: a label and a dropdown, used for a probe's mission and its
## contact doctrine.  Both re-cost the flight when changed, since mission decides probe mass.
func _make_option_row(parent: Control, label: String, entries: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(96, 0)
	l.add_theme_font_size_override("font_size", 11)
	row.add_child(l)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(entries.size()):
		opt.add_item(str((entries[i] as Dictionary)["name"]), i)
	opt.item_selected.connect(func(_i: int) -> void: _update_dialog_info())
	row.add_child(opt)
	row.set_meta("opt", opt)
	parent.add_child(row)
	return row

## Open the dialog for `kind`, showing only the rows that action needs.  Buttons are disabled
## when an action is unavailable, so this only ever opens for a valid, affordable-in-principle move.
func _open_action_dialog(kind: String) -> void:
	if _dialog_backdrop == null:
		return
	var star := selected_star()
	if star == "" or _colonized.has(star):
		return
	_dlg_kind = kind
	var is_laser := kind == "laser"
	var wants_count := kind == "berserker" or kind == "missile"
	_dlg_speed_row.visible  = not is_laser
	_dlg_accel_row.visible  = not is_laser
	_dlg_count_row.visible  = wants_count
	_dlg_energy_row.visible = is_laser
	# A von Neumann probe carries its ORDERS: what to do on arrival, and how to behave toward
	# whoever it meets.  Both are copied into every probe it goes on to build, so this is the
	# last moment either can be chosen.
	var is_vn := kind == "vnprobe"
	_dlg_mission_row.visible  = is_vn
	_dlg_doctrine_row.visible = is_vn
	if wants_count:
		var stock := _berserker_stock if kind == "berserker" else _missile_stock
		_dlg_count.min_value = 1
		_dlg_count.max_value = maxi(1, stock)
		_dlg_count.value = 1
	var titles := {
		"colonize": "Launch colony ship", "probe": "Send recon probe",
		"berserker": "Launch berserkers", "missile": "Fire missiles", "laser": "Fire orbital laser",
		"vnprobe": "Seed von Neumann probe"}
	_dlg_title.text = "%s  →  %s" % [str(titles.get(kind, "Launch")), star]
	_update_dialog_info()
	_dialog_backdrop.show()

func _close_action_dialog() -> void:
	if _dialog_backdrop:
		_dialog_backdrop.hide()
	_dlg_kind = ""

## Clicking the dimmed area outside the dialog cancels it.
func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_close_action_dialog()

## Recompute the dialog's live cost/summary readout and enable/disable Confirm on affordability.
func _update_dialog_info() -> void:
	if _dlg_info == null or _dlg_kind == "":
		return
	var dist := _selected_dist()
	if _dlg_speed_val:
		_dlg_speed_val.text = _fmt_speed(_selected_gamma())
	if _dlg_accel_val:
		_dlg_accel_val.text = _fmt_accel(_selected_accel())
	if _dlg_energy_val:
		_dlg_energy_val.text = "×%.1f" % _laser_power()
	var affordable := true
	var text := ""
	if _dlg_kind == "laser":
		var lc := StarMapPanel.laser_energy(dist) * _laser_power()
		affordable = lc <= _avail_energy
		text = "Light-speed pulse  ·  %s energy%s" % [
			Units.format_si(lc, "J"), "" if affordable else "   ✗ insufficient energy"]
	else:
		var g := _selected_gamma()
		var a := _selected_accel()
		var plan := StarMapPanel.plan_flight(dist, g, a)
		var years := float(plan["years"])
		var per := float(plan["energy"])
		var count := 1
		match _dlg_kind:
			"berserker":
				per *= BERSERKER_MASS_FRAC
				count = int(_dlg_count.value)
			"missile":
				per *= MISSILE_MASS_FRAC
				count = int(_dlg_count.value)
			"probe":
				per *= PROBE_MASS_FRAC
			"vnprobe":
				per *= DoctrineData.mission_mass_frac(_selected_mission())
		var total := per * float(count)
		affordable = total <= _avail_energy
		var speed_str := _fmt_speed(g)
		if not bool(plan["reaches"]):
			speed_str += " (peaks %s)" % _fmt_speed(float(plan["peak_gamma"]))
		var tail := "" if count <= 1 else "  ·  ×%d = %s total" % [count, Units.format_si(total, "J")]
		text = "%s  ·  %s  ·  %s travel  ·  %s each%s%s" % [
			speed_str, _fmt_accel(a), _fmt_years(years), Units.format_si(per, "J"),
			tail, "" if affordable else "   ✗ insufficient energy"]
		if _dlg_kind == "vnprobe":
			# Say what the orders actually commit to — a probe cannot be recalled or re-tasked.
			var mi: Dictionary = DoctrineData.get_mission(_selected_mission())
			var dd: Dictionary = DoctrineData.get_doctrine(_selected_doctrine())
			text += "
%s  %s" % [str(mi["name"]), str(mi["desc"])]
			text += "
On contact: %s  %s" % [str(dd["name"]), str(dd["desc"])]
	_dlg_info.text = text
	if _dlg_confirm:
		_dlg_confirm.disabled = not affordable

## The probe orders currently selected in the dialog.
func _selected_mission() -> String:
	if _dlg_mission_row == null:
		return DoctrineData.DEFAULT_MISSION
	var i: int = (_dlg_mission_row.get_meta("opt") as OptionButton).selected
	return str((DoctrineData.PROBE_MISSIONS[maxi(i, 0)] as Dictionary)["id"])

func _selected_doctrine() -> String:
	if _dlg_doctrine_row == null:
		return DoctrineData.DEFAULT_ID
	var i: int = (_dlg_doctrine_row.get_meta("opt") as OptionButton).selected
	return str((DoctrineData.DOCTRINES[maxi(i, 0)] as Dictionary)["id"])

## Commit the configured action: emit the matching request (weapons carry the salvo count).
func _on_dialog_confirm() -> void:
	var star := selected_star()
	if star == "":
		_close_action_dialog()
		return
	var g := _selected_gamma()
	var a := _selected_accel()
	match _dlg_kind:
		"colonize":
			colonize_requested.emit(star, g, a)
		"probe":
			probe_requested.emit(star, g, a)
		"vnprobe":
			vn_probe_requested.emit(star, g, a, _selected_mission(), _selected_doctrine())
		"berserker":
			berserker_requested.emit(star, g, a, int(_dlg_count.value))
		"missile":
			missile_requested.emit(star, g, a, int(_dlg_count.value))
		"laser":
			laser_requested.emit(star, _laser_power())
	_close_action_dialog()

## Animate the in-transit dashed lines + attack pulses while the map is visible.
func _process(delta: float) -> void:
	if visible and (not _missions.is_empty() or not _attacks.is_empty() or not _incoming.is_empty()):
		_dash_phase = fmod(_dash_phase + delta * 24.0, 1.0e6)
		queue_redraw()

## Resolve each galaxy's RA/Dec/distance into the cartesian frame the stars use, and
## record its comoving direction + base distance so cosmic expansion can push it outward
## later (unbound galaxies only — Local Group members stay put).
func _build_galaxies() -> void:
	_galaxies.clear()
	for g: Dictionary in GALAXIES:
		var entry := g.duplicate()
		var pos := _equatorial_to_xyz(float(g["ra_h"]), float(g["dec_deg"]), float(g["dist"]))
		entry["pos"] = pos
		entry["dir"] = pos.normalized()
		entry["base_dist"] = float(g["dist"])
		entry["bound"] = float(g["dist"]) <= LOCAL_GROUP_LY
		_galaxies.append(entry)

## Build the galactic basis, the seeded procedural star field, and the named landmarks.
func _build_galaxy() -> void:
	# Orthonormal galactic axes expressed in the equatorial cartesian frame the map uses:
	#   _g_x → galactic centre, _g_z → North Galactic Pole, _g_y = _g_z × _g_x (l=90).
	_g_x = _equatorial_to_xyz(GC_RA_H, GC_DEC, 1.0).normalized()
	_g_z = _equatorial_to_xyz(NGP_RA_H, NGP_DEC, 1.0).normalized()
	_g_z = (_g_z - _g_x * _g_z.dot(_g_x)).normalized()   # Gram–Schmidt: make the pole ⟂ the centre
	_g_y = _g_z.cross(_g_x).normalized()
	_gc_pos = _g_x * SOL_GC_LY
	_build_star_field()
	_build_landmarks()

## Sample the Milky Way's stellar distribution into a deterministic point cloud.  Disk stars
## follow an exponential radial profile with a Gaussian scale height and a spiral-arm
## overdensity; the rest populate the central bulge.  Points nearer than FIELD_MIN_LY (the
## catalogued-star domain) are dropped so the field only fills the galactic gap outward.
func _build_star_field() -> void:
	_field.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = GALAXY_SEED
	var guard: int = 0
	while _field.size() < FIELD_STARS and guard < FIELD_STARS * 6:
		guard += 1
		var pos: Vector3
		var col: Color
		if rng.randf() < BULGE_FRAC:
			# Central bulge: a roughly spherical concentration of old, yellow-orange stars.
			var r_b: float = absf(rng.randfn(0.0, BULGE_LY * 0.6))
			pos = _gc_pos + _random_unit(rng) * r_b
			col = Color(1.0, 0.84, 0.58).lerp(Color(1.0, 0.72, 0.45), rng.randf())
		else:
			# Disk: exponential radius (Gamma-2 = sum of two exponentials), Gaussian height,
			# azimuth biased toward the spiral arms.
			var radius: float = -DISK_SCALE_LY * (log(maxf(rng.randf(), 1e-6)) + log(maxf(rng.randf(), 1e-6)))
			if radius > DISK_MAX_LY:
				continue
			var phi: float = rng.randf() * TAU
			var arm: float = _arm_strength(radius, phi)
			if rng.randf() > 0.32 + 0.68 * arm:
				continue   # thin out the inter-arm regions
			var z: float = rng.randfn(0.0, DISK_H_LY)
			pos = _gc_pos + (_g_x * (radius * cos(phi))) + (_g_y * (radius * sin(phi))) + (_g_z * z)
			# Arm stars skew young/blue; inter-arm and outer disk skew yellow-white.
			col = Color(1.0, 0.93, 0.80).lerp(Color(0.68, 0.80, 1.0), arm * rng.randf())
		if pos.length() < FIELD_MIN_LY:
			continue
		var jitter: float = rng.randf_range(0.75, 1.0)
		_field.append({
			"pos": pos,
			"col": Color(col.r, col.g, col.b, 1.0) * jitter,
			"r":   rng.randf_range(0.8, 1.5),
		})

## Spiral-arm overdensity (0..1) at galactocentric (r, phi): proximity to the nearest log-spiral
## arm winding out from the centre — used only to bias the field's density and colour.
func _arm_strength(r: float, phi: float) -> float:
	var wind: float = log(maxf(r, 1.0) / SOL_GC_LY) / tan(ARM_PITCH_RAD)
	var best: float = 0.0
	for k in range(ARM_COUNT):
		var arm_phi: float = wind + TAU * float(k) / float(ARM_COUNT)
		var d: float = wrapf(phi - arm_phi, -PI, PI)
		best = maxf(best, exp(-(d * d) / (2.0 * ARM_WIDTH_RAD * ARM_WIDTH_RAD)))
	return best

## Resolve named landmarks: clusters/nebulae from equatorial coords.
func _build_landmarks() -> void:
	_landmarks.clear()
	for m: Dictionary in LANDMARKS_EQ:
		_landmarks.append({
			"name":  str(m["name"]),
			"pos":   _equatorial_to_xyz(float(m["ra_h"]), float(m["dec_deg"]), float(m["dist"])),
			"kind":  str(m["kind"]),
			"color": m["color"],
		})

## A uniformly-distributed unit vector (for scattering bulge stars).
func _random_unit(rng: RandomNumberGenerator) -> Vector3:
	var z: float = rng.randf_range(-1.0, 1.0)
	var t: float = rng.randf() * TAU
	var r: float = sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(r * cos(t), r * sin(t), z)

## Push the cosmic scale factor (≥1) from Game — proper distance of unbound galaxies
## grows by this as the universe ages.
func set_cosmic_scale(s: float) -> void:
	var ns := maxf(s, 1.0)
	if not is_equal_approx(ns, _cosmic_scale):
		_cosmic_scale = ns
		queue_redraw()

## Push the current game year so every star can be drawn and described at its EVOLVED state
## (a star's "age" field is its age at STELLAR_EPOCH; elapsed game years are added on top).
func set_year(y: float) -> void:
	if absf(y - _year) >= 1.0:
		_year = y
		queue_redraw()

## Compact luminosity readout in solar luminosities (SI prefixes at the extremes).
func _fmt_lum(l: float) -> String:
	if l >= 1000.0 or (l > 0.0 and l < 0.01):
		return Units.format_si(l, "")
	return "%.3g" % l

## Current age of a star (years) at the present game year: its epoch age plus elapsed time.
func _star_age_now(s: Dictionary) -> float:
	return float(s.get("age", 5.0)) * 1.0e9 + (_year - STELLAR_EPOCH)

## Evolutionary state of a star right now (phase, luminosity, current mass, colour, …).
func _star_state(s: Dictionary) -> Dictionary:
	return StellarEvolution.state(float(s.get("mass", 1.0)), _star_age_now(s), s["color"])

## Equatorial (RA hours, Dec degrees, distance) → cartesian light-years.
func _equatorial_to_xyz(ra_h: float, dec_deg: float, dist_ly: float) -> Vector3:
	var ra := deg_to_rad(ra_h * 15.0)
	var dec := deg_to_rad(dec_deg)
	return Vector3(
		dist_ly * cos(dec) * cos(ra),
		dist_ly * cos(dec) * sin(ra),
		dist_ly * sin(dec))

# ── Public API ────────────────────────────────────────────────────────────────

## Galaxy-data accessors, so the linear-scale debug view can render the same generated field and
## landmarks (single source of truth — no regeneration).
func galaxy_field() -> Array: return _field
func galaxy_landmarks() -> Array: return _landmarks
func galaxy_center() -> Vector3: return _gc_pos

## Name of the currently selected star, or "" if none.
func selected_star() -> String:
	if _selected_cluster >= 0:
		return str(star_clusters()[_selected_cluster]["name"])
	return str(all_stars()[_selected]["name"]) if _selected >= 0 else ""

## Push interstellar state from Game.gd: which stars are colonised, the in-flight
## colony missions (target name + 0..1 progress), and current energy for the readout.
func set_interstellar_state(colonized: Dictionary, missions: Array, energy: float) -> void:
	_colonized = colonized
	_missions = missions
	_avail_energy = energy
	_update_launch_ui()
	queue_redraw()

## Push alien presence (star name → "aggressive"/"peaceful") for the red/blue highlights.
func set_star_factions(factions: Dictionary) -> void:
	_factions = factions
	queue_redraw()

## Push in-flight attacks (laser pulses + berserker swarms) for the map animation.
func set_attacks(attacks: Array) -> void:
	_attacks = attacks
	queue_redraw()

## Push incoming hostile relativistic missiles: [{ source, target ("sol"|star), progress }].
func set_incoming(incoming: Array) -> void:
	_incoming = incoming
	queue_redraw()

## Push which weapons are available (Orbital Laser built / berserkers / relativistic missiles).
func set_weapon_caps(can_laser: bool, can_berserker: bool, can_missile: bool) -> void:
	_can_laser = can_laser
	_can_berserker = can_berserker
	_can_missile = can_missile
	_update_launch_ui()

## Push the player's crafted-weapon stockpile (Missile / Berserker units on hand).
## Crafted von Neumann Probes on hand, so the Seed button can gate on having one.
var _vn_stock: int = 0

func set_vn_stock(n: int) -> void:
	_vn_stock = n
	if _vn_btn:
		_vn_btn.disabled = n <= 0
		_vn_btn.tooltip_text = ("Send a crafted von Neumann Probe (%d in stock)." % n) if n > 0 			else "No von Neumann Probes built. Assemble one in the Production panel."

func set_arsenal(missiles: int, berserkers: int) -> void:
	_missile_stock = missiles
	_berserker_stock = berserkers
	_update_launch_ui()

## Push per-system alien intel (light-delayed, telescope-limited) for the info readout.
func set_alien_intel(intel: Dictionary) -> void:
	_intel = intel
	_update_launch_ui()

## Push the player's own colony infrastructure (colonised star → {dyson, telescopes, lasers}).
func set_colony_intel(intel: Dictionary) -> void:
	_colony_intel = intel
	_update_launch_ui()

## Whether interstellar colony launches are unlocked (Relativistic Navigation researched).
func set_interstellar_unlocked(unlocked: bool) -> void:
	_can_colonize = unlocked
	_update_launch_ui()

## Distance (ly) of the selected star, or 0.
func _selected_dist() -> float:
	if _selected_cluster >= 0:
		return float(star_clusters()[_selected_cluster]["dist"])
	return float(all_stars()[_selected]["dist"]) if _selected >= 0 else 0.0

## Current max Lorentz factor γ from the log speed slider (1 + 10^value).
func _selected_gamma() -> float:
	return 1.0 + pow(10.0, _speed_slider.value) if _speed_slider else 2.0

## Current max acceleration (m/s²) from the log slider.
func _selected_accel() -> float:
	return pow(10.0, _accel_slider.value) if _accel_slider else 0.1

## Refresh the launch sub-panel for the current selection + sliders, or hide it.
func _update_launch_ui() -> void:
	if _launch_ui == null:
		return
	var name := selected_star()
	if name == "":
		_launch_ui.hide()
		return
	_launch_ui.show()
	# Known-infrastructure listing for a detected alien system (shown for any selection above).
	if _intel_label:
		var block := _intel_block(name)
		_intel_label.text = block
		_intel_label.visible = block != ""
	var dist: float = _selected_dist()
	if _colonized.has(name):
		_launch_title.text = "%s  —  colonised" % name
		_launch_info.text = "A human colony orbits this star.\n%s" % _colony_infra_block(name)
		_launch_btn.disabled = true
		_launch_btn.text = "Colonised"
		_update_weapon_buttons(dist, true)
		return
	_launch_title.text = "%s  —  %.2f ly" % [name, dist]
	_launch_info.text = "Energy available: %s.  Pick an action to set speed / acceleration / number and confirm." % \
		Units.format_si(_avail_energy, "J")
	# A detected civilisation makes the system a neighbour, not a site.  Blocked here rather
	# than refused on confirm, so the map says why before the player commits to anything.
	var inhabited: bool = _intel.has(name)
	if inhabited:
		_launch_btn.disabled = true
		_launch_btn.text = "Inhabited — cannot be colonised"
		_launch_btn.tooltip_text = "%s already holds a civilisation." % name
	elif not _can_colonize:
		# Interstellar flight not yet unlocked — show the target's data but block the launch.
		_launch_btn.disabled = true
		_launch_btn.text = "Colony ship — research Relativistic Navigation"
		_launch_btn.tooltip_text = ""
	else:
		_launch_btn.disabled = false
		_launch_btn.text = "Launch colony ship…"
		_launch_btn.tooltip_text = ""
	if _vn_btn:
		if inhabited:
			_vn_btn.disabled = true
			_vn_btn.text = "Inhabited — cannot be seeded"
			_vn_btn.tooltip_text = "Seeding a self-replicating probe into an inhabited system would not be colonisation."
		else:
			_vn_btn.disabled = _vn_stock <= 0
			_vn_btn.text = "Seed von Neumann probe…"
			_vn_btn.tooltip_text = ("Send a crafted von Neumann Probe (%d in stock)." % _vn_stock) if _vn_stock > 0 else "No von Neumann Probes built. Assemble one in the Production panel."
	_update_weapon_buttons(dist, false)
	# Keep an open dialog's cost readout current if energy/stock changed underneath it.
	if _dialog_backdrop and _dialog_backdrop.visible:
		_update_dialog_info()

## Enable/label the weapon, probe, and diplomacy buttons for the current target.  These now
## only gate on AVAILABILITY (research / crafted stock / not-colonised); the actual energy cost
## and affordability are computed live in the configuration dialog each button opens.
func _update_weapon_buttons(_dist: float, colonised: bool) -> void:
	if _laser_btn == null:
		return
	var name := selected_star()
	var has_intel: bool = _intel.has(name)
	# Diplomacy is available only with a DETECTED alien system; probes/weapons need the tech.
	for db: Button in [_contact_btn, _ally_btn, _trade_btn, _war_btn]:
		if db:
			db.disabled = colonised or not has_intel
	if _probe_btn:
		_probe_btn.disabled = colonised or not _can_missile
		_probe_btn.text = "Send recon probe…" if _can_missile else "Recon probe — research"
	if colonised:
		for wb: Button in [_laser_btn, _berserker_btn, _missile_btn]:
			wb.disabled = true
		return
	if not _can_laser:
		_laser_btn.disabled = true
		_laser_btn.text = "Laser — build one"
	else:
		_laser_btn.disabled = false
		_laser_btn.text = "Fire laser…"
	if not _can_berserker:
		_berserker_btn.disabled = true
		_berserker_btn.text = "Berserkers — research"
	elif _berserker_stock < 1:
		_berserker_btn.disabled = true
		_berserker_btn.text = "Berserkers — craft one"
	else:
		_berserker_btn.disabled = false
		_berserker_btn.text = "Send berserkers…  (%d in stock)" % _berserker_stock
	if not _can_missile:
		_missile_btn.disabled = true
		_missile_btn.text = "Missile — research"
	elif _missile_stock < 1:
		_missile_btn.disabled = true
		_missile_btn.text = "Missile — craft one"
	else:
		_missile_btn.disabled = false
		_missile_btn.text = "Fire missiles…  (%d in stock)" % _missile_stock

## Multi-line intel block for a detected alien system: alignment/diplomacy header plus a list
## of its known infrastructure (fields the telescopes can't yet resolve read "unknown"; a
## returned probe reveals everything).  Returns "" for a system with no intel.
func _intel_block(name: String) -> String:
	if not _intel.has(name):
		return ""
	var d: Dictionary = _intel[name]
	var probed: bool = bool(d.get("probed", false))
	var detail: float = float(d.get("detail", 0.0))
	var lines: Array = []
	var head: String = "Alien civilisation: %s" % str(d.get("alignment", "unknown"))
	var diplo: String = str(d.get("diplo", ""))
	if diplo != "":
		head += "  [%s]" % diplo
	lines.append(head)
	lines.append("Known infrastructure%s:" % ("" if probed else " (light-delayed)"))
	var dyson: String = ("%d%%" % int(round(float(d.get("dyson", 0.0)) * 100.0))) \
		if (probed or detail > 0.2) else "unknown"
	var scopes: String = ("%d" % int(d.get("telescopes", 0))) if (probed or detail > 0.5) else "unknown"
	var lasers: String = ("%d" % int(d.get("lasers", 0))) if (probed or detail > 0.8) else "unknown"
	# Offensive arsenal is the hardest to resolve from afar — only a probe or the sharpest
	# telescope reach reveals a hostile's missile and berserker stockpiles.
	var missiles: String = ("%d" % int(d.get("missiles", 0))) if (probed or detail > 0.9) else "unknown"
	var berserkers: String = ("%d" % int(d.get("berserkers", 0))) if (probed or detail > 0.9) else "unknown"
	lines.append("  • Dyson swarm: %s" % dyson)
	lines.append("  • Orbital telescopes: %s" % scopes)
	lines.append("  • Orbital lasers: %s" % lasers)
	lines.append("  • Relativistic missiles: %s" % missiles)
	lines.append("  • Berserker seeds: %s" % berserkers)
	return "\n".join(lines)

## Infrastructure readout for one of the player's own colonies (full detail — it's ours).
func _colony_infra_block(name: String) -> String:
	if not _colony_intel.has(name):
		return "Colony infrastructure: developing…"
	var d: Dictionary = _colony_intel[name]
	return "Colony infrastructure:\n  • Dyson swarm: %d%%\n  • Orbital telescopes: %d\n  • Defensive lasers: %d" % [
		int(round(float(d.get("dyson", 0.0)) * 100.0)),
		int(d.get("telescopes", 0)), int(d.get("lasers", 0))]

## Laser energy multiplier from the power slider (≥1).
func _laser_power() -> float:
	return _laser_power_slider.value if _laser_power_slider else 1.0

## Speed readout from γ as a fraction of c (cruise is capped at 99.99% c).
func _fmt_speed(g: float) -> String:
	return "%.2f%% c" % (beta_from_gamma(g) * 100.0)

## "0.10 m/s² (0.01 g)" style label for the acceleration slider readout.
func _fmt_accel(a: float) -> String:
	var g := a / 9.80665
	if a >= 0.1:
		return "%.1f m/s² (%.2f g)" % [a, g]
	return "%.3f m/s² (%.4f g)" % [a, g]

func _fmt_years(y: float) -> String:
	if y >= 1000.0:
		return "%s yr" % Units.format_si(y, "")
	if y >= 1.0:
		return "%d yr" % int(round(y))
	return "<1 yr"

## Index of a star by name (-1 if not found).
func _star_index(name: String) -> int:
	for i in range(all_stars().size()):
		if str(all_stars()[i]["name"]) == name:
			return i
	return -1

## Map position of anything a mission can be addressed to — a catalogued star OR a cluster in
## the outer shell.  Game.gd already indexes both by name, so a launch at a cluster works; only
## the RENDERER could not resolve one, which is why those flights drew no path at all.
## Returns false when the name matches nothing (an in-flight target that no longer exists).
func _target_pos(name: String, out: Array) -> bool:
	var idx := _star_index(name)
	if idx >= 0:
		out.append(all_stars()[idx]["pos"])
		return true
	for c: Dictionary in star_clusters():
		if str(c["name"]) == name:
			out.append(c["pos"])
			return true
	return false

## Dashed line from `from` to `to` whose dashes flow toward `to`; the leg already
## traversed (≤ progress) is tinted green, the remainder blue, with a ship marker.
func _draw_travel_dashes(from: Vector2, to: Vector2, progress: float) -> void:
	var d := to - from
	var total := d.length()
	if total < 1.0:
		return
	var dir := d / total
	var period := 14.0          # dash(8) + gap(6)
	var ahead := Color(0.55, 0.80, 1.0, 0.55)
	var done := Color(0.45, 0.95, 0.65, 0.85)
	var s := fmod(_dash_phase, period) - period   # increasing phase → dashes shift toward `to`
	while s < total:
		var a := maxf(s, 0.0)
		var bend := minf(s + 8.0, total)
		if bend > a:
			var mid := (a + bend) * 0.5 / total
			draw_line(from + dir * a, from + dir * bend, done if mid <= progress else ahead, 1.5)
		s += period
	var ship := from + dir * (total * clampf(progress, 0.0, 1.0))
	draw_circle(ship, 3.0, Color(0.85, 0.97, 1.0, 0.95))

## Colour per probe mission, so a swarm's purpose is readable from the map alone: a survey
## front, a relay network, and a colonisation wave look like three different things because
## they are.
const PROBE_COLOURS: Dictionary = {
	"recon":    Color(0.60, 0.90, 0.95),   # pale cyan — looking
	"comms":    Color(0.70, 0.65, 1.00),   # violet    — listening
	"colonize": Color(0.55, 0.95, 0.60),   # green     — claiming
}

## A von Neumann probe in transit.  Deliberately NOT the colony ship's dashed lane: a solid
## hairline with a forward-pointing chevron at the probe, because the thing that matters about
## a probe is its heading — it is going somewhere and will not stop when it gets there.
func _draw_probe_track(from: Vector2, to: Vector2, progress: float, mission: String) -> void:
	var d := to - from
	var total := d.length()
	if total < 1.0:
		return
	var dir := d / total
	var col: Color = PROBE_COLOURS.get(mission, PROBE_COLOURS["colonize"])
	var p := clampf(progress, 0.0, 1.0)
	var head := from + dir * (total * p)
	# Faint hairline over the whole route, brighter along the part already flown.
	draw_line(from, to, Color(col.r, col.g, col.b, 0.16), 1.0, true)
	draw_line(from, head, Color(col.r, col.g, col.b, 0.55), 1.0, true)
	# A short bright wake trailing the probe, so direction reads even when it is barely moving.
	var wake := maxf(0.0, total * p - 14.0)
	draw_line(from + dir * wake, head, Color(col.r, col.g, col.b, 0.95), 1.6, true)
	# Chevron at the probe, pointing along the heading.
	var n := Vector2(-dir.y, dir.x)
	var tip := head + dir * 5.0
	draw_polyline(PackedVector2Array([
		tip - dir * 6.0 + n * 4.0, tip, tip - dir * 6.0 - n * 4.0]),
		Color(1.0, 1.0, 1.0, 0.95), 1.6, true)
	# Replicating probes travel as a group; a second faint chevron behind says "and more".
	if wake > 0.0:
		var t2 := head - dir * 7.0
		draw_polyline(PackedVector2Array([
			t2 - dir * 4.0 + n * 2.6, t2, t2 - dir * 4.0 - n * 2.6]),
			Color(col.r, col.g, col.b, 0.60), 1.2, true)

## A soft, blended star: faint halo layers under a bright antialiased core.
func _draw_soft_star(sp: Vector2, rad: float, col: Color) -> void:
	draw_circle(sp, rad * 2.6, Color(col.r, col.g, col.b, 0.06), true, -1.0, true)
	draw_circle(sp, rad * 1.7, Color(col.r, col.g, col.b, 0.14), true, -1.0, true)
	draw_circle(sp, rad, col, true, -1.0, true)
	draw_circle(sp, rad * 0.45, Color(1.0, 1.0, 1.0, 0.70), true, -1.0, true)

## A laser firing: a faint white beam-trail with a bright white rectangular pulse racing
## to the target.  The pulse grows with the energy (`power`) channelled into the shot.
func _draw_laser_pulse(from: Vector2, to: Vector2, progress: float, power: float) -> void:
	var d := to - from
	var total := d.length()
	if total < 1.0:
		return
	var dir := d / total
	var perp := Vector2(-dir.y, dir.x)
	var head := from + dir * (total * clampf(progress, 0.0, 1.0))
	draw_line(from, head, Color(1.0, 1.0, 1.0, 0.18), 1.0)
	# Rectangular pulse aligned to the beam; length/width scale with channelled energy.
	var half_len := (8.0 + power * 4.0) * 0.5
	var half_wid := (2.0 + power * 1.2) * 0.5
	var rect := PackedVector2Array([
		head + dir * half_len + perp * half_wid,
		head + dir * half_len - perp * half_wid,
		head - dir * half_len - perp * half_wid,
		head - dir * half_len + perp * half_wid,
	])
	var glow := PackedVector2Array([
		head + dir * (half_len + 3.0) + perp * (half_wid + 2.0),
		head + dir * (half_len + 3.0) - perp * (half_wid + 2.0),
		head - dir * (half_len + 3.0) - perp * (half_wid + 2.0),
		head - dir * (half_len + 3.0) + perp * (half_wid + 2.0),
	])
	draw_colored_polygon(glow, Color(1.0, 1.0, 1.0, 0.25))
	draw_colored_polygon(rect, Color(1.0, 1.0, 1.0, 0.98))

## A von Neumann berserker swarm: a red dashed trail with a menacing red marker.
func _draw_berserker_swarm(from: Vector2, to: Vector2, progress: float) -> void:
	var d := to - from
	var total := d.length()
	if total < 1.0:
		return
	var dir := d / total
	var period := 12.0
	var s := fmod(_dash_phase, period) - period
	while s < total:
		var a := maxf(s, 0.0)
		var bend := minf(s + 6.0, total)
		if bend > a:
			draw_line(from + dir * a, from + dir * bend, Color(1.0, 0.35, 0.30, 0.5), 1.5)
		s += period
	var head := from + dir * (total * clampf(progress, 0.0, 1.0))
	draw_circle(head, 6.0, Color(1.0, 0.30, 0.30, 0.25))
	draw_circle(head, 3.5, Color(1.0, 0.45, 0.35, 0.95))

## Incoming relativistic missile: a faint red trajectory from the hostile source to the
## target, with a sharp bright head and a short trailing streak at the missile's progress.
func _draw_incoming_missile(from: Vector2, to: Vector2, progress: float) -> void:
	var d := to - from
	var total := d.length()
	if total < 1.0:
		return
	var dir := d / total
	# Faint full trajectory so the player can trace where it's coming from.
	draw_line(from, to, Color(1.0, 0.25, 0.22, 0.28), 1.0, true)
	var p := clampf(progress, 0.0, 1.0)
	var head := from + dir * (total * p)
	# Bright leading streak (the missile), tapering back along its path.
	var tail := head - dir * minf(26.0, total * p)
	draw_line(tail, head, Color(1.0, 0.35, 0.28, 0.95), 2.5, true)
	draw_circle(head, 4.5, Color(1.0, 0.55, 0.35, 0.30))
	draw_circle(head, 2.4, Color(1.0, 0.85, 0.60, 1.0))

# ── Projection ────────────────────────────────────────────────────────────────

## Orbit-camera basis from azimuth (_yaw) and elevation (_pitch), with the star
## coordinate Z axis as "up".  Dragging horizontally spins the map about that
## vertical axis like a turntable; dragging vertically raises/lowers the viewpoint.
func _view_basis() -> Basis:
	var ca := cos(_yaw);   var sa := sin(_yaw)
	var ce := cos(_pitch); var se := sin(_pitch)
	var right := Vector3(-sa, ca, 0.0)                 # screen → world right (in XY plane)
	var up    := Vector3(-se * ca, -se * sa, ce)       # screen up (world Z when level)
	var fwd   := Vector3(ca * ce, sa * ce, se)         # toward the viewer (depth)
	return Basis(right, up, fwd)

func _max_dist() -> float:
	var m: float = 1.0
	for s: Dictionary in all_stars():
		m = maxf(m, float(s["dist"]))
	return m

# ── Logarithmic radial scale (to the Hubble horizon) ───────────────────────────
# Distance is mapped through log₁₀(r), so each decade of light-years is one even step
# out from Sol and the whole observable universe fits in the panel.  The direction of
# every star is preserved; only its radius is compressed.  At this scale the nearest
# stars (a single decade or two out) are a tight knot near the centre and the rings run
# all the way to the Hubble horizon — zoom in to resolve the local neighbourhood.

## Real light-years → display radius (log₁₀, clamped so everything inside 1 ly sits at
## the centre and the Sun stays exactly at the origin).
func _display_radius(r_ly: float) -> float:
	return log(maxf(r_ly, 1.0)) / log(10.0)

## A point remapped onto the log radial scale, preserving its 3D direction.
func _log_pos(p: Vector3) -> Vector3:
	var r := p.length()
	if r < 1.0e-6:
		return Vector3.ZERO
	return p * (_display_radius(r) / r)

## A world position in the CURRENT reference frame, rotated into the GALACTIC frame and then
## log-remapped: log(R·(pos − _ref_pos)), where R maps equatorial axes to (galactic centre,
## l=90, pole).  Rotating into the galactic frame lays the Milky Way's disk flat on the map's
## reference plane (z ≈ 0), so the galaxy "lies on the plane" instead of at a random tilt.  The
## reference object still lands at the origin; distances (log radius) are unchanged by rotation.
func _rel(p: Vector3) -> Vector3:
	var v := p - _ref_pos
	return _log_pos(Vector3(v.dot(_g_x), v.dot(_g_y), v.dot(_g_z)))

## Largest display radius shown — the Hubble horizon — used to fit the whole map.
func _max_display_radius() -> float:
	return maxf(_display_radius(HUBBLE_HORIZON_LY), 0.001)

## Display radius of the farthest catalogued star — used to normalise depth shading so
## the near/far size cue still reads across the tiny local cluster (not the whole void).
func _max_star_display_radius() -> float:
	return maxf(_display_radius(_max_dist()), 0.001)

## Pixels per display-unit so the Hubble horizon fits the panel with a margin.
func _fit_scale(center: Vector2) -> float:
	return (minf(center.x, center.y) * 0.86 / _max_display_radius()) * _zoom

## Opacity (0..1) for an object's name + drop-line, from its log-distance `rd` and the
## current view radius.  Full inside the band [INNER, OUTER] × view_radius and fading
## smoothly to 0 at each edge, so labels ease in/out as you zoom instead of popping.
## 0 means don't draw at all.
func _detail_alpha(rd: float) -> float:
	var view_radius := _max_display_radius() / _zoom
	var hi := view_radius * LABEL_OUTER_FRAC
	var lo := view_radius * LABEL_INNER_FRAC
	if rd <= lo or rd >= hi:
		return 0.0
	var t := (rd - lo) / (hi - lo)          # 0 at inner edge, 1 at outer edge
	return clampf(t / LABEL_FADE, 0.0, 1.0) * clampf((1.0 - t) / LABEL_FADE, 0.0, 1.0)

## Copy of a colour with its alpha scaled by `a` (for fading labels/lines).
func _fade(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

## "10ⁿ ly" label for the decade-k ring (k = order of magnitude in light-years).
func _decade_label(k: int) -> String:
	var sup := ""
	for ch in str(k):
		sup += str(SUPERSCRIPT[int(ch)])
	return "10%s ly" % sup

## A small tilted-ellipse "disk + core" glyph so galaxies read distinctly from stars.
## `alpha` dims the whole glyph (used as galaxies recede toward the horizon).
func _draw_galaxy_glyph(sp: Vector2, rad: float, col: Color, tilt: float, alpha: float = 1.0) -> void:
	var pts := PackedVector2Array()
	var ct := cos(tilt)
	var st := sin(tilt)
	for i in range(24):
		var t := TAU * float(i) / 24.0
		var ex := rad * cos(t)            # semi-major
		var ey := rad * 0.45 * sin(t)     # squashed into a disk
		pts.append(sp + Vector2(ex * ct - ey * st, ex * st + ey * ct))
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.30 * alpha))
	draw_circle(sp, rad * 0.42, Color(col.r, col.g, col.b, 0.95 * alpha))   # bright core

## Glyph + label for an intra-galactic landmark, distinct per kind:
##   cluster   — a small scatter of dots (a knot of stars)
##   nebula    — a soft translucent blob
##   structure — a faint open ring (spiral arm / bulge region)
func _draw_landmark(sp: Vector2, kind: String, col: Color, alpha: float, name: String) -> void:
	var c := _fade(col, alpha)
	match kind:
		"cluster":
			for off in [Vector2(0, -2), Vector2(-2, 1), Vector2(2, 1), Vector2(0, 2), Vector2(-1, -1)]:
				draw_circle(sp + off, 1.1, c)
		"nebula":
			draw_circle(sp, 6.0, _fade(col, alpha * 0.22))
			draw_circle(sp, 3.0, _fade(col, alpha * 0.38))
			draw_circle(sp, 1.2, c)
		_:  # structure — spiral arm / bulge
			draw_arc(sp, 7.0, 0.0, TAU, 28, _fade(col, alpha * 0.6), 1.0, true)
	draw_string(_font, sp + Vector2(9.0, 4.0), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col.r, col.g, col.b, 0.8 * alpha))

## Orthographic projection of a world point onto the camera's right/up axes.
## How far back the eye sits, in units of the current view radius.  Small values give a wide,
## dramatic cone; large values flatten toward the orthographic projection this replaced.  This
## is the only knob that decides how strongly the map reads as a volume rather than a chart.
const CAMERA_DIST_VR: float = 2.6
## Nearest depth a point may be projected at, again in view radii.  Anything closer (or behind
## the eye) is clamped rather than flung off-screen or mirrored through the origin.
const NEAR_CLIP_VR: float = 0.35

## Perspective foreshortening at a point: 1.0 at the focal plane, >1 nearer, <1 further.
## Everything on the map — positions, star radii, track widths — goes through this, which is
## what makes depth readable instead of merely sorted.
func _persp(p: Vector3, b: Basis) -> float:
	var cam: float = _view_radius_now() * CAMERA_DIST_VR
	var near: float = _view_radius_now() * NEAR_CLIP_VR
	# Depth measured from the eye: the focal plane sits at the origin of the current frame.
	var d: float = maxf(cam - p.dot(b.z), near)
	return cam / d

func _project(p: Vector3, b: Basis, center: Vector2, scale: float) -> Vector2:
	return center + Vector2(p.dot(b.x), -p.dot(b.y)) * scale * _persp(p, b)

## View radius for the current zoom.  Computed rather than cached: _persp runs during picking
## as well as drawing, and a per-frame cache would be stale for the first click after a zoom.
func _view_radius_now() -> float:
	return maxf(_max_display_radius() / _zoom, 1.0e-6)

## Signed depth along the view axis (larger = nearer the viewer).
func _depth(p: Vector3, b: Basis) -> float:
	return p.dot(b.z)

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, BG_COLOR)
	draw_rect(full, Color(0.4, 0.5, 0.7, 0.25), false, 1.0)

	var center: Vector2 = size * 0.5
	var b := _view_basis()
	var scale := _fit_scale(center)
	var star_maxdr := _max_star_display_radius()

	# Order-of-magnitude reference rings: one per decade of light-years, out to the
	# Hubble horizon.  On the log scale they're evenly spaced (log₁₀(10ᵏ) = k), so each
	# step outward is ×10 the distance — the map's way of showing the scale of the void.
	var max_k: int = int(ceil(_display_radius(HUBBLE_HORIZON_LY)))
	for k in range(0, max_k + 1):
		var r_ly := pow(10.0, float(k))
		if r_ly > HUBBLE_HORIZON_LY:
			break
		var rd := _display_radius(r_ly)
		var pts := PackedVector2Array()
		for i in range(65):
			var a := TAU * float(i) / 64.0
			pts.append(_project(Vector3(cos(a), sin(a), 0.0) * rd, b, center, scale))
		draw_polyline(pts, RING_COLOR, 1.0, true)
		draw_string(_font, _project(Vector3(rd, 0.0, 0.0), b, center, scale) + Vector2(3, -3),
			_decade_label(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, RING_LABEL)

	# The Hubble horizon itself — the outermost ring, in its own colour.
	var horizon_rd := _display_radius(HUBBLE_HORIZON_LY)
	var hpts := PackedVector2Array()
	for i in range(65):
		var ha := TAU * float(i) / 64.0
		hpts.append(_project(Vector3(cos(ha), sin(ha), 0.0) * horizon_rd, b, center, scale))
	draw_polyline(hpts, HORIZON_COLOR, 1.5, true)
	# Raised by the label's own height so it sits clear above the horizon ring.
	var horizon_label_y: float = -3.0 - _font.get_height(10)
	draw_string(_font, _project(Vector3(horizon_rd, 0.0, 0.0), b, center, scale) + Vector2(3, horizon_label_y),
		"Hubble horizon", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HORIZON_COLOR)

	# Nearby galaxies — out in the far decades, drawn as tilted disk glyphs.  Unbound
	# galaxies recede with cosmic expansion (proper distance × scale), fading as they
	# near the Hubble horizon and dropping out entirely once they cross it.
	for g: Dictionary in _galaxies:
		var eff_d: float = float(g["base_dist"])
		if not bool(g["bound"]):
			eff_d *= _cosmic_scale
		if eff_d >= HUBBLE_HORIZON_LY:
			continue   # receded beyond the observable horizon — gone for good
		var gpos: Vector3 = (g["dir"] as Vector3) * eff_d
		var glp := _rel(gpos)
		var gsp := _project(glp, b, center, scale)
		var gcol: Color = g["color"]
		# Dim as it approaches the horizon (redshifting out of sight).
		var horizon_fade: float = clampf(
			(HUBBLE_HORIZON_LY - eff_d) / (HUBBLE_HORIZON_LY * 0.3), 0.0, 1.0)
		var g_alpha := _detail_alpha(glp.length()) * horizon_fade
		if g_alpha > 0.0:
			var gfoot := _project(Vector3(glp.x, glp.y, 0.0), b, center, scale)
			draw_line(gfoot, gsp, _fade(DROP_COLOR, g_alpha), 1.0)
		var tilt: float = float(hash(str(g["name"])) % 360) * (PI / 360.0)
		_draw_galaxy_glyph(gsp, 6.0, gcol, tilt, horizon_fade)
		if g_alpha > 0.0:
			draw_string(_font, gsp + Vector2(9.0, 4.0), str(g["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(gcol.r, gcol.g, gcol.b, 0.80 * g_alpha))

	# Named intra-galactic landmarks — clusters, nebulae, spiral arms and the bulge — drawn as
	# distinct labelled glyphs so the galaxy has recognisable features between the nearby stars
	# and the extragalactic layer.
	for m: Dictionary in _landmarks:
		var mlp: Vector3 = _rel(m["pos"])
		var ma: float = _detail_alpha(mlp.length())
		if ma <= 0.0:
			continue
		_draw_landmark(_project(mlp, b, center, scale), str(m["kind"]), m["color"], ma, str(m["name"]))

	# The generated cluster shell: everything the player can reach but cannot resolve star by
	# star.  Drawn as a soft cloud of points rather than a single dot, so a cluster reads as a
	# GROUP of suns and never gets mistaken for one.
	var cl_all: Array = star_clusters()
	for ci in range(cl_all.size()):
		var cl: Dictionary = cl_all[ci]
		var clp: Vector3 = _rel(cl["pos"])
		var ca: float = _detail_alpha(clp.length())
		var csel: bool = ci == _selected_cluster
		if ca <= 0.0 and not csel:
			continue
		var cp := _project(clp, b, center, scale)
		if cp.x < -20.0 or cp.y < -20.0 or cp.x > size.x + 20.0 or cp.y > size.y + 20.0:
			continue
		var ccol: Color = cl["color"]
		var settled: bool = _colonized.has(str(cl["name"]))
		if settled:
			ccol = Color(0.40, 0.95, 0.55)
		var a: float = 1.0 if csel else maxf(ca, 0.25)
		# A ring of grains around a brighter core — a cluster, not a star.
		var seed_h: int = hash(str(cl["name"]))
		for k in range(7):
			var ang: float = float((seed_h >> (k * 3)) % 360) * PI / 180.0
			var rad: float = 2.5 + float((seed_h >> (k * 2)) % 5)
			draw_rect(Rect2(cp + Vector2(cos(ang), sin(ang)) * rad - Vector2(0.8, 0.8),
				Vector2(1.6, 1.6)), Color(ccol.r, ccol.g, ccol.b, 0.45 * a))
		draw_circle(cp, 2.2, Color(ccol.r, ccol.g, ccol.b, 0.9 * a))
		if csel:
			draw_arc(cp, 11.0, 0.0, TAU, 28, Color(1.0, 0.95, 0.6, 0.95), 1.5, true)
		if csel or ca > 0.55:
			draw_string(_font, cp + Vector2(13.0, 4.0), str(cl["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ccol.r, ccol.g, ccol.b, 0.85 * a))

	# Stars: with up to ~10 000 in range, cull to the current zoom band first (plus always-shown
	# ones — selected, alien, colonised, or the nearby catalogue), computing each position ONCE
	# rather than twice per sort comparison.  Then draw far-to-near so nearer ones overlap on top.
	var vis: Array = []
	for si in range(all_stars().size()):
		var s0: Dictionary = all_stars()[si]
		var nm0: String = str(s0["name"])
		var selected: bool = si == _selected
		var important: bool = selected or _colonized.has(nm0) or _factions.has(nm0)
		# Hard distance cutoff, measured from the current reference frame — beyond
		# STAR_RENDER_MAX_LY nothing draws, INCLUDING colonised and alien systems; only the
		# selected star is kept.  In the Sol frame this is just the Sol distance.
		if (s0["pos"] as Vector3).distance_to(_ref_pos) > STAR_RENDER_MAX_LY and not selected:
			continue
		var lp0: Vector3 = _rel(s0["pos"])
		var a0: float = 1.0 if selected else _detail_alpha(lp0.length())
		# Within the cutoff, colonised/alien/near stars always draw (at any zoom); far anonymous
		# ones only draw when in the current zoom band.
		if a0 <= 0.0 and not (important or float(s0["dist"]) < STAR_ALWAYS_LY):
			continue
		vis.append([si, lp0, maxf(a0, 0.0)])
	vis.sort_custom(func(x: Array, y: Array) -> bool: return _depth(x[1], b) < _depth(y[1], b))

	for e: Array in vis:
		var i: int = int(e[0])
		var s: Dictionary = all_stars()[i]
		var lp: Vector3 = e[1]
		var sp := _project(lp, b, center, scale)
		# A selected star keeps full opacity; everything else fades in/out with the view radius.
		var alpha: float = e[2]
		if alpha > 0.0:
			# Drop line to the reference plane conveys the star's height above/below it.
			var foot := _project(Vector3(lp.x, lp.y, 0.0), b, center, scale)
			draw_line(foot, sp, _fade(DROP_COLOR, alpha), 1.0)
			draw_circle(foot, 1.5, _fade(DROP_COLOR, alpha))

		# Stars shrink with distance from Sol (perspective): near = bigger, far = smaller.
		var dist_frac := clampf(lp.length() / star_maxdr, 0.0, 1.0)
		var rad := lerpf(6.0, 2.2, dist_frac)
		# Size with perspective too, not just position: foreshortening the spacing while every
		# star stays the same size reads as a warped chart rather than a volume.  Damped and
		# clamped, so a star drifting near the eye swells convincingly without filling the panel.
		rad *= clampf(1.0 + (_persp(lp, b) - 1.0) * 0.6, 0.45, 2.6)
		# Draw each star at its CURRENT evolved state: giants swell and redden, compact remnants
		# shrink to a dim point, and colour tracks the phase — so the map visibly ages over time.
		var st: Dictionary = _star_state(s)
		var col: Color = st["color"]
		var ph: String = str(st["phase"])
		if ph in ["Red giant", "Asymptotic giant", "Planetary nebula"]:
			rad *= 1.7
		elif ph == "Supergiant":
			rad *= 2.1
		elif bool(st["remnant"]):
			rad *= 0.55                    # white dwarf / neutron star / black hole: tiny
		if i == _selected:
			draw_circle(sp, rad + 6.0, Color(1.0, 1.0, 1.0, 0.22), true, -1.0, true)
			draw_arc(sp, rad + 6.0, 0.0, TAU, 40, Color(0.9, 0.95, 1.0, 0.9), 1.5, true)
		_draw_soft_star(sp, rad, col)
		# Alien presence highlight: red = aggressive, blue = peaceful, yellow = alignment
		# still unknown (always named so the player can see who's out there).
		var fac: String = str(_factions.get(str(s["name"]), ""))
		if fac == "aggressive":
			draw_circle(sp, rad + 3.0, Color(1.0, 0.30, 0.30, 0.28))
			draw_arc(sp, rad + 5.5, 0.0, TAU, 32, Color(1.0, 0.35, 0.35, 0.95), 2.0, true)
		elif fac == "peaceful":
			draw_circle(sp, rad + 3.0, Color(0.40, 0.60, 1.0, 0.28))
			draw_arc(sp, rad + 5.5, 0.0, TAU, 32, Color(0.50, 0.70, 1.0, 0.95), 2.0, true)
		elif fac == "unknown":
			draw_circle(sp, rad + 3.0, Color(1.0, 0.85, 0.25, 0.22))
			draw_arc(sp, rad + 5.5, 0.0, TAU, 32, Color(1.0, 0.88, 0.30, 0.95), 2.0, true)
		# Colonised stars get a steady green ring (named regardless of zoom).
		var colonised: bool = _colonized.has(str(s["name"]))
		if colonised:
			draw_arc(sp, rad + 4.0, 0.0, TAU, 32, Color(0.4, 0.95, 0.55, 0.9), 1.5, true)
		var always: bool = colonised or fac != ""
		if alpha > 0.0 or always:
			var lbl_col: Color = Color(0.88, 0.93, 1.0, 0.95) if i == _selected \
				else Color(0.78, 0.84, 0.96, 0.6)
			if fac == "aggressive":
				lbl_col = Color(1.0, 0.55, 0.55, 0.95)
			elif fac == "peaceful":
				lbl_col = Color(0.6, 0.78, 1.0, 0.95)
			elif fac == "unknown":
				lbl_col = Color(1.0, 0.90, 0.50, 0.95)
			if colonised:
				lbl_col = Color(0.6, 0.95, 0.7, 0.95)
			var la: float = 1.0 if (i == _selected or always) else alpha
			draw_string(_font, sp + Vector2(rad + 4.0, 4.0), str(s["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _fade(lbl_col, la))

	# Sol's projected position under the current reference frame — the origin of our own missions
	# and the default target of incoming attacks (only at screen centre in the Sol frame).
	var sol_px := _project(_rel(Vector3.ZERO), b, center, scale)

	# In-transit colony missions: an animated dashed line from Sol to the target star,
	# with dashes flowing toward the destination and a marker at the ship's progress.
	for m: Dictionary in _missions:
		var tpos: Array = []
		if not _target_pos(str(m.get("target", "")), tpos):
			continue
		var dst := _project(_rel(tpos[0]), b, center, scale)
		# A probe replicated at a colony departs from THAT star, not from Sol.  Empty origin
		# means it was launched from home, which is every mission the player sends directly.
		var src_px := sol_px
		var origin := str(m.get("origin", ""))
		if origin != "":
			var opos: Array = []
			if _target_pos(origin, opos):
				src_px = _project(_rel(opos[0]), b, center, scale)
		# A colony ship and a self-replicating probe are not the same object and should not
		# read as the same line.
		if str(m.get("kind", "colony")) == "vn":
			_draw_probe_track(src_px, dst, float(m.get("progress", 0.0)),
				str(m.get("mission", "colonize")))
		else:
			_draw_travel_dashes(src_px, dst, float(m.get("progress", 0.0)))

	# In-flight attacks: a white laser pulse racing out at light speed, or a red von
	# Neumann berserker swarm crawling toward its target.
	for atk: Dictionary in _attacks:
		var apos: Array = []
		if not _target_pos(str(atk.get("target", "")), apos):
			continue
		var adst := _project(_rel(apos[0]), b, center, scale)
		var ap := float(atk.get("progress", 0.0))
		match str(atk.get("kind", "")):
			"laser":
				_draw_laser_pulse(sol_px, adst, ap, float(atk.get("power", 1.0)))
			"missile":
				_draw_incoming_missile(sol_px, adst, ap)   # relativistic kinetic missile
			_:
				_draw_berserker_swarm(sol_px, adst, ap)

	# Incoming relativistic missiles: a red streak from the hostile source toward the target
	# (Sol, or one of our colonies), with a bright head at the missile's progress.
	for inc: Dictionary in _incoming:
		var ipos: Array = []
		if not _target_pos(str(inc.get("source", "")), ipos):
			continue
		var src_px := _project(_rel(ipos[0]), b, center, scale)
		var tgt_name := str(inc.get("target", "sol"))
		var tgt_px := sol_px
		if tgt_name != "sol":
			var itg: Array = []
			if _target_pos(tgt_name, itg):
				tgt_px = _project(_rel(itg[0]), b, center, scale)
		var ip := float(inc.get("progress", 0.0))
		match str(inc.get("kind", "missile")):
			"berserker":
				_draw_berserker_swarm(src_px, tgt_px, ip)   # slow red self-replicating swarm
			"laser":
				_draw_laser_pulse(src_px, tgt_px, ip, 1.0)   # white light-speed pulse
			_:
				_draw_incoming_missile(src_px, tgt_px, ip)   # relativistic kinetic missile

	# The Sun — rendered exactly like every other star (its live evolved state), at its position
	# in the current reference frame (map centre only while the frame IS Sol).  A G2V, ~4.6 Gyr
	# old, so it reads main-sequence yellow now and swells to a red giant far in the future.
	var sol_lp := _rel(Vector3.ZERO)
	var sol_star := {"mass": 1.0, "age": 4.6, "color": Color(1.0, 0.95, 0.82)}
	var sol_st := _star_state(sol_star)
	var sol_rad := lerpf(6.0, 2.2, clampf(sol_lp.length() / star_maxdr, 0.0, 1.0))
	var sol_ph := str(sol_st["phase"])
	if sol_ph in ["Red giant", "Asymptotic giant", "Planetary nebula"]:
		sol_rad *= 1.7
	elif sol_ph == "Supergiant":
		sol_rad *= 2.1
	elif bool(sol_st["remnant"]):
		sol_rad *= 0.55
	_draw_soft_star(sol_px, sol_rad, sol_st["color"])
	draw_string(_font, sol_px + Vector2(sol_rad + 4.0, 4.0), "Sol",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.92, 0.7))

	# Title + controls hint.
	draw_string(_font, Vector2(14, 24), "Star Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.95, 1.0))
	draw_string(_font, Vector2(14, 42), "Drag rotate · scroll zoom · click select · right-click set frame",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.68, 0.8))
	draw_string(_font, Vector2(14, 58), "Log scale · rings = orders of magnitude (ly) · out to the Hubble horizon",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.58, 0.72))
	# Observation reach — procedural stars beyond it stay hidden in the anonymous field.
	draw_string(_font, Vector2(14, 106),
		"Observable range: %s ly" % Units.format_si(observation_range(), ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.72, 0.66))
	# Current reference frame — the object at the map's centre (Sol unless recentred).  A
	# crosshair marks the frame origin (always the centre), labelled with the frame's name.
	var frame_col := Color(0.7, 0.85, 0.7) if _ref_name == "Sol" else Color(0.95, 0.85, 0.55)
	draw_string(_font, Vector2(14, 90),
		"Frame: %s%s" % [_ref_name, "" if _ref_name == "Sol" else "  ·  right-click empty space to reset"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, frame_col)
	var fc := _project(_rel(_ref_pos), b, center, scale)
	draw_line(fc - Vector2(7, 0), fc + Vector2(7, 0), _fade(frame_col, 0.7), 1.0)
	draw_line(fc - Vector2(0, 7), fc + Vector2(0, 7), _fade(frame_col, 0.7), 1.0)
	draw_arc(fc, 10.0, 0.0, TAU, 24, _fade(frame_col, 0.5), 1.0, true)
	# Cosmic expansion readout — once space has stretched noticeably.
	if _cosmic_scale > 1.01:
		draw_string(_font, Vector2(14, 74),
			"Cosmic expansion ×%s — unbound galaxies receding" % Units.format_si(_cosmic_scale, ""),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 0.55, 0.62))

	# Selected-cluster info box — the same slot the star readout uses, so only one is ever up.
	if _selected_cluster >= 0:
		var cl: Dictionary = star_clusters()[_selected_cluster]
		var settled: bool = _colonized.has(str(cl["name"]))
		var clines: Array = [
			str(cl["name"]),
			"Open cluster",
			"%s light-years" % Units.format_si(float(cl["dist"]), ""),
			"%s stars" % Units.format_si(float(cl["stars"]), ""),
			"Settled" if settled else "Uncolonised",
		]
		# Too far to resolve individually — this is what you get INSTEAD of picking a star.
		clines.append("Beyond individual resolution;")
		clines.append("colonised as a whole.")
		_draw_info_box(clines)
	# Selected-star info box.
	elif _selected >= 0:
		var s: Dictionary = all_stars()[_selected]
		var lines: Array = [str(s["name"]),
			"%.2f light-years" % float(s["dist"]),
			"Spectral type %s" % str(s["spectral"])]
		# Live stellar state at the current game year — phase, power output, mass, lifespan.
		var st: Dictionary = _star_state(s)
		var zams: float = float(s.get("mass", 1.0))
		lines.append("Phase: %s" % str(st["phase"]))
		lines.append("Output: %s  (%s Lsun)" % [
			Units.format_si(float(st["lum_w"]), "W"), _fmt_lum(float(st["lum_lsun"]))])
		lines.append("Mass now: %.2f Msun  ·  usable %s" % [
			float(st["mass_msun"]), Units.format_si(StellarEvolution.total_usable_mass_kg(zams), "kg")])
		var msl: float = float(st["ms_life"])
		var age_now: float = _star_age_now(s)
		if str(st["phase"]) == "Main sequence":
			lines.append("Main-sequence span %s  ·  leaves in %s" % [
				Units.format_si(msl, "yr"), Units.format_si(maxf(msl - age_now, 0.0), "yr")])
		else:
			lines.append("Main-sequence span %s  ·  ends as %s" % [
				Units.format_si(msl, "yr"), StellarEvolution.remnant_kind(zams)])
		var sfac: String = str(_factions.get(str(s["name"]), ""))
		if sfac == "aggressive":
			lines.append("⚠ Aggressive alien force")
		elif sfac == "peaceful":
			lines.append("◇ Peaceful alien contact")
		elif sfac == "unknown":
			lines.append("? Alien presence — alignment unknown")
		_draw_info_box(lines)

## The bottom-left readout, shared by the star and cluster selections so they cannot drift apart.
func _draw_info_box(lines: Array) -> void:
	var box := Rect2(Vector2(12, size.y - (16.0 * lines.size() + 16.0) - 12.0),
		Vector2(320, 16.0 * lines.size() + 16.0))
	draw_rect(box, Color(0.06, 0.08, 0.14, 0.92))
	draw_rect(box, Color(0.4, 0.55, 0.8, 0.5), false, 1.0)
	for li in range(lines.size()):
		draw_string(_font, box.position + Vector2(10, 19 + li * 16), str(lines[li]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12 if li == 0 else 11,
			Color(0.92, 0.96, 1.0) if li == 0 else Color(0.7, 0.78, 0.9))


# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_drag_moved = false
					_last_mouse = mb.position
				else:
					if _dragging and not _drag_moved:
						_try_select(mb.position)
					_dragging = false
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom = clampf(_zoom * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
					queue_redraw()
				# Swallow the wheel press AND its release — the solar-system camera zooms
				# on the *released* "zoom in/out" action (camera_3d.gd), so accepting only
				# the press let the release leak through and zoom the background.
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom = clampf(_zoom / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
					queue_redraw()
				accept_event()
			MOUSE_BUTTON_RIGHT:
				# Recentre the reference frame: right-click a star, nebula, or galaxy (incl. the
				# Galactic Centre) → centre on it; right-click empty space → reset to Sol.
				if mb.pressed:
					_try_set_frame(mb.position)
				accept_event()
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT:
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var d := mm.position - _last_mouse
		_last_mouse = mm.position
		if d.length() > 1.5:
			_drag_moved = true
		_yaw -= d.x * ROT_SENS
		_pitch = clampf(_pitch + d.y * ROT_SENS, MIN_PITCH, MAX_PITCH)
		queue_redraw()
		accept_event()

## Recentre the reference frame on whatever the player right-clicked — the nearest star, nebula/
## cluster landmark, or galaxy (including the Galactic Centre) — else reset to Sol (empty space).
## Positions re-lay-out around the new origin.
func _try_set_frame(mouse: Vector2) -> void:
	var center: Vector2 = size * 0.5
	var b := _view_basis()
	var scale := _fit_scale(center)
	var best_pos: Vector3 = Vector3.ZERO
	var best_name: String = ""
	var best_d: float = INF
	# Stars (tight tolerance — they're dense).
	for i in range(all_stars().size()):
		var dd := _project(_rel(all_stars()[i]["pos"]), b, center, scale).distance_to(mouse)
		if dd < PICK_PX and dd < best_d:
			best_d = dd
			best_pos = all_stars()[i]["pos"]
			best_name = str(all_stars()[i]["name"])
	# Nebulae / clusters (labelled markers — looser tolerance).
	for m: Dictionary in _landmarks:
		var dm := _project(_rel(m["pos"]), b, center, scale).distance_to(mouse)
		if dm < FRAME_PICK_PX and dm < best_d:
			best_d = dm
			best_pos = m["pos"]
			best_name = str(m["name"])
	# Galaxies, including the Galactic Centre (Sgr A*) — at their current (expansion-adjusted) spot.
	for g: Dictionary in _galaxies:
		var eff_d: float = float(g["base_dist"])
		if not bool(g["bound"]):
			eff_d *= _cosmic_scale
		if eff_d >= HUBBLE_HORIZON_LY:
			continue
		var gpos: Vector3 = (g["dir"] as Vector3) * eff_d
		var dg := _project(_rel(gpos), b, center, scale).distance_to(mouse)
		if dg < FRAME_PICK_PX and dg < best_d:
			best_d = dg
			best_pos = gpos
			best_name = str(g["name"])
	if best_name != "":
		_ref_pos = best_pos
		_ref_name = best_name
	else:
		_ref_pos = Vector3.ZERO   # empty space → back to the Sol frame
		_ref_name = "Sol"
	queue_redraw()

## Pick the nearest projected star to the click (within PICK_PX); clicking empty space clears it.
func _try_select(mouse: Vector2) -> void:
	var center: Vector2 = size * 0.5
	var b := _view_basis()
	var scale := _fit_scale(center)
	var best: int = -1
	var best_d: float = PICK_PX
	for i in range(all_stars().size()):
		var dd := _project(_rel(all_stars()[i]["pos"]), b, center, scale).distance_to(mouse)
		if dd < best_d:
			best_d = dd
			best = i
	# Clusters are picked from the same click.  Past STAR_RENDER_MAX_LY there are no stars to
	# compete with, so a generous radius just makes them easy to hit.
	var best_c: int = -1
	var best_cd: float = CLUSTER_PICK_PX
	var clusters: Array = star_clusters()
	for ci in range(clusters.size()):
		var cd := _project(_rel(clusters[ci]["pos"]), b, center, scale).distance_to(mouse)
		if cd < best_cd:
			best_cd = cd
			best_c = ci
	# Whichever is genuinely nearer the cursor wins; a hit on one clears the other.
	if best_c >= 0 and (best < 0 or best_cd <= best_d):
		_selected = -1
		_selected_cluster = best_c
	else:
		_selected = best
		_selected_cluster = -1
	_update_launch_ui()
	queue_redraw()
	star_selected.emit(selected_star())
