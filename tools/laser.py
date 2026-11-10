"""Orbital laser for 'Don't Go Extinct' - planet.gd's "laser" lane mesh.

buildings.gd calls this "a star-scale directed-energy weapon ringing the world it's
built on": it fires light-speed pulses at other star systems and burns down inbound
asteroids, relativistic missiles and berserker swarms.  Each lane instance is one
emitter of that ring, so the model is a single gun - barrel, focusing optics, and the
power section behind it.

It AIMS OUTWARD.  +Z here maps to Godot +Y, the radial-outward column of the instance
basis, so the aperture points away from the body and into the sky it is defending.
That is a change from the "rod" primitive it replaces, which lay along-track and so
pointed at nothing in particular.

The radiator fins are the silhouette.  A directed-energy weapon at this scale is
mostly a machine for making waste heat, and the fins are what distinguish it at a
glance from the other long thin things in the band.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

# Black body, gold and red and nothing else.  The lane this instances in is already a hot
# red, so a pale hull fought it; a near-black one lets the lane's own colour sit behind the
# silhouette instead of competing with it.
#
# The blacks are three values rather than one.  A single value across barrel, breech and
# collar loses every join between them - at this size the sections stop being sections and
# the whole thing reads as one extruded rod - so each is a step apart, which is enough to
# separate them under shading without any of them stopping being black.
#
# Everything thermal is gold: the fins, the coolant lines feeding them, and the focusing
# rings.  The copper the lines used to be was a third warm note next to the gold and read
# as a different system than the one they plumb.
V_BARREL   = (0.11, 0.11, 0.12)   # barrel
V_POWER    = (0.08, 0.08, 0.09)   # capacitor section at the breech
V_SLEEVE   = (0.14, 0.14, 0.15)   # cryo sleeve around the gain medium
V_COLLAR   = (0.17, 0.17, 0.19)   # mount collar, the lightest of the blacks
V_RING     = (0.88, 0.63, 0.16)   # gold focusing rings
V_FIN      = (0.88, 0.63, 0.16)   # gold radiator fins
V_COOLANT  = (0.88, 0.63, 0.16)   # gold coolant lines, fins to sleeve
V_EMITTER  = (0.88, 0.63, 0.16)   # gold emitter bell

parts = []

# Power / capacitor section at the back, with its mounting collar.
parts.append(S.cyl(0.040, 0.060, (0, 0, -0.095), V_POWER, bands=[('Z', 100.0)], amp=0.20))
parts.append(S.cyl(0.034, 0.012, (0, 0, -0.057), V_COLLAR, bands=[('Z', 150.0)], amp=0.14))

# Barrel, with two focusing rings along it.
parts.append(S.cyl(0.018, 0.170, (0, 0, 0.010), V_BARREL, bands=[('Z', 86.7)], amp=0.18))
for z in (-0.015, 0.040):
    parts.append(S.cyl(0.027, 0.008, (0, 0, z), V_RING, bands=[('Z', 200.0)], amp=0.12))

# Emitter: flaring out to the aperture at the outward end, with the mouth itself black.
# The bell is the one thing on the model that is pointed at you, so leaving it the same
# gold as the bell around it closed the barrel up and lost what the weapon is for.
parts.append(S.cone(0.020, 0.032, 0.030, (0, 0, 0.110), V_EMITTER))
parts.append(S.hatch((0, 0, 0.1235), 0.027, S.BLACK, depth=0.004, segments=10))

# Radiator fins around the power section.  Their grooves run along Z, the axis every
# fin shares, so all four grain identically however they are rotated about it - bands
# along a transverse axis would run lengthwise on one pair and crosswise on the other.
for i in range(4):
    a = math.radians(90 * i)
    parts.append(S.box((0.060, 0.004, 0.042),
                       (math.cos(a) * 0.070, math.sin(a) * 0.070, -0.093),
                       V_FIN, rot=(0, 0, a), bands=[('Z', 166.7)], amp=0.35))

# Cryo sleeve around the gain medium at the barrel root, and the coolant lines running to
# it from the root of every fin.  This is the only genuinely thermal part of the weapon,
# so it is the only gold on it; the capacitor section behind it is now bare.
parts.append(S.cyl(0.025, 0.034, (0, 0, -0.032), V_SLEEVE,
                   bands=[('Z', 233.3)], amp=0.30))
for i in range(4):
    a = math.radians(90 * i)
    c, s_ = math.cos(a), math.sin(a)
    parts.append(S.pipe((c * 0.044, s_ * 0.044, -0.093), (c * 0.022, s_ * 0.022, -0.036),
                        0.0035, V_COOLANT))

# Hazard bands: one at the muzzle where the beam comes out, one round the capacitor
# section, which is the other part of this that will kill someone working on it.
parts.append(S.cyl(0.0205, 0.006, (0, 0, 0.092), S.RED))
parts.append(S.cyl(0.0415, 0.005, (0, 0, -0.108), S.RED))

S.finish(parts, "OrbitalLaser", out, tex_out, tag="LASER")
