"""Sunshade constellation - planet.gd's "sunshade" lane mesh.

buildings.gd: "Light sails flown sunward of the inner worlds, held in place by the
pressure of the light they block.  They do nothing to the star - they stand between it
and the planets."

A sail: one continuous sheet on crossed diagonal spars, with a hub where they meet.  It
BLOCKS, so it is flat and solid - which is the distinction from the Shkadov Mirror two
lanes inward, that REFLECTS and is therefore dished.  Both are white-ish statite sails
and they would otherwise be the same object twice.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_SAIL, V_SPAR, V_HUB = 0.92, 0.45, 0.58

parts = []

parts.append(S.box((0.230, 0.230, 0.0015), (0, 0, 0), V_SAIL,
                   bands=[('X', 180.0), ('Y', 180.0)], amp=0.14, grime=0.02))
for a in (45.0, -45.0):
    parts.append(S.box((0.320, 0.006, 0.006), (0, 0, 0.004), V_SPAR,
                       rot=(0, 0, math.radians(a))))
parts.append(S.cyl(0.014, 0.014, (0, 0, 0.004), V_HUB, bands=[('Z', 600.0)], amp=0.16))

S.finish(parts, "SunshadeConstellation", out, tex_out, tag="SUNSHADE")
