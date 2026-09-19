"""Isolated cloth drop: no body, pins, launch keys, or imported mesh defects."""
import bpy, math, json, sys, time
from pathlib import Path
from mathutils import Vector

out=Path(sys.argv[sys.argv.index('--')+1]);out.mkdir(parents=True,exist_ok=True)
results=[]
rest_comparison='--rest-comparison' in sys.argv
garment=None
if '--garment' in sys.argv:
    ai=sys.argv.index('--garment');prepared=json.loads(Path(sys.argv[ai+1]).read_text())
    index=int(sys.argv[ai+2]);assert prepared['report']['items'][index]['collisionReady']
    garment=prepared['items'][index]
variants=[('isolated-garment',2)] if garment else ([('curved-rest',2),('flat-rest',2)] if rest_comparison else [('damping-'+str(d),d) for d in [2,.005,0]])
for variant,damping in variants:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene;scene.render.fps=60;scene.frame_end=61 if '--metric-control' in sys.argv else 361
    n=20;points=[];faces=[]
    for y in range(n+1):
        for x in range(n+1):
            u=x/n-.5;v=y/n-.5
            points.append((math.sin(u*math.pi)*.5/math.pi,v*.5,.2+math.cos(u*math.pi)*.5/math.pi) if rest_comparison else (u*.5,v*.5,.35+.025*math.sin(u*math.pi*2)*math.cos(v*math.pi*2)))
    for y in range(n):
        for x in range(n):
            a=y*(n+1)+x;faces.extend([(a,a+1,a+n+2),(a,a+n+2,a+n+1)])
    if garment:
        bottom=min(p[1] for p in garment['positions'])
        points=[(p[0],-p[2],p[1]-bottom+.35) for p in garment['positions']]
        faces=garment['faces']
    mesh=bpy.data.meshes.new('Panel');mesh.from_pydata(points,[],faces);mesh.update()
    obj=bpy.data.objects.new('Panel',mesh);scene.collection.objects.link(obj)
    if variant=='flat-rest':
        obj.shape_key_add(name='Basis');rest=obj.shape_key_add(name='Flat unstressed panel',from_mix=False)
        # Chord lengths, not arc lengths: preserve the discrete edge metric exactly.
        step=2*.5/math.pi*math.sin(math.pi/(2*n))
        for i,v in enumerate(rest.data):v.co=((i%(n+1)-n/2)*step,(i//(n+1)/n-.5)*.5,0)
        if '--metric-control' in sys.argv:
            for v in rest.data:v.co*=2
        rest.value=0
    c=obj.modifiers.new('Cloth','CLOTH');s=c.settings
    s.quality=24;s.mass=.3;s.time_scale=math.sqrt(1000)/60
    s.tension_stiffness=80;s.compression_stiffness=40;s.shear_stiffness=10
    s.bending_model='ANGULAR';s.bending_stiffness=.002
    if variant=='flat-rest':s.rest_shape_key=rest
    s.tension_damping=20;s.compression_damping=20;s.shear_damping=15
    s.bending_damping=damping;s.air_damping=2
    s.use_pressure=False;s.use_internal_springs=False;s.use_sewing_springs=False
    cc=c.collision_settings;cc.use_collision=True;cc.use_self_collision=True
    cc.distance_min=.001;cc.self_distance_min=.0007;cc.collision_quality=12
    cc.self_friction=15;cc.impulse_clamp=.05;cc.self_impulse_clamp=.05
    c.point_cache.frame_end=scene.frame_end
    bpy.ops.mesh.primitive_plane_add(size=4)
    floor=bpy.context.object;floor.modifiers.new('Floor','COLLISION')
    floor.collision.thickness_outer=.001;floor.collision.cloth_friction=80
    obj.data.update();obj.update_tag(refresh={'DATA'});bpy.context.view_layer.update()
    if '--reload' in sys.argv:
        blend=str((out/(variant+'-start.blend')).resolve())
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        bpy.ops.wm.open_mainfile(filepath=blend)
        scene=bpy.context.scene;obj=bpy.data.objects['Panel']
    previous=None;tail=[];centers=[];started=time.perf_counter();max_height=0
    for f in range(1,scene.frame_end+1):
        scene.frame_set(f);ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        p=[ev.matrix_world@v.co for v in ev.data.vertices]
        assert all(math.isfinite(x) for v in p for x in v)
        if f>scene.frame_end-60 and previous:
            ds=[(a-b)*60 for a,b in zip(p,previous)]
            tail.append(math.sqrt(sum(v.length_squared for v in ds)/len(ds)))
            centers.append((sum(ds,Vector())/len(ds)).length)
            max_height=max(max_height,max(v.z for v in p))
        previous=p
    row={'variant':variant,'bendingDamping':damping,'tailRms':sum(tail)/len(tail),'tailCentroidSpeed':sum(centers)/len(centers),'tailMaxHeight':max_height,'seconds':time.perf_counter()-started}
    results.append(row);print('PANEL',json.dumps(row),flush=True)
    (out/'report.json').write_text(json.dumps(results,indent=2))
