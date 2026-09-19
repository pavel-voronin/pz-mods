"""Render actual cached frames, without resimulating or moving the camera."""
import bpy,json,sys,struct
from pathlib import Path
from array import array
from mathutils import Matrix,Vector
directory=Path(sys.argv[sys.argv.index('--')+1]).resolve()
source=json.loads((directory/'scene-source.json').read_text())
raw=(directory/'scene.pzcloth').read_bytes();size=struct.unpack_from('<I',raw,8)[0]
h=json.loads(raw[12:12+size]);offset=12+((size+3)//4)*4
bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene
def obj(name,positions,faces):
    m=bpy.data.meshes.new(name);m.from_pydata([(p[0],-p[2],p[1]) for p in positions],[],faces);m.update()
    o=bpy.data.objects.new(name,m);scene.collection.objects.link(o)
    for p in m.polygons:p.use_smooth=True
    return o
tracks=[]
for i,t in enumerate(h['tracks']):
    n=t['particleCount']*3*h['frameCount'];values=array('f');values.frombytes(raw[offset:offset+n*4]);offset+=n*4
    o=obj('Garment '+str(i),[t['positions'][j:j+3] for j in range(0,len(t['positions']),3)],[t['indices'][j:j+3] for j in range(0,len(t['indices']),3)])
    uv=o.data.uv_layers.new()
    for loop in o.data.loops:uv.data[loop.index].uv=t['uvs'][loop.vertex_index*2:loop.vertex_index*2+2]
    material=bpy.data.materials.new(o.name);material.use_nodes=True;o.data.materials.append(material)
    tex=Path(__file__).resolve().parent.parent/'public'/source['garments'][i]['texture'].lstrip('/')
    if tex.exists():
        image=material.node_tree.nodes.new('ShaderNodeTexImage');image.image=bpy.data.images.load(str(tex));material.node_tree.nodes.active=image
        material.node_tree.links.new(image.outputs['Color'],material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    tracks.append((o,t,values))
for i,b in enumerate(source['body']):obj('Body '+str(i),[b['positions'][j:j+3] for j in range(0,len(b['positions']),3)],[b['indices'][j:j+3] for j in range(0,len(b['indices']),3)])
bpy.ops.mesh.primitive_plane_add(size=6,location=(0,0,source['floor']))
cm=source['camera'];conversion=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
matrix=conversion@Matrix([cm['matrix'][i:i+4] for i in range(0,16,4)]).transposed();p,r,s=matrix.decompose()
bpy.ops.object.camera_add(location=p);camera=bpy.context.object;camera.rotation_mode='QUATERNION';camera.rotation_quaternion=r
camera.data.type='ORTHO';camera.data.sensor_fit='HORIZONTAL';camera.data.ortho_scale=(cm['right']-cm['left'])/cm['zoom']/cm['contentWorldScale'][0];scene.camera=camera
scene.render.resolution_y=720;scene.render.resolution_x=round(720*(cm['right']-cm['left'])/(cm['top']-cm['bottom']));scene.render.resolution_percentage=100
scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.light='STUDIO';scene.display.shading.color_type='TEXTURE'
scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True
for f in [0,90,180,h['frameCount']-1]:
    for o,t,values in tracks:
        base=f*t['particleCount']*3
        for v in o.data.vertices:
            j=base+t['particleForVertex'][v.index]*3;x,y,z=values[j:j+3];v.co=(x,-z,y)
        o.data.update()
    scene.render.filepath=str(directory/('inspection-%03d.png'%f));bpy.ops.render.render(write_still=True)
