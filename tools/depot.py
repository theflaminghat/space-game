"""Procedural orbital depot for 'Kardashev' - planet.gd's "depot" lane mesh.

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

# Hardware colours: a short list of flat values, each one a material the depot is actually
# made of.  Nothing is shaded, blended or dirtied - a plate is one colour across its whole
# face, and the only break in it is the hard seam where the next plate starts.
#
# Gold is multi-layer insulation and goes on the THERMAL PLATES and nowhere else.  It used
# to sit on the docking collar and berthing plate purely because those were in view, which
# made the gold decoration rather than a material - a docking collar is a structural ring
# and is bare steel.  The plates below are the parts that are actually insulation.
V_SPINE   = (0.46, 0.52, 0.60)   # steel-blue structure, inside the tank cluster
V_TANK    = (0.90, 0.90, 0.87)   # white tankage
V_COLLAR  = (0.54, 0.58, 0.64)   # bare steel: docking collar and berthing plate
V_THERMAL = (0.88, 0.63, 0.16)   # gold MLI - thermal plates ONLY, nothing else
V_BOOM    = (0.28, 0.30, 0.34)   # graphite booms
V_PANEL   = (0.03, 0.05, 0.18)   # solar cells
V_PIPE    = (0.45, 0.48, 0.54)   # bare-metal plumbing: the propellant transfer lines
V_CABLE   = S.BLACK   # cable conduit and the junction boxes it runs between
V_PORT    = S.BLACK   # hatch and port faces, dark against the white tanks

parts = []

# Central spine, along Z (radial).  Bare: it is a column half-buried in the tank cluster,
# and a grid of plating squares on it was detail nobody can resolve at the size these
# instance at - it read as clutter and made the column busier than the tanks in front.
parts.append(S.cyl(0.026, 0.155, (0, 0, 0), V_SPINE))

# Four storage tanks clustered around the spine - the actual "depot".  Girth welds only:
# a pressure vessel is rolled in rings and welded around, so the seams run around it and
# not along it.
tank_a = [math.radians(45 + 90 * i) for i in range(4)]
for a in tank_a:
    parts.append(S.cyl(0.030, 0.105, (math.cos(a) * 0.052, math.sin(a) * 0.052, -0.010),
                       V_TANK, bands=[('Z', 100.0)], amp=0.26))

# Docking collar on the outward (+Z) end, berthing plate on the planet-facing end.  The
# flange detail they used to carry is finer than a 512 map resolves on a part this thin.
parts.append(S.cyl(0.042, 0.018, (0, 0, 0.086), V_COLLAR))
parts.append(S.cyl(0.052, 0.012, (0, 0, -0.082), V_COLLAR))

# The docking port itself, standing proud of the collar: what a ship actually mates to.
parts.append(S.hatch((0, 0, 0.0975), 0.018, V_PORT, depth=0.010, segments=12))

# Thermal plates: four insulation panels standing off the spine, in the gaps between the
# tanks so they are visible from outside rather than buried.  A fine seam pitch, because
# MLI is taped down in narrow strips and a smooth plate reads as sheet metal instead.
for i in range(4):
    a = math.radians(90 * i)
    parts.append(S.box((0.040, 0.004, 0.070),
                       (math.cos(a) * 0.044, math.sin(a) * 0.044, -0.010),
                       V_THERMAL, rot=(0, 0, a),
                       bands=[('Z', 233.3)], amp=0.30))

# Propellant transfer lines: one down the outboard face of each tank and into the rim of
# the berthing plate, where a tanker couples to them.  These are the detail that says the
# cylinders are tankage rather than four more hull sections.  They run on the OUTSIDE of
# the cluster on purpose - plumbed down the spine they would be correct and invisible,
# which is the same mistake as putting the gold where it merely showed.
for a in tank_a:
    c, s_ = math.cos(a), math.sin(a)
    parts.append(S.pipe((c * 0.081, s_ * 0.081, -0.048), (c * 0.081, s_ * 0.081, 0.030),
                        0.0045, V_PIPE))
    parts.append(S.pipe((c * 0.081, s_ * 0.081, -0.048), (c * 0.046, s_ * 0.046, -0.078),
                        0.0045, V_PIPE))

# Service hatch on the outward end of each tank - the fill and vent coupling - and a
# second one on its outboard face, lying flat against the curve.
for a in tank_a:
    c, s_ = math.cos(a), math.sin(a)
    parts.append(S.hatch((c * 0.052, s_ * 0.052, 0.0445), 0.013, V_PORT, depth=0.006))
    parts.append(S.hatch((c * 0.079, s_ * 0.079, -0.004), 0.011, V_PORT,
                         axis=(c, s_, 0), depth=0.006))

# Power and signal: a junction box at each boom root, and a conduit off the top of every
# tank converging on the docking collar.  Run over the top decks rather than down the
# spine, where it would be buried inside the tank cluster and cost geometry to be unseen.
for a in tank_a:
    c, s_ = math.cos(a), math.sin(a)
    parts.append(S.pipe((c * 0.044, s_ * 0.044, 0.044), (c * 0.020, s_ * 0.020, 0.080),
                        0.0035, V_CABLE))

# Solar wings on booms.  The booms carry right back to the spine rather than stopping short
# of it: a wing has to be mounted on the structure, not on the tank it happens to graze.
for sx in (-1, 1):
    parts.append(S.pipe((sx * 0.024, 0, 0.022), (sx * 0.095, 0, 0.022), 0.005, V_BOOM))
    parts.append(S.box((0.014, 0.016, 0.016), (sx * 0.036, 0, 0.022), V_CABLE))
    parts.append(S.box((0.058, 0.044, 0.004), (sx * 0.118, 0, 0.022), V_PANEL,
                       bands=[('X', 300.0), ('Y', 340.0)], amp=0.38))

# Alignment ring around the docking port - the target a tug flies at.
parts.append(S.cyl(0.026, 0.004, (0, 0, 0.0965), S.RED))

S.finish(parts, "OrbitalDepot", out, tex_out, tag="DEPOT")
