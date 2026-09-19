"""Small bending-response regression, not a real-fabric calibration."""
import bpy,math,json
from mathutils import Vector
scene=bpy.context.scene;bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene.render.fps=60
points=[];faces=[];n=11;rows=3
for part in range(2):
    start=len(points)
    for x in range(n):
        for y in range(rows):points.append((x*.02,y*.02+part*.3,1))
    for x in range(n-1):
        for y in range(rows-1):
            a=start+x*rows+y;b=a+rows;faces.extend([(a,b,b+1),(a,b+1,a+1)])
m=bpy.data.meshes.new('strips');m.from_pydata(points,[],faces);m.update()
o=bpy.data.objects.new('strips',m);scene.collection.objects.link(o)
pins=o.vertex_groups.new(name='pins');pins.add(list(range(rows*2))+list(range(n*rows,n*rows+rows*2)),1,'REPLACE')
bend=o.vertex_groups.new(name='bend')
for part,k in enumerate([.3,3]):bend.add(list(range(part*n*rows,(part+1)*n*rows)),(k-.2)/4.8,'REPLACE')
c=o.modifiers.new('cloth','CLOTH');s=c.settings;s.quality=24;s.mass=.3;s.time_scale=math.sqrt(1000)/60
s.tension_stiffness=80;s.compression_stiffness=40;s.shear_stiffness=10;s.air_damping=0
s.bending_model='ANGULAR';s.bending_stiffness=.0001;s.bending_stiffness_max=.0025;s.vertex_group_bending=bend.name
s.bending_damping=.005;s.vertex_group_mass=pins.name;s.use_pressure=False;s.use_internal_springs=False
c.collision_settings.use_collision=False;c.collision_settings.use_self_collision=False;c.point_cache.frame_end=31
for f in range(1,32):scene.frame_set(f);ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get())
soft=Vector(ev.data.vertices[(n-1)*rows].co);stiff=Vector(ev.data.vertices[(2*n-1)*rows].co);stiff.y-=.3
delta=(soft-stiff).length
assert delta>1e-5,('Stiffness had no effect',delta)
print('STIFFNESS RESPONSE PASS',json.dumps({'softTip':list(soft),'stiffTip':list(stiff),'delta':delta}),flush=True)
