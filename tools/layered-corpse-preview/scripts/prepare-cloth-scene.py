"""Build simulation-only retopology from an exact app snapshot; never alter assets.
blender --background --factory-startup --python scripts/prepare-cloth-scene.py -- SNAPSHOT
"""
import bpy,bmesh,json,sys,hashlib,time,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from importlib import import_module
sys.path.insert(0,str(Path(__file__).parent))
crossing_pairs=import_module('blender-cloth-prepare').pairs
untangle=import_module('blender-cloth-prepare').untangle
path=Path(sys.argv[sys.argv.index('--')+1]).resolve()
data=json.loads(path.read_text());assert data['format']=='pz-cloth-scene-v1'
edge=.012
if '--edge-meters' in sys.argv:
    edge=float(sys.argv[sys.argv.index('--edge-meters')+1])
    assert .006<=edge<=.03,'Physical edge target must be 6–30 mm'
conforming='--conforming' in sys.argv
posed_shell='--posed-shell' in sys.argv
conforming=conforming or posed_shell

def bary(p,a,b,c):
    u=b-a;v=c-a;w=p-a
    uu=u.dot(u);uv=u.dot(v);vv=v.dot(v);wu=w.dot(u);wv=w.dot(v)
    d=uu*vv-uv*uv
    if abs(d)<1e-20:return [1,0,0]
    s=(vv*wu-uv*wv)/d;t=(uu*wv-uv*wu)/d
    return [1-s-t,s,t]

def bound_point(p,tree,vertices,faces):
    hit,normal,index,distance=tree.find_nearest(p)
    ids=faces[index];weights=bary(hit,*(vertices[i] for i in ids))
    return ids,weights,distance

def mix(vertices,ids,weights):return sum((vertices[i]*w for i,w in zip(ids,weights)),Vector())

def stats(vertices,faces):
    lengths=[];angles=[];edges={};area=0
    for face in faces:
        a,b,c=(vertices[i] for i in face)
        area+=(b-a).cross(c-a).length*.5
        for i in range(3):
            ia,ib=face[i],face[(i+1)%3];key=tuple(sorted((ia,ib)));edges[key]=edges.get(key,0)+1
            u=vertices[ib]-vertices[ia];v=vertices[face[(i+2)%3]]-vertices[ia]
            if u.length>1e-9 and v.length>1e-9:angles.append(math.degrees(u.angle(v)))
    lengths=sorted((vertices[a]-vertices[b]).length for a,b in edges)
    return {'vertices':len(vertices),'triangles':len(faces),'area':area,'boundaryEdges':sum(v==1 for v in edges.values()),
            'nonManifoldEdges':sum(v>2 for v in edges.values()),'minAngle':min(angles,default=0),
            'edgesP10P50P90':[lengths[int((len(lengths)-1)*q)] for q in [.1,.5,.9]] if lengths else []}

