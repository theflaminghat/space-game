"""Power relay satellite - planet.gd's "relay" lane mesh.

buildings.gd: "Mirror-and-array platform with superconducting busbars.  Adds sending
capacity."

Every noun in that sentence is in the model: a platform, a canted mirror on struts above
it, and two fat busbars running its length.  The busbars are the detail that makes it
this lane rather than any other blue one - nothing else in the band has heavy conduit
lying along a deck.

They sit outboard of the mirror rather than under it.  Tucked in at the deck's centre
they were completely roofed over by the mirror from every angle above the plane, which
is most angles - the identifying feature, invisible.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_DECK, V_BUSBAR, V_STRUT, V_MIRROR = 0.52, 0.72, 0.45, 0.90

parts = []

parts.append(S.box((0.120, 0.100, 0.012), (0, 0, -0.030), V_DECK,
                   bands=[('Z', 420.0)], amp=0.18))

# Superconducting busbars, lying along the deck.
for sy in (-1, 1):
    parts.append(S.cyl(0.008, 0.110, (0, sy * 0.044, -0.018), V_BUSBAR,
                       rot=(0, math.radians(90), 0), bands=[('Z', 300.0)], amp=0.22))

# Mirror, canted, on a pair of struts.
for sx in (-1, 1):
    parts.append(S.cyl(0.006, 0.045, (sx * 0.034, 0, -0.004), V_STRUT))
parts.append(S.box((0.100, 0.070, 0.004), (0, 0, 0.026), V_MIRROR,
                   rot=(math.radians(28), 0, 0), grime=0.02))

S.finish(parts, "PowerRelaySatellite", out, tex_out, tag="RELAY")
