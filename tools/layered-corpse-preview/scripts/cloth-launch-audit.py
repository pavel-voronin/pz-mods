"""Run the production launch on one valid garment, without body/other garments.
Writes deliberately incompatible diagnostic caches, never an app-ready replacement.
"""
import sys,json,hashlib,runpy
from mathutils import Vector
from pathlib import Path
args=sys.argv[sys.argv.index('--')+1:]
path=Path(args[0]).resolve();out=Path(args[1]).resolve();out.mkdir(parents=True,exist_ok=True)
data=json.loads(path.read_text());source=json.loads((path.parent/data['sourceFile']).read_text())
index=int(args[2]);assert data['report']['items'][index]['collisionReady']
if data.get('material'):
    area=sum((Vector(i['positions'][f[1]])-Vector(i['positions'][f[0]])).cross(Vector(i['positions'][f[2]])-Vector(i['positions'][f[0]])).length*.5 for i in data['items'] for f in i['faces'])
    data['diagnosticPointMass']=area*data['material']['arealDensityKgM2']*data['material']['solverMassScale']/sum(len(i['positions']) for i in data['items'])
data['items']=[data['items'][index]];data['report']['items']=[data['report']['items'][index]]
data['items'][0]['index']=0
source['items']=[source['items'][index]];source['garments']=[source['garments'][index]]
source['velocities']=[source['velocities'][index]]
source['capsules']=[];source['body']=[];source['sceneKey']='diagnostic-launch-not-for-import'
data['duration']=source['duration']=6
if '--duration' in args:data['duration']=source['duration']=float(args[args.index('--duration')+1])
source_path=out/'scene-source.json';source_path.write_text(json.dumps(source))
data['sourceFile']=source_path.name;data['sourceSha256']=hashlib.sha256(source_path.read_bytes()).hexdigest()
prepared=out/'scene-prepared.json';prepared.write_text(json.dumps(data))
sys.argv=[sys.argv[0],'--',str(prepared)]+[a for a in args if a.startswith('--diagnostic-') or a.startswith('--settle-') or a in ['--surface-fabric','--drag-aware-launch']]
runpy.run_path(str(Path(__file__).with_name('blender-scene-bake.py')),run_name='__main__')
