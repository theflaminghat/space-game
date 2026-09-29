extends Node

## Real seconds per game-day at 1x.  The one fixed rate the whole clock is built on; the speed
## ladder multiplies it.  Lives here rather than in Game because it is a property of the clock,
## and because the blur threshold below is expressed against it.
const TIMESCALE_BASE: float = 0.25

## Fastest speed at which individual orbital positions are still drawn.
##
## Above this the bodies whip round their orbits far faster than a frame can show — a planet
## crosses its whole year between one frame and the next, so the dot the player sees is at an
## essentially random point on its orbit and reads as noise.  Past it the bodies are hidden and
## each draws a translucent ring instead (Planet._blur_torus): the honest picture of something
## moving too fast to resolve.  They come back the moment the player pauses, or slows down.
##
## This used to be a YEAR — ORBIT_FREEZE_YEAR, 1 000 000 — from when the timescale was a fixed
## super-linear function of the date, so "late" and "fast" were the same thing.  They are not any
## more: the player chooses the speed, so the cutoff has to be the speed.  It was also one-way,
## and never restored the bodies when the run slowed back down.
const ORBIT_BLUR_ABOVE_MULT: float = 100.0

## Real seconds per game-day.  Assigning it re-derives whether orbits are still worth drawing,
## so no caller has to remember to — including one that sets it directly rather than through the
## speed ladder.
var seconds_per_day: float = 0.1:
	set(v):
		seconds_per_day = v
		_refresh_orbit_rendering()
## The two pause flags.  Both emit paused_changed when they actually change, so a caller cannot
## pause or unpause without the bodies hearing about it: thirteen places wrote these directly and
## only five remembered to emit, which left planets holding whatever visibility they had when the
## last signal happened to fire.
var paused: bool = false:
	set(v):
		if paused == v:
			return
		paused = v
		paused_changed.emit()
var ui_paused: bool = false:
	set(v):
		if ui_paused == v:
			return
		ui_paused = v
		paused_changed.emit()

## Current in-game year — written by Game.gd each year tick so any node can
## read it without depending on Game directly.
var current_year: int = 1945

## Year the frozen planets snap to when shown.  Normally tracks current_year, but
## Game.gd overrides it just before a pause so the planet the player is viewing
## keeps its exact position (the others fall into their relative places for that
## time).  See Planet._snap_to_year / Planet.compute_anchor_year.
var snap_year: float = 1945.0

## False while the run is faster than ORBIT_BLUR_ABOVE_MULT, i.e. while individual orbital
## positions are not worth drawing.  Planets watch this via signals.
var solar_system_active: bool = true

## Emitted when solar_system_active flips.
signal active_changed

## Emitted when either pause flag changes so planets can update their visibility.
signal paused_changed


# ── The star ──────────────────────────────────────────────────────────────────
## Sol's state, and the single place anything asks about it.  Stellar engineering changes the
## star rather than the calendar: the mass below is the one thing a civilisation can alter, and
## every figure that used to be a fixed function of the year — luminosity, radius, when the red
## giant comes, when the nebula fires — is derived from it here.  See star_model.gd for the
## physics and for why a pristine 1 M☉ Sun reproduces the old fixed curve exactly.
##
## Phase 1 only reads this: nothing in the game lowers the mass yet (star lifting is next), so
## every run still behaves exactly as it did.

## What is left of Sol, in solar masses.  Lifting only ever takes mass away.
var star_mass_msun: float = 1.0
## Everything the lifters have ever taken off, kept separately and at full precision.
##
## A year of lifting moves the mass by about 5e-11 M☉, and a double cannot subtract that from
## 1.0 — the sliver is below the last bit of the number.  Accumulating the TOTAL removed from
## zero has no such problem, so the slivers add up and the remaining mass is computed from the
## running total rather than nibbled at.
var star_lifted_msun: float = 0.0

## Years of the star's age undone by husbandry — fresh hydrogen mixed into a core that would
## otherwise never meet it.  Unlike lifting, this changes nothing about the star's mass or light:
## it only sets the clock back.
var star_age_offset_years: float = 0.0

## Fraction of the Sun's light the shades intercept before it reaches the inner worlds.  Derived
## from what is standing (see Game._sync_star_shades), not set by hand.
var star_shade_fraction: float = 0.0

# ── Where the star is ─────────────────────────────────────────────────────────
## How far Sol has been moved from where it began, in light-years, and how fast it is going, in
## m/s.  A Shkadov thruster pushes for as long as it stands, so both only ever grow.
##
## The drift is what makes the engine mean anything: every distance in the game is measured from
## Sol, so moving the star moves the whole neighbourhood relative to it — flights, messages and
## trade round-trips all shorten towards wherever it is aimed and lengthen behind it.
var star_drift_ly: Vector3 = Vector3.ZERO
var star_velocity_ms: float = 0.0
## Unit vector the mirrors push along, and the star it is aimed at ("" for a bare heading).
var star_thrust_dir: Vector3 = Vector3.ZERO
var star_thrust_target: String = ""
## Mirror coverage: the share of the sky the statites cover, derived from what is standing.
var star_mirror_coverage: float = 0.0

