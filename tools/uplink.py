"""Microwave uplink - planet.gd's "uplink" lane mesh.

buildings.gd: "Phased-array transmitter.  Adds sending capacity to the power-beam
network."

A phased array is flat, not a dish: the beam is steered by the phase across a face of
emitters, and the face is the whole machine.  So this is a hex emitter panel on a short
mast, carrying a dense element grid, with no curved aperture anywhere on it.

It shares the power-link band with four other blue lanes, which is the hardest crowd in
the whole INFRA_LANES table to stand apart in.  What separates this one is that the face
is FLAT and the model has no dish at all - the Orbital Power Grid two lanes out has a
face too, but carries relay dishes above it.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_FACE, V_BUS, V_MAST, V_MOUNT, V_FIN = 0.78, 0.55, 0.48, 0.60, 0.40

parts = []

# Emitter face: hexagonal, with the element grid crossing it.
parts.append(S.cyl(0.070, 0.016, (0, 0, 0.031), V_FACE, segments=6,
                   bands=[('X', 600.0), ('Y', 600.0)], amp=0.40, grime=0.04))
parts.append(S.cyl(0.010, 0.030, (0, 0, 0.017), V_MAST))

# Bus, its mount, and a pair of small fins.
parts.append(S.box((0.050, 0.050, 0.040), (0, 0, -0.009), V_BUS,
                   bands=[('Z', 400.0)], amp=0.18))
parts.append(S.cyl(0.034, 0.012, (0, 0, -0.033), V_MOUNT, bands=[('Z', 520.0)], amp=0.14))
for sx in (-1, 1):
    parts.append(S.box((0.030, 0.004, 0.030), (sx * 0.035, 0, -0.009), V_FIN,
                       bands=[('Z', 520.0)], amp=0.30, grime=0.05))

S.finish(parts, "MicrowaveUplink", out, tex_out, tag="UPLINK")
