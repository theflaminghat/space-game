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

V_KEEL, V_FOUNDRY, V_HOOP, V_ARM = 0.55, 0.70, 0.62, 0.48

parts = []

# Keel, running the length of the station.
parts.append(S.box((0.028, 0.028, 0.190), (0, 0, 0), V_KEEL, bands=[('Z', 280.0)], amp=0.18))

# Foundry, slung under it: the only heavy closed volume on the thing.
parts.append(S.box((0.075, 0.065, 0.055), (0, 0, -0.045), V_FOUNDRY,
                   bands=[('Z', 340.0)], amp=0.20))

# Two dock hoops on gantry arms.  Arms run from inside the keel out past the hoop tube,
# so the frame is continuous rather than a ring floating off a spar.
for z in (0.030, 0.085):
    parts.append(S.torus(0.060, 0.007, (0, 0, z), V_HOOP, major_seg=10, minor_seg=3))
    for i in range(3):
        a = math.radians(120 * i + (0 if z < 0.05 else 60))
        parts.append(S.box((0.057, 0.008, 0.008),
                           (math.cos(a) * 0.0385, math.sin(a) * 0.0385, z),
                           V_ARM, rot=(0, 0, a), grime=0.08))

S.finish(parts, "ConstructionStation", out, tex_out, tag="STATION")
