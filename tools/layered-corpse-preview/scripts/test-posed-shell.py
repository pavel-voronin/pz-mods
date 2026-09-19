"""Validate the generated physical surfaces, not the source render asset."""
import sys,json,math
from pathlib import Path
from importlib import import_module
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
pairs=import_module('blender-cloth-prepare').pairs
args=sys.argv[sys.argv.index('--')+1:]
for filename in args:
    data=json.loads(Path(filename).read_text());assert data['material']['arealDensityKgM2']>0
    for item in data['items']:
        assert item['positions']==item['restPositions'],'Old bind-pose metric leaked into physics'
        bindings=item.get('renderBindings')
        assert len(item['renderStartPositions'])==len(bindings or item['positions'])
        assert all(math.isfinite(v) for p in item['positions'] for v in p)
        assert not pairs([Vector(p) for p in item['positions']],item['faces'])
        assert all(len(f)==3 and len(set(f))==3 for f in item['faces'])
        assert all(math.isfinite(v) for f in item['faceUvs'] for uv in f for v in uv)
        if bindings:
            for binding in bindings:
                assert len(binding['ids'])==len(binding['weights'])==3
                assert all(0<=i<len(item['positions']) for i in binding['ids'])
                assert all(math.isfinite(w) for w in binding['weights'])
                assert abs(sum(binding['weights'])-1)<1e-6
            anchors=[sum((Vector(item['positions'][i])*w for i,w in zip(b['ids'],b['weights'])),Vector()) for b in bindings]
        else:anchors=[Vector(p) for p in item['positions']]
        shift=max((p-Vector(q)).length for p,q in zip(anchors,item['renderStartPositions']))
        separation=Vector(item.get('releaseSeparation',[0,0,0])).length
        # Older diagnostic prepared files record the layer bound only in the report.
        separation=max(separation,max((r['maxShift'] for r in data['report'].get('layerRepairs',[]) if r['releaseTime']==item['releaseTime']),default=0))
        assert shift<=.030001+separation+(.020001 if bindings else 0),'Unbounded repair'
    area=sum((Vector(i['positions'][f[1]])-Vector(i['positions'][f[0]])).cross(Vector(i['positions'][f[2]])-Vector(i['positions'][f[0]])).length*.5 for i in data['items'] for f in i['faces'])
    mass=area*data['material']['arealDensityKgM2'];count=sum(len(i['positions']) for i in data['items'])
    print('PASS posed shell',filename,'particles',count,'area',area,'total mass kg',mass,flush=True)
    if 'first_mass' in globals() and not data['report'].get('isotropicRemesh'):assert abs(mass-first_mass)<1e-6,'Refinement changed total material mass'
    first_mass=mass
