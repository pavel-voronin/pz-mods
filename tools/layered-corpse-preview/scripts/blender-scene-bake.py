"""All garment islands in one cloth solver: shared contacts, independent releases.
Produces a native app vertex cache, not a rendered movie. Input is an app snapshot.
"""
import bpy,bmesh,sys,json,math,time,hashlib,struct
from pathlib import Path
from mathutils import Vector
from array import array
from importlib import import_module
sys.path.insert(0,str(Path(__file__).parent))
pairs=import_module('blender-cloth-prepare').pairs
args=sys.argv[sys.argv.index('--')+1:];path=Path(args[0]).resolve()
data=json.loads(path.read_text());source_path=path.parent/data['sourceFile']
source=json.loads(source_path.read_text())
assert hashlib.sha256(source_path.read_bytes()).hexdigest()==data['sourceSha256']
warnings=[]
for report in data['report']['items']:
    assert report['geometricTransferPassed'], 'Surface transfer failed'
    if not report['collisionReady']:warnings.append('Вещь %d: исходная сетка уже пересекает себя'%report['index'])
if warnings and '--allow-initial-intersections' not in args:
    raise RuntimeError('; '.join(warnings)+'; inspect the source or explicitly use --allow-initial-intersections for a diagnostic bake')
assert source.get('sceneKey'), 'Use bake-blender-scene.mjs to generate scene identity'
if '--damped-fabric' in args:
    # Validate the mesh actually sent to the solver, not the pre-remesh report.
    release_layers={}
    for item in data['items']:release_layers.setdefault(item['releaseTime'],[]).append(item)
    for group in release_layers.values():
        status=import_module('cloth-release-clearance').layer_status(group,[[Vector(v) for v in i['positions']] for i in group])
        if status['crossings']:
            if '--allow-initial-intersections' not in args:raise RuntimeError('Физические сетки слоя пересекаются после ремеша: '+str(status))
            warnings.append('Слой рассчитан с остаточными пересечениями: %d'%status['crossings'])
def co(p):return Vector((p[0],-p[2],p[1]))
scene=bpy.context.scene;bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
fps=data['fps'];assert fps==60
scene.render.fps=fps;scene.frame_start=1;scene.frame_end=round(data['duration']*fps)+1
positions=[];faces=[];ranges=[]
for item in data['items']:
    start=len(positions);positions.extend(co(p) for p in item['positions'])
    faces.extend(tuple(start+i for i in f) for f in item['faces'])
    ranges.append((start,len(positions)))
for start,end in ranges:
    assert all(all(start<=v<end for v in face) for face in faces if start<=face[0]<end), 'Cross-garment spring topology'
assert positions and len(positions)<200000
material=data.get('material')
area=sum((positions[f[1]]-positions[f[0]]).cross(positions[f[2]]-positions[f[0]]).length*.5 for f in faces)
launch_mass=area*material['arealDensityKgM2']/len(positions)*material['solverMassScale'] if material else .3
launch_mass=data.get('diagnosticPointMass',launch_mass)
air_damping=10 if '--settle-air' in args else 2
launch_report=[]
mesh=bpy.data.meshes.new('Independent garment islands');mesh.from_pydata(positions,[],faces);mesh.update()
surface_fabric='--surface-fabric' in args
damped_fabric='--damped-fabric' in args
if damped_fabric:assert surface_fabric,'Damped fabric requires the isotropic surface pipeline'
if '--diagnostic-linear' in args or surface_fabric:
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.join_triangles(bm,faces=list(bm.faces),angle_face_threshold=.1,angle_shape_threshold=math.pi)
    bm.to_mesh(mesh);bm.free();mesh.update()
    assert len(mesh.vertices)==len(positions)
    assert max((v.co-p).length for v,p in zip(mesh.vertices,positions))<1e-7
    print('QUAD_FACES',sum(len(f.vertices)==4 for f in mesh.polygons),len(mesh.polygons),flush=True)
