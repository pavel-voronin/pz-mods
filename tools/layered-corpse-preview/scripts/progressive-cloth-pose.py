"""Experimental quasi-static dressing; collision-safe path, then reset rest metric.

No cutting, Boolean unions, simulated launch, or velocities from preparation.
IPC supplies contact barriers and continuous collision detection, not a material
model: this stage minimizes distance to an animated skinning target with smooth
local corrections. The subsequent Blender solve supplies fabric dynamics.
"""
import sys,json,time,hashlib,math
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'.cloth-deps'))
import numpy as np
import scipy.sparse as sp
from scipy.sparse.linalg import spsolve
from scipy.spatial.transform import Rotation,Slerp
import ipctk,pymeshlab
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from importlib import import_module
sys.path.insert(0,str(Path(__file__).parent))
helpers=import_module('blender-cloth-prepare')

def edges(f):return np.unique(np.sort(np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),axis=1),axis=0)
def normals(x,f):
    n=np.zeros_like(x);fn=np.cross(x[f[:,1]]-x[f[:,0]],x[f[:,2]]-x[f[:,0]])
    for j in range(3):np.add.at(n,f[:,j],fn)
    return n/np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-15)
def binding(points,x,f):
    vs=[Vector(v) for v in x];tree=BVHTree.FromPolygons(vs,f.tolist(),all_triangles=True)
    ids=[];weights=[]
    for point in points:
        hit,_,fi,_=tree.find_nearest(Vector(point));face=f[fi];a,b,c=x[face]
        uv=np.linalg.lstsq(np.column_stack((b-a,c-a)),np.array(hit)-a,rcond=None)[0]
        ids.append(face);weights.append([1-uv.sum(),*uv])
    return np.array(ids),np.array(weights)
def transfer(x,ids,w):return (x[ids]*w[:,:,None]).sum(axis=1)

def capsule_obstacles(capsules,pose_path=None):
    faces=[];descriptions=[];offset=0
    for cap in capsules:
        a0,b0,a1,b1=(np.array(cap[k]) for k in ['startA','startB','a','b'])
        axes=[(b0-a0)/np.linalg.norm(b0-a0),(b1-a1)/np.linalg.norm(b1-a1)]
        ref=np.eye(3)[min(range(3),key=lambda j:max(abs(v[j]) for v in axes))]
        rings=[];local=[(-math.pi/2,0,0.)]
        for end,latitudes in [(0,[-math.pi/3,-math.pi/6,0]),(1,[0,math.pi/6,math.pi/3])]:
            ring_ids=[]
            for theta in latitudes:
                ring_ids=list(range(len(local),len(local)+8));rings.append(ring_ids)
                local.extend((theta,end,k*math.pi/4) for k in range(8))
        top=len(local);local.append((math.pi/2,1,0.))
        for k in range(8):faces.append([offset,offset+rings[0][(k+1)%8],offset+rings[0][k]])
        for r,s in zip(rings[:-1],rings[1:]):
            for k in range(8):
                j=(k+1)%8;faces.extend([[offset+r[k],offset+r[j],offset+s[k]],[offset+s[k],offset+r[j],offset+s[j]]])
        for k in range(8):faces.append([offset+top,offset+rings[-1][k],offset+rings[-1][(k+1)%8]])
        descriptions.append((a0,b0,a1,b1,ref,cap['radius'],local,cap));offset+=len(local)
    def target(t):
        points=[]
        for a0,b0,a1,b1,ref,r,local,cap in descriptions:
            a=(1-t)*a0+t*a1;b=(1-t)*b0+t*b1
            if pose_path and 'attachmentA' in cap:
                def endpoint(key):
                    info=cap[key];m=pose_path.at(t)[info['bone']]
                    return m[:3,:3]@np.array(info['local'])+m[:3,3]
                a=endpoint('attachmentA');b=endpoint('attachmentB')
            axis=b-a;axis/=np.linalg.norm(axis)
            u=np.cross(axis,ref);u/=np.linalg.norm(u);v=np.cross(axis,u)
            for theta,end,phi in local:points.append((b if end else a)+r*(axis*math.sin(theta)+math.cos(theta)*(u*math.cos(phi)+v*math.sin(phi))))
        return np.array(points)
    return target,np.array(faces,dtype=np.int32)

