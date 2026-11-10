"""Render one lane model the way planet.gd lights it, for eyeballing a change.

Not a model script - the leading underscore keeps build_models.sh from running it.

    blender -b -noaudio --python tools/_preview_look.py -- <glb> <albedo> <normal> <out.png>

The view transform is forced to Standard.  Blender defaults to AgX, which desaturates
hard; Godot's Environment sets no tonemapper and so renders LINEAR, and a preview through
AgX quietly shows less colour than the game will.
"""
import bpy, sys, math
glb, alb, nrm, out = sys.argv[-4], sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
sc = bpy.context.scene
sc.view_settings.view_transform = 'Standard'
mat = bpy.data.materials.new("L"); mat.use_nodes = True
nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Metallic"].default_value = 0.3
bsdf.inputs["Roughness"].default_value = 0.7
ti = nt.nodes.new("ShaderNodeTexImage"); ti.image = bpy.data.images.load(alb)
nt.links.new(ti.outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(ti.outputs["Color"], bsdf.inputs["Emission Color"])
bsdf.inputs["Emission Strength"].default_value = 0.20
ni = nt.nodes.new("ShaderNodeTexImage")
nimg = bpy.data.images.load(nrm); nimg.colorspace_settings.name = 'Non-Color'
ni.image = nimg
nmn = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(ni.outputs["Color"], nmn.inputs["Color"])
nt.links.new(nmn.outputs["Normal"], bsdf.inputs["Normal"])
for o in [o for o in sc.objects if o.type == 'MESH']:
    o.data.materials.clear(); o.data.materials.append(mat)
k = bpy.data.lights.new("K", type='SUN'); k.energy = 3.0
ko = bpy.data.objects.new("K", k); sc.collection.objects.link(ko)
ko.rotation_euler = (math.radians(58), 0, math.radians(40))
f = bpy.data.lights.new("F", type='SUN'); f.energy = 0.8
fo = bpy.data.objects.new("F", f); sc.collection.objects.link(fo)
fo.rotation_euler = (math.radians(70), 0, math.radians(-120))
cd = bpy.data.cameras.new("C"); cd.lens = 55
cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 96
sc.render.resolution_x = 420; sc.render.resolution_y = 420
sc.render.image_settings.file_format = 'PNG'
w = bpy.data.worlds.new("W"); w.use_nodes = True; sc.world = w
w.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.02, 0.03, 1)
e, a, d = math.radians(28), math.radians(45), 0.60
cam.location = (d*math.cos(e)*math.sin(a), -d*math.cos(e)*math.cos(a), d*math.sin(e))
cam.rotation_euler = (math.radians(90) - e, 0, a)
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("LOOK_OK")