obj=bpy.data.objects.new('All clothing',mesh);scene.collection.objects.link(obj)
pins=obj.vertex_groups.new(name='Pins');pins.add(list(range(len(positions))),1,'REPLACE')
extraction=obj.vertex_groups.new(name='Extraction body exclusion');extraction.add(list(range(len(positions))),1,'REPLACE')
bend=obj.vertex_groups.new(name='Fabric bending')
obj.shape_key_add(name='Basis')
for item,(start,end) in zip(data['items'],ranges):
    ids=list(range(start,end));part=obj.vertex_groups.new(name='Garment '+str(item['index']));part.add(ids,1,'REPLACE')
    stiffness=max(.2,min(5,item.get('fabricStiffness',1)))
    bend.add(ids,(stiffness-.2)/4.8,'REPLACE')
    release=round(item['releaseTime']*fps)+1
    w=obj.modifiers.new('Release '+str(item['index']),'VERTEX_WEIGHT_MIX')
    w.vertex_group_a=pins.name;w.default_weight_b=0;w.mix_mode='SET';w.mix_set='ALL';w.mask_vertex_group=part.name
    for frame,value in [(1,0),(release+1,0),(release+2,1)]:
        w.mask_constant=value;w.keyframe_insert('mask_constant',frame=frame)
    # A layer is removed, not pulled through an immovable dressed mannequin.
    # Body contacts resume after the same extraction interval used by the app.
    body_mask=obj.modifiers.new('Body extraction '+str(item['index']),'VERTEX_WEIGHT_MIX')
    body_mask.vertex_group_a=extraction.name;body_mask.default_weight_b=0
    body_mask.mix_mode='SET';body_mask.mix_set='ALL';body_mask.mask_vertex_group=part.name
    end_extraction=release+math.ceil(.18*fps)
    for frame,value in [(1,0),(end_extraction,0),(end_extraction+1,1)]:
        body_mask.mask_constant=value;body_mask.keyframe_insert('mask_constant',frame=frame)
    # Never inherit the already-keyed launch of another island from the current mix.
    key=obj.shape_key_add(name='Launch '+str(item['index']),from_mix=False)
    assert all((v.co-p).length<1e-7 for v,p in zip(key.data,positions)), 'Launch inherited another garment transform'
    center=sum(positions[start:end],Vector())/(end-start)
    omega=co((.2+item['spin'],math.sin(item['seed'])*.65,.25))
    velocity=Vector(item['velocity'])
    if '--drag-aware-launch' in args:
        # Match the existing shared-layer ballistic displacement, accounting for
        # Blender's linear air drag. No attraction or position correction in flight.
        flight=source['items'][item['index']].get('flightTime',.55)
        drag=air_damping*.01/launch_mass*math.sqrt(1000)
        free=max(0,flight-1/fps)
        integral=-math.expm1(-drag*free)/drag
        displacement=velocity*flight-Vector((0,.5*9.81*flight*flight,0))
        velocity=(displacement+Vector((0,9.81/drag*(free-integral),0)))/(1/fps+integral)
    launch_report.append({'index':item['index'],'sourceVelocity':item['velocity'],'velocity':list(velocity)})
    for i in ids:key.data[i].co=positions[i]+(co(velocity)+omega.cross(positions[i]-center))/fps
    for frame,value in [(1,0),(release,0),(release+1,1),(scene.frame_end,1)]:
        key.value=value;key.keyframe_insert('value',frame=frame)
# Linear velocity field and a discrete release, no easing-induced impulses.
for owner in [obj,obj.data.shape_keys]:
    if owner.animation_data and owner.animation_data.action:
        for layer in owner.animation_data.action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for k in curve.keyframe_points:k.interpolation='LINEAR'