def collect(surfaces,rest_surfaces,rig=None,pose_path=None):
    x=[];end=[];f=[];uv=[];weld={};seen=set();influences=[]
    for si,s in enumerate(surfaces):
        r=np.array(rest_surfaces[si]['positions']).reshape(-1,3);p=np.array(s['positions']).reshape(-1,3)
        tex=np.array(s['uvs']).reshape(-1,2);mapping={}
        for v in sorted(set(s['indices'])):
            key=tuple(np.round(r[v],7))
            if key not in weld:
                weld[key]=len(x);x.append(r[v]);end.append(p[v]);influences.append((si,v))
            mapping[v]=weld[key]
        for face in np.array(s['indices']).reshape(-1,3):
            ids=[mapping[int(v)] for v in face];key=tuple(sorted(ids))
            if len(set(ids))<3 or key in seen:continue
            if np.linalg.norm(np.cross(np.array(x[ids[1]])-x[ids[0]],np.array(x[ids[2]])-x[ids[0]]))<1e-12:continue
            seen.add(key);f.append(ids);uv.append(tex[face].tolist())
    x=np.array(x);end=np.array(end);f=np.array(f,dtype=np.int32)
    if rig:
        transforms=[]
        for part in rig:
            part_m=[]
            for bone,values in enumerate(part.get('endGlobals',part['skinMatrices'])):
                m=np.array(values).reshape(4,4).T
                u,scale,v=np.linalg.svd(m[:3,:3]);rot=u@v
                if np.linalg.det(rot)<0:raise RuntimeError('Reflected skin transform is not supported by progressive posing')
                starts=part.get('startGlobals',part.get('startMatrices'))
                start=np.array(starts[bone]).reshape(4,4).T if starts else np.eye(4)
                u0,_,v0=np.linalg.svd(start[:3,:3]);rot0=u0@v0
                part_m.append((Slerp([0,1],Rotation.from_matrix([rot0,rot])),rot0.T@start[:3,:3],rot.T@m[:3,:3],start[:3,3],m[:3,3]))
            transforms.append(part_m)
        def target(t):
            if pose_path:
                globals=pose_path.at(t);out=np.zeros_like(x)
                matrices=[[(np.eye(4) if n=='__identity' else globals[n])@np.array(o).reshape(4,4).T for n,o in zip(part['boneNames'],part['offsets'])] for part in rig]
                for i,(si,v) in enumerate(influences):
                    for j in range(4):
                        weight=rig[si]['weights'][v*4+j]
                        if weight:
                            m=matrices[si][rig[si]['joints'][v*4+j]]
                            out[i]+=weight*(m[:3,:3]@x[i]+m[:3,3])
                return out
            matrices=[[r([t]).as_matrix()[0]@((1-t)*scale0+t*scale1) for r,scale0,scale1,tr0,tr1 in part] for part in transforms]
            out=np.zeros_like(x)
            for i,(si,v) in enumerate(influences):
                for j in range(4):
                    weight=rig[si]['weights'][v*4+j]
                    if weight:
                        bone=rig[si]['joints'][v*4+j]
                        point=x[i]
                        if rig[si].get('offsets'):
                            offset=np.array(rig[si]['offsets'][bone]).reshape(4,4).T;point=offset[:3,:3]@point+offset[:3,3]
                        out[i]+=weight*(matrices[si][bone]@point+(1-t)*transforms[si][bone][3]+t*transforms[si][bone][4])
            return out
        error=float(np.max(np.linalg.norm(target(1)-end,axis=1)))
        if error>1e-5:raise RuntimeError('Skinning export mismatch: '+str(error))
        mode='hierarchical-joint-continuation' if pose_path else 'skin-transform-continuation'
    else:
        # Older snapshots lack skeleton data. Diagnostic only; not the new UI path.
        a=x.mean(axis=0);b=end.mean(axis=0);u,_,vt=np.linalg.svd((x-a).T@(end-b));r=vt.T@u.T
        if np.linalg.det(r)<0:vt[-1]*=-1;r=vt.T@u.T
        rotation=Slerp([0,1],Rotation.from_matrix([np.eye(3),r]))
        aligned=(end-b)@r+a
        def target(t):return ((1-t)*(x-a)+t*(aligned-a))@rotation([t]).as_matrix()[0].T+(1-t)*a+t*b
        mode='legacy-diagnostic-rigid-aligned-continuation'
    return target(0),end,f,uv,target,mode

