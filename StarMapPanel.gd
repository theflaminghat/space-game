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
## Launch a von Neumann berserker swarm at a star system (a slower self-replicating weapon).
signal berserker_requested(star_name: String)

## Laser energy scales with distance² (the beam spreads, so delivering a lethal flux
## across light-years costs enormously more).  Shared with Game for the cost readout.
const LASER_ENERGY_PER_LY2: float = 5.0e7
## Berserker swarm cruise speed (fraction of c) — slow, but self-replicating on arrival.
const BERSERKER_BETA: float = 0.3

static func laser_energy(dist_ly: float) -> float:
	return LASER_ENERGY_PER_LY2 * dist_ly * dist_ly

# ── Relativistic flight model (shared with Game so cost/time match what's shown) ──
# A colony ship accelerates at its chosen max acceleration `a` up to its max speed β,
# coasts, then decelerates to arrive at rest.  Over short interstellar hops a low
# acceleration may run out of distance before reaching β — then it peaks lower.  The
# energy is the ship's relativistic kinetic energy, paid twice (speed up + slow down).
const C_MS: float    = 2.998e8      # m/s
const LY_M: float    = 9.4607e15    # metres per light-year
const YEAR_S: float  = 3.1557e7     # seconds per year
## Speed is parameterised by the Lorentz factor γ (not β), so the player can dial in
## arbitrarily relativistic cruise speeds — right up to the GZK limit — without β losing
## all precision against 1.0.  The GZK cutoff (~5×10¹⁹ eV protons) is γ ≈ E/(m_p c²).
const GZK_GAMMA: float = 5.3e10
## Standard colony-ship rest mass (kg) and the factor converting real joules to the
## game's energy units — both tuned so a near-c dash needs a built-out grid's reserves.
const SHIP_MASS: float           = 2.0e7
const ENERGY_GAME_PER_JOULE: float = 5.0e-17

## β (fraction of c) for a Lorentz factor γ.  Saturates to 1.0 in float for huge γ.
static func beta_from_gamma(g: float) -> float:
	return sqrt(maxf(1.0 - 1.0 / (g * g), 0.0))

