"""Stellar rectenna grid - planet.gd's "rect_grid" lane mesh.

buildings.gd: "Receiving aperture at planetary-orbit scale, sized to land a Dyson swarm's
output."

Built as an actual open lattice - five bars each way with sky between them - rather than
as a solid plate with a grid painted on.  At this point in the band every remaining lane
is some kind of flat rectangle, and a painted grid is not a silhouette; a lattice you can
see through is.

It is also square and the widest thing in the band, against the Thermal Radiator's oblong
six-panel field, which is the other flat amber-to-blue plate nearby.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_BAR, V_NODE = 0.60, 0.82

parts = []

for v in (-0.100, -0.050, 0.0, 0.050, 0.100):
    parts.append(S.box((0.250, 0.012, 0.004), (0, v, 0), V_BAR,
                       bands=[('X', 420.0)], amp=0.28, grime=0.05))
    parts.append(S.box((0.012, 0.250, 0.004), (v, 0, 0), V_BAR,
                       bands=[('Y', 420.0)], amp=0.28, grime=0.05))

parts.append(S.cyl(0.026, 0.014, (0, 0, 0), V_NODE, bands=[('Z', 520.0)], amp=0.16))

S.finish(parts, "StellarRectennaGrid", out, tex_out, tag="RECTGRID")
