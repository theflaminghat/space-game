"""Superconducting storage ring for 'Don't Go Extinct' - planet.gd's "sc_ring" lane mesh.

A superconducting magnetic energy store: current circulates in a closed cryogenic
coil and the energy sits in its magnetic field.  So the model is a coil ring with
cryostat modules clamped around it, braced back to a central plant by spokes.

It gets its own mesh kind rather than replacing "ring", which the Orbital Habitat,
Orbital Ring Store and Core Mixing Array all still share.  What distinguishes this
one at a glance is that it is clearly WOUND - the lane colour is already close to
the Ring Store's, so the silhouette has to carry the difference.

The ring lies in XY with its axis along Z, which glTF maps to Godot +Y - the
radial-outward column of the instance basis.  So it is seen face-on from outside
the body it orbits, which is how the torus primitive it replaces already read.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_COIL, V_CRYO, V_HUB, V_SPOKE = 0.82, 0.52, 0.68, 0.45

R_COIL = 0.112   # major radius; overall width stays under the 0.34 the lanes allow
R_TUBE = 0.024

parts = []

# The coil itself.  40 windings, not more: at 512px the torus island is a few hundred
# pixels around, so a finer pitch would alias into grey mush rather than read as wound.
parts.append(S.torus(R_COIL, R_TUBE, (0, 0, 0), V_COIL,
                     major_seg=20, minor_seg=6, windings=40, amp=0.32))

# Cryostat modules clamped around the coil - the cold mass has to live somewhere.
# Offset from the spoke angles below so the two never collide.
for i in range(6):
    a = math.radians(15 + 60 * i)
    parts.append(S.box((0.034, 0.040, 0.056),
                       (math.cos(a) * R_COIL, math.sin(a) * R_COIL, 0),
                       V_CRYO, rot=(0, 0, a), bands=[('Z', 380.0)], amp=0.18))

# Central plant, braced to the coil by four spokes.
parts.append(S.cyl(0.030, 0.026, (0, 0, 0), V_HUB, bands=[('Z', 450.0)], amp=0.16))
for i in range(4):
    a = math.radians(90 * i)
    parts.append(S.box((0.085, 0.010, 0.007),
                       (math.cos(a) * 0.070, math.sin(a) * 0.070, 0),
                       V_SPOKE, rot=(0, 0, a), grime=0.08))

S.finish(parts, "StorageRing", out, tex_out, tag="RING")