def solve_path(x,faces,goals,body_start=None,steps=48):
    """Damped Newton minimization + CCD line search; every accepted step is checked."""
    mesh=ipctk.CollisionMesh(x,edges(faces),faces)
    if body_start is not None:mesh.can_collide=ipctk.make_static_obstacle_filter(body_start)
    if ipctk.has_intersections(mesh,x):raise RuntimeError('Исходная расправленная поверхность IPC всё ещё пересекается')
    ee=edges(faces);n=len(x)
    # Smooth displacement from the goal, not a spring trying to retain T-pose.
    incidence=sp.coo_matrix((np.tile([1.,-1.],len(ee)),(np.repeat(np.arange(len(ee)),2),ee.ravel())),shape=(len(ee),n)).tocsr()
    weights=np.ones(n)
    if body_start is not None:weights[body_start:]=1000
    base=sp.kron(sp.diags(weights)+.15*(incidence.T@incidence),sp.eye(3),format='csc')
    barrier=ipctk.BarrierPotential(.0015,1e6)
    logs=[];history=[x.copy()];started=time.perf_counter()
    def energy(y,goal,derivatives=False):
        collisions=ipctk.NormalCollisions();collisions.build(mesh,y,.0015)
        d=(y-goal).ravel();value=.5*d@(base@d)+barrier(collisions,mesh,y)
        if not derivatives:return value
        g=base@d+barrier.gradient(collisions,mesh,y)
        h=base+barrier.hessian(collisions,mesh,y,ipctk.PSDProjectionMethod.CLAMP)
        return value,g,h
    for step in range(1,steps+1):
        goal=goals(step/steps);last_move=0;converged=False
        for iteration in range(40):
            value,g,h=energy(x,goal,True)
            direction=spsolve(h,-g).reshape(-1,3)
            if not np.isfinite(direction).all():raise RuntimeError('Non-finite preparation direction')
            alpha=min(1.,float(ipctk.compute_collision_free_stepsize(mesh,x,x+direction)))
            slope=float(g@direction.ravel())
            for line in range(32):
                candidate=x+alpha*direction
                if energy(candidate,goal)<=value+1e-4*alpha*slope:break
                alpha*=.5
            else:raise RuntimeError('Preparation line search did not converge')
            last_move=float(np.max(np.linalg.norm(alpha*direction,axis=1)))
            x=candidate
            if last_move<2e-6:converged=True;break
        if ipctk.has_intersections(mesh,x):raise RuntimeError('IPC intersection after an accepted step')
        error=np.linalg.norm(x-goal,axis=1)
        logs.append({'step':step,'iterations':iteration+1,'converged':converged,'maxGoalError':float(error.max()),'lastMove':last_move})
        history.append(x.copy())
        print('POSE',step,steps,round(time.perf_counter()-started,2),'error',round(float(error.max()),5),flush=True)
    return x,logs,history

