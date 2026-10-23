"""Core mixing array for 'Don't Go Extinct' - planet.gd's "core_mixer" lane mesh.

buildings.gd: "Driven circulation reaching from the Sun's envelope into its core,
feeding it unburnt hydrogen it would never otherwise meet", and in the definition
above it, "the surgical end of stellar engineering ... this stirs the star".

Two things follow from that, and they are what the model is:

  * It REACHES INWARD.  Everything else in the band either points away from the body
    or lies flat across it; this is the only one whose business end is aimed down the
    gravity well.  So it is a bundle of lances hanging below a shield, and the lances
    are what the silhouette is for.
  * It is an ARRAY, not a gun.  Five lances rather than one barrel - which is also
    what keeps it from reading as the Orbital Laser stood on its head, since that is
    otherwise a fair description of the shape.

It is allowed_types ["star"], so unlike every other model here it is only ever drawn
around the Sun, at lane radius 1.020 - the innermost of the whole band.  That is also
why the shield is the brightest value on it: that face sits closest to the star.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shared as S

out = sys.argv[-1]
tex_out = out.replace(".glb", "_albedo.png")
S.setup()

V_LANCE, V_SHIELD, V_STACK, V_VANE = 0.45, 0.90, 0.62, 0.75

parts = []

# The lances, pointing -Z: inward, once +Z is mapped to Godot's radial-outward axis.
# primitive_cone_add puts radius1 at -Z, so the NARROW radius goes first to point the
# tip down the well; the obvious order builds the array upside down.
# Both lengths run up INTO the shield rather than stopping just short of it: at 0.160
# and 0.100 they ended 0.004 and 0.009 below it, hanging unattached under a plate.
parts.append(S.cone(0.003, 0.022, 0.170, (0, 0, -0.031), V_LANCE,
                    bands=[('Z', 300.0)], amp=0.16))
for i in range(4):
    a = math.radians(45 + 90 * i)
    parts.append(S.cone(0.002, 0.011, 0.120, (math.cos(a) * 0.038, math.sin(a) * 0.038, -0.001),
                        V_LANCE, segments=8, bands=[('Z', 400.0)], amp=0.16))

# Shield: the face that sits closest to the star, so the brightest value here.
parts.append(S.cyl(0.058, 0.012, (0, 0, 0.054), V_SHIELD, segments=12,
                   windings=12, amp=0.28, grime=0.05))

# Control stack and its radiator vanes, on the cold side.
parts.append(S.cyl(0.030, 0.055, (0, 0, 0.089), V_STACK, bands=[('Z', 420.0)], amp=0.18))
# Fins, not plates: thin tangentially and running outward from the stack, the way the
# Orbital Laser's radiators are built.  As face-on plates at radius 0.048 they were
# 0.016 clear of the stack they are supposed to be bolted to.
for i in range(4):
    a = math.radians(90 * i)
    parts.append(S.box((0.040, 0.004, 0.045),
                       (math.cos(a) * 0.045, math.sin(a) * 0.045, 0.094),
                       V_VANE, rot=(0, 0, a), grime=0.06))

S.finish(parts, "CoreMixingArray", out, tex_out, tag="MIXER")
