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

V_SAIL = (0.88, 0.89, 0.92)   # light sail
V_SPAR = (0.40, 0.41, 0.44)   # spars
V_HUB = (0.88, 0.63, 0.16)   # gold MLI over the statite bus: a free-flying
        # electronics can is blanketed, which structure is not

parts = []

parts.append(S.box((0.230, 0.230, 0.0015), (0, 0, 0), V_SAIL,
                   bands=[('X', 180.0), ('Y', 180.0)], amp=0.14))
for a in (45.0, -45.0):
    parts.append(S.box((0.320, 0.006, 0.006), (0, 0, 0.004), V_SPAR,
                       rot=(0, 0, math.radians(a))))
parts.append(S.cyl(0.014, 0.014, (0, 0, 0.004), V_HUB, bands=[('Z', 600.0)], amp=0.16))

# Shroud lines from the hub out along each spar to the sail's corners, and an attitude
# thruster port on the hub.  A sail is held in tension by its rigging; drawing the rigging
# is what stops it reading as a painted square.
for a in (45.0, 135.0, 225.0, 315.0):
    r = math.radians(a)
    parts.append(S.pipe((math.cos(r) * 0.010, math.sin(r) * 0.010, 0.008),
                        (math.cos(r) * 0.150, math.sin(r) * 0.150, 0.004),
                        0.0022, (0.52, 0.54, 0.58), bands=[('Z', 700.0)], amp=0.25))
parts.append(S.hatch((0, 0, 0.013), 0.006, (0.24, 0.26, 0.30), depth=0.006,
                     bands=[('Z', 900.0)], amp=0.25))

S.finish(parts, "SunshadeConstellation", out, tex_out, tag="SUNSHADE")
