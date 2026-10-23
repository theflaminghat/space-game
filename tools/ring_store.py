"""Orbital ring store for 'Don't Go Extinct' - planet.gd's "ring_store" lane mesh.

buildings.gd: "Superconducting loop of orbital diameter, holding current indefinitely.
Stellar-scale energy storage."

This is the hard one to tell apart.  It is the same physics as the Superconducting
Storage Ring one lane inward, its colour is nearly the same teal, and its radius is
0.04 away - so the silhouette has to carry the entire difference, and the two sit close
enough that a player will see them together.

What separates them is in the description: this is a LOOP, not a coil in a machine.

  * Its centre is EMPTY.  The storage ring's hub and spokes are the busiest part of it;
    here there is nothing inside the hoop at all, because at orbital diameter there is
    nothing to brace against.  That hole is the single clearest read at a glance.
  * It is bigger and thinner - near the widest the lane spacing allows, on a slender
    conduit, where the storage ring is a compact fat-tubed device.
  * It is SMOOTH.  The storage ring is wound 40 times and reads as coil; this carries
    one current in one conduit, so it gets only faint segment joints at 16.

Thin, but not as thin as the fiction wants: a conduit of truly proportionate gauge
would be sub-pixel at the size these actually render, and a megastructure that vanishes
is worse than one slightly too stout.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_LOOP, V_STATION = 0.72, 0.50

R_MAJOR = 0.145   # near the widest the 0.04 lane spacing leaves room for
R_TUBE = 0.014

parts = []

# The loop.  32 segments: a big thin hoop shows its polygon count, where the storage
# ring's fat tube hides it at 20.
parts.append(S.torus(R_MAJOR, R_TUBE, (0, 0, 0), V_LOOP,
                     major_seg=32, minor_seg=5, windings=16, amp=0.12, grime=0.08))

# Three tap stations on the loop - far fewer and smaller than the storage ring's six
# cryostat blocks, so they read as punctuation on a cable rather than as the machine.
for i in range(3):
    a = math.radians(120 * i)
    parts.append(S.box((0.032, 0.026, 0.044),
                       (math.cos(a) * R_MAJOR, math.sin(a) * R_MAJOR, 0),
                       V_STATION, rot=(0, 0, a), bands=[('Z', 400.0)], amp=0.18))

S.finish(parts, "OrbitalRingStore", out, tex_out, tag="STORE")
