"""Orbital rectenna - planet.gd's "rectenna" lane mesh.

buildings.gd: "Receiving aperture in orbit, where no atmosphere scatters the beam."

The only one of the four power-link lanes that is genuinely a dish, so it gets to be
one: a single large collector on a mast, and nothing else competing with it.

The dish is canted rather than square-on to the radial axis.  primitive_cone_add caps
its wide end, so a collector pointed straight out presents the viewer a flat disc and
reads as a drum - the same trap the Star Lifter fell into.  Canted, that cap becomes a
dish face catching the light across it.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_DISH = (0.87, 0.87, 0.85)   # collector dish
V_MAST = (0.40, 0.41, 0.44)   # mast
V_BUS   = (0.40, 0.42, 0.46)   # converter box - electrical, so bare
V_GUIDE = (0.76, 0.48, 0.27)   # copper waveguide, feed horn down to the converter
V_HORN  = S.BLACK   # the feed horn itself

parts = []

parts.append(S.cone(0.020, 0.085, 0.040, (0, 0, 0.010), V_DISH, segments=14,
                    rot=(math.radians(25), 0, 0), windings=14, amp=0.18))
parts.append(S.cyl(0.010, 0.050, (0, 0, -0.030), V_MAST, bands=[('Z', 140.0)], amp=0.16))
parts.append(S.box((0.040, 0.040, 0.030), (0, 0, -0.062), V_BUS,
                   bands=[('Z', 126.7)], amp=0.20))

# Feed horn at the dish's focus and the waveguide carrying it down the mast to the
# converter.  Without them the dish is a bowl pointed at nothing, which is the one thing
# a collector must not look like.
parts.append(S.hatch((0, -0.022, 0.058), 0.009, V_HORN, axis=(0, -0.42, 0.91),
                     depth=0.012))
parts.append(S.pipe((0, -0.020, 0.054), (0, -0.012, -0.050), 0.0035, V_GUIDE))

parts.append(S.box((0.048, 0.048, 0.005), (0, 0, -0.050), S.RED))

S.finish(parts, "OrbitalRectenna", out, tex_out, tag="RECTENNA")
