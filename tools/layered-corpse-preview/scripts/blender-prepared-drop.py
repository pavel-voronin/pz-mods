"""Diagnostic drop of one prepared garment, from the real application snapshot.
No hardcoded pose, target, source model or moving camera. Not a full-scene bake.
"""
import bpy,json,sys,math,time,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
from array import array
from importlib import import_module
from bpy_extras.object_utils import world_to_camera_view
sys.path.insert(0,str(Path(__file__).parent))
intersections=import_module('blender-cloth-prepare').pairs
path=Path(sys.argv[sys.argv.index('--')+1]).resolve();data=json.loads(path.read_text())
source_path=path.parent/data['sourceFile'];source=json.loads(source_path.read_text())
assert hashlib.sha256(source_path.read_bytes()).hexdigest()==data['sourceSha256']
index=int(sys.argv[sys.argv.index('--')+2]);item=data['items'][index]
assert data['report']['items'][index]['collisionReady'],'Initial intersections must be resolved before this test'
contact='--contact' in sys.argv
out=path.parent/('drop-'+str(index)+('-contact' if contact else ''));out.mkdir(exist_ok=True)
scene=bpy.context.scene;bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
fps=data['fps'];scene.render.fps=fps;scene.frame_start=1;scene.frame_end=round(data['duration']*fps)+1
def co(p):return Vector((p[0],-p[2],p[1]))
def material(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);return m
def mesh_obj(name,positions,faces,color):
    m=bpy.data.meshes.new(name);m.from_pydata([co(p) for p in positions],[],faces);m.update()
    o=bpy.data.objects.new(name,m);scene.collection.objects.link(o);m.materials.append(material(name,color))
    return o
obj=mesh_obj('Prepared clothing',item['positions'],item['faces'],(.21,.44,.62))
# Other garments remain worn. The body is an explicit wire reference, not a replacement pose.
for i,other in enumerate(data['items']):
    if i!=index:mesh_obj('Worn '+str(i),other['positions'],other['faces'],(.3,.32,.34))
for body in source['body']:
    o=mesh_obj('Body wire',[body['positions'][i:i+3] for i in range(0,len(body['positions']),3)],
        [body['indices'][i:i+3] for i in range(0,len(body['indices']),3)],(.35,.38,.32))
    wire=o.modifiers.new('Diagnostic wire','WIREFRAME');wire.thickness=.0004
for capsule in source['capsules']:
    a=co(capsule['a']);b=co(capsule['b']);d=b-a;r=capsule['radius']
    # Closed capsule: stretched sphere with straight middle segment.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=r)
    collider=bpy.context.object;collider.name='App body capsule'
    for v in collider.data.vertices:v.co.z+=d.length*.5*(1 if v.co.z>=0 else -1)
    collider.location=(a+b)*.5;collider.rotation_euler=d.to_track_quat('Z','Y').to_euler()
    collider.modifiers.new('Collision','COLLISION');collider.collision.thickness_outer=.001
    collider.hide_render=True
bpy.ops.mesh.primitive_plane_add(size=6,location=(0,0,data['floor']))
floor=bpy.context.object;floor.name='App floor';floor.modifiers.new('Collision','COLLISION')
floor.collision.thickness_outer=.001;floor.data.materials.append(material('Floor',(.18,.19,.17)))
if contact:floor.collision.cloth_friction=80
group=obj.vertex_groups.new(name='Release');group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
weight=obj.modifiers.new('Release weights','VERTEX_WEIGHT_MIX');weight.vertex_group_a=group.name
weight.default_weight_b=0;weight.mix_mode='SET';weight.mix_set='ALL'
release=round(item['releaseTime']*fps)+1
weight.mask_constant=0;weight.keyframe_insert('mask_constant',frame=1);weight.keyframe_insert('mask_constant',frame=release+1)
weight.mask_constant=1;weight.keyframe_insert('mask_constant',frame=release+2)
if contact:
    basis=obj.shape_key_add(name='Basis');launch=obj.shape_key_add(name='App release velocity field')
    center=sum((v.co for v in obj.data.vertices),Vector())/len(obj.data.vertices)
    omega=co((.2+item['spin'],math.sin(item['seed'])*.65,.25))
    for v,p in zip(launch.data,obj.data.vertices):v.co=p.co+(co(item['velocity'])+omega.cross(p.co-center))*(2/fps)
    launch.value=0;launch.keyframe_insert('value',frame=1);launch.keyframe_insert('value',frame=release-1)
    launch.value=1;launch.keyframe_insert('value',frame=release+1);launch.keyframe_insert('value',frame=scene.frame_end)
else:
    obj.location=(0,0,0);obj.keyframe_insert('location',frame=1);obj.keyframe_insert('location',frame=release-1)
    obj.location=co(item['velocity'])*(2/fps);obj.keyframe_insert('location',frame=release+1);obj.keyframe_insert('location',frame=scene.frame_end)
