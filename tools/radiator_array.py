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

V_FIN    = (0.88, 0.63, 0.16)   # gold radiating fins - the whole point of the model
V_SPINE  = (0.56, 0.58, 0.62)   # coolant spine
V_COLLAR = (0.76, 0.48, 0.27)   # copper manifold collars - plumbing, not insulation
V_LINE   = (0.68, 0.44, 0.26)   # the coolant risers they feed

parts = []

# Coolant spine, and a manifold collar at each end.
parts.append(S.cyl(0.012, 0.200, (0, 0, 0), V_SPINE, bands=[('Z', 106.7)], amp=0.18))
for sz in (-1, 1):
    parts.append(S.cyl(0.020, 0.016, (0, 0, sz * 0.090), V_COLLAR,
                       bands=[('Z', 173.3)], amp=0.14))

# Fins, reaching in past the spine's surface so the array is one piece.
for i in range(6):
    a = math.radians(60 * i)
    parts.append(S.box((0.085, 0.004, 0.140),
                       (math.cos(a) * 0.050, math.sin(a) * 0.050, 0),
                       V_FIN, rot=(0, 0, a), bands=[('Z', 173.3)], amp=0.38))

# A coolant riser up the leading edge of every fin, off the manifold at each end.  A
# radiator that is not plumbed to anything is a sheet of metal; the risers are what make
# the six fins read as one loop.
for i in range(6):
    a = math.radians(60 * i)
    c, s_ = math.cos(a), math.sin(a)
    parts.append(S.pipe((c * 0.088, s_ * 0.088, -0.062), (c * 0.088, s_ * 0.088, 0.062),
                        0.0035, V_LINE))
    parts.append(S.pipe((c * 0.022, s_ * 0.022, 0.082), (c * 0.088, s_ * 0.088, 0.062),
                        0.0030, V_LINE))

# Shutoff on the outward manifold, so the loop can be isolated.
parts.append(S.hatch((0.022, 0, 0.090), 0.007, S.RED, axis='X'))

S.finish(parts, "RadiatorArray", out, tex_out, tag="RADIATOR")
