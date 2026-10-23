"""Swarm relay network - planet.gd's "swarm_relay" lane mesh.

buildings.gd: "Phased transmitting apertures STRUNG BETWEEN the swarm's collectors and
the worlds that use the power."

Strung is the word the model is built on.  This is not one machine but a run of small
apertures spaced along a tether, and that line of repeated discs on a thread is a
silhouette none of the other power-link lanes can be confused with - they are all a
single body with something mounted on it.

It is also the most elongated thing in the band, which is the point: it reaches.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_TETHER, V_APERTURE = 0.42, 0.82

parts = []

parts.append(S.cyl(0.006, 0.230, (0, 0, 0), V_TETHER, bands=[('Z', 240.0)], amp=0.20))

# Five apertures strung along it.  Each is centred on the tether and wider than it, so
# the tether runs through them and the run is one piece.
for z in (-0.090, -0.045, 0.0, 0.045, 0.090):
    parts.append(S.cyl(0.026, 0.008, (0, 0, z), V_APERTURE, segments=6,
                       bands=[('X', 700.0), ('Y', 700.0)], amp=0.35, grime=0.04))

S.finish(parts, "SwarmRelayNetwork", out, tex_out, tag="SWARMRELAY")
