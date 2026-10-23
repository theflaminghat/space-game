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

# Greyscale base values.  Solar panels are the dark note that makes the silhouette
# read; the tanks are the bright one, because they are the depot.
V_SPINE, V_TANK, V_COLLAR, V_BOOM, V_PANEL = 0.75, 0.88, 0.62, 0.50, 0.28

parts = []

# Central spine, along Z (radial).
parts.append(S.cyl(0.026, 0.155, (0, 0, 0), V_SPINE, bands=[('Z', 250.0)], amp=0.16))

# Four storage tanks clustered around the spine - the actual "depot".
for i in range(4):
    a = math.radians(45 + 90 * i)
    parts.append(S.cyl(0.030, 0.105, (math.cos(a) * 0.052, math.sin(a) * 0.052, -0.010),
                       V_TANK, bands=[('Z', 300.0)], amp=0.22))

# Docking collar on the outward (+Z) end, berthing plate on the planet-facing end.
parts.append(S.cyl(0.042, 0.018, (0, 0, 0.086), V_COLLAR, bands=[('Z', 420.0)], amp=0.14))
parts.append(S.cyl(0.052, 0.012, (0, 0, -0.082), V_COLLAR, bands=[('Z', 420.0)], amp=0.14))

# Solar wings on booms, spread along X -> along-track once instanced.  The booms matter:
# without them the panels sink into the tank cluster and the silhouette reads as a blob.
for sx in (-1, 1):
    parts.append(S.cyl(0.005, 0.040, (sx * 0.075, 0, 0.022), V_BOOM,
                       rot=(0, math.radians(90), 0)))
    parts.append(S.box((0.058, 0.044, 0.004), (sx * 0.118, 0, 0.022), V_PANEL,
                       bands=[('X', 520.0), ('Y', 560.0)], amp=0.45, grime=0.04))

S.finish(parts, "OrbitalDepot", out, tex_out, tag="DEPOT")
