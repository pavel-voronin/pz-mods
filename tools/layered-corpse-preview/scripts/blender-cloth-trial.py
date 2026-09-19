"""Standalone diagnostic, not a replacement for the app solver.
blender --background --factory-startup --python scripts/blender-cloth-trial.py -- INPUT_JSON
Exports a baked vertex cache, a self-contained playback .blend and four PNGs.
"""
import bpy, bmesh, json, sys, time, math
from pathlib import Path
from mathutils import Vector
from array import array
sys.path.insert(0,str(Path(__file__).parent))
from importlib import import_module

input_path=Path(sys.argv[sys.argv.index('--')+1]).resolve()
data=json.loads(input_path.read_text(encoding='utf-8'))
out=input_path.parent
name=data['name']
cotton='--cotton' in sys.argv
prepared='--prepare' in sys.argv
visible_only='--visible-only' in sys.argv
soft_cotton='--soft-cotton' in sys.argv
calibrated='--calibrated' in sys.argv
gentle='--gentle' in sys.argv
bind_rest='--bind-rest' in sys.argv
edge_size=.018 if prepared else (.014 if cotton else .035)
if soft_cotton:edge_size=.02
scene=bpy.context.scene
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene.render.fps=data['fps'];scene.frame_start=1;scene.frame_end=round(data['duration']*data['fps'])+1
scene.gravity=(0,0,-9.81)
def to_blender(p):return (p[0],-p[2],p[1])
verts=[];faces=[];weld={};rest_verts=[]
texture=bpy.data.images.load(data['texture']) if visible_only else None
pixels=list(texture.pixels) if texture else []
def opaque(surface,ids):
    if not texture:return True
    w,h=texture.size
    for weights in [(1/3,1/3,1/3),(.8,.1,.1),(.1,.8,.1),(.1,.1,.8),(.45,.45,.1),(.1,.45,.45),(.45,.1,.45)]:
        u=sum(surface['uvs'][i*2]*weight for i,weight in zip(ids,weights));v=sum(surface['uvs'][i*2+1]*weight for i,weight in zip(ids,weights))
        x=max(0,min(w-1,int(u*w)));y=max(0,min(h-1,int(v*h)))
        if pixels[((h-1-y)*w+x)*4+3]>=3/255:return True
    return False
for surface_index,surface in enumerate(data['item']['surfaces']):
    mapping=[]
    for at in range(0,len(surface['positions']),3):
        p=to_blender(surface['positions'][at:at+3]);key=tuple(round(x,6) for x in p)
        if key not in weld:
            weld[key]=len(verts);verts.append(p)
            rest_verts.append(to_blender(data['restSurfaces'][surface_index]['positions'][at:at+3]) if bind_rest else p)
        mapping.append(weld[key])
    ids=surface['indices']
    for at in range(0,len(ids),3):
        if not opaque(surface,ids[at:at+3]):continue
        f=tuple(mapping[i] for i in ids[at:at+3])
        if len(set(f))==3:faces.append(f)
preparation={}
if prepared:
    verts,preparation=import_module('blender-cloth-prepare').untangle(verts,faces)
    print('PREPARATION',json.dumps(preparation),flush=True)
mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj)
bpy.context.view_layer.objects.active=obj;obj.select_set(True)
# Refine long edges without changing the source silhouette or scale.
bm=bmesh.new();bm.from_mesh(mesh)
rest_layer=bm.verts.layers.float_vector.new('simulation-rest-position')
for vertex in bm.verts:vertex[rest_layer]=rest_verts[vertex.index]
if visible_only:bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
for _ in range(7 if cotton else 4):
    edges=[e for e in bm.edges if e.calc_length()>edge_size]
    if not edges:break
    bmesh.ops.subdivide_edges(bm,edges=edges,cuts=1,use_grid_fill=True)
bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.verts.index_update()
refined_rest=[tuple(vertex[rest_layer]) for vertex in bm.verts]
bm.to_mesh(mesh);bm.free();mesh.update()
if bind_rest:
    obj.shape_key_add(name='Basis')
    rest_key=obj.shape_key_add(name='Unposed garment rest metric')
    for vertex,p in zip(rest_key.data,refined_rest):vertex.co=p
    rest_key.value=0
