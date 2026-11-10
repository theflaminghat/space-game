"""Orbital habitat for 'Don't Go Extinct' - planet.gd's "habitat" lane mesh.

buildings.gd calls it "a spun cylinder holding its own air, gravity and farmland", so
this is an O'Neill cylinder, NOT a torus.  That matters: it was sharing the "ring"
primitive with the Orbital Ring Store and the Core Mixing Array, and a ring is the one
shape the game's own description says it is not.

The bright stripes along the hull are the windows, with land between them, painted by
`windings`: an angular pattern that runs bands down the length of the drum.  The
superconducting ring uses the same mechanism at 40, where it reads as coil winding
instead - same machinery, opposite end of the dial.

The count is 12 rather than the three-and-three a real O'Neill cylinder has, and that is
a legibility choice, not an oversight.  Only half the drum faces the camera and its
curvature crushes the edges of that half into the silhouette, so a band count low enough
to be literally correct puts one broad stripe across the middle and hides the rest: the
drum just looks evenly lit.  Twelve survives the foreshortening with bands to spare.  The superconducting
ring uses the same mechanism at 40, where it reads as coil winding instead.  Same
machinery, opposite end of the dial, and the two are not mistakable for each other.

The three outboard panels are the sunlight mirrors that feed those windows.

+Z is the spin axis and maps to Godot +Y, the radial-outward column of the instance
basis, so the drum stands end-on to the body it orbits.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_HULL   = (0.58, 0.62, 0.66)   # drum hull
V_CAP    = (0.52, 0.56, 0.60)   # end caps - pressure structure, so steel and not gold
V_CABLE  = (0.76, 0.48, 0.27)   # copper trunk feeding the mirror drives
V_PORT   = S.BLACK   # airlock hatches
V_DOCK   = (0.56, 0.58, 0.62)   # docking ports
V_MIRROR = (0.88, 0.63, 0.16)   # gold sunlight mirrors - the panels on this model, so
                                # they take the gold the same way the radiator fins do

parts = []

# The drum itself.  12 sides: it has to read as round, where the depot's tanks are
# happy being faceted at 8.
parts.append(S.cyl(0.068, 0.180, (0, 0, 0), V_HULL, segments=12,
                   windings=12, amp=0.60, duty=0.45))

# End caps, and a docking port on each.
for sz in (-1, 1):
    parts.append(S.cyl(0.074, 0.012, (0, 0, sz * 0.092), V_CAP, segments=12,
                       bands=[('Z', 166.7)], amp=0.14))
    parts.append(S.cyl(0.026, 0.030, (0, 0, sz * 0.113), V_DOCK,
                       bands=[('Z', 200.0)], amp=0.12))

# Sunlight mirrors, hung outboard along the full length and offset from the window
# stripes they feed rather than shadowing them.
#
# Thin on the RADIAL axis, wide on the tangential one: a mirror is a plate presenting
# its face, and the obvious (0.030, 0.004, ...) makes it thin tangentially instead -
# a radial fin, edge-on from almost everywhere, which reads as a handle on a drum.
for i in range(3):
    a = math.radians(60 + 120 * i)
    # Boom out to the mirror.  The hull is 0.068 in radius and the mirror sits at 0.093;
    # the mirrors used to simply float there.
    parts.append(S.cyl(0.005, 0.034, (math.cos(a) * 0.080, math.sin(a) * 0.080, 0),
                       V_CAP, rot=(0, math.radians(90), a)))
    parts.append(S.box((0.004, 0.055, 0.180),
                       (math.cos(a) * 0.095, math.sin(a) * 0.095, 0),
                       V_MIRROR, rot=(0, 0, a)))

# Conduit running the length of the drum to each mirror's drive, and an airlock hatch
# beside each docking port.  A spun habitat has to steer its mirrors, and the cable that
# does it is the thing that reads as machinery rather than as a painted drum.
for i in range(3):
    a = math.radians(60 + 120 * i)
    c, s_ = math.cos(a), math.sin(a)
    parts.append(S.pipe((c * 0.070, s_ * 0.070, -0.088), (c * 0.070, s_ * 0.070, 0.088),
                        0.0035, V_CABLE))
for sz in (-1, 1):
    parts.append(S.hatch((0.044, 0.0, sz * 0.100), 0.013, V_PORT, depth=0.006))

# Alignment band around each docking port: a ring a pilot lines up on.
for sz in (-1, 1):
    parts.append(S.cyl(0.029, 0.005, (0, 0, sz * 0.122), S.RED))

S.finish(parts, "OrbitalHabitat", out, tex_out, tag="HABITAT")