result={'format':'pz-cloth-prepared-v1','sourceSha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'sourceFile':path.name,'camera':data['camera'],'floor':data['floor'],'duration':data['duration'],'fps':data['fps'],'items':[]}
reports=[];coarse_items=[];started=time.perf_counter()
for item_index,(item,garment) in enumerate(zip(data['items'],data['garments'])):
    rest=[];posed=[];faces=[];face_uvs=[];weld={};seen=set();render_surfaces=[]
    for si,surface in enumerate(item['surfaces']):
        rest_data=garment['restSurfaces'][si]['positions'];mapping={}
        for i in sorted(set(surface['indices'])):
            r=Vector(rest_data[i*3:i*3+3]);p=Vector(surface['positions'][i*3:i*3+3])
            key=tuple(round(x,7) for x in r)
            if key not in weld:weld[key]=len(rest);rest.append(r);posed.append(p)
            mapping[i]=weld[key]
        for i in range(0,len(surface['indices']),3):
            f=[mapping[j] for j in surface['indices'][i:i+3]];key=tuple(sorted(f))
            if len(set(f))<3 or key in seen:continue
            if (rest[f[1]]-rest[f[0]]).cross(rest[f[2]]-rest[f[0]]).length<1e-12:continue
            seen.add(key);faces.append(f)
            face_uvs.append([surface['uvs'][j*2:j*2+2] for j in surface['indices'][i:i+3]])
    # Keep source connectivity to avoid welding opposite sheets at a crossing.
    # All subsequent construction uses the baked pose, never the skeleton/bind pose.
    if posed_shell:rest=[p.copy() for p in posed]
    before=stats(rest,faces)
    if before['nonManifoldEdges']:raise RuntimeError(('Non-manifold source',item_index,before))
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    mesh=bpy.data.meshes.new('source');mesh.from_pydata(rest,[],faces);mesh.update()
    obj=bpy.data.objects.new('simulation proxy',mesh);bpy.context.collection.objects.link(obj)
    obj.select_set(True);bpy.context.view_layer.objects.active=obj
    # Global retopology in the unposed metric, not recursive splits of skinny posed triangles.
    target=max(200,round(before['area']/edge**2))
    if not conforming:
        status=bpy.ops.object.quadriflow_remesh(target_faces=target,use_mesh_symmetry=False,
            use_preserve_boundary=True,use_preserve_sharp=False,seed=0)
        if 'FINISHED' not in status:raise RuntimeError(('Quadriflow failed',item_index,str(status)))
    bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.triangulate(bm,faces=list(bm.faces))
    if conforming:
        # Shared-edge subdivisions preserve seams and do not connect opposite sheets.
        # Resolution is based on the undeformed surface, not collapsed posed edges.
        cuts=max(1,min(3,math.ceil(before['edgesP10P50P90'][1]/edge)-1))
        bmesh.ops.subdivide_edges(bm,edges=list(bm.edges),cuts=cuts,use_grid_fill=True)
        bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bm.to_mesh(obj.data);bm.free();obj.data.update()
    tree=BVHTree.FromPolygons(rest,faces,all_triangles=True)
    proxy_rest=[];proxy_posed=[];bindings=[];projection_distances=[]
    for vertex in obj.data.vertices:
        ids,weights,distance=bound_point(vertex.co,tree,rest,faces)
        proxy_rest.append(mix(rest,ids,weights));proxy_posed.append(mix(posed,ids,weights))
        bindings.append({'ids':ids,'weights':weights});projection_distances.append(distance)
    proxy_faces=[list(p.vertices) for p in obj.data.polygons]
    proxy_uvs=[]
    for face in proxy_faces:
        center=sum((proxy_rest[i] for i in face),Vector())/3
        _,_,fi,_=tree.find_nearest(center)
        tri=faces[fi];coords=face_uvs[fi]
        proxy_uvs.append([[sum(w*coords[k][axis] for k,w in enumerate(bary(proxy_rest[i],*(rest[j] for j in tri)))) for axis in [0,1]] for i in face])
    after=stats(proxy_rest,proxy_faces)
    proxy_tree=BVHTree.FromPolygons(proxy_rest,proxy_faces,all_triangles=True)
    max_render_gap=0
    for si,surface in enumerate(item['surfaces']):
        rest_data=surface['positions'] if posed_shell else garment['restSurfaces'][si]['positions'];vertex_bindings=[]
        # Keep the render topology/UVs and exact start positions; bind only used vertices.
        for i in sorted(set(surface['indices'])):
            ids,weights,distance=bound_point(Vector(rest_data[i*3:i*3+3]),proxy_tree,proxy_rest,proxy_faces)
            start=Vector(surface['positions'][i*3:i*3+3]);anchor=mix(proxy_posed,ids,weights)
            max_render_gap=max(max_render_gap,(start-anchor).length)
            vertex_bindings.append({'vertex':i,'ids':ids,'weights':weights,'startAnchor':list(anchor)})
        render_surfaces.append({**surface,'bindings':vertex_bindings})
    render_start=[list(p) for p in proxy_posed]
    repair=None
    if posed_shell:
        coarse,coarse_report=untangle(posed,faces,max_shift=.03)
        coarse_items.append({'positions':coarse,'faces':faces,'bindings':bindings})
        print('COARSE_REPAIR',item_index,json.dumps(coarse_report),flush=True)
        if not coarse_report['after']:
            coarse_vectors=[Vector(p) for p in coarse]
            repaired=[mix(coarse_vectors,b['ids'],b['weights']) for b in bindings]
            repair={'before':len(crossing_pairs(proxy_posed,proxy_faces)),'after':len(crossing_pairs(repaired,proxy_faces)),
                'maxShift':max((p-q).length for p,q in zip(repaired,proxy_posed))}
        else:repaired,repair=untangle(proxy_posed,proxy_faces,max_shift=.03)
        proxy_posed=[Vector(p) for p in repaired]
        proxy_rest=[p.copy() for p in proxy_posed]
        if repair['after'] and '--allow-initial-intersections' not in sys.argv:
            raise RuntimeError('Не удалось безопасно распутать физическую поверхность вещи %d: осталось %d пересечений. Геометрия не вырезалась.'%(item_index+1,repair['after']))
        if coarse_report['after']:
            # A successful fine-mesh repair must not be replaced by the still
            # intersecting coarse mesh during the layer-level preparation.
            coarse_items[-1]={'positions':[list(p) for p in proxy_posed],'faces':proxy_faces,
                'bindings':[{'ids':[i,i,i],'weights':[1,0,0]} for i in range(len(proxy_posed))]}
    report={'index':item_index,'method':'baked-pose-shell' if posed_shell else ('conforming-rest-surface' if conforming else 'quadriflow'),'model':garment['model'],'texture':garment['texture'],'before':before,'after':after,
        'sourcePosedIntersections':len(crossing_pairs(posed,faces)),
        'proxyPosedIntersections':len(crossing_pairs(proxy_posed,proxy_faces)),
        'maxRestProjection':max(projection_distances,default=0),'maxRenderBindingGap':max_render_gap,
        'renderStartDelta':0,'areaRatio':after['area']/before['area']}
    if repair:
        report['repair']=repair
        report['physicalSurface']=stats(proxy_posed,proxy_faces)
    report['geometricTransferPassed']=report['maxRenderBindingGap']<.001 and abs(report['areaRatio']-1)<.01 and not after['nonManifoldEdges']
    report['collisionReady']=report['proxyPosedIntersections']==0
    reports.append(report);print('PREPARED',json.dumps(report),flush=True)
    result['items'].append({'index':item_index,'model':garment['model'],'texture':garment['texture'],
        'releaseTime':item['releaseTime'],'target':item['target'],'velocity':data['velocities'][item_index],
        'spin':item.get('spin',0),'layerId':item.get('layerId'),'seed':item['seed'],
        'fabricStiffness':item.get('fabricStiffness',1),
        'restPositions':[list(p) for p in proxy_rest],'positions':[list(p) for p in proxy_posed],
        'renderStartPositions':render_start if posed_shell else None,
        'faces':proxy_faces,'faceUvs':proxy_uvs,'sourceBindings':bindings,'renderSurfaces':render_surfaces})
layer_repairs=[]
if posed_shell and '--repair-layers' in sys.argv:
    layers={}
    for i,item in enumerate(result['items']):layers.setdefault(item['releaseTime'],[]).append(i)
    for release,indices in layers.items():
        if len(indices)<2:continue
        points=[];triangles=[];ranges={}
        for i in indices:
            coarse=coarse_items[i];start=len(points)
            points.extend(coarse['positions']);ranges[i]=(start,len(points))
            triangles.extend([v+start for v in face] for face in coarse['faces'])
        vectors=[Vector(p) for p in points]
        centers={i:sum(vectors[a:b],Vector())/(b-a) for i,(a,b) in ranges.items()}
        center=sum(centers.values(),Vector())/len(indices)
        directions={}
        for rank,i in enumerate(indices):
            direction=centers[i]-center;direction.y=0
            if direction.length<1e-6:
                angle=rank*2*math.pi/len(indices);direction=Vector((math.cos(angle),0,math.sin(angle)))
            directions[i]=direction.normalized()
        average_direction=sum(directions.values(),Vector())/len(indices)
        directions={i:d-average_direction for i,d in directions.items()}
        max_direction=max(d.length for d in directions.values())
        if max_direction>1e-8:directions={i:d/max_direction for i,d in directions.items()}
        first=len(crossing_pairs(vectors,triangles));distance=0;repaired=vectors
        if first:
            for step in range(1,25):
                distance=step*.005
                repaired=[p+directions[i]*distance for i in indices for p in vectors[slice(*ranges[i])]]
                if not crossing_pairs(repaired,triangles):
                    # Contact clearance, not merely a zero-depth crossing.
                    distance+=.002
                    repaired=[p+directions[i]*distance for i in indices for p in vectors[slice(*ranges[i])]]
                    break
        repair={'before':first,'after':len(crossing_pairs(repaired,triangles)),'maxShift':distance,'method':'independent-island-separation'}
        print('LAYER_REPAIR',release,json.dumps(repair),flush=True)
        layer_repairs.append({'releaseTime':release,**repair})
        if repair['after']:
            if '--allow-initial-intersections' not in sys.argv:raise RuntimeError('Не удалось распутать слой: '+str(repair))
            # Failed separation must not add the maximum trial displacement.
            # Keep the already repaired pieces and report the unresolved contact.
            repair['fallback']='keep-individual-repair';continue
        for i in indices:
            start,end=ranges[i];coarse=[Vector(p) for p in repaired[start:end]]
            physical=[list(mix(coarse,b['ids'],b['weights'])) for b in coarse_items[i]['bindings']]
            result['items'][i]['positions']=physical;result['items'][i]['restPositions']=physical
            result['items'][i]['releaseSeparation']=list(directions[i]*distance)
            reports[i]['physicalSurface']=stats([Vector(p) for p in physical],result['items'][i]['faces'])
        refined=[];refined_faces=[]
        for i in indices:
            start=len(refined);item=result['items'][i]
            refined.extend(Vector(p) for p in item['positions'])
            refined_faces.extend([v+start for v in face] for face in item['faces'])
        repair['refinedAfter']=len(crossing_pairs(refined,refined_faces))
        layer_repairs[-1]['refinedAfter']=repair['refinedAfter']
        if repair['refinedAfter'] and '--allow-initial-intersections' not in sys.argv:raise RuntimeError('Уточнённая поверхность слоя пересекается: '+str(repair))
result['report']={'seconds':time.perf_counter()-started,'items':reports,'layerRepairs':layer_repairs}
if posed_shell:result['material']={'model':'baked-pose-thin-shell-v1','arealDensityKgM2':.2,'contactThicknessM':.0014,'solverMassScale':15000,'renderRepairBlendSeconds':.18,'targetEdgeM':edge}
suffix='prepared' if conforming else 'quadriflow-rejected'
(path.parent/('scene-'+suffix+'.json')).write_text(json.dumps(result,separators=(',',':')))
(path.parent/(suffix+'-report.json')).write_text(json.dumps(result['report'],indent=2))
print('DONE',result['report']['seconds'],flush=True)
