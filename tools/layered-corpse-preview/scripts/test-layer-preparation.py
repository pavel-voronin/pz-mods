"""Prepared release layers must be nonintersecting, without deforming either island."""
import sys,json
from pathlib import Path
from importlib import import_module
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent));pairs=import_module('blender-cloth-prepare').pairs
args=sys.argv[sys.argv.index('--')+1:]
d=json.loads(Path(args[0]).read_text());before=json.loads(Path(args[1]).read_text()) if len(args)>1 else None
layers={}
for i,item in enumerate(d['items']):
    assert item['positions']==item['restPositions']
    assert not pairs([Vector(p) for p in item['positions']],item['faces'])
    layers.setdefault(item['releaseTime'],[]).append(i)
    if before:
        old=before['items'][i]
        assert item['faces']==old['faces'] and item['faceUvs']==old['faceUvs']
        assert item['renderStartPositions']==old['renderStartPositions']
        shifts=[Vector(p)-Vector(q) for p,q in zip(item['positions'],old['positions'])]
        assert max((p-shifts[0]).length for p in shifts)<2e-6,'Repair deformed a garment'
for ids in layers.values():
    p=[];f=[]
    for i in ids:
        start=len(p);item=d['items'][i];p.extend(Vector(v) for v in item['positions'])
        f.extend([v+start for v in face] for face in item['faces'])
    assert not pairs(p,f),('Release layer overlaps',ids)
print('PASS: all simultaneous release layers disjoint; rest equals prepared pose')
if before:print('PASS: source texture, topology and shown pose preserved; repair is rigid per island')
