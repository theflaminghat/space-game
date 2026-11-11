"""Star lifter for 'Kardashev' - planet.gd's "lifter" lane mesh.

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

# The bell stares into a photosphere, so it is refractory black: a surface meant to take
# starlight and not reflect it, the same reasoning as the core mixer's lances.  Black also
# buys this model its silhouette back - a pale bell washed out against the star behind it,
# and the flare in outline is the only thing the shape has to say.
#
# Gold is the thermal hardware, as everywhere else in the set: the coil windings' jackets
# and the throat, which is the one section with heat to shed rather than soak.  Two blacks
# a step apart, because one value welded bell and throat housing into a single lump.
V_BELL   = (0.09, 0.09, 0.10)   # refractory black bell, facing the star
V_HOUSE  = (0.15, 0.15, 0.17)   # black throat housing, a step up from the bell
V_COIL   = (0.88, 0.63, 0.16)   # gold-jacketed field coils
V_THROAT = (0.90, 0.66, 0.18)   # gold throat, the hot section
V_TANK   = (0.42, 0.46, 0.53)   # steel collection tanks
V_LINE   = (0.34, 0.36, 0.40)   # transfer plumbing

parts = []

# The bell: wide mouth at -Z facing the star, narrowing to the throat at +Z.
# The ribs come from an angular pattern, which on a cone runs them down the flare.
parts.append(S.cone(0.085, 0.022, 0.140, (0, 0, -0.012), V_BELL, segments=16,
                    windings=16, amp=0.22))

# Throat head on the outward end, where the lifted mass leaves for the tanks: a black
# housing with the gold throat collar standing proud of it, so the hot section is a band
# and not the whole head.
parts.append(S.cyl(0.021, 0.024, (0, 0, 0.068), V_HOUSE, bands=[('Z', 140.0)], amp=0.16))
parts.append(S.torus(0.0215, 0.0045, (0, 0, 0.074), V_THROAT, major_seg=14, minor_seg=3))

# Field coils, widening with the bell they ring.  The brightest thing on the model, and
# now the only bright thing: against a black bell they are what the eye lands on, which is
# right, because they are the part that is energised.  minor_seg 3 on purpose - three of them at six would cost
# more triangles than the rest of the model put together, for a tube 5mm across.
for major, z in ((0.082, -0.062), (0.059, -0.012), (0.037, 0.038)):
    parts.append(S.torus(major, 0.005, (0, 0, z), V_COIL,
                         major_seg=12, minor_seg=3))

# Collection tankage, clamped round the throat end where the mass arrives.
for i in range(3):
    a = math.radians(120 * i)
    parts.append(S.cyl(0.014, 0.045, (math.cos(a) * 0.060, math.sin(a) * 0.060, 0.043),
                       V_TANK, bands=[('Z', 133.3)], amp=0.18))

# Transfer lines from the throat down to each collection tank, and a fill hatch on every
# tank.  The bell states the direction of flow; the plumbing states where it ends up.
for i in range(3):
    a = math.radians(120 * i)
    c, s_ = math.cos(a), math.sin(a)
    parts.append(S.pipe((c * 0.016, s_ * 0.016, 0.070), (c * 0.058, s_ * 0.058, 0.058),
                        0.0040, V_LINE))
    parts.append(S.hatch((c * 0.060, s_ * 0.060, 0.067), 0.008, S.BLACK,
                         depth=0.006))

# Markings.  The throat band has to stand clear of the 0.021 housing by more than a
# hair or the bake never catches it - 0.001 proud reads as nothing at a 512 map.  The
# second one rings the mouth: the line a tug does not cross, on the part aimed at a star.
parts.append(S.cyl(0.026, 0.005, (0, 0, 0.0775), S.RED))
parts.append(S.torus(0.0845, 0.0035, (0, 0, -0.078), S.RED, major_seg=20, minor_seg=3))

S.finish(parts, "StarLifter", out, tex_out, tag="LIFTER")
