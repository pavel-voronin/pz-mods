from pathlib import Path
import re, json, tempfile, xml.etree.ElementTree as ET, urllib.request
ROOT=Path(__file__).parent
import assimp_py as ai
import numpy as np
GAME=Path(r'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
MEDIA=GAME/'media'
PUBLIC=ROOT/'public'
(PUBLIC/'geometry').mkdir(parents=True,exist_ok=True)
(PUBLIC/'vendor').mkdir(exist_ok=True)

def load(name):
    path=MEDIA/'models_X'/name
    if path.suffix.lower()=='.x':
        raw=path.read_text()
        raw=re.sub(r'SkinWeights\s*\{\s*"[^"]+";\s*0;.*?\}', '', raw, flags=re.S)
        with tempfile.TemporaryDirectory(prefix='dead-pockets-model-') as temporary:
            path=Path(temporary)/path.name
            path.write_text(raw)
            return ai.import_file(str(path),ai.Process_Triangulate|ai.Process_GenSmoothNormals)
    return ai.import_file(str(path),ai.Process_Triangulate|ai.Process_GenSmoothNormals)

body_scenes={s:load(f'Skinned/{s}Body.x') for s in ('Male','Female')}
targets={}
for sex,scene in body_scenes.items():
    # Put every garment onto the same game skeleton's bind pose, then lower
    # both arms. The original meshes, UVs and vertex weights stay unchanged.
    bones={b.name:np.linalg.inv(np.array(b.offset_matrix)) for b in scene.meshes[0].bones}
    for side in ('L','R'):
        name=f'Bip01_{side}_UpperArm'
        pivot=bones[name][:3,3]
        angle=np.deg2rad(-66 if pivot[0]>0 else 66)
        c,s=np.cos(angle),np.sin(angle)
        rot=np.eye(4);rot[:2,:2]=[[c,-s],[s,c]]
        translate=np.eye(4);translate[:3,3]=pivot
        transform=translate@rot@np.linalg.inv(translate)
        for key in bones:
            if key.startswith(f'Bip01_{side}_') and any(x in key for x in ('UpperArm','Forearm','Hand','Finger')):
                bones[key]=transform@bones[key]
    targets[sex]=bones

geometry_cache={}
def geometry(name,sex=None):
    key=(name,sex)
    if key in geometry_cache: return geometry_cache[key]
    scene=body_scenes[sex] if sex and name==f'Skinned/{sex}Body.x' else load(name)
    meshes=[]
    def visit(node,parent):
        world=parent@np.array(node.transformation)
        for idx in node.mesh_indices:
            m=scene.meshes[idx]
            v=np.array(m.vertices).reshape(-1,3).astype(float)
            normal=np.array(m.normals).reshape(-1,3).astype(float)
            vh=np.column_stack((v,np.ones(len(v))))
            if sex and m.bones:
                posed=np.zeros((len(v),4));posed_normals=np.zeros_like(normal);weights=np.zeros(len(v))
                for b in m.bones:
                    joint=targets[sex].get(b.name,np.linalg.inv(np.array(b.offset_matrix)))
                    ids=np.array(b.weight_vertex_ids,dtype=int)
                    w=np.array(b.weights)
                    transform=joint@np.array(b.offset_matrix)
                    transformed=vh[ids]@transform.T
                    posed_normals[ids]+=(normal[ids]@np.linalg.inv(transform[:3,:3]))*w[:,None]
                    posed[ids]+=transformed*w[:,None];weights[ids]+=w
                good=weights>0
                v[good]=posed[good,:3]/weights[good,None]
                normal[good]=posed_normals[good]/np.maximum(np.linalg.norm(posed_normals[good],axis=1)[:,None],1e-8)
            else:
                v=(vh@world.T)[:,:3]
                normal=normal@np.linalg.inv(world[:3,:3])
                normal/=np.maximum(np.linalg.norm(normal,axis=1)[:,None],1e-8)
            uv=np.array(m.texcoords[0]).reshape(len(v),-1)[:,:2] if m.texcoords else np.zeros((len(v),2))
            meshes.append({'positions':np.round(v,7).flatten().tolist(),'normals':np.round(normal,7).flatten().tolist(),'uv':np.round(uv,7).flatten().tolist(),'indices':list(m.indices)})
        for ch in node.children: visit(ch,world)
    visit(scene.root_node,np.eye(4))
    fname=re.sub(r'[^a-zA-Z0-9]+','_',name)+'_'+str(sex)+'.json'
    (PUBLIC/'geometry'/fname).write_text(json.dumps({'meshes':meshes},separators=(',',':')))
    geometry_cache[key]='geometry/'+fname
    return geometry_cache[key]

textures={p.relative_to(MEDIA).as_posix().lower():p.relative_to(MEDIA).as_posix() for p in (MEDIA/'textures').rglob('*.png')}
allowed=set()
def texture(name):
    key=('textures/'+name.replace('\\','/').removeprefix('media/textures/').removesuffix('.png')+'.png').lower()
    if key not in textures: raise ValueError('Missing texture '+key)
    p=textures[key];allowed.add(p)
    return '/game/'+p

catalog=[]
def add(id,label,kind,models,tex,**extra):
    catalog.append(dict(id=id,label=label,kind=kind,models=models,texture=texture(tex),**extra))

for n in (1,2,3,4):
    for decay in ('','_level2'):
        add(f'body_{n}{decay}',f'Зомби {n}'+(' · разложение' if decay else ''),'body',
            {s:geometry(f'Skinned/{s}Body.x',s) for s in targets},f'Body/M_ZedBody0{n}{decay}',
            femaleTexture=texture(f'Body/F_ZedBody0{n}{decay}'))

clothing=[
 ('Shirt_Denim','Джинсовая рубашка','shirt'),('Shirt_Lumberjack','Клетчатая рубашка','shirt'),
 ('Shirt_HawaiianRed','Гавайская рубашка','shirt'),('Shirt_BowlingGreen','Рубашка для боулинга','shirt'),
 ('Shirt_Workman','Рабочая рубашка','shirt'),('Shirt_OliveDrab','Оливковая рубашка','shirt'),
 ('Jacket_Leather','Кожаная куртка','jacket'),('Jacket_WhiteTINT','Куртка','jacket'),
 ('JacketLong_Random','Длинная куртка','jacket'),('Jacket_Shellsuit_Black','Спортивная куртка','jacket'),
 ('Jacket_Suit_Black','Пиджак','jacket'),('Vest_Hunting','Охотничий жилет','jacket')]
for xmlname,label,kind in clothing:
    path=MEDIA/'clothing/clothingItems'/(xmlname+'.xml')
    if not path.exists():
        print('skip xml',xmlname);continue
    root=ET.parse(path).getroot()
    choices=[e.text for e in root.findall('textureChoices')]+[e.text for e in root.findall('m_BaseTextures')]
    if not choices: print('skip no texture',xmlname);continue
    models={}
    for sex in targets:
        model=(root.findtext('m_'+sex+'Model') or '').replace('\\','/').removeprefix('media/models_X/')
        if model and not model.lower().endswith(('.x','.fbx')): model+='.x'
        models[sex]=geometry(model if model else f'Skinned/{sex}Body.x',sex)
    for i,tex in enumerate(choices[:6]):
        try: add(xmlname+'_'+str(i),label+(f' {i+1}' if len(choices)>1 else ''),kind,models,tex,overlay=not bool(root.findtext('m_MaleModel')))
        except ValueError as e: print(e)

scripts=(MEDIA/'scripts/generated/models_items.txt').read_text()
props=[('Wallet','Кошелёк · чёрный'),('Wallet2','Кошелёк · фиолетовый'),('Wallet3','Кошелёк · светлый'),('Wallet4','Кошелёк · рыжий'),
 ('LighterDisposable','Зажигалка'),('Matches','Спички'),('CigarettePack_Ground','Сигареты'),('Money','Купюра'),('MoneyBundle','Пачка денег'),
 ('CreditCard','Банковская карта'),('KeyRing_Ground','Ключи'),('KnifePocketClosed','Карманный нож')]
for name,label in props:
    match=re.search(r'\bmodel\s+'+re.escape(name)+r'\s*\{([^}]+)',scripts)
    if not match: print('skip item',name);continue
    fields=dict(re.findall(r'(\w+)\s*=\s*([^,\n]+)',match[1]))
    mesh=fields.get('mesh','').strip();tex=fields.get('texture','').strip()
    path=next((mesh+ext for ext in ('.fbx','.x') if (MEDIA/'models_X'/(mesh+ext)).exists()),None)
    if path and tex:
        try: add(name,label,'item',{'any':geometry(path)},tex)
        except ValueError as e: print(e)

(PUBLIC/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False),encoding='utf-8')
(ROOT/'allowed-textures.json').write_text(json.dumps(sorted(allowed)))
for name in ('three.module.js','three.core.js'):
    path=PUBLIC/'vendor'/name
    if not path.exists():
        urllib.request.urlretrieve('https://unpkg.com/three@0.180.0/build/'+name,path)
print('Catalog:',len(catalog),'assets;',len(geometry_cache),'meshes;',len(allowed),'textures')
