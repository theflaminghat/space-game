"""Procedural orbital depot for 'Don't Go Extinct' - planet.gd's "depot" lane mesh.

Drawn for the Orbital Vault: a spine with storage tanks clustered around it, a
docking collar on the outward end, and solar wings on booms.  See tools/_shared.py
for the constraints the lane imposes and how the texture is baked.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

# Hardware colours.  Solar panels are the dark note that makes the silhouette read; the
# tanks are the bright one, because they are the depot.
#
# Gold is multi-layer insulation and goes on the THERMAL PLATES and nowhere else.  It used
# to sit on the docking collar and berthing plate purely because those were in view, which
# made the gold decoration rather than a material — a docking collar is a structural ring
# and is bare steel.  The plates below are the parts that are actually insulation.
V_SPINE   = (0.46, 0.52, 0.60)   # steel-blue structure, inside the tank cluster
V_TANK    = (0.90, 0.90, 0.87)   # white tankage
V_COLLAR  = (0.54, 0.58, 0.64)   # bare steel: docking collar and berthing plate
V_THERMAL = (0.88, 0.63, 0.16)   # gold MLI — thermal plates ONLY, nothing else
V_BOOM    = (0.28, 0.30, 0.34)   # graphite booms
V_PANEL   = (0.07, 0.12, 0.38)   # solar cells

parts = []

# Central spine, along Z (radial).
parts.append(S.cyl(0.026, 0.155, (0, 0, 0), V_SPINE,
                   bands=[('Z', 250.0)], windings=12, amp=0.18))

# Four storage tanks clustered around the spine - the actual "depot".
for i in range(4):
    a = math.radians(45 + 90 * i)
    parts.append(S.cyl(0.030, 0.105, (math.cos(a) * 0.052, math.sin(a) * 0.052, -0.010),
                       V_TANK, bands=[('Z', 300.0)], windings=16, amp=0.26))

# Docking collar on the outward (+Z) end, berthing plate on the planet-facing end.
parts.append(S.cyl(0.042, 0.018, (0, 0, 0.086), V_COLLAR,
                   bands=[('Z', 420.0)], windings=20, amp=0.18))
parts.append(S.cyl(0.052, 0.012, (0, 0, -0.082), V_COLLAR,
                   bands=[('Z', 420.0)], windings=24, amp=0.18))

# Thermal plates: four insulation panels standing off the spine, in the gaps between the
# tanks so they are visible from outside rather than buried.  Heavy grime and a fine seam
# pitch, because MLI is crinkled foil and reads wrong if it is smooth.
for i in range(4):
    a = math.radians(90 * i)
    parts.append(S.box((0.040, 0.004, 0.070),
                       (math.cos(a) * 0.044, math.sin(a) * 0.044, -0.010),
                       V_THERMAL, rot=(0, 0, a),
                       bands=[('Z', 700.0)], amp=0.30, grime=0.22))

# Solar wings on booms, spread along X -> along-track once instanced.  The booms matter:
# without them the panels sink into the tank cluster and the silhouette reads as a blob.
for sx in (-1, 1):
    parts.append(S.cyl(0.005, 0.040, (sx * 0.075, 0, 0.022), V_BOOM,
                       rot=(0, math.radians(90), 0)))
    parts.append(S.box((0.058, 0.044, 0.004), (sx * 0.118, 0, 0.022), V_PANEL,
                       bands=[('X', 520.0), ('Y', 560.0)], amp=0.52, grime=0.04))

S.finish(parts, "OrbitalDepot", out, tex_out, tag="DEPOT")
