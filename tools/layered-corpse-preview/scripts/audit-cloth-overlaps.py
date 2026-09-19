import sys,json
from pathlib import Path
from importlib import import_module
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
pairs=import_module('blender-cloth-prepare').pairs
d=json.loads(Path(sys.argv[sys.argv.index('--')+1]).read_text())
p=[];f=[];owners=[]
for i,item in enumerate(d['items']):
 start=len(p);p.extend(Vector(v) for v in item['positions'])
 f.extend(tuple(v+start for v in face) for face in item['faces']);owners.extend([i]*len(item['faces']))
counts={}
for a,b in pairs(p,f):
 key=str(tuple(sorted((owners[a],owners[b]))));counts[key]=counts.get(key,0)+1
print('INITIAL_CROSSINGS',json.dumps(counts),flush=True)
