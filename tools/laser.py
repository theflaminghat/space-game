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

# The aperture is the bright note: the lane colour is a hot red, so a high value there
# reads as the emitter rather than as more hull.
V_APERTURE, V_BARREL, V_RING, V_POWER, V_COLLAR, V_FIN = 0.95, 0.70, 0.55, 0.62, 0.50, 0.35

parts = []

# Power / capacitor section at the back, with its mounting collar.
parts.append(S.cyl(0.040, 0.060, (0, 0, -0.095), V_POWER, bands=[('Z', 300.0)], amp=0.20))
parts.append(S.cyl(0.034, 0.012, (0, 0, -0.057), V_COLLAR, bands=[('Z', 450.0)], amp=0.14))

# Barrel, with two focusing rings along it.
parts.append(S.cyl(0.018, 0.170, (0, 0, 0.010), V_BARREL, bands=[('Z', 260.0)], amp=0.18))
for z in (-0.015, 0.040):
    parts.append(S.cyl(0.027, 0.008, (0, 0, z), V_RING, bands=[('Z', 600.0)], amp=0.12))

# Emitter: flaring out to the aperture at the outward end.
parts.append(S.cone(0.020, 0.032, 0.030, (0, 0, 0.110), V_APERTURE, grime=0.05))

# Radiator fins around the power section.  Their grooves run along Z, the axis every
# fin shares, so all four grain identically however they are rotated about it - bands
# along a transverse axis would run lengthwise on one pair and crosswise on the other.
for i in range(4):
    a = math.radians(90 * i)
    parts.append(S.box((0.060, 0.004, 0.042),
                       (math.cos(a) * 0.070, math.sin(a) * 0.070, -0.093),
                       V_FIN, rot=(0, 0, a), bands=[('Z', 500.0)], amp=0.35, grime=0.06))

S.finish(parts, "OrbitalLaser", out, tex_out, tag="LASER")
