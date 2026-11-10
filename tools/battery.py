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

V_CELL    = (0.46, 0.50, 0.54)   # cell stacks
V_RAIL    = (0.52, 0.54, 0.58)   # rails
V_PLATE   = (0.54, 0.56, 0.60)   # end plates - structure, so bare steel and not gold
V_MLI     = (0.88, 0.63, 0.16)   # gold blankets hung down the two shaded faces - panels
                                 # standing off the rack, not a coat of paint on it
V_BUSBAR  = (0.76, 0.48, 0.27)   # copper: terminals and the harness that links them
V_CONTROL = (0.87, 0.87, 0.85)   # controller

parts = []

# Corner rails, running the full height.
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(S.box((0.010, 0.010, 0.170), (sx * 0.042, sy * 0.042, 0), V_RAIL,
                           bands=[('Z', 100.0)], amp=0.20))

# Cell slabs, with a grid so the individual cells read rather than a blank block.
for z in (-0.063, -0.021, 0.021, 0.063):
    parts.append(S.box((0.090, 0.090, 0.022), (0, 0, z), V_CELL,
                       bands=[('X', 100.0), ('Y', 100.0)], amp=0.35))

# End plates, and the controller on the outward one.
for sz in (-1, 1):
    parts.append(S.box((0.100, 0.100, 0.010), (0, 0, sz * 0.090), V_PLATE,
                       bands=[('Z', 173.3)], amp=0.14))

# Insulation blankets down the two shaded faces, caught under the corner rails.  Gold is
# the one thing on this model that is thermal hardware, so it is the one thing wearing it
# - the end plates it used to sit on are load-bearing structure.
for sx in (-1, 1):
    parts.append(S.box((0.005, 0.098, 0.160), (sx * 0.046, 0, 0), V_MLI,
                       bands=[('Z', 233.3)], amp=0.30))
parts.append(S.box((0.040, 0.040, 0.018), (0, 0, 0.101), V_CONTROL,
                   bands=[('Z', 160.0)], amp=0.16))

# Terminals on each slab and the harness bussing them up to the controller: the detail
# that says this is a rack of cells wired in series rather than a stack of plates.
for z in (-0.063, -0.021, 0.021, 0.063):
    parts.append(S.hatch((0, 0.047, z), 0.008, V_BUSBAR, axis='Y', depth=0.006))
parts.append(S.pipe((0, 0.050, -0.070), (0, 0.050, 0.090), 0.0035, V_BUSBAR))
parts.append(S.pipe((0, 0.050, 0.090), (0, 0.018, 0.101), 0.0035, V_BUSBAR))

# Marked cap on the controller: the disconnect.
parts.append(S.hatch((0, 0, 0.112), 0.010, S.RED, depth=0.005))

S.finish(parts, "OrbitalBattery", out, tex_out, tag="BATTERY")