## Plan a flight of `dist_ly` light-years with max Lorentz factor γ (cruise speed) and
## max acceleration `a` (m/s²): accelerate to γ, coast, decelerate to rest.  Returns the
## game-energy required, Sol-frame travel time (years), the peak β/γ actually reached,
## and whether the requested γ was hit (short hops at low accel fall short).
static func plan_flight(dist_ly: float, gamma_max: float, accel: float) -> Dictionary:
	var dist_m: float = maxf(dist_ly, 1.0e-4) * LY_M
	var a: float = maxf(accel, 1.0e-4)
	var gv: float = clampf(gamma_max, 1.0001, GZK_GAMMA)
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
	# Energy = relativistic KE at peak, spent on the burn AND the matching deceleration.
	var joules: float = 2.0 * (g_peak - 1.0) * SHIP_MASS * C_MS * C_MS
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
	{"name": "Proxima Centauri", "pos": Vector3(-1.55, -1.18, -3.77), "dist": 4.25, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Alpha Centauri A", "pos": Vector3(-1.63, -1.36, -3.81), "dist": 4.37, "spectral": "G", "color": Color(1.0, 0.93, 0.66)},
	{"name": "Alpha Centauri B", "pos": Vector3(-1.63, -1.36, -3.81), "dist": 4.37, "spectral": "K", "color": Color(1.0, 0.8, 0.55)},
	{"name": "Barnard's Star", "pos": Vector3(-0.06, -5.94, 0.49), "dist": 5.96, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Wolf 359", "pos": Vector3(-7.50, 2.13, 0.96), "dist": 7.86, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Lalande 21185", "pos": Vector3(-6.52, 1.65, 4.88), "dist": 8.31, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Sirius", "pos": Vector3(-1.62, 8.13, -2.49), "dist": 8.66, "spectral": "A", "color": Color(0.82, 0.88, 1.0)},
	{"name": "Luyten 726-8", "pos": Vector3(7.54, 3.48, -2.69), "dist": 8.73, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Ross 154", "pos": Vector3(1.91, -8.66, -3.92), "dist": 9.69, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Ross 248", "pos": Vector3(7.37, -0.58, 7.18), "dist": 10.30, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Epsilon Eridani", "pos": Vector3(6.18, 8.28, -1.72), "dist": 10.47, "spectral": "K", "color": Color(1.0, 0.8, 0.55)},
	{"name": "Lacaille 9352", "pos": Vector3(8.46, -2.04, -6.29), "dist": 10.74, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Ross 128", "pos": Vector3(-10.98, 0.59, 0.15), "dist": 11.00, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "61 Cygni", "pos": Vector3(6.47, -6.09, 7.14), "dist": 11.40, "spectral": "K", "color": Color(1.0, 0.8, 0.55)},
	{"name": "Procyon", "pos": Vector3(-4.79, 10.36, 1.04), "dist": 11.46, "spectral": "F", "color": Color(1.0, 1.0, 0.94)},
	{"name": "Epsilon Indi", "pos": Vector3(5.68, -3.17, -9.93), "dist": 11.87, "spectral": "K", "color": Color(1.0, 0.8, 0.55)},
	{"name": "Tau Ceti", "pos": Vector3(10.29, 5.02, -3.27), "dist": 11.91, "spectral": "G", "color": Color(1.0, 0.93, 0.66)},
	{"name": "Gliese 581", "pos": Vector3(-13.03, -15.45, -2.74), "dist": 20.40, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	# ── More nearby red dwarfs ────────────────────────────────────────────────
	{"name": "40 Eridani", "pos": Vector3(7.14, 14.53, -2.18), "dist": 16.34, "spectral": "K", "color": Color(1.0, 0.80, 0.55)},
	{"name": "Kapteyn's Star", "pos": Vector3(1.90, 8.87, -9.07), "dist": 12.83, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Lacaille 8760", "pos": Vector3(7.44, -6.80, -8.13), "dist": 12.95, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Kruger 60", "pos": Vector3(6.47, -2.75, 11.11), "dist": 13.15, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	# ── Bright naked-eye stars (tens to hundreds of ly) ───────────────────────
	{"name": "Altair", "pos": Vector3(7.68, -14.64, 2.58), "dist": 16.73, "spectral": "A", "color": Color(0.85, 0.90, 1.0)},
	{"name": "Vega", "pos": Vector3(3.13, -19.27, 15.68), "dist": 25.04, "spectral": "A", "color": Color(0.85, 0.90, 1.0)},
	{"name": "Fomalhaut", "pos": Vector3(21.04, -5.87, -12.42), "dist": 25.13, "spectral": "A", "color": Color(0.85, 0.90, 1.0)},
	{"name": "Pollux", "pos": Vector3(-13.23, 26.73, 15.87), "dist": 33.78, "spectral": "K", "color": Color(1.0, 0.80, 0.55)},
	{"name": "Arcturus", "pos": Vector3(-28.73, -19.32, 12.05), "dist": 36.66, "spectral": "K", "color": Color(1.0, 0.80, 0.55)},
	{"name": "Capella", "pos": Vector3(5.60, 29.29, 30.87), "dist": 42.92, "spectral": "G", "color": Color(1.0, 0.93, 0.66)},
	{"name": "Castor", "pos": Vector3(-17.37, 39.67, 26.94), "dist": 51.0, "spectral": "A", "color": Color(0.85, 0.90, 1.0)},
	{"name": "Aldebaran", "pos": Vector3(22.43, 58.38, 18.54), "dist": 65.23, "spectral": "K", "color": Color(1.0, 0.80, 0.55)},
	{"name": "Regulus", "pos": Vector3(-68.55, 36.31, 16.44), "dist": 79.3, "spectral": "B", "color": Color(0.80, 0.87, 1.0)},
	{"name": "Mizar", "pos": Vector3(-44.48, -17.06, 67.85), "dist": 82.9, "spectral": "A", "color": Color(0.85, 0.90, 1.0)},
	{"name": "Spica", "pos": Vector3(-228.52, -89.09, -48.39), "dist": 250.0, "spectral": "B", "color": Color(0.80, 0.87, 1.0)},
	{"name": "Polaris", "pos": Vector3(4.39, 3.42, 432.96), "dist": 433.0, "spectral": "F", "color": Color(1.0, 1.0, 0.94)},
	{"name": "Betelgeuse", "pos": Vector3(11.45, 543.31, 70.65), "dist": 548.0, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Antares", "pos": Vector3(-189.65, -454.53, -244.82), "dist": 550.0, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Rigel", "pos": Vector3(167.74, 834.51, -122.69), "dist": 860.0, "spectral": "B", "color": Color(0.80, 0.87, 1.0)},
	{"name": "Deneb", "pos": Vector3(1191.51, -1402.13, 1858.11), "dist": 2615.0, "spectral": "A", "color": Color(0.85, 0.90, 1.0)},
]

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

const ROT_SENS:  float = 0.01    # radians of rotation per pixel dragged
const MIN_PITCH: float = -1.45   # ~ ±83° — stop short of gimbal flip at the poles
const MAX_PITCH: float =  1.45
const ZOOM_STEP: float = 1.12
const ZOOM_MIN:  float = 0.4
const ZOOM_MAX:  float = 80.0    # deep zoom needed: the scale spans ~10 decades of ly
const PICK_PX:   float = 16.0    # click tolerance for selecting a star
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
var _pitch: float = 0.5
var _zoom:  float = 1.0
var _selected: int = -1

var _dragging:   bool = false
var _drag_moved: bool = false
var _last_mouse: Vector2 = Vector2.ZERO

var _font: Font

## GALAXIES with their equatorial coords resolved to cartesian "pos" (built in _ready).
var _galaxies: Array = []

## Interstellar state pushed by Game.gd.
var _colonized: Dictionary = {}      # star name → true
var _factions: Dictionary = {}       # star name → "aggressive" | "peaceful"
var _missions: Array = []            # [{ "target": name, "progress": 0..1 }]
var _avail_energy: float = 0.0       # current energy, for the launch affordability readout
var _dash_phase: float = 0.0         # animates the travel-line dashes
var _cosmic_scale: float = 1.0       # proper-distance multiplier for unbound galaxies (≥1)
var _attacks: Array = []             # [{ "target": name, "progress": 0..1, "kind": "laser"|"berserker" }]
var _can_laser: bool = false         # an Orbital Laser is built
var _can_berserker: bool = false     # von Neumann (self-replicating industry) researched

## Launch sub-panel (built in _ready, shown when a colonisable star is selected).
var _launch_ui:     PanelContainer = null
var _launch_title:  Label   = null
var _speed_slider:  HSlider = null
var _accel_slider:  HSlider = null   # log₁₀ of max acceleration in m/s²
var _launch_info:   Label   = null
var _launch_btn:    Button  = null
var _laser_power_slider: HSlider = null   # laser energy multiplier (≥1)
var _laser_btn:     Button  = null
var _berserker_btn: Button  = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL
	# Clip all drawing (stars/labels/lines projected beyond the edges) to the panel rect
	# so nothing bleeds outside the star map into the rest of the UI.
	clip_contents = true
	_font = ThemeDB.fallback_font
	_build_galaxies()
	_build_launch_ui()
	resized.connect(queue_redraw)

## Build the bottom-docked launch sub-panel (speed slider + Launch button).
func _build_launch_ui() -> void:
	_launch_ui = PanelContainer.new()
	# Docked bottom-right and lifted off the bottom edge, clear of the bottom-left planet
	# column and the lower edge of the panel.
	_launch_ui.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_launch_ui.offset_left = -480
	_launch_ui.offset_right = -96
	_launch_ui.offset_top = -184
	_launch_ui.offset_bottom = -56
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

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 8)
	var sl := Label.new()
	sl.text = "Max speed"
	sl.custom_minimum_size = Vector2(86, 0)
	sl.add_theme_font_size_override("font_size", 11)
	speed_row.add_child(sl)
	# Cruise speed as log₁₀(γ−1): from γ≈1.001 up to the GZK limit (γ ≈ 5.3×10¹⁰), so the
	# player can request arbitrarily relativistic speeds — energy/accel are the real cap.
	_speed_slider = HSlider.new()
	_speed_slider.min_value = -3.0
	_speed_slider.max_value = log(GZK_GAMMA - 1.0) / log(10.0)
	_speed_slider.step = 0.05
	_speed_slider.value = -1.0    # γ ≈ 1.1
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.value_changed.connect(func(_v): _update_launch_ui())
	speed_row.add_child(_speed_slider)
	vb.add_child(speed_row)

	# Max acceleration — log scale (m/s²); the ship thrusts at this until it hits max
	# speed (or runs out of distance).  Higher accel reaches cruise sooner = faster trip.
	var accel_row := HBoxContainer.new()
	accel_row.add_theme_constant_override("separation", 8)
	var al := Label.new()
	al.text = "Max accel"
	al.custom_minimum_size = Vector2(86, 0)
	al.add_theme_font_size_override("font_size", 11)
	accel_row.add_child(al)
	_accel_slider = HSlider.new()
	_accel_slider.min_value = -3.0    # 10^-3 = 0.001 m/s²
	_accel_slider.max_value = 4.0     # 10^4 = 10 000 m/s² (~1000 g) — needed to approach
	                                  # high γ over short interstellar hops
	_accel_slider.step = 0.05
	_accel_slider.value = -1.0        # 0.1 m/s² ≈ 0.01 g
	_accel_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accel_slider.value_changed.connect(func(_v): _update_launch_ui())
	accel_row.add_child(_accel_slider)
	vb.add_child(accel_row)

	_launch_info = Label.new()
	_launch_info.add_theme_font_size_override("font_size", 11)
	_launch_info.modulate = Color(0.75, 0.82, 0.95)
	vb.add_child(_launch_info)

	_launch_btn = Button.new()
	_launch_btn.text = "Launch colony ship"
	_launch_btn.pressed.connect(_on_launch_pressed)
	vb.add_child(_launch_btn)

	# ── Weapons ──────────────────────────────────────────────────────────────
	var power_row := HBoxContainer.new()
	power_row.add_theme_constant_override("separation", 8)
	var pl := Label.new()
	pl.text = "Laser power"
	pl.custom_minimum_size = Vector2(86, 0)
	pl.add_theme_font_size_override("font_size", 11)
	power_row.add_child(pl)
	_laser_power_slider = HSlider.new()
	_laser_power_slider.min_value = 1.0     # at least full base energy to be lethal
	_laser_power_slider.max_value = 10.0    # overcharge for a bigger, brighter pulse
	_laser_power_slider.step = 0.5
	_laser_power_slider.value = 1.0
	_laser_power_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_laser_power_slider.value_changed.connect(func(_v): _update_launch_ui())
	power_row.add_child(_laser_power_slider)
	vb.add_child(power_row)

	var weapons := HBoxContainer.new()
	weapons.add_theme_constant_override("separation", 6)
	_laser_btn = Button.new()
	_laser_btn.text = "Fire laser"
	_laser_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_laser_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.9))
	_laser_btn.pressed.connect(_on_laser_pressed)
	weapons.add_child(_laser_btn)
	_berserker_btn = Button.new()
	_berserker_btn.text = "Send berserkers"
	_berserker_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_berserker_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	_berserker_btn.pressed.connect(_on_berserker_pressed)
	weapons.add_child(_berserker_btn)
	vb.add_child(weapons)

## Animate the in-transit dashed lines + attack pulses while the map is visible.
func _process(delta: float) -> void:
	if visible and (not _missions.is_empty() or not _attacks.is_empty()):
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

## Push the cosmic scale factor (≥1) from Game — proper distance of unbound galaxies
## grows by this as the universe ages.
func set_cosmic_scale(s: float) -> void:
	var ns := maxf(s, 1.0)
	if not is_equal_approx(ns, _cosmic_scale):
		_cosmic_scale = ns
		queue_redraw()

## Equatorial (RA hours, Dec degrees, distance) → cartesian light-years.
func _equatorial_to_xyz(ra_h: float, dec_deg: float, dist_ly: float) -> Vector3:
	var ra := deg_to_rad(ra_h * 15.0)
	var dec := deg_to_rad(dec_deg)
	return Vector3(
		dist_ly * cos(dec) * cos(ra),
		dist_ly * cos(dec) * sin(ra),
		dist_ly * sin(dec))

# ── Public API ────────────────────────────────────────────────────────────────

## Name of the currently selected star, or "" if none.
func selected_star() -> String:
	return str(STARS[_selected]["name"]) if _selected >= 0 else ""

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

## Push which weapons are available (Orbital Laser built / berserkers researched).
func set_weapon_caps(can_laser: bool, can_berserker: bool) -> void:
	_can_laser = can_laser
	_can_berserker = can_berserker
	_update_launch_ui()

## Distance (ly) of the selected star, or 0.
func _selected_dist() -> float:
	return float(STARS[_selected]["dist"]) if _selected >= 0 else 0.0

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
	var dist: float = _selected_dist()
	if _colonized.has(name):
		_launch_title.text = "%s  —  colonised" % name
		_launch_info.text = "A human colony already orbits this star."
		_launch_btn.disabled = true
		_launch_btn.text = "Colonised"
		_update_weapon_buttons(dist, true)
		return
	var gamma: float = _selected_gamma()
	var accel: float = _selected_accel()
	var plan: Dictionary = StarMapPanel.plan_flight(dist, gamma, accel)
	var cost: float = float(plan["energy"])
	var years: float = float(plan["years"])
	_launch_title.text = "%s  —  %.2f ly" % [name, dist]
	var speed_str: String = _fmt_speed(gamma)
	if not bool(plan["reaches"]):
		speed_str += "  (peaks %s, range-limited)" % _fmt_speed(float(plan["peak_gamma"]))
	_launch_info.text = "%s  ·  %s  ·  %s travel  ·  %s energy %s" % [
		speed_str, _fmt_accel(accel), _fmt_years(years), Units.format_si(cost, "J"),
		"" if cost <= _avail_energy else "  ✗ insufficient"]
	var affordable := cost <= _avail_energy
	_launch_btn.disabled = not affordable
	_launch_btn.text = "Launch colony ship" if affordable else "Not enough energy"
	_update_weapon_buttons(dist, false)

## Enable/label the laser + berserker buttons for the current target.
func _update_weapon_buttons(dist: float, colonised: bool) -> void:
	if _laser_btn == null:
		return
	if colonised:
		_laser_btn.disabled = true
		_laser_btn.text = "Fire laser"
		_berserker_btn.disabled = true
		_berserker_btn.text = "Send berserkers"
		return
	if not _can_laser:
		_laser_btn.disabled = true
		_laser_btn.text = "Laser — build one"
	else:
		var lc: float = StarMapPanel.laser_energy(dist) * _laser_power()
		var ok: bool = lc <= _avail_energy
		_laser_btn.disabled = not ok
		_laser_btn.text = "Fire laser ×%.1f (%s)" % [_laser_power(), Units.format_si(lc, "J")] if ok \
			else "Laser ×%.1f — need %s" % [_laser_power(), Units.format_si(lc, "J")]
	if not _can_berserker:
		_berserker_btn.disabled = true
		_berserker_btn.text = "Berserkers — research"
	else:
		_berserker_btn.disabled = false
		_berserker_btn.text = "Send berserkers"

## Laser energy multiplier from the power slider (≥1).
func _laser_power() -> float:
	return _laser_power_slider.value if _laser_power_slider else 1.0

func _on_laser_pressed() -> void:
	var n := selected_star()
	if n != "" and not _colonized.has(n):
		laser_requested.emit(n, _laser_power())

func _on_berserker_pressed() -> void:
	var n := selected_star()
	if n != "" and not _colonized.has(n):
		berserker_requested.emit(n)

## Speed readout from γ: "% c" while it's meaningful, then γ (with a GZK-limit flag).
func _fmt_speed(g: float) -> String:
	if g < 100.0:
		return "%.2f%% c" % (beta_from_gamma(g) * 100.0)
	var s := "γ %s" % Units.format_si(g, "")
	if g >= GZK_GAMMA * 0.5:
		s += " (GZK limit)"
	return s

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

func _on_launch_pressed() -> void:
	var name := selected_star()
	if name == "" or _colonized.has(name):
		return
	colonize_requested.emit(name, _selected_gamma(), _selected_accel())

## Index of a star by name (-1 if not found).
func _star_index(name: String) -> int:
	for i in range(STARS.size()):
		if str(STARS[i]["name"]) == name:
			return i
	return -1

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
	for s: Dictionary in STARS:
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

## Orthographic projection of a world point onto the camera's right/up axes.
func _project(p: Vector3, b: Basis, center: Vector2, scale: float) -> Vector2:
	return center + Vector2(p.dot(b.x), -p.dot(b.y)) * scale

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
	draw_string(_font, _project(Vector3(horizon_rd, 0.0, 0.0), b, center, scale) + Vector2(3, -3),
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
		var glp := _log_pos(gpos)
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

	# Stars, far-to-near so nearer ones overlap on top (depth uses log positions).
	var order: Array = range(STARS.size())
	order.sort_custom(func(i: int, j: int) -> bool:
		return _depth(_log_pos(STARS[i]["pos"]), b) < _depth(_log_pos(STARS[j]["pos"]), b))

	for i: int in order:
		var s: Dictionary = STARS[i]
		var lp: Vector3 = _log_pos(s["pos"])
		var sp := _project(lp, b, center, scale)
		# A selected star always keeps its name + line at full opacity so you can see
		# what's chosen; everything else fades in/out with the view radius.
		var alpha := 1.0 if i == _selected else _detail_alpha(lp.length())
		if alpha > 0.0:
			# Drop line to the reference plane conveys the star's height above/below it.
			var foot := _project(Vector3(lp.x, lp.y, 0.0), b, center, scale)
			draw_line(foot, sp, _fade(DROP_COLOR, alpha), 1.0)
			draw_circle(foot, 1.5, _fade(DROP_COLOR, alpha))

		# Stars shrink with distance from Sol (perspective): near = bigger, far = smaller.
		var dist_frac := clampf(lp.length() / star_maxdr, 0.0, 1.0)
		var rad := lerpf(6.0, 2.2, dist_frac)
		var col: Color = s["color"]
		if i == _selected:
			draw_circle(sp, rad + 6.0, Color(1.0, 1.0, 1.0, 0.22), true, -1.0, true)
			draw_arc(sp, rad + 6.0, 0.0, TAU, 40, Color(0.9, 0.95, 1.0, 0.9), 1.5, true)
		_draw_soft_star(sp, rad, col)
		# Alien presence highlight: red glow/ring for an aggressive force, blue for a
		# peaceful one (always named so the player can see who's out there).
		var fac: String = str(_factions.get(str(s["name"]), ""))
		if fac == "aggressive":
			draw_circle(sp, rad + 3.0, Color(1.0, 0.30, 0.30, 0.28))
			draw_arc(sp, rad + 5.5, 0.0, TAU, 32, Color(1.0, 0.35, 0.35, 0.95), 2.0, true)
		elif fac == "peaceful":
			draw_circle(sp, rad + 3.0, Color(0.40, 0.60, 1.0, 0.28))
			draw_arc(sp, rad + 5.5, 0.0, TAU, 32, Color(0.50, 0.70, 1.0, 0.95), 2.0, true)
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
			if colonised:
				lbl_col = Color(0.6, 0.95, 0.7, 0.95)
			var la: float = 1.0 if (i == _selected or always) else alpha
			draw_string(_font, sp + Vector2(rad + 4.0, 4.0), str(s["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _fade(lbl_col, la))

	# In-transit colony missions: an animated dashed line from Sol to the target star,
	# with dashes flowing toward the destination and a marker at the ship's progress.
	for m: Dictionary in _missions:
		var idx := _star_index(str(m.get("target", "")))
		if idx < 0:
			continue
		var dst := _project(_log_pos(STARS[idx]["pos"]), b, center, scale)
		_draw_travel_dashes(center, dst, float(m.get("progress", 0.0)))

	# In-flight attacks: a white laser pulse racing out at light speed, or a red von
	# Neumann berserker swarm crawling toward its target.
	for atk: Dictionary in _attacks:
		var aidx := _star_index(str(atk.get("target", "")))
		if aidx < 0:
			continue
		var adst := _project(_log_pos(STARS[aidx]["pos"]), b, center, scale)
		var ap := float(atk.get("progress", 0.0))
		if str(atk.get("kind", "")) == "laser":
			_draw_laser_pulse(center, adst, ap, float(atk.get("power", 1.0)))
		else:
			_draw_berserker_swarm(center, adst, ap)

	# The Sun, fixed at the centre of the map.
	draw_circle(center, 10.0, Color(1.0, 0.85, 0.3, 0.22))
	draw_circle(center, 5.5, Color(1.0, 0.9, 0.42))
	draw_string(_font, center + Vector2(9, -6), "Sol", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.92, 0.6))

	# Title + controls hint.
	draw_string(_font, Vector2(14, 24), "Star Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.95, 1.0))
	draw_string(_font, Vector2(14, 42), "Drag to rotate  ·  scroll to zoom  ·  click a star to select",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.68, 0.8))
	draw_string(_font, Vector2(14, 58), "Log scale · rings = orders of magnitude (ly) · out to the Hubble horizon",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.58, 0.72))
	# Cosmic expansion readout — once space has stretched noticeably.
	if _cosmic_scale > 1.01:
		draw_string(_font, Vector2(14, 74),
			"Cosmic expansion ×%s — unbound galaxies receding" % Units.format_si(_cosmic_scale, ""),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 0.55, 0.62))

	# Selected-star info box.
	if _selected >= 0:
		var s: Dictionary = STARS[_selected]
		var lines: Array = [str(s["name"]),
			"%.2f light-years" % float(s["dist"]),
			"Spectral type %s" % str(s["spectral"])]
		var sfac: String = str(_factions.get(str(s["name"]), ""))
		if sfac == "aggressive":
			lines.append("⚠ Aggressive alien force")
		elif sfac == "peaceful":
			lines.append("◇ Peaceful alien contact")
		var box := Rect2(Vector2(12, size.y - (16.0 * lines.size() + 16.0) - 12.0),
			Vector2(248, 16.0 * lines.size() + 16.0))
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

## Pick the nearest projected star to the click, within PICK_PX pixels.
func _try_select(mouse: Vector2) -> void:
	var center: Vector2 = size * 0.5
	var b := _view_basis()
	var scale := _fit_scale(center)
	var best: int = -1
	var best_d: float = PICK_PX
	for i in range(STARS.size()):
		var dd := _project(_log_pos(STARS[i]["pos"]), b, center, scale).distance_to(mouse)
		if dd < best_d:
			best_d = dd
			best = i
	_selected = best
	_update_launch_ui()
	queue_redraw()
	star_selected.emit(selected_star())
