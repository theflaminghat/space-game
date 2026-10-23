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
## The same journey as a scalar, and the AUTHORITATIVE one.
##
## Vector3 is 32-bit per component whatever the engine's own float precision is, so
## star_drift_ly.length() squares the components in float32 and returns `inf` once any of them
## passes about 1.8e19 ly — the stored vector is fine, it is the magnitude that blows up.  A
## thruster held at near-c for 1e19 years covers that, and the run goes to 1e100, so it is
## reachable by simply letting it run: every readout of how far the star had come, and the
## "crossed another light-year" announcement, turned into infinity.
##
## This is a 64-bit float and is what every distance-travelled readout reads.  The vector is
## still the POSITION, because that is what the spatial systems need and what they can use; see
## sol_position() for what happens to it out there.
var star_drift_dist_ly: float = 0.0
## The largest magnitude the POSITION vector is allowed to reach.  Vector3 squares its
## components in 32-bit inside length(), which overflows past ~1.8e19, so the position is held
## below that and saturates there rather than becoming inf and then nan.  Saturating is the
## graceful failure: distances out of it come back enormous but finite, so the map reports
## nothing nearby, where a nan would silently poison every comparison that touched it.
const DRIFT_POSITION_MAX_LY: float = 1.0e18
var star_velocity_ms: float = 0.0
## Unit vector the mirrors push along, and the star it is aimed at ("" for a bare heading).
var star_thrust_dir: Vector3 = Vector3.ZERO
var star_thrust_target: String = ""
## Mirror coverage: the share of the sky the statites cover, derived from what is standing.
var star_mirror_coverage: float = 0.0

## Debug multiplier on the thruster's acceleration — the `shkadov` console command.
##
## A real Shkadov thruster is appallingly slow: a full mirror shell on a 1 L☉ star gives about
## 1e-13 m/s², which is roughly a light-year per hundred million years.  That is the correct
## number and the game should keep it, but it makes the engine impossible to TEST — and
## impossible to see working at all without fast-forwarding past the point where the solar
## system stops being drawn.
##
## Applied to the acceleration rather than to the distance, so the velocity and the position stay
## consistent with each other: it is a bigger engine, not a teleport.  Deliberately not saved and
## reset by reset_star(), because a cheat that survived into a loaded game would silently change
## how that run behaves.
var star_thrust_mult: float = 1.0

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
	star_drift_dist_ly = 0.0
	star_velocity_ms = 0.0
	star_thrust_dir = Vector3.ZERO
	star_thrust_target = ""
	star_mirror_coverage = 0.0
	star_thrust_mult = 1.0
	set_star_mass(1.0)


## True once the star has been altered at all; lets callers skip "engineered" UI on a normal run.
func star_is_engineered() -> bool:
	return not is_equal_approx(star_mass_msun, 1.0) or star_age_offset_years > 0.0 \
		or star_shade_fraction > 0.0 or star_mirror_coverage > 0.0 \
		or star_drift_dist_ly > 0.0


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
##
## A position, not a distance travelled: for that use star_drift_dist_ly, which is 64-bit and
## stays exact however far the engine runs.  This vector is 32-bit per component and saturates
## around 1.8e19 ly, which is nine orders past anything the spatial model has content in — the
## galaxy is 1e5 ly across and the Hubble horizon 1.4e10 — so a star that has gone that far has
## left every catalogue behind and the honest answer to "what is near it" is nothing at all.
func sol_position() -> Vector3:
	return star_drift_ly


## How far the star has travelled, in light-years.  Exact at any magnitude.
func star_distance_travelled_ly() -> float:
	return star_drift_dist_ly


## `pos` advanced by `step` light-years along `dir`, held inside DRIFT_POSITION_MAX_LY.
##
## Both halves of this have to dodge 32-bit overflow, and in the right order.  A single slice in
## fast mode can be 1e100 light-years wide, so `dir * step` on its own puts inf into the vector
## before anything has a chance to clamp it — the step is capped FIRST.  And the magnitude is
## summed from the components as 64-bit doubles rather than read from length(), which squares
## them in 32-bit and returns inf past ~1.8e19; clamping on an infinite length called
## normalized() on an infinite vector and produced nan, which is how the position went from
## merely wrong to poisoning every distance computed against it.
func _clamp_position(pos: Vector3, dir: Vector3, step: float) -> Vector3:
	var capped: float = clampf(step, -DRIFT_POSITION_MAX_LY * 2.0, DRIFT_POSITION_MAX_LY * 2.0)
	var p: Vector3 = pos + dir * capped
	var mag: float = sqrt(float(p.x) * float(p.x) + float(p.y) * float(p.y)
		+ float(p.z) * float(p.z))
	if mag > DRIFT_POSITION_MAX_LY and mag > 0.0:
		p *= DRIFT_POSITION_MAX_LY / mag
	return p