def main():
    args=sys.argv[sys.argv.index('--')+1:];path=Path(args[0]).resolve();source=json.loads(path.read_text());started=time.perf_counter()
    selected=int(args[args.index('--item')+1]) if '--item' in args else None
    pose_path=import_module('progressive-skeleton').PosePath(source['bodyPreparationRig']) if source.get('bodyPreparationRig',[{}])[0].get('boneNames') else None
    body_data=None;body_tree=None;body_normals=None
    if source.get('bodyPreparationRig'):
        body_data=collect(source['body'],source['bodyPreparationRig'],source['bodyPreparationRig'],pose_path)
        body_tree=BVHTree.FromPolygons([Vector(v) for v in body_data[0]],body_data[2].tolist(),all_triangles=True)
        body_normals=normals(body_data[0],body_data[2])
    pieces=[];all_faces=[];all_x=[];ranges=[];targets=[];reports=[]
    for index,(item,garment) in enumerate(zip(source['items'],source['garments'])):
        if selected is not None and index!=selected:continue
        rest,end,faces,uv,target,mode=collect(item['surfaces'],garment['restSurfaces'],garment.get('preparationRig'),pose_path)
        initial_crossings=len(helpers.pairs([Vector(v) for v in rest],faces.tolist()))
        repaired,repair=helpers.untangle([Vector(v) for v in rest],faces.tolist(),max_shift=.005)
        if repair['after']:raise RuntimeError('Исходная T-поза требует отдельного восстановления: '+str(repair))
        ms=pymeshlab.MeshSet();ms.add_mesh(pymeshlab.Mesh(vertex_matrix=np.array(repaired),face_matrix=faces))
        ms.meshing_isotropic_explicit_remeshing(iterations=5,targetlen=pymeshlab.PureValue(.018),featuredeg=180,checksurfdist=True,maxsurfdist=pymeshlab.PureValue(.001))
        physical=ms.current_mesh().vertex_matrix().copy();pf=ms.current_mesh().face_matrix().copy()
        native_physical=physical.copy()
        ids,w=binding(physical,rest,faces)
        ns=normals(physical,pf);garment_normals=ns.copy()
        if body_tree:
            ni,nw=binding(physical,body_data[0],body_data[2]);ns=transfer(body_normals,ni,nw);ns/=np.maximum(np.linalg.norm(ns,axis=1)[:,None],1e-10)
        print('REST_NORMAL',index,float(np.mean(np.sum(ns*(physical-physical.mean(axis=0)),axis=1))),flush=True)
        # Candidate initial layer separation. This is not guaranteed to be
        # intersection-free: the combined IPC check must accept it before posing.
        if body_tree:
            anchors=transfer(body_data[0],ni,nw)
            signed=np.sum((physical-anchors)*ns,axis=1)
            shift=ns*np.maximum(0,.003*(index+1)-signed)[:,None]
        else:shift=ns*(.002*(index+1))
        worst=int(np.linalg.norm(shift,axis=1).argmax());print('INITIAL_SHIFT',index,float(np.linalg.norm(shift[worst])),native_physical[worst].tolist(),shift[worst].tolist(),flush=True)
        if body_tree and garment['model']!='body':
            raw=physical.copy();goal=physical+shift
            physical,initial_logs,_=solve_path(raw,pf,lambda t:raw+t*(goal-raw),steps=16)
            shift=physical-raw
        else:physical+=shift
        # A small initial layer separation fades from the target, never from the
        # collision-constrained result. Contacts decide the final separation.
        def target_physical(t,target=target,ids=ids,w=w,shift=shift):return transfer(target(t),ids,w)+(1-t)*shift
        render_ids,render_w=binding(rest,physical,pf)
        start=len(all_x);all_x.extend(physical);all_faces.extend(pf+start);ranges.append((start,len(all_x)))
        targets.append(target_physical)
        pieces.append({'index':index,'original':item,'garment':garment,'rest':rest,'end':end,'faces':faces,'uv':uv,'physicalFaces':pf,'renderIds':render_ids,'renderWeights':render_w,'nativePhysical':native_physical})
        reports.append({'index':index,'sourceRestCrossings':initial_crossings,'initialRepair':repair,'mode':mode,'particles':len(physical)})
    cloth_count=len(all_x)
    body_goal=None
    if source.get('preparationCapsules'):
        fitted_capsules=[]
        for cap in source['preparationCapsules']:
            a=np.array(cap['startA']);b=np.array(cap['startB'])
            distances=[body_tree.find_nearest(Vector(a+(b-a)*t))[3] for t in np.linspace(0,1,9)]
            fitted_capsules.append({**cap,'radius':min(cap['radius'],.8*min(distances))})
        print('BODY_RADII',[(c['radius'],d['radius']) for c,d in zip(source['preparationCapsules'],fitted_capsules)],flush=True)
        cap_goal,body_faces=capsule_obstacles(fitted_capsules,pose_path)
        floor=np.array([[-3,source['floor'],-3],[3,source['floor'],-3],[3,source['floor'],3],[-3,source['floor'],3]])
        count=len(cap_goal(0));body_faces=np.vstack((body_faces,np.array([[0,1,2],[0,2,3]])+count))
        body_goal=lambda t:np.vstack((cap_goal(t),floor))
        all_x.extend(body_goal(0));all_faces.extend(body_faces+cloth_count);targets.append(body_goal)
    x=np.array(all_x);faces=np.array(all_faces,dtype=np.int32)
    (path.parent/'initial-debug.json').write_text(json.dumps({'positions':x.tolist(),'faces':faces.tolist(),'ranges':ranges,'body':body_data[0].tolist() if body_data else []}))
    print('POSE_INITIAL',len(x),len(faces),json.dumps(reports),flush=True)
    final,logs,history=solve_path(x,faces,lambda t:np.concatenate([fn(t) for fn in targets]),body_start=cloth_count if body_goal else None)
    body_error=float(np.max(np.linalg.norm(final[cloth_count:]-body_goal(1),axis=1))) if body_goal else None
    if body_error is not None and body_error>.002:raise RuntimeError('Body constraint conflict: '+str(body_error))
    result={'format':'pz-cloth-prepared-v1','sourceSha256':hashlib.sha256(path.read_bytes()).hexdigest(),'sourceFile':path.name,
      'camera':source['camera'],'floor':source['floor'],'duration':source['duration'],'fps':source['fps'],'items':[],
      'material':{'model':'progressive-pose-shell-v1','arealDensityKgM2':.2,'contactThicknessM':.0014,'solverMassScale':15000,'renderRepairBlendSeconds':.18,'targetEdgeM':.018}}
    if body_goal:result['bodyCapsules']=[{k:c[k] for k in ['a','b','radius']} for c in fitted_capsules]
    for piece,(a,b),report in zip(pieces,ranges,reports):
        i=piece['index'];item=piece['original'];g=piece['garment'];p=final[a:b];ids=piece['renderIds'];w=piece['renderWeights']
        gap=np.linalg.norm(transfer(p,ids,w)-piece['end'],axis=1)
        report.update({'maxPosedDeviation':float(gap.max()),'p95PosedDeviation':float(np.quantile(gap,.95)),
          'geometricTransferPassed':bool(gap.max()<.04),'collisionReady':True,'proxyPosedIntersections':0})
        if not report['geometricTransferPassed']:raise RuntimeError('Preparation changed garment by more than 4 cm: '+str(report))
        result['items'].append({'index':i,'model':g['model'],'texture':g['texture'],'releaseTime':item['releaseTime'],'target':item['target'],
          'velocity':source['velocities'][i],'spin':item.get('spin',0),'layerId':item.get('layerId'),'seed':item['seed'],'fabricStiffness':item.get('fabricStiffness',1),
          'positions':p.tolist(),'restPositions':p.tolist(),'faces':piece['physicalFaces'].tolist(),'faceUvs':[[[0,0]]*3 for _ in piece['physicalFaces']],
          'renderStartPositions':piece['end'].tolist(),'renderFaces':piece['faces'].tolist(),'renderFaceUvs':piece['uv'],
          'renderBindings':[{'ids':ix.tolist(),'weights':ww.tolist()} for ix,ww in zip(ids,w)]})
    result['report']={'seconds':time.perf_counter()-started,'items':reports,'progressivePose':{'steps':logs,'initialIntersections':False,'finalIntersections':False,'bodyContacts':'capsules' if body_goal else False,'maxBodyDeviation':body_error,'velocitiesReset':True,'restMetricReset':True}}
    (path.parent/'scene-progressive.json').write_text(json.dumps(result,separators=(',',':')))
    (path.parent/'progressive-report.json').write_text(json.dumps(result['report'],indent=2))
    np.savez_compressed(path.parent/'progressive-path.npz',frames=np.array(history),faces=faces,ranges=np.array(ranges))
    print('POSE_RESULT',json.dumps(reports),flush=True)
if __name__=='__main__':
    try:main()
    except Exception as error:
        if '--' in sys.argv and len(sys.argv)>sys.argv.index('--')+1:
            source_path=Path(sys.argv[sys.argv.index('--')+1]).resolve()
            (source_path.parent/'progressive-failure.json').write_text(json.dumps({'status':'rejected','error':str(error),'sourceSha256':hashlib.sha256(source_path.read_bytes()).hexdigest()},ensure_ascii=False,indent=2),encoding='utf-8')
        raise
