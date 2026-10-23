"""Shkadov mirror - planet.gd's "shkadov" lane mesh.

buildings.gd: "A statite sail flown to one side of the Sun: it REFLECTS the star's light
back, and the star feels the recoil."

Reflecting is the difference from the Sunshade Constellation, which blocks.  A reflector
is dished, so this is built as three concentric steps narrowing away from the star - a
shallow curved mirror in the only way a low-polygon model can be one - with the statite
bus on a short boom behind it.

Stepped rather than a smooth cone because the steps read at distance: a smooth shallow
cone of this width is visually a flat disc, and a flat disc is what the sunshade is.

It sits at lane radius 0.980, the innermost of the entire band - closer in than the Core
Mixing Array and the Star Lifter both.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_MIRROR, V_BOOM, V_BUS = 0.95, 0.40, 0.55

parts = []

# Steps overlap in Z by design: at 0.012 thick on an 0.008 pitch each one bites into the
# next, so the stack is one piece rather than three discs hovering above each other.
for radius, z in ((0.140, 0.0), (0.100, 0.008), (0.060, 0.016)):
    parts.append(S.cyl(radius, 0.012, (0, 0, z), V_MIRROR, segments=16,
                       windings=16, amp=0.16, grime=0.02))

parts.append(S.cyl(0.008, 0.040, (0, 0, -0.024), V_BOOM, bands=[('Z', 420.0)], amp=0.18))
parts.append(S.box((0.030, 0.030, 0.020), (0, 0, -0.052), V_BUS,
                   bands=[('Z', 380.0)], amp=0.20))

S.finish(parts, "ShkadovMirror", out, tex_out, tag="SHKADOV")
