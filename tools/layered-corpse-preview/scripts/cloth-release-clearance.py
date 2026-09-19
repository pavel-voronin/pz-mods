"""Final physical-mesh validation; remeshing can reconnect a previously clear seam."""
import math
from importlib import import_module
from mathutils import Vector
from mathutils.bvhtree import BVHTree
pairs=import_module('blender-cloth-prepare').pairs

def layer_status(items, points):
    vertices=[];faces=[];trees=[]
    for item,p in zip(items,points):
        offset=len(vertices);vertices.extend(p)
        faces.extend(tuple(offset+i for i in f) for f in item['faces'])
        trees.append(BVHTree.FromPolygons(p,item['faces'],all_triangles=True))
    gap=1e9
    for a in range(len(items)):
        for b in range(a):
            for src,dst in [(a,b),(b,a)]:
                for v in points[src]:
                    hit=trees[dst].find_nearest(v)
                    if hit[0] is not None:gap=min(gap,hit[3])
    return {'crossings':len(pairs(vertices,faces)),'vertexSurfaceGap':gap}

def ensure_release_clearance(items, clearance=.0022, limit=.05, allow_intersections=False):
    layers={};reports=[]
    for item in items:layers.setdefault(item['releaseTime'],[]).append(item)
    for release,group in layers.items():
        points=[[Vector(v) for v in item['positions']] for item in group]
        before=layer_status(group,points)
        if len(group)==1:
            if before['crossings']:
                if not allow_intersections:raise RuntimeError('Self-intersection after remesh')
                reports.append({'releaseTime':release,'before':before,'after':before,'maxShift':0,'fallback':'unresolved-self-contact'})
            continue
        centers=[sum(p,Vector())/len(p) for p in points];center=sum(centers,Vector())/len(centers)
        directions=[]
        for i,c in enumerate(centers):
            d=c-center;d.y=0
            if d.length<1e-6:d=Vector((math.cos(i*math.tau/len(group)),0,math.sin(i*math.tau/len(group))))
            directions.append(d.normalized())
        average=sum(directions,Vector())/len(directions)
        directions=[d-average for d in directions];scale=max(d.length for d in directions)
        directions=[d/scale for d in directions]
        distance=0;after=before;shifted=points
        if before['crossings'] or before['vertexSurfaceGap']<clearance:
            for step in range(1,round(limit/.001)+1):
                distance=step*.001
                shifted=[[p+d*distance for p in pp] for pp,d in zip(points,directions)]
                after=layer_status(group,shifted)
                if not after['crossings'] and after['vertexSurfaceGap']>=clearance:break
            else:
                if not allow_intersections:raise RuntimeError('Не удалось разделить физические сетки слоя после ремеша: '+str(after))
                # Preserve trajectory and pose rather than applying a failed 5 cm offset.
                reports.append({'releaseTime':release,'before':before,'after':before,'maxShift':0,'fallback':'keep-individual-repair'})
                continue
        for item,p,d in zip(group,shifted,directions):
            item['positions']=[list(v) for v in p];item['restPositions']=item['positions']
            item['releaseSeparation']=list(Vector(item.get('releaseSeparation',(0,0,0)))+d*distance)
        reports.append({'releaseTime':release,'before':before,'after':after,'maxShift':distance})
    return reports
