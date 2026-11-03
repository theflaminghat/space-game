"""Radiator swarm - planet.gd's "rad_swarm" lane mesh.

buildings.gd: "Radiator FILMS co-orbiting the Dyson swarm, sized to shed a stellar
economy's waste heat."

Film, not panel.  Three enormous sheets a millimetre thick, each canted at its own angle
off a hub barely big enough to see - no frame, no spine, nothing rigid.  That looseness
is the whole distinction from the Thermal Radiator, which is a rigid framed field, and
from the Orbital Radiator Array, which is fins bolted to a coolant spine.

The sheets are canted about their own radial axis by different amounts on purpose: three
identical coplanar sheets would read as one solid disc rather than as separate film.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_FILM = (0.90, 0.90, 0.88)   # radiator film
V_HUB = (0.88, 0.63, 0.16)   # gold MLI over the statite bus: a free-flying
        # electronics can is blanketed, which structure is not

parts = []

parts.append(S.cyl(0.010, 0.012, (0, 0, 0), V_HUB, bands=[('Z', 600.0)], amp=0.16))

for i, tilt in enumerate((18.0, -22.0, 26.0)):
    a = math.radians(120 * i)
    parts.append(S.box((0.120, 0.080, 0.0015),
                       (math.cos(a) * 0.058, math.sin(a) * 0.058, 0), V_FILM,
                       rot=(math.radians(tilt), 0, a),
                       bands=[('X', 420.0)], amp=0.22))

# Coolant lines from the bus out to the root of each sheet, and the pump hatch they leave
# from.  Film hanging off a hub is a mystery; film plumbed to a hub is a radiator.
parts.append(S.hatch((0, 0, 0.008), 0.006, (0.24, 0.26, 0.30), depth=0.006,
                     bands=[('Z', 900.0)], amp=0.25))
for i in range(3):
    a = math.radians(120 * i)
    parts.append(S.pipe((math.cos(a) * 0.006, math.sin(a) * 0.006, 0.004),
                        (math.cos(a) * 0.042, math.sin(a) * 0.042, 0.0),
                        0.0028, (0.76, 0.48, 0.27), bands=[('Z', 600.0)], amp=0.25))

S.finish(parts, "RadiatorSwarm", out, tex_out, tag="RADSWARM")
