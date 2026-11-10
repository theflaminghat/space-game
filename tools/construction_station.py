"""Orbital construction station - planet.gd's "station" lane mesh.

buildings.gd: "Docks, gantries and a foundry flying free.  The only manufacturing
capacity that needs no ground under it."

So it is built as a yard rather than a vessel: a keel with the foundry slung under it,
and two open dock hoops on gantry arms above, which is where something is being built.
The hoops are the point - everything else modelled here is closed hull, and an open
frame with nothing inside it reads as a place where work happens.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_KEEL    = (0.56, 0.58, 0.62)   # keel
V_FOUNDRY = (0.72, 0.52, 0.34)   # foundry, running hot
V_HOOP    = (0.88, 0.74, 0.10)   # dock hoops in caution yellow - a marking, not a blanket
V_CABLE   = S.BLACK   # service conduit down the keel
V_LAMP    = (0.95, 0.94, 0.86)   # work floodlights
V_PORT    = S.BLACK   # hatches
V_ARM     = (0.40, 0.41, 0.44)   # gantry arms

parts = []

# Keel, running the length of the station.
parts.append(S.box((0.028, 0.028, 0.190), (0, 0, 0), V_KEEL, bands=[('Z', 93.3)], amp=0.18))

# Foundry, slung under it: the only heavy closed volume on the thing.
parts.append(S.box((0.075, 0.065, 0.055), (0, 0, -0.045), V_FOUNDRY,
                   bands=[('Z', 113.3)], amp=0.20))

# Two dock hoops on gantry arms.  Arms run from inside the keel out past the hoop tube,
# so the frame is continuous rather than a ring floating off a spar.
for z in (0.030, 0.085):
    parts.append(S.torus(0.060, 0.007, (0, 0, z), V_HOOP, major_seg=10, minor_seg=3))
    for i in range(3):
        a = math.radians(120 * i + (0 if z < 0.05 else 60))
        parts.append(S.box((0.057, 0.008, 0.008),
                           (math.cos(a) * 0.0385, math.sin(a) * 0.0385, z),
                           V_ARM, rot=(0, 0, a)))

# Service conduit down the keel, feeding the foundry and both docks.  Run on the outside
# face rather than through the frame: a run nobody can see is not a detail.
parts.append(S.pipe((0.017, 0, -0.088), (0.017, 0, 0.092), 0.0035, V_CABLE))

# Work floodlights on the outboard end of one arm per hoop, aimed into the dock, and the
# foundry's charging hatch.  Lights are what a dock is for at this scale.
for z, a0 in ((0.030, 0.0), (0.085, 60.0)):
    a = math.radians(a0)
    parts.append(S.hatch((math.cos(a) * 0.062, math.sin(a) * 0.062, z), 0.008, V_LAMP,
                         axis=(math.cos(a), math.sin(a), 0), depth=0.007))
parts.append(S.hatch((0.0, -0.033, -0.045), 0.014, V_PORT, axis='Y', depth=0.006))

# Grapple fixtures down the keel, marked so an arm can find them.
for z in (-0.060, 0.060):
    parts.append(S.box((0.012, 0.012, 0.010), (0, -0.016, z), S.RED))

S.finish(parts, "ConstructionStation", out, tex_out, tag="STATION")
