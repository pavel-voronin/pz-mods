import sys,json,copy
from pathlib import Path
from mathutils import Vector
from importlib import import_module
sys.path.insert(0,str(Path(__file__).parent))
repair=import_module('cloth-release-clearance').ensure_release_clearance
d=json.loads(Path(sys.argv[sys.argv.index('--')+1]).read_text());before=copy.deepcopy(d['items'])
report=repair(d['items']);groups={}
for old,new in zip(before,d['items']):
    shifts=[Vector(a)-Vector(b) for a,b in zip(new['positions'],old['positions'])]
    assert max((v-shifts[0]).length for v in shifts)<2e-6,'Non-rigid clearance repair'
    assert shifts[0].length<=.050001
    groups.setdefault(new['releaseTime'],[]).append(shifts[0])
    for key in old:
        if key not in ['positions','restPositions','releaseSeparation']:assert old[key]==new[key],key
    assert new['positions']==new['restPositions']
for shifts in groups.values():assert sum(shifts,Vector()).length<2e-6,'Moved common layer center'
first=copy.deepcopy(d['items']);second=repair(d['items'])
assert all(r['maxShift']==0 for r in second),'Repair is not idempotent'
assert d['items']==first
print('PASS: post-remesh release clearance; rigid bounded offsets; unchanged layer center, launch and UVs; idempotent')
print(json.dumps(report))
