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

V_BAR  = (0.16, 0.22, 0.38)   # receiving bars
V_NODE   = (0.44, 0.46, 0.50)   # centre node - a junction box, so bare
V_BUSBAR = (0.76, 0.48, 0.27)   # copper collection bars feeding it

parts = []

for v in (-0.100, -0.050, 0.0, 0.050, 0.100):
    parts.append(S.box((0.250, 0.012, 0.004), (0, v, 0), V_BAR,
                       bands=[('X', 420.0)], amp=0.28))
    parts.append(S.box((0.012, 0.250, 0.004), (v, 0, 0), V_BAR,
                       bands=[('Y', 420.0)], amp=0.28))

parts.append(S.cyl(0.026, 0.014, (0, 0, 0), V_NODE, bands=[('Z', 520.0)], amp=0.16))

# Collection bars from the node out along the two centre lines, and a tie-down clamp
# where each outer bar crosses them.  The lattice is the antenna; these are the harness
# that takes what it gathers to one place.
for ax in ('X', 'Y'):
    for s_sign in (-1, 1):
        a = (s_sign * 0.118, 0) if ax == 'X' else (0, s_sign * 0.118)
        parts.append(S.pipe((0, 0, 0.005), (a[0], a[1], 0.005), 0.0035, V_BUSBAR,
                            bands=[(ax, 500.0)], amp=0.25))
for v in (-0.100, -0.050, 0.050, 0.100):
    parts.append(S.hatch((v, 0, 0.005), 0.008, V_NODE, depth=0.006,
                         bands=[('Z', 900.0)], amp=0.25))
    parts.append(S.hatch((0, v, 0.005), 0.008, V_NODE, depth=0.006,
                         bands=[('Z', 900.0)], amp=0.25))

S.finish(parts, "StellarRectennaGrid", out, tex_out, tag="RECTGRID")