## Emitted when the star changes, so panels and visuals can refresh.
signal star_changed


## Set the star's mass (clamped to what the model allows) and tell anyone watching.
##
## The comparison is exact on purpose.  A year of lifting at full swarm power moves the mass by
## about 5e-11 M☉, which any "near enough" test would throw away — and a change that is always
## discarded is a star that never changes.  Deep-time work arrives in slivers; they have to add
## up.
func set_star_mass(msun: float) -> void:
	var m: float = StarModel.clamp_mass(msun)
	if m == star_mass_msun:
		return
	star_mass_msun = m
	# Keep the running total in step for anything that sets the mass outright (a loaded save).
	star_lifted_msun = maxf(star_lifted_msun, 1.0 - m)
	star_changed.emit()


## Take mass off the star, accumulating at full precision.  Returns what was actually removed,
## which is less than asked for only when the mass floor is in the way.
func lift_star_mass(msun: float) -> float:
	var room: float = star_mass_msun - StarModel.MIN_MASS_MSUN
	var take: float = clampf(msun, 0.0, maxf(room, 0.0))
	if take <= 0.0:
		return 0.0
	star_lifted_msun += take
	set_star_mass(1.0 - star_lifted_msun)
	return take


## Back to a pristine Sun — called when a new run starts.
func reset_star() -> void:
	star_lifted_msun = 0.0
	star_age_offset_years = 0.0
	star_shade_fraction = 0.0
	star_drift_ly = Vector3.ZERO
	star_velocity_ms = 0.0
	star_thrust_dir = Vector3.ZERO
	star_thrust_target = ""
	star_mirror_coverage = 0.0
	set_star_mass(1.0)


## True once the star has been altered at all; lets callers skip "engineered" UI on a normal run.
func star_is_engineered() -> bool:
	return not is_equal_approx(star_mass_msun, 1.0) or star_age_offset_years > 0.0 \
		or star_shade_fraction > 0.0 or star_mirror_coverage > 0.0 \
		or star_drift_ly.length_squared() > 0.0


## Set the shade fraction (clamped to what the model allows).
func set_star_shade(fraction: float) -> void:
	var f: float = clampf(fraction, 0.0, StarModel.MAX_SHADE_FRACTION)
	if f == star_shade_fraction:
		return
	star_shade_fraction = f
	star_changed.emit()


## Undo `years` of the star's age.  Never past the epoch: husbandry can hold Sol where it is and
## give back what it has burnt since the run began, but it cannot make it younger than it was.
func rejuvenate_star(years: float) -> float:
	if years <= 0.0:
		return 0.0
	var room: float = maxf(0.0, stellar_age() - StarModel.EPOCH_YEAR)
	var take: float = minf(years, room)
	if take <= 0.0:
		return 0.0
	star_age_offset_years += take
	star_changed.emit()
	return take


## Where Sol is now, in light-years from where it started — the origin every star distance is
## measured against.
func sol_position() -> Vector3:
	return star_drift_ly


## Aim the thruster along a heading (any non-zero vector; it is normalised here).  Aiming does
## not move the star: the mirrors do, and only while they are standing.
func aim_star_thrust(dir: Vector3, target_name: String = "") -> void:
	if dir.length_squared() <= 0.0:
		return
	star_thrust_dir = dir.normalized()
	star_thrust_target = target_name
	star_changed.emit()


## Push the star for `days` at the current mirror coverage.  Returns the light-years moved.
func advance_star_thrust(days: float) -> float:
	if star_mirror_coverage <= 0.0 or days <= 0.0 or star_thrust_dir.length_squared() <= 0.0:
		return 0.0
	var accel: float = StarModel.shkadov_accel_ms2(
		star_mirror_coverage, sun_luminosity_lsun(), star_mass_msun)
	if accel <= 0.0:
		return 0.0
	var secs: float = days * 86400.0
	# Constant acceleration over the slice: the distance covered counts the speed it already had,
	# which is the whole point of an engine that never stops.
	var moved_m: float = star_velocity_ms * secs + 0.5 * accel * secs * secs
	star_velocity_ms += accel * secs
	var moved_ly: float = moved_m / StarModel.LY_M
	star_drift_ly += star_thrust_dir * moved_ly
	star_changed.emit()
	return moved_ly


