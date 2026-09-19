"""Review an already baked trial; never reruns the cloth simulation."""
import bpy,json,sys,math,time
from pathlib import Path
from mathutils import Vector,geometry
from mathutils.bvhtree import BVHTree
from array import array
stem=Path(bpy.data.filepath).with_name(Path(bpy.data.filepath).stem.replace('-playback',''))
report_path=Path(str(stem)+'-report.json');report=json.loads(report_path.read_text())
raw=array('f');raw.frombytes(Path(str(stem)+'-frames.f32').read_bytes())
n=report['vertices'];faces=[report['indices'][i:i+3] for i in range(0,len(report['indices']),3)]
sample_frames=sorted(set(range(0,report['frames'],10))|{report['frames']-1})
crossings=[];worst_strain=0
rest=[Vector(raw[i*3:i*3+3]) for i in range(n)]
def crosses(a,b,tri):
    direction=b-a;length=direction.length
    if length<1e-9:return False
    hit=geometry.intersect_ray_tri(*tri,direction,a,True)
    if hit is None:return False
    t=(hit-a).dot(direction)/(length*length)
    # Strict interior crossings only, not touching endpoints or coplanar contact.
    normal=(tri[1]-tri[0]).cross(tri[2]-tri[0])
    return 1e-5<t<1-1e-5 and (a-tri[0]).dot(normal)*(b-tri[0]).dot(normal)<-1e-18
for frame in sample_frames:
    offset=frame*n*3;verts=[Vector(raw[offset+i*3:offset+i*3+3]) for i in range(n)]
    tree=BVHTree.FromPolygons(verts,faces,all_triangles=True,epsilon=0)
    pairs=set()
    for a,b in tree.overlap(tree):
        if a>=b or set(faces[a])&set(faces[b]):continue
        ta=[verts[i] for i in faces[a]];tb=[verts[i] for i in faces[b]]
        if any(crosses(ta[i],ta[(i+1)%3],tb) or crosses(tb[i],tb[(i+1)%3],ta) for i in range(3)):pairs.add((a,b))
    crossings.append({'frame':frame+1,'pairs':len(pairs)})
    for face in faces:
        for i in range(3):
            a,b=face[i],face[(i+1)%3];length=(rest[a]-rest[b]).length
            if length>1e-6:worst_strain=max(worst_strain,abs((verts[a]-verts[b]).length/length-1))
report['sampledIntersections']=crossings;report['worstSampledEdgeStrain']=worst_strain
source=json.loads(Path(str(stem)+'-input.json').read_text())
texture=bpy.data.images.load(source['texture']) if report.get('visibleOnly') else None
pixels=list(texture.pixels) if texture else []
def opaque(surface,ids):
    if not texture:return True
    w,h=texture.size
    for weights in [(1/3,1/3,1/3),(.8,.1,.1),(.1,.8,.1),(.1,.1,.8),(.45,.45,.1),(.1,.45,.45),(.45,.1,.45)]:
        u=sum(surface['uvs'][i*2]*weight for i,weight in zip(ids,weights));v=sum(surface['uvs'][i*2+1]*weight for i,weight in zip(ids,weights))
        x=max(0,min(w-1,int(u*w)));y=max(0,min(h-1,int(v*h)))
        if pixels[((h-1-y)*w+x)*4+3]>=3/255:return True
    return False
sv=[];sf=[];weld={}
for surface in source['item']['surfaces']:
    mapping=[]
    for at in range(0,len(surface['positions']),3):
        p=surface['positions'][at:at+3];key=tuple(round(x,6) for x in p)
        if key not in weld:weld[key]=len(sv);sv.append(Vector(p))
        mapping.append(weld[key])
    sf.extend(tuple(mapping[i] for i in surface['indices'][at:at+3]) for at in range(0,len(surface['indices']),3) if opaque(surface,surface['indices'][at:at+3]))
tree=BVHTree.FromPolygons(sv,sf,all_triangles=True,epsilon=0);source_pairs=[]
for a,b in tree.overlap(tree):
    if a>=b or set(sf[a])&set(sf[b]):continue
    ta=[sv[i] for i in sf[a]];tb=[sv[i] for i in sf[b]]
    if any(crosses(ta[i],ta[(i+1)%3],tb) or crosses(tb[i],tb[(i+1)%3],ta) for i in range(3)):source_pairs.append((a,b))
report['sourceIntersectionsBeforeRefinement']=len(source_pairs)
report_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
print('VALIDATION',json.dumps({'sourceIntersections':len(source_pairs),'intersections':crossings,'worstStrain':worst_strain}),flush=True)
scene=bpy.context.scene;obj=bpy.data.objects[stem.name];camera=scene.camera
# Keep the saved whole-scene camera for video. Detail stills may reframe, never video.
fixed_camera_matrix=camera.matrix_world.copy();fixed_camera_scale=camera.data.ortho_scale
camera.animation_data_clear();camera.data.animation_data_clear()
scene.frame_set(scene.frame_end)
evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());points=[evaluated.matrix_world@v.co for v in evaluated.data.vertices]
center=sum(points,Vector())/len(points)
camera.location=center+Vector((.7,-1,1));camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=.85
scene.render.filepath=str(stem)+'-detail.png';scene.render.resolution_x=768;scene.render.resolution_y=768
bpy.ops.render.render(write_still=True)
scene.frame_set(1)
evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());points=[evaluated.matrix_world@v.co for v in evaluated.data.vertices]
center=sum(points,Vector())/len(points)
camera.location=center+Vector((.7,-1,1))
scene.render.filepath=str(stem)+'-initial-detail.png';bpy.ops.render.render(write_still=True)
camera.matrix_world=fixed_camera_matrix;camera.data.ortho_scale=fixed_camera_scale
camera_delta=0
for frame in [1,scene.frame_end//2,scene.frame_end]:
    scene.frame_set(frame);bpy.context.view_layer.update()
    camera_delta=max(camera_delta,max(abs(camera.matrix_world[r][c]-fixed_camera_matrix[r][c]) for r in range(4) for c in range(4)))
assert camera_delta<1e-6,('Camera must remain fixed',camera_delta)
report['previewCamera']='fixed';report['previewCameraMaxMatrixDelta']=camera_delta
report_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True
scene.render.image_settings.media_type='VIDEO';scene.render.image_settings.file_format='FFMPEG';scene.render.ffmpeg.format='MPEG4';scene.render.ffmpeg.codec='H264';scene.render.ffmpeg.constant_rate_factor='MEDIUM'
scene.render.filepath=str(stem)+'-fixed-preview.mp4';bpy.ops.render.render(animation=True)
