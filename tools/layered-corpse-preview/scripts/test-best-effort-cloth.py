"""Run with Blender: unresolved contacts warn/continue, strict diagnostics still fail."""
import sys
from pathlib import Path
from importlib import import_module
sys.path.insert(0,str(Path(__file__).parent))
clearance=import_module('cloth-release-clearance')
crossing={'releaseTime':0,'positions':[[-1,-1,0],[1,-1,0],[0,1,0],[0,0,-1],[0,0,1],[0,.8,0]],'faces':[[0,1,2],[3,4,5]]}
try:clearance.ensure_release_clearance([crossing])
except RuntimeError:pass
else:raise AssertionError('Strict diagnostic must still detect intersections')
report=clearance.ensure_release_clearance([crossing],allow_intersections=True)
assert report[0]['after']['crossings']>0
assert report[0]['fallback']=='unresolved-self-contact'
original=[p[:] for p in crossing['positions']]
other={'releaseTime':0,'positions':[[4,0,0],[5,0,0],[4,1,0]],'faces':[[0,1,2]]}
report=clearance.ensure_release_clearance([crossing,other],limit=.002,allow_intersections=True)
assert report[0]['fallback']=='keep-individual-repair'
assert crossing['positions']==original,'Failed search must not shift the user scene'
print('PASS best-effort cloth: self/contact failures continue, reports retained, no failed-search displacement')
