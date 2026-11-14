"""Orbital compute core - planet.gd's "compute_core" lane mesh.

buildings.gd: server modules flown in orbit, "cooled by their own radiators".

A computer in vacuum is a heat problem with some logic attached, so the model is the two
halves of that sentence and the link that makes it worth building:

  * The CORE is a dark rack block, gridded fine on every face - the one hull in the band
    that is all doors and no plating.  Two teal coolant collars ring it, the only cool
    colour on it, so it never reads as a dark battery slab.
  * The RADIATORS are two WHITE wings, edge-on to the radial axis.  Every other radiator
    in the band is gold; these are the white panels a station carries for its own
    electronics, and white is what separates them from the telescope's blue cells and the
    radiator array's six gold fins.  Copper risers run their inner edges and the struts
    that carry them are the coolant lines themselves.
  * The DISH on the outward end is the data link: what a compute core is for is answers,
    and answers have to get home.

A power module squats on the inward end, which is also what keeps the bounds centred: the
dish alone would push the middle of the box well outward of the lane.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_RACK   = (0.22, 0.25, 0.30)   # rack doors - the core
V_COLLAR = (0.18, 0.64, 0.68)   # teal coolant collars
V_RAD    = (0.86, 0.87, 0.88)   # white radiator wings
V_LINE   = (0.76, 0.48, 0.27)   # copper coolant lines
V_POWER  = (0.54, 0.56, 0.60)   # power conditioning module
V_DISH   = (0.84, 0.86, 0.90)   # data-link dish

parts = []

# The core: a rack block, its doors gridded on every face.
parts.append(S.box((0.084, 0.084, 0.150), (0, 0, 0), V_RACK,
                   bands=[('Z', 180.0), ('X', 220.0), ('Y', 220.0)], amp=0.40))

# Coolant collars, standing just proud of the rack.
for z in (-0.040, 0.040):
    parts.append(S.box((0.090, 0.090, 0.008), (0, 0, z), V_COLLAR))

# Radiator wings, one off each side, lying in the plane of the radial axis so they are
# edge-on to whatever they orbit.  The struts are coolant lines: they run from a collar
# out to a riser up each wing's inner edge.
for sx in (-1, 1):
    parts.append(S.box((0.100, 0.004, 0.140), (sx * 0.110, 0, 0), V_RAD,
                       bands=[('X', 300.0)], amp=0.22))
    parts.append(S.pipe((sx * 0.060, 0, -0.066), (sx * 0.060, 0, 0.066), 0.0035, V_LINE))
    for z in (-0.040, 0.040):
        parts.append(S.pipe((sx * 0.044, 0, z), (sx * 0.062, 0, z), 0.0040, V_LINE))

# Power module on the inward end.
parts.append(S.cyl(0.032, 0.022, (0, 0, -0.085), V_POWER, segments=10,
                   bands=[('Z', 200.0)], amp=0.16))

# Data link on the outward end: a mast, a dish opening outward, and its feed.
parts.append(S.cyl(0.006, 0.016, (0, 0, 0.082), V_POWER))
parts.append(S.cone(0.008, 0.040, 0.012, (0, 0, 0.095), V_DISH, segments=14))
parts.append(S.pipe((0, 0, 0.096), (0, 0, 0.114), 0.0030, S.BLACK))

# The data trunk down one face, dish to power module, and the marked shutdown on the other.
parts.append(S.pipe((0, 0.044, -0.080), (0, 0.044, 0.078), 0.0030, S.BLACK))
parts.append(S.hatch((0, -0.042, 0), 0.010, S.RED, axis='Y', depth=0.006))

S.finish(parts, "OrbitalComputeCore", out, tex_out, tag="COMPUTE")
