"""Diagnostic search for an intersection-free outer-shell initial embedding."""
import sys,json
from pathlib import Path
from importlib import import_module
sys.path.insert(0,str(Path(__file__).parent));p=import_module('progressive-cloth-pose');np=p.np
args=sys.argv[sys.argv.index('--')+1:];source=json.loads(Path(args[0]).read_text());inner=json.loads(Path(args[1]).read_text())
path=import_module('progressive-skeleton').PosePath(source['bodyPreparationRig'])
item=source['items'][3];g=source['garments'][3]
rest,end,f,uv,target,mode=p.collect(item['surfaces'],g['restSurfaces'],g['preparationRig'],path)
ms=p.pymeshlab.MeshSet();ms.add_mesh(p.pymeshlab.Mesh(vertex_matrix=rest,face_matrix=f))
ms.meshing_isotropic_explicit_remeshing(iterations=5,targetlen=p.pymeshlab.PureValue(.018),featuredeg=180,checksurfdist=True,maxsurfdist=p.pymeshlab.PureValue(.001))
x=ms.current_mesh().vertex_matrix().copy();ff=ms.current_mesh().face_matrix().copy()
inside=np.array(inner['positions']);faces=np.array(inner['faces']);count=len(inside)
full_faces=np.vstack((faces,ff+count));center=x.mean(axis=0)
for scale in [1,1.1,1.25,1.5,2,3,4]:
 for vertical in [1,scale]:
  y=(x-center)*[scale,vertical,scale]+center;xx=np.vstack((inside,y))
  mesh=p.ipctk.CollisionMesh(xx,p.edges(full_faces),full_faces)
  # Inner geometry includes fitted capsules: ignore their mutual overlap.
  # Count only pairs involving the outer garment using the triangle diagnostic.
  pairs=p.helpers.pairs([p.Vector(v) for v in xx],full_faces.tolist())
  outer=[(a,b) for a,b in pairs if a>=len(faces) or b>=len(faces)]
  print('SCALE',scale,vertical,'CROSSES',len(outer),'SELF',sum(a>=len(faces) and b>=len(faces) for a,b in outer),flush=True)
  if not outer:
   Path(args[0]).with_name('outer-initial.json').write_text(json.dumps({'positions':y.tolist(),'faces':ff.tolist(),'scale':[scale,vertical,scale]}));raise SystemExit(0)
