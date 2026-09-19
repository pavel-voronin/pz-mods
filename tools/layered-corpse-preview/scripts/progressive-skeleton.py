"""Preparation-only joint chain. Interpolate LOCAL transforms, never skin matrices.

This hierarchy follows the app's torso/limb chains, with the named clavicle,
toe and accessory joints inserted. It does not modify the runtime skeleton.
Both supplied global endpoint poses are reproduced exactly.
"""
import numpy as np
from scipy.spatial.transform import Rotation, Slerp

def parent(name):
    fixed={'Bip01_Pelvis':None,'Bip01_Spine':'Bip01_Pelvis','Bip01_Spine1':'Bip01_Spine',
           'Bip01_Neck':'Bip01_Spine1','Bip01_Head':'Bip01_Neck','Bip01_BackPack':'Bip01_Spine1',
           'Bip01_DressBack':'Bip01_Pelvis','Bip01_DressBack02':'Bip01_DressBack',
           'Bip01_DressFront':'Bip01_Pelvis','Bip01_DressFront02':'Bip01_DressFront'}
    if name in fixed:return fixed[name]
    for side in ['L','R']:
        prefix='Bip01_'+side+'_'
        if name.startswith(prefix):
            suffix=name[len(prefix):]
            chain={'Clavicle':'Bip01_Spine1','UpperArm':prefix+'Clavicle','Forearm':prefix+'UpperArm',
                   'Hand':prefix+'Forearm','Finger0':prefix+'Hand','Finger1':prefix+'Hand',
                   'Thigh':'Bip01_Pelvis','Calf':prefix+'Thigh','Foot':prefix+'Calf','Toe0':prefix+'Foot'}
            if suffix in chain:return chain[suffix]
    raise ValueError('Unknown preparation joint: '+name)

class PosePath:
    def __init__(self,parts):
        starts={};ends={}
        for part in parts:
            for name,a,b in zip(part['boneNames'],part['startGlobals'],part['endGlobals']):
                starts[name]=np.array(a).reshape(4,4).T;ends[name]=np.array(b).reshape(4,4).T
        self.parents={n:parent(n) for n in starts};self.local={};self.cache={}
        for n,p in self.parents.items():
            if p is not None and p not in starts:raise ValueError('Missing preparation parent '+p)
            a=np.linalg.solve(starts[p],starts[n]) if p else starts[n]
            b=np.linalg.solve(ends[p],ends[n]) if p else ends[n]
            rotations=[];scales=[]
            for m in [a,b]:
                u,_,v=np.linalg.svd(m[:3,:3]);r=u@v
                if np.linalg.det(r)<0:raise ValueError('Reflected preparation joint '+n)
                rotations.append(r);scales.append(r.T@m[:3,:3])
            self.local[n]=(Slerp([0,1],Rotation.from_matrix(rotations)),*scales,a[:3,3],b[:3,3])
        for t,want in [(0,starts),(1,ends)]:
            got=self.at(t)
            assert max(np.max(np.abs(got[n]-want[n])) for n in want)<1e-8

    def at(self,t):
        if t in self.cache:return self.cache[t]
        result={}
        def visit(n):
            if n in result:return result[n]
            r,s0,s1,p0,p1=self.local[n];m=np.eye(4)
            m[:3,:3]=r([t]).as_matrix()[0]@((1-t)*s0+t*s1);m[:3,3]=(1-t)*p0+t*p1
            p=self.parents[n];result[n]=visit(p)@m if p else m
            return result[n]
        for n in self.local:visit(n)
        self.cache[t]=result
        return result
