import sys,json
from pathlib import Path
from importlib import import_module
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent));pairs=import_module('blender-cloth-prepare').pairs
d=json.loads(Path(sys.argv[sys.argv.index('--')+1]).read_text())
a,b=d['items'][2:4]
pa=[Vector(p) for p in a['positions']];pb=[Vector(p) for p in b['positions']]
f=a['faces']+[[v+len(pa) for v in face] for face in b['faces']]
direction=(sum(pb,Vector())/len(pb)-sum(pa,Vector())/len(pa));direction.y=0;direction.normalize()
for axis in [direction,Vector((0,1,0)),Vector((direction.z,0,-direction.x))]:
 for distance in [.01,.02,.04,.06,.08,.1,.15]:
  points=[p-axis*distance*.5 for p in pa]+[p+axis*distance*.5 for p in pb]
  print('SEPARATION',list(axis),distance,len(pairs(points,f)),flush=True)
