"""Orbital radiator array - planet.gd's "radiator" lane mesh.

buildings.gd: "Free-flying radiator panels in high orbit, sized for a fusion-scale
economy."

Almost nothing but panel: six fins on a thin coolant spine with a manifold collar at
each end.  The proportion is the whole idea - a fusion-scale economy's waste heat needs
more radiator than it needs structure to hang it on.

Six rather than the Orbital Laser's four, and on a bare spine rather than at the foot of
a barrel.  That matters because the laser's fins are the same shape: what separates them
is that there is nothing else here, where on the laser the fins are a detail at the base
of something much bigger.

The grooves run along Z, the axis every fin shares, so all six grain identically however
they are rotated about it - bands on a transverse axis would run lengthwise on some and
crosswise on others.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_FIN, V_SPINE, V_COLLAR = 0.80, 0.50, 0.60

parts = []

# Coolant spine, and a manifold collar at each end.
parts.append(S.cyl(0.012, 0.200, (0, 0, 0), V_SPINE, bands=[('Z', 320.0)], amp=0.18))
for sz in (-1, 1):
    parts.append(S.cyl(0.020, 0.016, (0, 0, sz * 0.090), V_COLLAR,
                       bands=[('Z', 520.0)], amp=0.14))

# Fins, reaching in past the spine's surface so the array is one piece.
for i in range(6):
    a = math.radians(60 * i)
    parts.append(S.box((0.085, 0.004, 0.140),
                       (math.cos(a) * 0.050, math.sin(a) * 0.050, 0),
                       V_FIN, rot=(0, 0, a), bands=[('Z', 520.0)], amp=0.38, grime=0.05))

S.finish(parts, "RadiatorArray", out, tex_out, tag="RADIATOR")