c=obj.modifiers.new('Cloth','CLOTH');s=c.settings;s.quality=16;s.mass=.3;s.time_scale=math.sqrt(1000)/fps
s.tension_stiffness=80;s.compression_stiffness=40;s.shear_stiffness=10
s.bending_model='ANGULAR';s.bending_stiffness=.0005;s.bending_damping=.005;s.air_damping=0
s.use_pressure=False;s.use_internal_springs=False;s.vertex_group_mass=group.name
cc=c.collision_settings;cc.use_collision=True;cc.use_self_collision=True;cc.distance_min=.001;cc.self_distance_min=.0007;cc.collision_quality=12
if contact:cc.impulse_clamp=.05;cc.self_impulse_clamp=.05;s.quality=24
c.point_cache.frame_start=1;c.point_cache.frame_end=scene.frame_end
frames=[];started=time.perf_counter()
for f in range(1,scene.frame_end+1):
    scene.frame_set(f);ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    frames.append([tuple(ev.matrix_world@v.co) for v in ev.data.vertices])
    if f%30==0:print('SIM',f,scene.frame_end,round(time.perf_counter()-started,2),flush=True)
elapsed=time.perf_counter()-started
start_error=max((Vector(p)-co(q)).length for p,q in zip(frames[0],item['positions']))
assert start_error<1e-6,('Initial state changed',start_error)
obj.modifiers.clear();obj.animation_data_clear();obj.location=(0,0,0);obj.shape_key_clear();obj.shape_key_add(name='Basis')
for f,positions in enumerate(frames,1):
    k=obj.shape_key_add(name=str(f))
    for v,p in zip(k.data,positions):v.co=p
    for frame,value in [(f-1,0),(f,1),(f+1,0)]:k.value=value;k.keyframe_insert('value',frame=frame)
for p in obj.data.polygons:p.use_smooth=True
cm=data['camera'];conversion=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
matrix=conversion@Matrix([cm['matrix'][i:i+4] for i in range(0,16,4)]).transposed()
position,rotation,scale=matrix.decompose()
bpy.ops.object.camera_add(location=position);camera=bpy.context.object;camera.rotation_mode='QUATERNION';camera.rotation_quaternion=rotation
camera.data.type='ORTHO';camera.data.sensor_fit='HORIZONTAL';camera.data.ortho_scale=(cm['right']-cm['left'])/cm['zoom']/cm['contentWorldScale'][0];scene.camera=camera
scene.render.resolution_y=720;scene.render.resolution_x=round(720*(cm['right']-cm['left'])/(cm['top']-cm['bottom']));scene.render.resolution_percentage=100
bpy.context.view_layer.update()
view=Matrix([cm['matrix'][i:i+4] for i in range(0,16,4)]).transposed().inverted()
projection_error=0
for point in item['positions'][::max(1,len(item['positions'])//20)]:
    p=view@Vector(point);actual=world_to_camera_view(scene,camera,co(point))
    expected=Vector((.5+p.x*cm['zoom']/(cm['right']-cm['left']),.5+p.y*cm['zoom']/(cm['top']-cm['bottom'])))
    projection_error=max(projection_error,(Vector((actual.x,actual.y))-expected).length)
assert projection_error<.001,('Camera projection mismatch',projection_error)
scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL'
scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True
scene.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(out/'playback.blend'))
scene.render.image_settings.file_format='PNG'
for f in [1,release,release+30,scene.frame_end]:
    scene.frame_set(f);scene.render.filepath=str(out/('frame-%03d.png'%f));bpy.ops.render.render(write_still=True)
cache=array('f',(x for frame in frames for p in frame for x in (p[0],p[2],-p[1])))
with (out/'frames.f32').open('wb') as file:cache.tofile(file)
final=[Vector(p) for p in frames[-1]]
report={'seconds':elapsed,'itemIndex':index,'vertices':len(final),'triangles':len(item['faces']),
        'sourceSha256':data['sourceSha256'],'initialDelta':start_error,'camera':'exact snapshot, fixed',
        'releaseTime':item['releaseTime'],'velocity':item['velocity'],'target':item['target'],
        'floorPenetration':max(0,data['floor']-min(p[2] for frame in frames for p in frame)),
        'finalIntersections':len(intersections(final,item['faces'])),
        'finalCentroid':list(sum(final,Vector())/len(final)),'cameraProjectionError':projection_error,
        'spinReproduced':contact,'floorFriction':floor.collision.cloth_friction,
        'scope':'one garment; other clothes stay worn; app capsule colliders; diagnostic materials'}
(out/'report.json').write_text(json.dumps(report,indent=2));print('RESULT',json.dumps(report),flush=True)
scene.render.image_settings.media_type='VIDEO';scene.render.image_settings.file_format='FFMPEG';scene.render.ffmpeg.format='MPEG4';scene.render.ffmpeg.codec='H264'
scene.render.filepath=str(out/'fixed-preview.mp4');bpy.ops.render.render(animation=True)
