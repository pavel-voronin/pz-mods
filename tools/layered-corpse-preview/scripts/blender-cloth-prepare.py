"""Bounded local untangling for the standalone cloth experiment, not app geometry."""
from mathutils import Vector,geometry
from mathutils.bvhtree import BVHTree

def intersect(a,b,tri):
    d=b-a
    if d.length_squared<1e-16:return False
    hit=geometry.intersect_ray_tri(*tri,d,a,True)
    if hit is None:return False
    t=(hit-a).dot(d)/d.length_squared
    normal=(tri[1]-tri[0]).cross(tri[2]-tri[0]).normalized()
    return 1e-5<t<1-1e-5 and (a-tri[0]).dot(normal)*(b-tri[0]).dot(normal)<-1e-12

def pairs(verts,faces):
    tree=BVHTree.FromPolygons(verts,faces,all_triangles=True,epsilon=0)
    result=[]
    for a,b in tree.overlap(tree):
        if a>=b or set(faces[a])&set(faces[b]):continue
        ta=[verts[i] for i in faces[a]];tb=[verts[i] for i in faces[b]]
        if any(intersect(ta[i],ta[(i+1)%3],tb) or intersect(tb[i],tb[(i+1)%3],ta) for i in range(3)):result.append((a,b))
    return result

def untangle(vertices,faces,max_shift=.03):
    rest=[Vector(p) for p in vertices];p=[v.copy() for v in rest]
    first=len(pairs(p,faces));best=first;bestp=[v.copy() for v in p]
    for iteration in range(160):
        intersections=pairs(p,faces)
        if len(intersections)<best:best=len(intersections);bestp=[v.copy() for v in p]
        if not intersections:break
        for a,b in intersections:
            options=[]
            for fa,fb in [(faces[a],faces[b]),(faces[b],faces[a])]:
                tri=[p[i] for i in fb];normal=(tri[1]-tri[0]).cross(tri[2]-tri[0]).normalized()
                distances=[(p[i]-tri[0]).dot(normal) for i in fa]
                for sign in [-1,1]:
                    amount=max(0,.0008-min(sign*d for d in distances))
                    options.append((amount,fa,fb,normal*sign))
            amount,fa,fb,normal=min(options,key=lambda option:option[0]);amount=min(amount,.004)
            for ids,sign in [(fa,1),(fb,-1)]:
                for i in ids:
                    candidate=p[i]+normal*(sign*amount*.5);delta=candidate-rest[i]
                    if delta.length>max_shift:delta=delta.normalized()*max_shift
                    p[i]=rest[i]+delta
    if len(pairs(p,faces))<best:bestp=p
    return [tuple(v) for v in bestp],{'before':first,'after':len(pairs(bestp,faces)),'maxShift':max((p-r).length for p,r in zip(bestp,rest))}
