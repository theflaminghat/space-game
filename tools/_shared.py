"""Shared Blender machinery for the lane models in models/.

Imported by the per-model scripts beside it; the leading underscore keeps
build_models.sh from mistaking it for one of them.

Everything here exists to satisfy what planet.gd's MultiMesh lanes impose:

  * ONE surface, NO materials  - mmi.material_override replaces them anyway.
  * Real UVs                   - the lane's material supplies the texture.
  * +Z is radial-outward       - glTF maps Blender +Z to Godot +Y, which is the
                                 'radial' column of the instance Basis.
  * GREYSCALE texture          - the lane sets albedo_color and the map multiplies
                                 through it, so the bake carries value, not hue.

The per-part values have to be assigned BEFORE the join, because afterwards it is
one mesh and the parts are gone - which is why building and baking live in one
script per model rather than a modelling pass and a texturing pass.
"""
import bpy, bmesh, math
import numpy as np
from mathutils.bvhtree import BVHTree


def setup():
    """Empty factory scene with a world (an empty one has none, and baking needs it)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.world = bpy.data.worlds.new("W")
    return bpy.context.scene


def mat(value, bands=(), windings=0, amp=0.0, grime=0.10):
    """A greyscale material: a base value, optional ridging, and a little grime.

    The pattern is driven from OBJECT coordinates, not UVs.  smart_project lays the
    islands out for packing efficiency, so anything authored in UV space would run in
    an arbitrary direction on each island; object space makes the ridges follow the
    hull.

      bands    - [(axis, frequency)] for straight ridges: plating seams, solar cells.
      windings - an INTEGER count of ridges around the Z axis, for a coil.  Integer
                 matters: the angle comes from atan2, which jumps by 2*pi across its
                 branch cut, and sin(n*theta) is continuous there only when n is a
                 whole number.  A fractional count puts one mismatched band in the ring.

    Deliberately NOT metallic.  This is baked with a DIFFUSE/COLOR pass, and Cycles
    scales diffuse albedo down by metalness - so setting it would darken the map by the
    same 0.3 that StandardMaterial3D already applies at runtime, baking it in twice.
    """
    assert float(windings).is_integer(), "windings must be a whole number, got %r" % windings
    m = bpy.data.materials.new("v%.2f_%d_%d" % (value, len(bands), windings))
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]

    def mk(t, **kw):
        n = nt.nodes.new(t)
        for k, v in kw.items():
            setattr(n, k, v)
        return n

    def op(operation, *args):
        """One Math node; args are sockets or constants, in socket order."""
        n = mk("ShaderNodeMath", operation=operation)
        for i, v in enumerate(args):
            if isinstance(v, bpy.types.NodeSocket):
                nt.links.new(v, n.inputs[i])
            else:
                n.inputs[i].default_value = v
        return n.outputs[0]

    coord = mk("ShaderNodeTexCoord")
    sep = mk("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Object"], sep.inputs[0])

    # Ridges: sin(x) folded to 0..1, then squared so the dark lines read as narrow
    # seams between plates rather than a soft sine wash.
    def ridge(phase):
        return op("POWER", op("MULTIPLY_ADD", op("SINE", phase), 0.5, 0.5), 2.0)

    pattern = None
    for axis, freq in bands:
        seam = ridge(op("MULTIPLY", sep.outputs[axis], freq))
        pattern = seam if pattern is None else op("MULTIPLY", pattern, seam)

    if windings:
        angle = op("ARCTAN2", sep.outputs["Y"], sep.outputs["X"])
        seam = ridge(op("MULTIPLY", angle, float(windings)))
        pattern = seam if pattern is None else op("MULTIPLY", pattern, seam)

    out = None if pattern is None else op("MULTIPLY_ADD", pattern, amp, 1.0 - amp)

    noise = mk("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 90.0
    noise.inputs["Detail"].default_value = 4.0
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    dirt = op("MULTIPLY_ADD", noise.outputs["Fac"], grime, 1.0 - grime)
    out = dirt if out is None else op("MULTIPLY", out, dirt)

    nt.links.new(op("MULTIPLY", out, value), bsdf.inputs["Base Color"])

    # The same pattern again as an emission tap, so finish() can bake it on its own as a
    # height field.  Left unlinked from the output: it is swapped in for one pass only.
    #
    # Not a Bump node, which is the obvious way and does not work.  Bump takes the screen
    # derivative of its height input, and derivatives are not defined during a bake - the
    # normal pass comes back perfectly flat, and a flat tangent-space map averages exactly
    # (0.5, 0.5, 1.0), which is also what a correct one averages.  It looks right in every
    # summary statistic and is blank.
    height = mk("ShaderNodeEmission", name="LaneHeight")
    nt.links.new(out, height.inputs["Color"])
    return m


# ── Primitives.  Each takes its greyscale value and pattern, and returns the object ──

def cyl(r, depth, loc, value, segments=8, rot=(0, 0, 0), **kw):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=segments, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.data.materials.append(mat(value, **kw))
    return o


def box(size, loc, value, rot=(0, 0, 0), **kw):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    o.data.materials.append(mat(value, **kw))
    return o


def cone(r_base, r_tip, depth, loc, value, segments=10, rot=(0, 0, 0), **kw):
    bpy.ops.mesh.primitive_cone_add(
        vertices=segments, radius1=r_base, radius2=r_tip, depth=depth,
        location=loc, rotation=rot)
    o = bpy.context.active_object
    o.data.materials.append(mat(value, **kw))
    return o


def torus(major, minor, loc, value, major_seg=16, minor_seg=6, rot=(0, 0, 0), **kw):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor, major_segments=major_seg,
        minor_segments=minor_seg, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.data.materials.append(mat(value, **kw))
    return o


# ── Join, unwrap, bake, export ───────────────────────────────────────────────────────

def _inside(diff, nor, eps=1.0e-3):
    """Is a point inside the surface its closest point lies on?

    The test is the sign of the offset against the surface normal, but it has to be a
    DECISIVE sign.  Where two parts are flush - a vane whose top ends on exactly the
    same plane as the stack beside it - the closest point lands on that shared cap,
    whose normal is perpendicular to the offset, and the dot product sits on zero with
    float noise picking the side.  That is how three of four identical vanes once read
    as touching while the fourth read as adrift: cos(180 degrees) is exactly -1 where
    cos(90) is 6e-17, and the two rounded opposite ways.

    So near-perpendicular counts as outside, and the real gap gets reported.
    """
    length = diff.length
    if length < 1.0e-9:
        return True
    return diff.dot(nor) / length < -eps


def _floating(parts, tol=2.0e-3):
    """Parts that touch nothing else.  Returns [(name, gap)], empty when all are joined up.

    Assumes transforms are already applied, so object space is world space.

    A floating part is invisible in the summary line - vertex and triangle counts and
    overall bounds all look perfectly normal with a solar panel hanging in the vacuum
    beside its spacecraft - and easy to miss in a render if it happens to overlap the
    body from the angle you looked from.  So the build checks instead of the eye.

    Touching is decided by BVH surface overlap first, and only then by distance.  The
    distance test alone is not enough: a focusing ring threaded onto a barrel genuinely
    intersects it, but every one of the ring's vertices sits out at its own radius and
    every one of the barrel's sits in its end caps, so the nearest vertex-to-surface
    measurement is the ring's clearance over the barrel and the part reads as adrift.
    What is wanted is whether the surfaces cross, which is what overlap() answers.

    Distance is kept as the fallback, for parts that abut without intersecting and for
    one part wholly inside another - a point on the far side of the nearest surface from
    its normal is inside that part, not a gap away from it.  It is also what gets
    reported, so the message says how wide the gap is.
    """
    if len(parts) < 2:
        return []
    # Built straight from mesh data rather than FromObject: transforms have just been
    # applied, so these coordinates are already world space, and going through the
    # depsgraph here risks reading it before it has caught up with that apply.
    trees = [BVHTree.FromPolygons([v.co.copy() for v in o.data.vertices],
                                  [list(poly.vertices) for poly in o.data.polygons])
             for o in parts]
    out = []
    for i, a in enumerate(parts):
        touched = False
        best = float("inf")
        for j, b in enumerate(parts):
            if i == j:
                continue
            if trees[i].overlap(trees[j]):
                touched = True
                break
            for src, dst in ((a, b), (b, a)):
                for v in src.data.vertices:
                    ok, loc, nor, _idx = dst.closest_point_on_mesh(v.co)
                    if not ok:
                        continue
                    diff = v.co - loc
                    d = 0.0 if _inside(diff, nor) else diff.length
                    if d < best:
                        best = d
            if best <= tol:
                touched = True
                break
        if not touched:
            out.append((a.name, best))
    return out


def _height_to_normal(height, strength=7.0):
    """Turn a baked height field into an encoded tangent-space normal map.

    Done numerically rather than with a Bump node for the reason given in mat(): bump
    cannot bake.  The slope at each texel comes from a central difference of its
    neighbours, which is exact for a field that was itself generated procedurally.

    Row 0 of a Blender image is the BOTTOM row, so the row axis already runs the same way
    as V and the green channel needs no flip for the OpenGL convention Godot expects.
    """
    dv, du = np.gradient(height.astype(np.float32))
    nx = -du * strength
    ny = -dv * strength
    nz = np.ones_like(nx)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.empty((height.size, 4), dtype=np.float32)
    out[:, 0] = (nx * inv * 0.5 + 0.5).reshape(-1)
    out[:, 1] = (ny * inv * 0.5 + 0.5).reshape(-1)
    out[:, 2] = (nz * inv * 0.5 + 0.5).reshape(-1)
    out[:, 3] = 1.0
    return out


def finish(parts, name, out, tex_out, res=512, tag="MODEL"):
    """Join the parts into one textured, exported asset and print a summary line."""
    # Apply transforms before anything measures the parts, so object space is world
    # space and the connectivity check below can compare them directly.
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    adrift = _floating(parts)
    if adrift:
        raise SystemExit("%s: %d part(s) touch nothing else — %s" % (
            name, len(adrift),
            ", ".join("%s (nearest %.4f)" % (n, d) for n, d in adrift)))

    bpy.ops.object.join()

    obj = bpy.context.active_object
    obj.name = name
    # location=True matters.  join() leaves the object's origin wherever parts[0] sat, and
    # everything downstream reads the MESH, not the node: planet.gd pulls the ArrayMesh out
    # of the imported scene and hands it to a MultiMesh, which positions instances from the
    # mesh's own coordinates.  Leaving the origin unapplied offsets every instance by
    # parts[0]'s location - invisible whenever that part happens to sit at (0,0,0), which is
    # why the depot and the ring did not catch this and the laser did.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()

    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 64
    scene.render.bake.margin = 16    # bleed past island edges, or seams show as dark lines
    scene.render.bake.use_clear = True

    def bake(pass_name, **kw):
        img = bpy.data.images.new("bake_" + pass_name, res, res, float_buffer=True)
        for slot in me.materials:
            nodes = slot.node_tree.nodes
            n = nodes.new("ShaderNodeTexImage")
            n.image = img
            nodes.active = n
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.bake(type=pass_name, **kw)
        buf = np.empty(res * res * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        return buf.reshape(-1, 4)

    ao = bake('AO')
    col = bake('DIFFUSE', pass_filter={'COLOR'})

    # Height pass: swap each material's output over to the emission tap, bake, swap back.
    restore = []
    for slot in me.materials:
        tree = slot.node_tree
        tap = tree.nodes.get("LaneHeight")
        mat_out = next((n for n in tree.nodes if n.type == 'OUTPUT_MATERIAL'), None)
        if tap is None or mat_out is None:
            continue
        was = mat_out.inputs["Surface"].links[0].from_socket
        tree.links.new(tap.outputs["Emission"], mat_out.inputs["Surface"])
        restore.append((tree, mat_out, was))
    height = bake('EMIT')[:, 0].reshape(res, res)
    for tree, mat_out, was in restore:
        tree.links.new(was, mat_out.inputs["Surface"])

    nrm = _height_to_normal(height)

    # Multiply in linear space, then flatten alpha: the lane's material is opaque and a
    # stray alpha gradient would punch holes in the hull.
    px = col.copy()
    px[:, :3] *= 0.35 + 0.65 * ao[:, :3]   # keep AO from crushing crevices to black
    px[:, 3] = 1.0

    final = bpy.data.images.new("albedo", res, res, float_buffer=True)
    final.pixels.foreach_set(px.reshape(-1))

    # Save 8-bit greyscale, not Blender's default 16-bit RGB.  The map carries one
    # channel of information and the lane supplies the colour, so three 16-bit channels
    # would be ~10x the bytes in the repo for nothing a player could see.
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'BW'
    scene.render.image_settings.color_depth = '8'
    scene.render.image_settings.compression = 95
    final.save_render(filepath=tex_out, scene=scene)

    # Normal map: RGB, and saved as NON-COLOUR data.  A normal map holds directions, not
    # brightness, so letting the sRGB transform touch it on the way out would bend every
    # one of those directions and light the model wrongly in a way that looks like a
    # modelling mistake rather than a colour-management one.
    # Saved with Image.save(), NOT save_render().  save_render pushes the buffer through
    # the scene's colour management on the way out, and with the non-colour override that
    # pipeline wrote a 1KB file of pure black - a valid PNG of nothing.  save() writes the
    # buffer as it stands, honouring only the image's own colourspace.
    nrm_out = tex_out.replace("_albedo.png", "_normal.png")
    nrm_img = bpy.data.images.new("normal", res, res, float_buffer=False)
    nrm_img.colorspace_settings.name = 'Non-Color'   # before the pixels, not after
    nrm_img.pixels.foreach_set(nrm.reshape(-1))
    nrm_img.filepath_raw = nrm_out
    nrm_img.file_format = 'PNG'
    nrm_img.save()

    me.materials.clear()
    dims = obj.dimensions

    bpy.ops.export_scene.gltf(
        filepath=out, export_format='GLB',
        export_apply=True, export_materials='NONE',
        export_yup=True, use_selection=False)

    # A tangent-space normal map should average near (0.5, 0.5, 1.0) - mostly "straight
    # out", perturbed either side.  Printing it is the cheapest guard against having saved
    # a flat or colour-managed one, both of which are invisible in a thumbnail.
    lit = nrm
    print("%s_OK verts=%d tris=%d dims=%.3f,%.3f,%.3f uv=%s tex=%dx%d range=%.2f-%.2f "
          "nrm=%.2f,%.2f,%.2f sd=%.4f" % (
        tag, len(me.vertices), len(me.loop_triangles), dims.x, dims.y, dims.z,
        bool(me.uv_layers), res, res, px[:, :3].min(), px[:, :3].max(),
        lit[:, 0].mean(), lit[:, 1].mean(), lit[:, 2].mean(), lit[:, :2].std()))
