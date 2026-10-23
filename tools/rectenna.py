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

V_DISH, V_MAST, V_BUS = 0.86, 0.45, 0.55

parts = []

parts.append(S.cone(0.020, 0.085, 0.040, (0, 0, 0.010), V_DISH, segments=14,
                    rot=(math.radians(25), 0, 0), windings=14, amp=0.18, grime=0.04))
parts.append(S.cyl(0.010, 0.050, (0, 0, -0.030), V_MAST, bands=[('Z', 420.0)], amp=0.16))
parts.append(S.box((0.040, 0.040, 0.030), (0, 0, -0.062), V_BUS,
                   bands=[('Z', 380.0)], amp=0.20))

S.finish(parts, "OrbitalRectenna", out, tex_out, tag="RECTENNA")
