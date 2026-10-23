"""Orbital power grid - planet.gd's "grid" lane mesh.

buildings.gd: "Receiving and relaying constellation around one world.  Adds both
sending and receiving capacity."

Both halves of that sentence are in the model: the broad dark rectenna face does the
receiving, the two dishes on masts do the relaying.  Four lanes further out still share
the plain "flat" primitive and several of them are also blue, so a bare panel here would
be indistinguishable - the dishes are what say this one sends as well as receives.

They are tilted off the radial axis on purpose.  A dish pointed straight out presents
the flat cap that primitive_cone_add puts on its wide end, which is the Star Lifter's
problem over again; canting them turns that cap into a dish face.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_RECTENNA, V_BUS, V_MAST, V_DISH = 0.30, 0.58, 0.45, 0.85

parts = []

# Rectenna face, with the cell grid the Orbital Vault's panels use.
parts.append(S.box((0.160, 0.115, 0.006), (0, 0, -0.048), V_RECTENNA,
                   bands=[('X', 380.0), ('Y', 460.0)], amp=0.45, grime=0.04))

# Bus, straddling the panel's upper face.
parts.append(S.box((0.044, 0.044, 0.034), (0, 0, -0.030), V_BUS,
                   bands=[('Z', 400.0)], amp=0.18))

# Relay dishes on masts, canted outward.
for sx in (-1, 1):
    parts.append(S.cyl(0.005, 0.040, (sx * 0.020, 0, 0.005), V_MAST))
    parts.append(S.cone(0.006, 0.028, 0.016, (sx * 0.020, 0, 0.030), V_DISH,
                        segments=10, rot=(0, sx * math.radians(30), 0), grime=0.04))

S.finish(parts, "PowerGrid", out, tex_out, tag="GRID")
