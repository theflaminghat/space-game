"""Contact sheet of every lane model, labelled, lit the way planet.gd lights them.

Not a model script - the leading underscore keeps build_models.sh from running it.

    blender -b -noaudio --python tools/_preview_grid.py -- <out.png>

Useful for the questions a single render cannot answer: whether two lanes have drifted
into looking like each other, and whether a palette rule holds across the whole set.
"""
import bpy, sys, math, os, glob
from mathutils import Vector
M = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models")
out = sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.view_settings.view_transform = 'Standard'   # Godot tonemaps LINEAR, not AgX
cells = []
names = sorted(os.path.basename(p)[:-4] for p in glob.glob(M + "/*.glb"))
COLS, PITCH = 6, 0.46
for i, n in enumerate(names):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath="%s/%s.glb" % (M, n))
    new = [o for o in set(bpy.data.objects) - before if o.type == 'MESH']
    mat = bpy.data.materials.new(n); mat.use_nodes = True
    nt = mat.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Metallic"].default_value = 0.3
    b.inputs["Roughness"].default_value = 0.7
    ti = nt.nodes.new("ShaderNodeTexImage")
    ti.image = bpy.data.images.load("%s/%s_albedo.png" % (M, n))
    nt.links.new(ti.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(ti.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = 0.20
    ni = nt.nodes.new("ShaderNodeTexImage")
    nimg = bpy.data.images.load("%s/%s_normal.png" % (M, n))
    nimg.colorspace_settings.name = 'Non-Color'; ni.image = nimg
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(ni.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    cx, cy = (i % COLS - (COLS - 1) / 2.0) * PITCH, -(i // COLS) * PITCH
    for o in new:
        o.data.materials.clear(); o.data.materials.append(mat)
        o.location = (cx, cy, 0)
    cells.append((cx, cy, new[0].name if new else n))
k = bpy.data.lights.new("K", type='SUN'); k.energy = 3.0
ko = bpy.data.objects.new("K", k); sc.collection.objects.link(ko)
ko.rotation_euler = (math.radians(58), 0, math.radians(40))
f = bpy.data.lights.new("F", type='SUN'); f.energy = 0.8
fo = bpy.data.objects.new("F", f); sc.collection.objects.link(fo)
fo.rotation_euler = (math.radians(70), 0, math.radians(-120))

# Caption under each model, billboarded to the camera and lit by its own emission so it
# stays legible wherever the model's shading lands.  The angle is spelled out here rather
# than read off the camera, which does not exist yet - the two have to agree or the text
# renders edge-on.
E, A = math.radians(30), math.radians(40)
lm = bpy.data.materials.new("label"); lm.use_nodes = True
lb = lm.node_tree.nodes["Principled BSDF"]
lb.inputs["Emission Color"].default_value = (0.86, 0.88, 0.92, 1)
lb.inputs["Emission Strength"].default_value = 1.0
lb.inputs["Base Color"].default_value = (0, 0, 0, 1)
for cx, cy, label in cells:
    bpy.ops.object.text_add(location=(cx, cy - PITCH * 0.46, -0.03))
    t = bpy.context.active_object
    t.data.body = label; t.data.size = 0.026; t.data.align_x = 'CENTER'
    t.rotation_euler = (math.radians(90) - E, 0, A)
    t.data.materials.append(lm)

cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'
cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
cam.rotation_euler = (math.radians(90) - E, 0, A)
cam.location = (0, 0, 0)
bpy.context.view_layer.update()

# Fit the frame to what is actually there rather than to the grid's nominal width.  The
# view is three-quarter, so a row projects wider and shallower than its spacing suggests,
# and a guessed ortho_scale clipped the end model off every row.
inv = cam.matrix_world.inverted()
pts = []
for o in sc.objects:
    if o.type == 'MESH':
        pts += [inv @ (o.matrix_world @ v.co) for v in o.data.vertices]
    elif o.type == 'FONT':
        pts += [inv @ (o.matrix_world @ Vector(c)) for c in o.bound_box]
xs = [p.x for p in pts]; ys = [p.y for p in pts]
pad = 0.04
x0, x1, y0, y1 = min(xs) - pad, max(xs) + pad, min(ys) - pad, max(ys) + pad
cd.ortho_scale = max(x1 - x0, y1 - y0)
# Shift along the camera's own right and up axes to centre - and back along its view axis
# as well.  An ortho camera still clips at its own near plane, so centring it without the
# pull-back drops it into the middle of the scene and renders most of the sheet from
# behind that plane.
cd.clip_start, cd.clip_end = 0.01, 20.0
cam.location = cam.matrix_world.to_3x3() @ Vector(((x0 + x1) / 2.0, (y0 + y1) / 2.0, 4.0))
bpy.context.view_layer.update()

sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 48
W = 1400
sc.render.resolution_x = W
sc.render.resolution_y = max(1, int(round(W * (y1 - y0) / (x1 - x0))))
w = bpy.data.worlds.new("W"); w.use_nodes = True; sc.world = w
w.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.02, 0.03, 1)
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("GRID_OK %dx%d" % (sc.render.resolution_x, sc.render.resolution_y))
