"""Small free-fall diagnostic: solver conditioning, not garment appearance."""
import bpy,math
scene=bpy.context.scene
scene.render.fps=60
scene.gravity=(0,0,-9.81)
scene.frame_end=61
for mass,time_scale in [(.3,1),(.3,math.sqrt(1000)/60)]:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    scene.frame_set(1)
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=12,y_subdivisions=12,size=.3,location=(0,0,10))
    obj=bpy.context.object
    c=obj.modifiers.new('test','CLOTH');c.settings.mass=mass;c.settings.quality=20
    c.settings.time_scale=time_scale
    c.settings.air_damping=0;c.settings.tension_stiffness=80;c.settings.compression_stiffness=40
    c.settings.shear_stiffness=10;c.settings.bending_stiffness=.0000001
    c.collision_settings.use_collision=False
    c.point_cache.frame_end=61
    for f in range(1,62):
        scene.frame_set(f)
        ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        z=sum((ev.matrix_world@v.co).z for v in ev.data.vertices)/len(ev.data.vertices)
        if f in [1,31,61]:print('FALL',mass,time_scale,f,z,flush=True)
    if time_scale!=1:
        expected=10-.5*9.81
        assert abs(z-expected)<.015,('Free-fall calibration failed',z,expected)
        print('CALIBRATION PASS',abs(z-expected),flush=True)
