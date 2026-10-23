"""Star lifter for 'Don't Go Extinct' - planet.gd's "lifter" lane mesh.

buildings.gd: "Magnetic nozzles standing off the photosphere, driving a controlled wind
off the Sun and collecting it as hydrogen."

So this is a nozzle, and it is built like one: a wide mouth facing the star, narrowing
to a throat outward, ringed by three field coils that widen with it.  Mass comes off the
photosphere, into the mouth, and out through the throat to the tanks - the shape states
the direction of flow, which is the whole of what this building does.

The mouth faces the STAR, and that is a rendering decision as much as a physical one.
A lane instance is seen from outside, looking down its +Y axis, and a cone built by
primitive_cone_add is capped at both ends - so pointing the mouth outward presents the
viewer with that cap and the thing reads as a flat-topped drum, bell entirely hidden.
Open-ending the cone instead would leave single-sided geometry that Godot's default
back-face culling renders see-through.  Mouth inward solves both: the big cap is turned
away, and what is left against the sky is the flare in silhouette.

The three tanks clamped round the mouth are the "collecting it as hydrogen" half.  They
also stop the bell reading as another of the "dish" lanes further out: those are
apertures pointed somewhere, and four of them still share that primitive, so a bare bell
here would be one more of the same.

It hangs at lane radius 1.060, the second-innermost of the band - the lifters have to
stand close, and the comment in INFRA_LANES says as much.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_BELL, V_COIL, V_THROAT, V_TANK = 0.68, 0.92, 0.50, 0.60

parts = []

# The bell: wide mouth at -Z facing the star, narrowing to the throat at +Z.
# The ribs come from an angular pattern, which on a cone runs them down the flare.
parts.append(S.cone(0.085, 0.022, 0.140, (0, 0, -0.012), V_BELL, segments=16,
                    windings=16, amp=0.22, grime=0.07))

# Throat head on the outward end, where the lifted mass leaves for the tanks.
parts.append(S.cyl(0.020, 0.024, (0, 0, 0.070), V_THROAT, bands=[('Z', 420.0)], amp=0.16))

# Field coils, widening with the bell they ring.  Brightest value on the model: these are
# the part that is energised.  minor_seg 3 on purpose - three of them at six would cost
# more triangles than the rest of the model put together, for a tube 5mm across.
for major, z in ((0.082, -0.062), (0.059, -0.012), (0.037, 0.038)):
    parts.append(S.torus(major, 0.005, (0, 0, z), V_COIL,
                         major_seg=12, minor_seg=3, grime=0.04))

# Collection tankage, clamped round the throat end where the mass arrives.
for i in range(3):
    a = math.radians(120 * i)
    parts.append(S.cyl(0.014, 0.045, (math.cos(a) * 0.060, math.sin(a) * 0.060, 0.043),
                       V_TANK, bands=[('Z', 400.0)], amp=0.18))

S.finish(parts, "StarLifter", out, tex_out, tag="LIFTER")