c=obj.modifiers.new('Shared cloth contacts','CLOTH');s=c.settings
s.quality=24;s.mass=.3;s.time_scale=math.sqrt(1000)/fps
material=data.get('material')
material_report=None
if material:
    area=sum((positions[f[1]]-positions[f[0]]).cross(positions[f[2]]-positions[f[0]]).length*.5 for f in faces)
    physical_mass=area*material['arealDensityKgM2']
    point_mass=physical_mass/len(positions)
    # Blender's legacy numerical force scale is kept explicit, not mislabeled kg.
    # A common particle mass preserves total mass under refinement.
    s.mass=point_mass*material['solverMassScale']
    material_report={**material,'areaM2':area,'totalMassKg':physical_mass,'pointMassKg':point_mass,
        'solverPointMass':s.mass,'garmentMassKg':[point_mass*(b-a) for a,b in ranges]}
if 'diagnosticPointMass' in data:
    assert source['sceneKey']=='diagnostic-launch-not-for-import'
    s.mass=data['diagnosticPointMass']
    material_report['diagnosticSolverPointMass']=s.mass
s.tension_stiffness=80;s.compression_stiffness=40;s.shear_stiffness=10
s.bending_model='ANGULAR';s.bending_stiffness=.0004;s.bending_stiffness_max=.01;s.vertex_group_bending=bend.name
# Dissipative terms, not shape/volume goals and not a frozen end frame.
s.tension_damping=20;s.compression_damping=20;s.shear_damping=15
s.bending_damping=2;s.air_damping=air_damping
if surface_fabric:
    # Compression-only bending springs on quad patches resist sharp folding,
    # without an angular goal trying to recover the dressed body's curvature.
    s.bending_model='LINEAR';s.bending_stiffness=.001;s.bending_stiffness_max=.025
if '--settle-damping' in args:
    # Relative spring motion only: do not change drag or the shared launch.
    s.tension_damping=50;s.compression_damping=50;s.shear_damping=50
    # LINEAR bending's cb is an elastic force cap, NOT velocity damping in
    # Blender's implicit solver. Keep it unchanged instead of stiffening folds.
if '--settle-contacts' in args:
    s.quality=48
if '--settle-angular' in args:
    # Test a true local angular velocity damper, with much weaker rest-angle
    # elasticity. Compression is disabled to retain the old buckling behavior.
    s.bending_model='ANGULAR';s.bending_stiffness=.0001;s.bending_stiffness_max=.0025
    s.bending_damping=.5;s.compression_stiffness=0;s.compression_stiffness_max=0;s.compression_damping=0
if '--settle-viscous' in args:
    s.bending_model='ANGULAR';s.bending_stiffness=0;s.bending_stiffness_max=0
    s.bending_damping=2;s.compression_stiffness=0;s.compression_stiffness_max=0;s.compression_damping=0
if '--settle-viscoelastic' in args or damped_fabric:
    s.bending_model='ANGULAR';s.bending_stiffness=.0001;s.bending_stiffness_max=.0025
    s.bending_damping=2;s.compression_stiffness=0;s.compression_stiffness_max=0;s.compression_damping=0
if '--settle-strong' in args or damped_fabric:
    assert s.bending_model=='ANGULAR','Velocity damping requires angular bending'
    s.bending_damping=8
s.use_pressure=False;s.use_internal_springs=False;s.use_sewing_springs=False;s.vertex_group_mass=pins.name
cc=c.collision_settings;cc.use_collision=True;cc.use_self_collision=True
# Dressed islands must not act as fixed obstacles to an earlier released layer.
# After release all detached islands join the same mutual-contact solve.
cc.vertex_group_self_collisions=pins.name
cc.vertex_group_object_collisions=extraction.name
cc.distance_min=.001;cc.self_distance_min=.0007;cc.collision_quality=12
if '--settle-contacts' in args:cc.collision_quality=24
if material:cc.self_distance_min=material['contactThicknessM']*.5
if '--settle-thickness' in args:cc.self_distance_min=.00025
cc.self_friction=15
if '--settle-friction' in args:cc.self_friction=60
cc.impulse_clamp=.05;cc.self_impulse_clamp=.05
if material:
    # Blender skips (does not saturate) contact impulses above this threshold.
    # Repaired input should receive the full separating/stopping response.
    cc.impulse_clamp=0;cc.self_impulse_clamp=0
