"""Orbital battery - planet.gd's "battery" lane mesh.

buildings.gd: "Orbital battery farm.  Raises the energy storage cap", and in the
definition above it, "10x the Battery Bank (energy only)".

Farm is the operative word.  Everything else in the band is one machine; this is the
same cell repeated until it adds up, so it is built as a rack: four cell slabs threaded
on corner rails between two end plates, with the controller on top.  A stack of
identical layers is a silhouette nothing else here has.

The rails are what make it a rack rather than four slabs floating in a column - they run
the full height and pass through every slab's corner, so the thing is one piece.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_CELL, V_RAIL, V_PLATE, V_CONTROL = 0.68, 0.45, 0.58, 0.80

parts = []

# Corner rails, running the full height.
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(S.box((0.010, 0.010, 0.170), (sx * 0.042, sy * 0.042, 0), V_RAIL,
                           bands=[('Z', 300.0)], amp=0.20))

# Cell slabs, with a grid so the individual cells read rather than a blank block.
for z in (-0.063, -0.021, 0.021, 0.063):
    parts.append(S.box((0.090, 0.090, 0.022), (0, 0, z), V_CELL,
                       bands=[('X', 300.0), ('Y', 300.0)], amp=0.35, grime=0.06))

# End plates, and the controller on the outward one.
for sz in (-1, 1):
    parts.append(S.box((0.100, 0.100, 0.010), (0, 0, sz * 0.090), V_PLATE,
                       bands=[('Z', 520.0)], amp=0.14))
parts.append(S.box((0.040, 0.040, 0.018), (0, 0, 0.101), V_CONTROL,
                   bands=[('Z', 480.0)], amp=0.16))

S.finish(parts, "OrbitalBattery", out, tex_out, tag="BATTERY")