area=sum(p.area for p in mesh.polygons)
print('MESH',len(faces),len(mesh.vertices),len(mesh.polygons),'area',area,flush=True)
pins=obj.vertex_groups.new(name='launch-pins');pins.add(list(range(len(mesh.vertices))),1,'REPLACE')
weight=obj.modifiers.new('Release pins','VERTEX_WEIGHT_MIX');weight.vertex_group_a=pins.name;weight.default_weight_b=0;weight.mix_mode='SET';weight.mix_set='ALL'
release=round(data['item']['releaseTime']*data['fps'])+1
weight.mask_constant=0;weight.keyframe_insert('mask_constant',frame=1);weight.keyframe_insert('mask_constant',frame=release+2)
weight.mask_constant=1;weight.keyframe_insert('mask_constant',frame=release+3)
velocity=Vector(to_blender(data['velocity']))
obj.location=(0,0,0);obj.keyframe_insert('location',frame=1);obj.keyframe_insert('location',frame=release)
obj.location=velocity*(2/data['fps']);obj.keyframe_insert('location',frame=release+2);obj.keyframe_insert('location',frame=scene.frame_end)
cloth=obj.modifiers.new('Blender Cloth','CLOTH');s=cloth.settings
s.quality=8;s.mass=.3;s.tension_stiffness=15;s.compression_stiffness=15;s.shear_stiffness=15;s.bending_stiffness=.05
s.tension_damping=5;s.compression_damping=5;s.shear_damping=5;s.bending_damping=.5;s.air_damping=1
s.use_pressure=False;s.use_internal_springs=False;s.vertex_group_mass=pins.name
if bind_rest:s.rest_shape_key=rest_key
if cotton:
    s.quality=16;s.mass=area*.18/len(mesh.vertices)
    s.tension_stiffness=80;s.compression_stiffness=40;s.shear_stiffness=10
    s.bending_model='ANGULAR';s.bending_stiffness=.00005
    s.tension_damping=5;s.compression_damping=5;s.shear_damping=2;s.bending_damping=.001;s.air_damping=.1
cs=cloth.collision_settings;cs.use_collision=True;cs.use_self_collision=True;cs.distance_min=.0015;cs.self_distance_min=.0015;cs.collision_quality=6;cs.self_friction=5
if cotton:cs.collision_quality=12;cs.distance_min=.001;cs.self_distance_min=.0007;cs.self_friction=5
if prepared:cs.impulse_clamp=.0001;cs.self_impulse_clamp=.0001
if soft_cotton:
    s.quality=20;s.bending_stiffness=.0000001;s.bending_damping=.000001;s.air_damping=0
    cs.impulse_clamp=s.mass*.1;cs.self_impulse_clamp=s.mass*.1
if calibrated:
    # Blender cloth uses a legacy internal time/force scale (gravity * .001).
    # Keep well-conditioned numerical masses, not an unvalidated SI conversion.
    s.mass=.3;s.time_scale=math.sqrt(1000)/data['fps'];s.quality=20
    s.tension_stiffness=80;s.compression_stiffness=40;s.shear_stiffness=10
    s.bending_stiffness=.0005;s.bending_damping=.005;s.air_damping=0
    cs.impulse_clamp=0;cs.self_impulse_clamp=0
if gentle:
    # Isolate local buckling/contact snagging. No pressure or global shape target.
    s.bending_stiffness=.006;s.bending_damping=.02
    s.compression_stiffness=80;s.shear_stiffness=20
    cs.self_friction=1