## Aim the thruster along a heading (any non-zero vector; it is normalised here).  Aiming does
## not move the star: the mirrors do, and only while they are standing.
func aim_star_thrust(dir: Vector3, target_name: String = "") -> void:
	if dir.length_squared() <= 0.0:
		return
	star_thrust_dir = dir.normalized()
	star_thrust_target = target_name
	star_changed.emit()


## Push the star for `days` at the current mirror coverage.  Returns the light-years moved.
##
## RELATIVISTIC, because this engine runs for geological time and a Newtonian `v += a*t` does not
## survive that.  A full mirror shell accelerates Sol at ~1e-15 m/s², which sounds harmless and
## reaches c in 9.2e15 years — well inside a run that ends at the heat death.  Measured before
## this was fixed: v/c = 0.108 at 1e15 years and 1.081 at 1e16, i.e. the star went faster than
## light on its own, with no console multiplier involved.
##
## Hyperbolic motion, the standard constant-proper-acceleration result.  Carrying the PROPER
## velocity u = γv is what makes it tractable: under constant a, u grows linearly without bound
## exactly as Newtonian velocity used to, while the coordinate speed v = u/γ approaches c and
## never reaches it.
##
##     u2 = u1 + a·Δt        γ = sqrt(1 + (u/c)²)        v = u/γ
##     Δx = Δt·(u1 + u2) / (γ1 + γ2)
##
## That Δx is the exact integral of v dt across the slice, not an approximation of it: with
## du = a·dt and dγ/du = u/(c²γ), ∫v dt = (1/a)∫(u/γ)du = (c²/a)(γ2 − γ1), and since
## γ2² − γ1² = (u2² − u1²)/c² that rearranges to the form above.  So a slice a billion years wide
## is as accurate as a slice of one day, which matters here — fast mode hands this function
## enormous steps.
##
## The rearrangement is not cosmetic.  Computed as (c²/a)(γ2 − γ1) this returns exactly ZERO at
## ordinary speeds: u/c is around 1e-16 after a year of thrust, so (u/c)² is 1e-32, and
## sqrt(1 + 1e-32) is 1.0 in a double — both gammas are 1 and their difference cancels to
## nothing.  The star simply stopped moving.  The form above never subtracts two near-equal
## numbers, needs no division by a tiny acceleration, and degenerates to the Newtonian
## Δt·(v1 + v2)/2 at low speed, which for constant acceleration is itself exact.
func advance_star_thrust(days: float) -> float:
	if star_mirror_coverage <= 0.0 or days <= 0.0 or star_thrust_dir.length_squared() <= 0.0:
		return 0.0
	var accel: float = StarModel.shkadov_accel_ms2(
		star_mirror_coverage, sun_luminosity_lsun(), star_mass_msun) * maxf(star_thrust_mult, 0.0)
	if accel <= 0.0:
		return 0.0
	var secs: float = days * 86400.0
	var c: float = StarModel.LIGHT_SPEED_MS
	# star_velocity_ms is the COORDINATE speed — what the player is shown and what the save
	# carries — so the proper velocity is recovered from it rather than stored alongside.  The
	# clamp is for a save written before this was fixed, which can hold a superluminal figure
	# that would otherwise take the square root of a negative number.
	var v0: float = clampf(star_velocity_ms, 0.0, c * 0.999999999)
	var u0: float = v0 / sqrt(maxf(1.0 - (v0 / c) * (v0 / c), 1.0e-18))
	var u1: float = u0 + accel * secs
	var g0: float = sqrt(1.0 + (u0 / c) * (u0 / c))
	var g1: float = sqrt(1.0 + (u1 / c) * (u1 / c))
	var moved_m: float = secs * (u0 + u1) / (g0 + g1)
	star_velocity_ms = u1 / g1
	var moved_ly: float = moved_m / StarModel.LY_M
	# Accumulated separately and in full precision, so the figure the player is shown never
	# depends on whether a Vector3 can still hold it.
	star_drift_dist_ly += moved_ly
	# Past DRIFT_POSITION_MAX_LY the two deliberately part company: star_drift_dist_ly goes on
	# counting the real journey, and the position stops at the edge of what a 32-bit coordinate
	# can hold.  Nothing is lost that the spatial model could have used — the galaxy is 1e5 ly
	# across and the Hubble horizon 1.4e10, so a star a billion billion light-years out has left
	# every catalogue behind and "nothing is near it" is the true answer at any larger number.
	star_drift_ly = _clamp_position(star_drift_ly, star_thrust_dir, moved_ly)
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