## Set the mirror coverage (from the roster; see Game._sync_star_shades).
func set_star_mirror_coverage(fraction: float) -> void:
	var f: float = clampf(fraction, 0.0, 1.0)
	if f == star_mirror_coverage:
		return
	star_mirror_coverage = f
	star_changed.emit()


## What reaches the inner worlds, as a fraction of the unshaded light.
func insolation_mult() -> float:
	return 1.0 - star_shade_fraction


## The star's own age at a calendar year (defaults to now).  Equal to the year until Sol is
## lightened, after which the star runs behind the calendar.
func stellar_age(year: float = NAN) -> float:
	var y: float = float(current_year) if is_nan(year) else year
	return StarModel.stellar_age(y, star_mass_msun, star_age_offset_years)


## The calendar year at which the star reaches an age.
func star_year_of_age(age: float) -> float:
	return StarModel.year_of_age(age, star_mass_msun, star_age_offset_years)


## The Sun's output in solar luminosities at a calendar year (defaults to now).
func sun_luminosity_lsun(year: float = NAN) -> float:
	var y: float = float(current_year) if is_nan(year) else year
	return StarModel.luminosity_at(stellar_age(y), star_mass_msun)


## The Sun's photosphere radius in AU at a calendar year.  Once the envelope has been ejected
## there is no photosphere to speak of and the whole system is sterilised, which the huge return
## value expresses to every caller that compares an orbit against it.
func sun_radius_au(year: float = NAN) -> float:
	var y: float = float(current_year) if is_nan(year) else year
	if y >= sun_nebula_year():
		return 99999.0
	return StarModel.SUN_RADIUS_BASE_AU * StarModel.radius_solar_at(stellar_age(y), star_mass_msun)


## The Sun's radius in solar radii at a calendar year — the same figure without the AU scaling.
func sun_radius_solar(year: float = NAN) -> float:
	var y: float = float(current_year) if is_nan(year) else year
	return StarModel.radius_solar_at(stellar_age(y), star_mass_msun)


## The year the Sun reaches the red-giant tip (Earth's orbit), as things currently stand.
##
## INF once the star has been lightened past helium ignition: there is then no giant branch to
## reach, so the answer is not "later", it is "never".  Every caller compares a year against
## this, so the comparison simply stops being true — and the readouts print "never" (see
## sun_fate_dates_known()).
func sun_red_giant_year() -> float:
	if not StarModel.has_giant_phase(star_mass_msun):
		return INF
	return star_year_of_age(StarModel.RED_GIANT_AGE)


## The year the envelope is ejected and the system ends, or INF when it never is.
func sun_nebula_year() -> float:
	if not StarModel.has_giant_phase(star_mass_msun):
		return INF
	return star_year_of_age(StarModel.NEBULA_AGE)


## When the HUD should start warning about the red giant, or INF when there is nothing coming.
func sun_warning_year() -> float:
	if not StarModel.has_giant_phase(star_mass_msun):
		return INF
	return star_year_of_age(StarModel.RED_GIANT_AGE - StarModel.WARNING_LEAD_YEARS)


## Whether the Sun still has a violent end to date at all.
func sun_fate_dates_known() -> bool:
	return StarModel.has_giant_phase(star_mass_msun)


## What Sol is now bound to become, in words.
func sun_fate_text() -> String:
	return StarModel.fate_text(star_mass_msun)


## The light actually arriving at the inner worlds, as a fraction of a pristine Sun's at the
## epoch: the star's own output and the shades together.  1.0 for an untouched run.
func insolation_at_earth(year: float = NAN) -> float:
	return sun_luminosity_lsun(year) * insolation_mult()


func toggle_pause() -> void:
	paused = !paused      # the setter emits paused_changed


func toggle_ui_pause() -> void:
	ui_paused = !ui_paused


## Call this instead of writing solar_system_active directly so the signal fires.
func set_solar_system_active(v: bool) -> void:
	if solar_system_active == v:
		return
	solar_system_active = v
	active_changed.emit()


## The current speed as a multiple of the base rate: 1, 100, 1e9.
func speed_multiplier() -> float:
	return TIMESCALE_BASE / maxf(seconds_per_day, 1.0e-12)


## Whether individual orbital positions are still worth drawing at the current speed.
## ORBIT_BLUR_ABOVE_MULT itself still draws; anything faster does not.  The small margin absorbs
## the float division above, so the rung that IS 100x is never judged to be 100.000001x.
func orbits_resolvable() -> bool:
	return speed_multiplier() <= ORBIT_BLUR_ABOVE_MULT * 1.001


## Re-derive the orbit rendering state from the current speed.  Fires active_changed when it
## flips, which is what the bodies listen to.
func _refresh_orbit_rendering() -> void:
	set_solar_system_active(orbits_resolvable())
