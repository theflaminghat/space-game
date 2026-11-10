"""Shkadov mirror - planet.gd's "shkadov" lane mesh.

buildings.gd: "A statite sail flown to one side of the Sun: it REFLECTS the star's light
back, and the star feels the recoil."

Reflecting is the difference from the Sunshade Constellation, which blocks.  A reflector
is dished, so this is built as three concentric steps narrowing away from the star - a
shallow curved mirror in the only way a low-polygon model can be one - with the statite
bus on a short boom behind it.

Stepped rather than a smooth cone because the steps read at distance: a smooth shallow
cone of this width is visually a flat disc, and a flat disc is what the sunshade is.

RETIRED, and kept only as a record of what was there.  Nothing loads this model any more.

There is one mirror, not a fleet, and one of these at a hundred times its authored size was
a piece of satellite hardware the width of a star - a dish, a boom and a bus, all of them
details of a spacecraft rather than of a sail, with the boom reaching back towards the
photosphere so the standoff had to be solved around it.  A sail is a surface.  planet.gd
builds it as a plain spherical cap instead (Planet.mirror_cap_mesh), sized by the share of
the star's sky its coverage claims, so there is no mesh to load and no hardware to scale.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_MIRROR = (0.92, 0.94, 0.96)   # statite sail
V_BOOM   = (0.40, 0.41, 0.44)   # boom
V_BUS = (0.46, 0.48, 0.52)   # bare bus - a mirror reflects, so nothing here is gold

parts = []

# Steps overlap in Z by design: at 0.012 thick on an 0.008 pitch each one bites into the
# next, so the stack is one piece rather than three discs hovering above each other.
for radius, z in ((0.140, 0.0), (0.100, 0.008), (0.060, 0.016)):
    parts.append(S.cyl(radius, 0.012, (0, 0, z), V_MIRROR, segments=16,
                       windings=16, amp=0.16))

parts.append(S.cyl(0.008, 0.040, (0, 0, -0.024), V_BOOM, bands=[('Z', 140.0)], amp=0.18))
parts.append(S.box((0.030, 0.030, 0.020), (0, 0, -0.052), V_BUS,
                   bands=[('Z', 126.7)], amp=0.20))

# Stay lines from the bus out to the back of the mirror's widest step, and a thruster port
# on the bus.  A statite is station-kept by photon pressure against a rigged sail, so the
# rigging is the mechanism and not decoration.
for i in range(4):
    a = math.radians(45 + 90 * i)
    parts.append(S.pipe((math.cos(a) * 0.012, math.sin(a) * 0.012, -0.044),
                        (math.cos(a) * 0.098, math.sin(a) * 0.098, -0.006),
                        0.0028, (0.52, 0.54, 0.58)))
# On the bus's side, not its back: hung off the back it pushed the model's extent to
# 0.022 off centre, and a lane mesh that is not origin-centred rides at the wrong radius.
parts.append(S.hatch((0.017, 0, -0.052), 0.007, S.RED, axis='X',
                     depth=0.006))

S.finish(parts, "ShkadovMirror", out, tex_out, tag="SHKADOV")
