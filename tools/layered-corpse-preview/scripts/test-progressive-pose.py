import sys
from pathlib import Path
from importlib import import_module
sys.path.insert(0,str(Path(__file__).parent))
p=import_module('progressive-cloth-pose');np=p.np;ipc=p.ipctk
vertices=np.array([[0,0,.02],[.1,0,.02],[0,.1,.02],[-1,-1,0],[1,-1,0],[0,1,0]],float)
faces=np.array([[0,1,2],[3,4,5]],dtype=np.int32)
mesh=ipc.CollisionMesh(vertices,p.edges(faces),faces);mesh.can_collide=ipc.make_static_obstacle_filter(3)
target=vertices.copy();target[:3,2]=-.02
assert not ipc.has_intersections(mesh,vertices)
assert not ipc.has_intersections(mesh,target),'Endpoint-only checking is insufficient'
step=ipc.compute_collision_free_stepsize(mesh,vertices,target)
assert 0<step<.51,'CCD failed to catch tunnelling'
result,log,_=p.solve_path(vertices,faces,lambda t:vertices+t*(target-vertices),body_start=3,steps=4)
assert not ipc.has_intersections(mesh,result)
assert result[:3,2].min()>-.001,'Cloth crossed the obstacle'
assert np.linalg.norm(result[3:]-vertices[3:],axis=1).max()<.001
print('PASS progressive posing: endpoint tunnelling rejected, shared barrier solve, bounded obstacle drift')

# A rotating parent must carry its child around a joint, not shorten the limb
# along the chord between two global positions.
PosePath=import_module('progressive-skeleton').PosePath
root0=np.eye(4);root1=np.eye(4);root1[:3,:3]=p.Rotation.from_euler('z',90,degrees=True).as_matrix()
local=np.eye(4);local[0,3]=1
flat=lambda m:m.T.ravel().tolist()
path=PosePath([{'boneNames':['Bip01_Pelvis','Bip01_Spine'],
               'startGlobals':[flat(root0),flat(root0@local)],
               'endGlobals':[flat(root1),flat(root1@local)]}])
for t in np.linspace(0,1,49):
    matrices=path.at(float(t))
    assert abs(np.linalg.norm(matrices['Bip01_Spine'][:3,3]-matrices['Bip01_Pelvis'][:3,3])-1)<1e-9
print('PASS hierarchical continuation: exact endpoints and constant joint-chain length')
