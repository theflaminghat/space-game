class_name LaunchPlanner

## Pure, stateless launch math — the single source of truth for trajectory cost and
## time, shared by the interactive LaunchPanel and the AutomationPanel's executor so
## the two can never drift.  Every function is static and takes the world state it
## needs (orbital angles, multipliers) as arguments rather than reading any UI.
##
## A launch is a constant-acceleration (brachistochrone) transfer; the chosen fuel
## fixes the acceleration.  Costs scale with the trajectory's Δv budget and how well
## the launch window is phased.

## Orbit radii (AU) for every launch endpoint.  The Sun is a close solar orbit
## (Parker-probe class) — shedding Earth's orbital speed to fall in makes it costly.
const PLANET_ORBIT_AU := {
	"Mercury": 0.387, "Venus": 0.723, "Earth": 1.0,   "Mars": 1.524,
	"Jupiter": 5.203, "Saturn": 9.537, "Uranus": 19.191, "Neptune": 30.069,
	"Sun": 0.05,
}

const AU_METERS:        float = 1.495978707e11
const LIGHT_SPEED:      float = 2.998e8    # m/s
const LOCAL_ORBIT_DAYS: int   = 30         # surface-to-orbit insertion baseline
const V_EARTH_KMS:      float = 29.78      # circular heliocentric speed at 1 AU
const SURFACE_TO_ORBIT_DV: float = 9.0     # Δv every launch pays; the 1.0× baseline
const PHASE_ENERGY_WEIGHT: float = 1.0     # extra fuel a worst-case window adds

static func orbit_au(name: String) -> float:
	return float(PLANET_ORBIT_AU.get(name, 1.0))

## Mean motion (rad/day) of a circular orbit at semi-major axis a_au.
static func mean_motion(a_au: float) -> float:
	return TAU / (365.25 * pow(a_au, 1.5))

## Heliocentric Hohmann transfer Δv (km/s) between two circular orbits (AU).
static func hohmann_delta_v(r1: float, r2: float) -> float:
	if is_equal_approx(r1, r2):
		return 0.0
	var vc1: float = V_EARTH_KMS / sqrt(r1)
	var vc2: float = V_EARTH_KMS / sqrt(r2)
	var dv1: float = absf(vc1 * (sqrt(2.0 * r2 / (r1 + r2)) - 1.0))
	var dv2: float = absf(vc2 * (1.0 - sqrt(2.0 * r1 / (r1 + r2))))
	return dv1 + dv2

## Cost multiplier from the trajectory's total Δv vs a bare surface-to-orbit launch.
static func difficulty_factor(origin: String, target: String) -> float:
	var total_dv: float = SURFACE_TO_ORBIT_DV \
		+ hohmann_delta_v(orbit_au(origin), orbit_au(target))
	return total_dv / SURFACE_TO_ORBIT_DV

## Straight-line distance the ship crosses (AU): the live separation between origin and
## target at the chosen start offset, falling back to a representative separation.
static func transfer_distance_au(origin: String, target: String,
		angles: Dictionary, offset_days: float) -> float:
	var r1: float = orbit_au(origin)
	var r2: float = orbit_au(target)
	var ol := origin.to_lower()
	var tl := target.to_lower()
	if angles.has(ol) and angles.has(tl):
		var a1: float = float(angles[ol]) + mean_motion(r1) * offset_days
		var a2: float = float(angles[tl]) + mean_motion(r2) * offset_days
		var p1 := Vector2(r1 * sin(a1), r1 * cos(a1))
		var p2 := Vector2(r2 * sin(a2), r2 * cos(a2))
		return maxf(p1.distance_to(p2), 0.001)
	return maxf((r1 + r2 + absf(r2 - r1)) * 0.5, 0.001)

## Launch-window energy multiplier (≥ 1.0): how far the real planet configuration at
## departure is from the ideal Hohmann phase.  1.0 when origin == target.
static func path_energy_factor(origin: String, target: String,
		angles: Dictionary, offset_days: float) -> float:
	if origin == target:
		return 1.0
	var ol := origin.to_lower()
	var tl := target.to_lower()
	if not (angles.has(ol) and angles.has(tl)):
		return 1.0
	var a1: float = orbit_au(origin)
	var a2: float = orbit_au(target)
	var ang1: float = float(angles[ol]) + mean_motion(a1) * offset_days
	var ang2: float = float(angles[tl]) + mean_motion(a2) * offset_days
	var ideal_lead: float = PI * (1.0 - pow((a1 + a2) / (2.0 * a2), 1.5))
	var lead: float  = fposmod(ang2 - ang1, TAU)
	var ideal: float = fposmod(ideal_lead, TAU)
	var diff: float = absf(lead - ideal)
	diff = minf(diff, TAU - diff)
	return 1.0 + PHASE_ENERGY_WEIGHT * (diff / PI)

## Transit time in days.  Local orbit insertion (origin == target) is a fixed
## baseline; an interplanetary transfer is a brachistochrone floored at light-time.
## `dur_mult` folds in origin infrastructure + policy duration discounts.
static func duration_days(origin: String, target: String, arrival: String,
		accel: float, angles: Dictionary, offset_days: float, dur_mult: float) -> int:
	if origin == target:
		if arrival == "orbit":
			return maxi(1, int(round(LOCAL_ORBIT_DAYS * dur_mult)))
		return 0
	var d_m: float = transfer_distance_au(origin, target, angles, offset_days) * AU_METERS
	var t_s: float = maxf(2.0 * sqrt(d_m / accel), d_m / LIGHT_SPEED)
	return maxi(1, int(round(t_s / 86400.0 * dur_mult)))

## True when a transfer is pinned at the light-travel-time floor (for UI tagging).
static func is_light_limited(origin: String, target: String, accel: float,
		angles: Dictionary, offset_days: float) -> bool:
	var d_m: float = transfer_distance_au(origin, target, angles, offset_days) * AU_METERS
	return 2.0 * sqrt(d_m / accel) <= d_m / LIGHT_SPEED

## Rockets (vehicle mass) a mission needs: base × Δv difficulty × origin cost discount.
static func rockets(mission_idx: int, origin: String, target: String, cost_mult: float) -> int:
	var base: float = float(MissionData.MISSION_TYPES[mission_idx].get("rockets", 1))
	return maxi(1, int(ceil(base * difficulty_factor(origin, target) * cost_mult)))

## Fuel units a mission burns: base × Δv difficulty × launch-window factor × discount.
static func fuel(mission_idx: int, origin: String, target: String,
		angles: Dictionary, offset_days: float, cost_mult: float) -> int:
	var base: float = float(MissionData.MISSION_TYPES[mission_idx].get("fuel", 0))
	var f: float = base * difficulty_factor(origin, target) \
		* path_energy_factor(origin, target, angles, offset_days) * cost_mult
	return maxi(0, int(ceil(f)))
