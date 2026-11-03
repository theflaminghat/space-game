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

V_MIRROR = (0.92, 0.94, 0.96)   # statite sail
V_BOOM   = (0.40, 0.41, 0.44)   # boom
V_BUS = (0.88, 0.63, 0.16)   # gold MLI over the statite bus: a free-flying
        # electronics can is blanketed, which structure is not

parts = []

# Steps overlap in Z by design: at 0.012 thick on an 0.008 pitch each one bites into the
# next, so the stack is one piece rather than three discs hovering above each other.
for radius, z in ((0.140, 0.0), (0.100, 0.008), (0.060, 0.016)):
    parts.append(S.cyl(radius, 0.012, (0, 0, z), V_MIRROR, segments=16,
                       windings=16, amp=0.16))

parts.append(S.cyl(0.008, 0.040, (0, 0, -0.024), V_BOOM, bands=[('Z', 420.0)], amp=0.18))
parts.append(S.box((0.030, 0.030, 0.020), (0, 0, -0.052), V_BUS,
                   bands=[('Z', 380.0)], amp=0.20))

# Stay lines from the bus out to the back of the mirror's widest step, and a thruster port
# on the bus.  A statite is station-kept by photon pressure against a rigged sail, so the
# rigging is the mechanism and not decoration.
for i in range(4):
    a = math.radians(45 + 90 * i)
    parts.append(S.pipe((math.cos(a) * 0.012, math.sin(a) * 0.012, -0.044),
                        (math.cos(a) * 0.098, math.sin(a) * 0.098, -0.006),
                        0.0028, (0.52, 0.54, 0.58), bands=[('Z', 700.0)], amp=0.25))
# On the bus's side, not its back: hung off the back it pushed the model's extent to
# 0.022 off centre, and a lane mesh that is not origin-centred rides at the wrong radius.
parts.append(S.hatch((0.017, 0, -0.052), 0.007, (0.24, 0.26, 0.30), axis='X',
                     depth=0.006, bands=[('Z', 900.0)], amp=0.25))

S.finish(parts, "ShkadovMirror", out, tex_out, tag="SHKADOV")
