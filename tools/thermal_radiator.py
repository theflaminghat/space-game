"""Thermal radiator - planet.gd's "thermal" lane mesh.

buildings.gd: "Field of high-emissivity panels that sheds waste heat to space."

A FIELD: discrete rigid panels laid out in a plane on a shared spine, which is what
separates it from the two other radiators in the band.  The Orbital Radiator Array is
fins standing off a spine in three dimensions; the Radiator Swarm is loose film.  This
one is a flat, framed, six-panel farm.

It carries "ground": true in INFRA_LANES, so on a rocky world it is ground infrastructure
and gets no lane at all - this is only ever drawn around a gas giant or the star.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_PANEL    = (0.88, 0.63, 0.16)   # gold high-emissivity panels
V_SPINE    = (0.40, 0.41, 0.44)   # spine
V_MANIFOLD = (0.76, 0.48, 0.27)   # copper manifold - plumbing, not insulation
V_LINE     = (0.68, 0.44, 0.26)   # the coolant runs it feeds

parts = []

# Spine, running the length of the field, with the panels hung either side of it.
parts.append(S.box((0.230, 0.010, 0.010), (0, 0, 0), V_SPINE, bands=[('X', 100.0)], amp=0.20))
for x in (-0.073, 0.0, 0.073):
    for sy in (-1, 1):
        parts.append(S.box((0.066, 0.070, 0.004), (x, sy * 0.038, 0), V_PANEL,
                           bands=[('X', 173.3)], amp=0.32))

parts.append(S.box((0.030, 0.030, 0.016), (0, 0, 0), V_MANIFOLD,
                   bands=[('Z', 166.7)], amp=0.16))

# Coolant runs from the manifold out along the spine and into every panel.  Six plates on
# a bar are a frame; six plates fed from one manifold are a radiator.
for sy in (-1, 1):
    parts.append(S.pipe((-0.112, sy * 0.009, 0.0), (0.112, sy * 0.009, 0.0),
                        0.0030, V_LINE))
    for x in (-0.073, 0.0, 0.073):
        parts.append(S.pipe((x, sy * 0.009, 0.0), (x, sy * 0.030, 0.0),
                            0.0026, V_LINE))

parts.append(S.hatch((0, 0, 0.010), 0.008, S.RED, depth=0.005))

S.finish(parts, "ThermalRadiator", out, tex_out, tag="THERMAL")
