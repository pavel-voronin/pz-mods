"""Small free-flight calibration: production pin release versus ballistic motion."""
import bpy, math, json
from mathutils import Vector

for scale,air in [(math.sqrt(1000)/60,0),(1,0),(math.sqrt(1000)/60,2)]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene;scene.render.fps=60
    mesh=bpy.data.meshes.new('Probe');mesh.from_pydata([(0,0,10),(.01,0,10),(0,.01,10)],[],[(0,1,2)])
    obj=bpy.data.objects.new('Probe',mesh);scene.collection.objects.link(obj)
    pins=obj.vertex_groups.new(name='Pins');pins.add([0,1,2],1,'REPLACE')
    part=obj.vertex_groups.new(name='Part');part.add([0,1,2],1,'REPLACE')
    obj.shape_key_add(name='Basis');key=obj.shape_key_add(name='Launch',from_mix=False)
    for v in key.data:v.co+=Vector((1,0,2))/60
    for f,v in [(1,0),(10,0),(11,1),(60,1)]:key.value=v;key.keyframe_insert('value',frame=f)
    w=obj.modifiers.new('Release','VERTEX_WEIGHT_MIX');w.vertex_group_a=pins.name
    w.default_weight_b=0;w.mix_mode='SET';w.mix_set='ALL';w.mask_vertex_group=part.name
    for f,v in [(1,0),(11,0),(12,1)]:w.mask_constant=v;w.keyframe_insert('mask_constant',frame=f)
    for owner in [obj,obj.data.shape_keys]:
        for layer in owner.animation_data.action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for k in curve.keyframe_points:k.interpolation='LINEAR'
    c=obj.modifiers.new('Cloth','CLOTH');s=c.settings
    s.quality=24;s.mass=.314340949;s.time_scale=scale;s.vertex_group_mass=pins.name
    s.air_damping=air;c.collision_settings.use_collision=False
    rows=[];previous=None
    for f in range(1,42):
        scene.frame_set(f);ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        p=sum((v.co for v in ev.data.vertices),Vector())/3
        if f in [10,11,12,13,16,21,41]:rows.append({'frame':f,'position':list(p),'velocity':list((p-previous)*60) if previous else None})
        previous=p.copy()
    print('CALIBRATION',json.dumps({'scale':scale,'air':air,'frames':rows}),flush=True)
