"""Space telescope for 'Don't Go Extinct' - planet.gd's "telescope" lane mesh.

buildings.gd: "Observatory in orbit, above atmospheric absorption and noise.  Adds
signature-detection power."

Modelled on Chandra: a long slender optical bench, two large solar wings mounted
mid-body, a stepped forward section carrying the grazing-incidence mirrors, and the
instrument module aft.  The proportions are Chandra's own - the wings span about 1.3x
the bench's length, which is the first thing the eye picks up and the reason it does not
read as just another cylinder.  That span is also most of what the lane envelope allows:
0.32 against the 0.34 the neighbouring lanes leave room for.

It looks OUTWARD, away from the body it orbits, because an observatory above atmospheric
absorption is pointed at the sky and not at the ground.  The aperture is therefore the
+Z end, which glTF maps to Godot +Y.

The wings are the whole disambiguation here.  The Orbital Vault also carries panels, but
its are small outriggers on a cluster of fat tanks, where these are the dominant feature
on a single slim tube; and the Orbital Laser is a barrel of roughly this length but with
four radial fins and no flat surfaces at all.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_BENCH, V_MIRROR, V_APERTURE, V_AFT, V_PANEL = 0.72, 0.60, 0.85, 0.55, 0.30

parts = []

# Optical bench: the long slender run of it.
parts.append(S.cyl(0.026, 0.130, (0, 0, -0.005), V_BENCH, segments=10,
                   bands=[('Z', 300.0)], amp=0.18))

# Forward: mirror housing, then the sunshade ring at the aperture.
parts.append(S.cyl(0.034, 0.040, (0, 0, 0.078), V_MIRROR, segments=10,
                   bands=[('Z', 420.0)], amp=0.16))
parts.append(S.cyl(0.038, 0.022, (0, 0, 0.108), V_APERTURE, segments=10,
                   bands=[('Z', 600.0)], amp=0.12, grime=0.04))

# Aft instrument module.
parts.append(S.cyl(0.040, 0.050, (0, 0, -0.095), V_AFT, segments=10,
                   bands=[('Z', 340.0)], amp=0.20))

# Solar wings, spanning wider than the bench is long - Chandra's giveaway proportion.
# Dark, with a cell grid, the way the Orbital Vault's panels are done.
for sx in (-1, 1):
    # Yoke from the bench out to the wing root.  Without it the panel hangs in the
    # vacuum beside the spacecraft: the bench is 0.026 in radius and the wing root is
    # out at 0.050, and nothing crossed that gap.
    parts.append(S.cyl(0.006, 0.034, (sx * 0.037, 0, -0.020), V_BENCH,
                       rot=(0, math.radians(90), 0), bands=[('Z', 600.0)], amp=0.12))
    parts.append(S.box((0.110, 0.056, 0.004), (sx * 0.105, 0, -0.020), V_PANEL,
                       bands=[('X', 420.0), ('Y', 560.0)], amp=0.45, grime=0.04))

S.finish(parts, "SpaceTelescope", out, tex_out, tag="SCOPE")