cloth.point_cache.frame_start=1;cloth.point_cache.frame_end=scene.frame_end
solver_parameters={'numericalVertexMass':s.mass,'timeScale':s.time_scale}
solver_parameters.update({'bending':s.bending_stiffness,'compression':s.compression_stiffness,'shear':s.shear_stiffness,'selfFriction':cs.self_friction})
bpy.ops.mesh.primitive_plane_add(size=8,location=(0,0,data['floor']))
floor=bpy.context.object;floor.name='Floor';floor.modifiers.new('Collision','COLLISION');floor.collision.thickness_outer=.001
if gentle:floor.collision.cloth_friction=.5
def material(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    bsdf=m.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(*color,1);bsdf.inputs['Roughness'].default_value=.8
    return m
obj.data.materials.append(material('Neutral fabric',(.18,.36,.55)));floor.data.materials.append(material('Ground',(.19,.19,.17)))
body_points=[]
for number,surface in enumerate(data.get('body',[])):
    body_points.extend(to_blender(surface['positions'][i:i+3]) for i in range(0,len(surface['positions']),3))
    points=[to_blender(surface['positions'][i:i+3]) for i in range(0,len(surface['positions']),3)]
    body_mesh=bpy.data.meshes.new('Body');body_mesh.from_pydata(points,[],[surface['indices'][i:i+3] for i in range(0,len(surface['indices']),3)])
    body_obj=bpy.data.objects.new('Body reference '+str(number),body_mesh);scene.collection.objects.link(body_obj)
    body_obj.data.materials.append(material('Body reference',(.24,.29,.18)))
    # Visible scene reference only in this isolated fabric/contact A/B test.
    for polygon in body_mesh.polygons:polygon.use_smooth=True
frames=[];started=time.perf_counter()
for frame in range(1,scene.frame_end+1):
    scene.frame_set(frame);deps=bpy.context.evaluated_depsgraph_get();evaluated=obj.evaluated_get(deps)
    positions=[tuple(evaluated.matrix_world@v.co) for v in evaluated.data.vertices]
    if any(not math.isfinite(x) for p in positions for x in p):raise RuntimeError('Non-finite simulation')
    frames.append(positions)
    if frame%15==0:print('CLOTH',frame,'/',scene.frame_end,'seconds',round(time.perf_counter()-started,2),flush=True)
elapsed=time.perf_counter()-started
# Make the deliverable independent of Blender's temporary point cache.
obj.modifiers.clear();obj.animation_data_clear();obj.location=(0,0,0)
obj.shape_key_clear()
obj.shape_key_add(name='Basis')
for frame,positions in enumerate(frames,1):
    key=obj.shape_key_add(name='Frame %03d'%frame)
    for vertex,p in zip(key.data,positions):vertex.co=p
    key.value=0;key.keyframe_insert('value',frame=frame-1);key.value=1;key.keyframe_insert('value',frame=frame);key.value=0;key.keyframe_insert('value',frame=frame+1)
for polygon in mesh.polygons:polygon.use_smooth=True
cache=array('f',(x for positions in frames for p in positions for x in (p[0],p[2],-p[1])))
with (out/(name+'-frames.f32')).open('wb') as f:cache.tofile(f)
meta={'blender':bpy.app.version_string,'seconds':elapsed,'vertices':len(mesh.vertices),'triangles':len(mesh.polygons),'fps':data['fps'],'frames':len(frames),'floor':data['floor'],'initialHeight':max(p[2] for p in frames[0])-min(p[2] for p in frames[0]),'finalHeight':max(p[2] for p in frames[-1])-min(p[2] for p in frames[-1]),'minimumZ':min(p[2] for positions in frames for p in positions),'indices':[i for p in mesh.polygons for i in p.vertices]}
meta.update({'variant':out.name,'area':area,**solver_parameters,'maxEdge':edge_size})
meta['preparation']=preparation
meta['visibleOnly']=visible_only;meta['sourceVisibleTriangles']=len(faces)
meta['softCotton']=soft_cotton
meta['gentle']=gentle;meta['bodyReferenceOnly']=bool(body_points);meta['floorFriction']=floor.collision.cloth_friction
meta['restMetric']='unposed garment' if bind_rest else 'posed garment'
(out/(name+'-report.json')).write_text(json.dumps(meta,indent=2),encoding='utf-8')
all_positions=[Vector(p) for positions in frames for p in positions]+[Vector(p) for p in body_points]
lo=Vector(tuple(min(p[i] for p in all_positions) for i in range(3)));hi=Vector(tuple(max(p[i] for p in all_positions) for i in range(3)));center=(lo+hi)/2
bpy.ops.object.camera_add(location=center+Vector((1.6,-2,1.8)));camera=bpy.context.object;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=max(1.3,(hi-lo).length*1.15);scene.camera=camera
bpy.ops.object.light_add(type='AREA',location=center+Vector((0,-1,3)));bpy.context.object.data.energy=450;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=4
scene.world.color=(.25,.25,.25);scene.render.engine='CYCLES';scene.cycles.samples=16
scene.render.resolution_x=640;scene.render.resolution_y=640;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(out/(name+'-playback.blend')))
for frame in [1,release+15,release+40,scene.frame_end]:
    scene.frame_set(frame);scene.render.filepath=str(out/(name+'-%03d.png'%frame));bpy.ops.render.render(write_still=True)
print('RESULT',json.dumps({k:v for k,v in meta.items() if k!='indices'}),flush=True)