if any(a.startswith('--diagnostic-') for a in args):
    assert source['sceneKey']=='diagnostic-launch-not-for-import'
    if '--diagnostic-no-self' in args:cc.use_self_collision=False
    if '--diagnostic-no-bend' in args:s.bending_stiffness=0;s.bending_stiffness_max=0;s.bending_damping=0
    if '--diagnostic-no-air' in args:s.air_damping=0
    if '--diagnostic-linear' in args:s.bending_model='LINEAR';s.bending_stiffness=.05;s.bending_stiffness_max=.05
c.point_cache.frame_start=1;c.point_cache.frame_end=scene.frame_end
for capsule in source['capsules']:
    a=co(capsule['a']);b=co(capsule['b']);d=b-a
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=capsule['radius'])
    o=bpy.context.object
    for v in o.data.vertices:v.co.z+=d.length*.5*(1 if v.co.z>=0 else -1)
    o.location=(a+b)*.5;o.rotation_euler=d.to_track_quat('Z','Y').to_euler()
    o.modifiers.new('Body collision','COLLISION');o.collision.thickness_outer=.001;o.hide_render=True
bpy.ops.mesh.primitive_plane_add(size=6,location=(0,0,data['floor']))
floor=bpy.context.object;floor.modifiers.new('Floor collision','COLLISION')
floor.collision.thickness_outer=.001;floor.collision.cloth_friction=80
tracks=[]
for item in data['items']:
    ids=[i for face in item.get('renderFaces',item['faces']) for i in face]
    render_start=item.get('renderStartPositions') or item['positions']
    tracks.append({'positions':[v for i in ids for v in render_start[i]],
        'uvs':[v for face in item.get('renderFaceUvs',item['faceUvs']) for uv in face for v in uv],
        'indices':list(range(len(ids))),'particleForVertex':ids,'particleCount':len(render_start),
        'releaseTime':item['releaseTime']})
buffers=[array('f') for _ in tracks];started=time.perf_counter();penetration=0;start_error=0;held_error=0
for f in range(1,scene.frame_end+1):
    scene.frame_set(f);ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    points=[ev.matrix_world@v.co for v in ev.data.vertices]
    assert len(points)==len(positions)
    for item_number,(item,(start,end),buf) in enumerate(zip(data['items'],ranges,buffers)):
        # Verify the actual modifier result, not just configured keyframes.
        pin_weights={g.group:g.weight for g in ev.data.vertices[start].groups}
        expected_pin=1 if f<=round(item['releaseTime']*fps)+2 else 0
        assert abs(pin_weights.get(pins.index,0)-expected_pin)<1e-6,('Release group mismatch',item['index'],f)
        for i,p in enumerate(points[start:end],start):
            assert all(math.isfinite(v) and abs(v)<100 for v in p),'Solver instability'
            shown=p
            if material and not item.get('renderBindings'):
                # Render starts exactly in the app pose; only the small repair offset
                # fades after release. No T-pose, scaling, or simulated shape goal.
                t=(f-1)/fps-item['releaseTime']
                u=max(0,min(1,t/material['renderRepairBlendSeconds']))
                fade=1-u*u*(3-2*u)
                original=co(item['renderStartPositions'][i-start])
                shown=p+(original-positions[i])*fade
            if not item.get('renderBindings'):buf.extend((shown.x,shown.z,-shown.y))
            if f==1:start_error=max(start_error,(p-positions[i]).length)
            if f<=round(item['releaseTime']*fps)+1:
                delta=(p-positions[i]).length;held_error=max(held_error,delta)
                assert delta<1e-5,('Garment moved before release',item['index'],f,delta)
            if f>round(item['releaseTime']*fps)+1:penetration=max(penetration,data['floor']-p.z)
        if item.get('renderBindings'):
            t=(f-1)/fps-item['releaseTime'];u=max(0,min(1,t/material['renderRepairBlendSeconds']))
            fade=1-u*u*(3-2*u)
            for original,binding in zip(item['renderStartPositions'],item['renderBindings']):
                ids=binding['ids'];weights=binding['weights']
                anchor=sum((positions[start+i]*w for i,w in zip(ids,weights)),Vector())
                shown=sum((points[start+i]*w for i,w in zip(ids,weights)),Vector())+(co(original)-anchor)*fade
                buf.extend((shown.x,shown.z,-shown.y))
    if f%30==0:print('SIM',f,scene.frame_end,round(time.perf_counter()-started,2),flush=True)
