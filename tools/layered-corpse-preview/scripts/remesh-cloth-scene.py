"""Isotropic simulation mesh + barycentric binding of the untouched textured surface."""
import sys,json,math,time
from pathlib import Path
from importlib import import_module
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'.cloth-deps'))
try:import pymeshlab
except ImportError as error:
    raise RuntimeError('Не установлен локальный PyMeshLab. Установите scripts/requirements-cloth.txt в .cloth-deps через Python из Blender; инструкция в BLENDER-CLOTH.md.') from error
sys.path.insert(0,str(Path(__file__).parent))
helpers=import_module('blender-cloth-prepare')
args=sys.argv[sys.argv.index('--')+1:];path=Path(args[0]).resolve()
data=json.loads(path.read_text());edge=float(args[1]) if len(args)>1 and not args[1].startswith('--') else .018
allow_intersections='--allow-initial-intersections' in args

def bary(p,a,b,c):
    u=b-a;v=c-a;w=p-a;uu=u.dot(u);uv=u.dot(v);vv=v.dot(v)
    d=uu*vv-uv*uv
    if abs(d)<1e-20:return [1,0,0]
    s=(vv*w.dot(u)-uv*w.dot(v))/d;t=(uu*w.dot(v)-uv*w.dot(u))/d
    return [1-s-t,s,t]

def quality(p,faces):
    angles=[];edges=set();area=0
    for f in faces:
        a,b,c=(p[i] for i in f);area+=(b-a).cross(c-a).length*.5
        for j in range(3):
            u=p[f[(j+1)%3]]-p[f[j]];v=p[f[(j+2)%3]]-p[f[j]]
            if u.length>1e-10 and v.length>1e-10:angles.append(math.degrees(u.angle(v)))
            edges.add(tuple(sorted((f[j],f[(j+1)%3]))))
    angles.sort();lengths=sorted((p[a]-p[b]).length for a,b in edges)
    return {'vertices':len(p),'triangles':len(faces),'area':area,'minAngle':angles[0],
        'angleP01':angles[len(angles)//100],'edgeP10P50P90':[lengths[int((len(lengths)-1)*q)] for q in [.1,.5,.9]]}

reports=[];started=time.perf_counter()
for item in data['items']:
    old=[Vector(p) for p in item['positions']];old_faces=item['faces']
    ms=pymeshlab.MeshSet();ms.add_mesh(pymeshlab.Mesh(vertex_matrix=np.array(item['positions']),face_matrix=np.array(old_faces,dtype=np.int32)))
    ms.meshing_isotropic_explicit_remeshing(iterations=8,targetlen=pymeshlab.PureValue(edge),
        featuredeg=180,checksurfdist=True,maxsurfdist=pymeshlab.PureValue(.002))
    mesh=ms.current_mesh();p=[Vector(v) for v in mesh.vertex_matrix()];faces=mesh.face_matrix().tolist()
    before=quality(old,old_faces);after=quality(p,faces)
    repaired,repair=helpers.untangle(p,faces,max_shift=.005)
    if repair['after'] and not allow_intersections:raise RuntimeError('Ремеш содержит самопересечения: '+str(repair))
    p=[Vector(v) for v in repaired];after=quality(p,faces)
    tree=BVHTree.FromPolygons(p,faces,all_triangles=True)
    bindings=[];max_gap=0
    for point in old:
        hit,normal,face,distance=tree.find_nearest(point)
        ids=faces[face];weights=bary(hit,*(p[i] for i in ids))
        bindings.append({'ids':ids,'weights':weights});max_gap=max(max_gap,distance)
    if max_gap>.02:
        if not allow_intersections:raise RuntimeError('Слишком большая ошибка переноса на физическую сетку: '+str(max_gap))
        # A poor remesh is optional, not grounds to discard the user's scene.
        p=old;faces=old_faces;after=before
        bindings=[{'ids':[i,i,i],'weights':[1,0,0]} for i in range(len(old))]
        repair={'before':len(helpers.pairs(old,old_faces)),'after':len(helpers.pairs(old,old_faces)),'maxShift':0,'fallback':'original-prepared-mesh','rejectedBindingGap':max_gap}
        max_gap=0
    item['renderBindings']=bindings;item['renderFaces']=old_faces;item['renderFaceUvs']=item['faceUvs']
    item['positions']=[list(v) for v in p];item['restPositions']=item['positions'];item['faces']=faces
    # Physical faces have no rendering role; original UV seams stay untouched.
    item['faceUvs']=[[[0,0]]*3 for _ in faces]
    row={'index':item['index'],'before':before,'after':after,'repair':repair,'maxBindingGap':max_gap}
    reports.append(row);print('REMESH',json.dumps(row),flush=True)
data['material']['targetEdgeM']=edge
data['report']['postRemeshLayerRepairs']=import_module('cloth-release-clearance').ensure_release_clearance(data['items'],allow_intersections=allow_intersections)
print('FINAL_RELEASE_CLEARANCE',json.dumps(data['report']['postRemeshLayerRepairs']),flush=True)
data['report']['isotropicRemesh']={'items':reports,'seconds':time.perf_counter()-started}
path.write_text(json.dumps(data,separators=(',',':')))
(path.parent/'remesh-report.json').write_text(json.dumps(data['report']['isotropicRemesh'],indent=2))
