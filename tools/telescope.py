"""Space telescope for 'Kardashev' - planet.gd's "telescope" lane mesh.

buildings.gd: "Observatory in orbit, above atmospheric absorption and noise.  Adds
signature-detection power."

Modelled on Chandra, and closely enough that the specific things that make Chandra
recognisable are each in here:

  * The body is GOLD.  Chandra is wrapped nearly end to end in amber MLI, and that
    colour is the first thing anyone recognises about it.  This is the one model in the
    set where gold is the hull rather than the thermal hardware bolted to it - the rest
    carry it on fins, films and blankets - and that exception is the whole likeness.
  * The tube is LONG and SLENDER, and most of its length is forward of the wings.  The
    wings hang well aft, so the gold tube reaches out ahead of them rather than sitting
    centred between them.
  * Each wing is THREE panels in a row, not one slab.  Chandra's arrays are segmented,
    and at this size the two gaps are what separate it from the Orbital Vault's plain
    outriggers.
  * A SILVER sunshade door caps the front, the one cool-coloured section on the body,
    which is what stops the whole thing reading as a single gold rod.

The wings span 0.322 against a 0.273 body - wider than it is long, Chandra's giveaway
proportion, and most of the 0.34 the neighbouring lanes leave room for.

It looks OUTWARD, away from the body it orbits, because an observatory above atmospheric
absorption is pointed at the sky and not at the ground.  The aperture is therefore the
+Z end, which glTF maps to Godot +Y.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

# Two golds, the way the Core Mixing Array carries two: one value across bench, mirror
# section and aft module welds them into a single rod at the size these instance at.
V_BENCH  = (0.88, 0.63, 0.16)   # gold MLI over the optical bench - the body
V_HRMA   = (0.72, 0.50, 0.12)   # darker gold on the mirror section and the aft module
V_DOOR   = (0.82, 0.84, 0.88)   # silver sunshade door at the aperture
V_YOKE   = (0.35, 0.36, 0.39)   # graphite wing yokes
V_PANEL  = (0.04, 0.06, 0.18)   # solar cells

parts = []

# Optical bench: the long slender run, reaching well forward of the wings.
parts.append(S.cyl(0.024, 0.165, (0, 0, -0.012), V_BENCH, segments=10,
                   bands=[('Z', 90.0)], amp=0.18))

# Forward: the mirror assembly, then the sunshade door, then the aperture itself.  The
# mouth is black - it is the one part of an observatory that is a hole, and leaving it
# the colour of the shroud around it closes the telescope up.
parts.append(S.cyl(0.032, 0.044, (0, 0, 0.090), V_HRMA, segments=10,
                   bands=[('Z', 130.0)], amp=0.16))
parts.append(S.cyl(0.035, 0.026, (0, 0, 0.125), V_DOOR, segments=10,
                   bands=[('Z', 180.0)], amp=0.14))
parts.append(S.hatch((0, 0, 0.136), 0.030, S.BLACK, depth=0.004, segments=10))
# The marking band sits at the door's base, not on its lip.  Round the lip it read as a
# crown rather than a marking, and at 10 segments against a 10-sided shroud the two
# polygon counts beat against each other and the ring came out scalloped.
parts.append(S.torus(0.0345, 0.0030, (0, 0, 0.113), S.RED, major_seg=20, minor_seg=3))

# Aft spacecraft bus, carrying the instruments.
parts.append(S.cyl(0.042, 0.046, (0, 0, -0.112), V_HRMA, segments=10,
                   bands=[('Z', 110.0)], amp=0.20))

# Solar wings, mounted aft and segmented three to a side.  The panels overlap their
# neighbours by 0.002 rather than sitting in a row with a gap: butted up with clear air
# between them the outer two touch nothing and the build's floating-part check rejects
# the model, which is the correct complaint - a panel has to be carried by something.
for sx in (-1, 1):
    parts.append(S.pipe((sx * 0.020, 0, -0.060), (sx * 0.054, 0, -0.060), 0.005, V_YOKE))
    for x in (0.070, 0.106, 0.142):
        parts.append(S.box((0.038, 0.062, 0.004), (sx * x, 0, -0.060), V_PANEL,
                           bands=[('X', 330.0), ('Y', 200.0)], amp=0.42))

# Harness down the bench from the bus to the mirror section, and a radiator hatch on the
# bus.  An observatory is read out from the back, so the cable that does it runs forward.
parts.append(S.pipe((0.026, 0, -0.090), (0.026, 0, 0.066), 0.0030, S.BLACK))
parts.append(S.hatch((0, 0.044, -0.112), 0.014, S.BLACK, axis='Y', depth=0.006))

S.finish(parts, "SpaceTelescope", out, tex_out, tag="SCOPE")