assert start_error<1e-6 and held_error<1e-5,('Pinned state moved',start_error,held_error)
final_pairs=len(pairs(points,faces))
tail=[]
for item,track,buf in zip(data['items'],tracks,buffers):
    count=track['particleCount'];samples=[];centers=[]
    for frame in range(max(1,scene.frame_end-30),scene.frame_end):
        a=(frame-1)*count*3;b=frame*count*3
        ds=[Vector((buf[b+i*3+j]-buf[a+i*3+j] for j in range(3)))*fps for i in range(count)]
        samples.append(math.sqrt(sum(v.length_squared for v in ds)/count))
        centers.append((sum(ds,Vector())/count).length)
    tail.append({'rmsVertexSpeed':sum(samples)/len(samples),'centroidSpeed':sum(centers)/len(centers)})
if any(t['rmsVertexSpeed']>.02 for t in tail):warnings.append('К концу секвенции ткань ещё движется')
if final_pairs:warnings.append('Финальный кадр: %d пересечений треугольников'%final_pairs)
if penetration>.001:warnings.append('Проникновение в пол до %.1f мм'%(penetration*1000))
report={'seconds':time.perf_counter()-started,'sceneKey':source['sceneKey'],'sourceSha256':data['sourceSha256'],
    'garments':len(tracks),'particles':len(positions),'frameCount':scene.frame_end,'initialDelta':start_error,
    'heldDelta':held_error,'floorPenetration':penetration,'finalIntersections':final_pairs,
    'stiffness':[i.get('fabricStiffness',1) for i in data['items']],'tailMotion':tail,
    'solverRevision':'isotropic-damped-v2' if damped_fabric else ('surface-fabric-v1' if surface_fabric else ('baked-pose-shell-v2' if material else 'release-contacts-damping-v3-checked')),
    'material':material_report,'launches':launch_report,
    'solverSettings':{'quality':s.quality,'collisionQuality':cc.collision_quality,
        'tensionDamping':s.tension_damping,'compressionDamping':s.compression_damping,
        'shearDamping':s.shear_damping,'bendingDamping':s.bending_damping,'airDamping':s.air_damping,
        'selfFriction':cc.self_friction,'selfDistance':cc.self_distance_min,
        'bendingModel':s.bending_model,'bendingStiffness':s.bending_stiffness,'bendingStiffnessMax':s.bending_stiffness_max},
    'warnings':warnings,'scope':'All clothing with mutual contacts. Loot stays in the app solver. No camera animation.'}
header=json.dumps({'sceneKey':source['sceneKey'],'fps':fps,'frameCount':scene.frame_end,'tracks':tracks,'warnings':warnings},separators=(',',':')).encode()
with (path.parent/'scene.pzcloth').open('wb') as out:
    out.write(b'PZCLOTH1');out.write(struct.pack('<I',len(header)));out.write(header);out.write(b'\0'*((-len(header))%4))
    for buf in buffers:
        if sys.byteorder!='little':buf.byteswap()
        buf.tofile(out)
(path.parent/'scene-bake-report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print('RESULT',json.dumps(report),flush=True)
