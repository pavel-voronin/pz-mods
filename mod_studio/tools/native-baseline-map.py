"""Prepare static native-map textures before measurements (300 -> 256 cell conversion)."""
from pathlib import Path
import argparse, re, xml.etree.ElementTree as ET, json, hashlib
from PIL import Image, ImageDraw

p=argparse.ArgumentParser()
p.add_argument('--media',type=Path,default=Path('C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/media'))
p.add_argument('--output',type=Path,default=Path('.build/native-map'))
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
style=(a.media/'lua/client/ISUI/Maps/ISMapDefinitions.lua').read_text('utf-8-sig')
layers=[]
for block in re.split(r'styleAPI:newPolygonLayer\(',style)[1:]:
    f=re.search(r':setFilter\("([^"]+)",\s*"([^"]+)"\)',block)
    c=re.search(r':addFill\(MAXZ,\s*(\d+),\s*(\d+),\s*(\d+),\s*255\)',block)
    if f and c:layers.append((f.groups(),tuple(map(int,c.groups()))))
features=[]
for name in ('worldmap-forest.xml','worldmap.xml'):
    for _,cell in ET.iterparse(a.media/'maps/Muldraugh, KY'/name,events=('end',)):
        if cell.tag!='cell':continue
        cx,cy=int(cell.attrib['x']),int(cell.attrib['y'])
        for feature in cell.findall('feature'):
            props={q.attrib['name']:q.attrib['value'] for q in feature.findall('./properties/property')}
            found=[(i,c) for i,((k,v),c) in enumerate(layers) if k in props and (props[k]==v or v=='*')]
            if not found:continue
            rings=[[( (cx*300+float(q.attrib['x']))*256/300,(cy*300+float(q.attrib['y']))*256/300) for q in coords.findall('point')] for coords in feature.findall('./geometry[@type="Polygon"]/coordinates')]
            for ring in rings:
                if len(ring)>2:features.append((*found[-1],ring))
        cell.clear()
features.sort(key=lambda f:f[0])
regions={'world':(0,0,25600,2048),'city':(9216,0,6144,4096),'rural':(6144,4096,6144,4096)}
for name,(x,y,span,pixels) in regions.items():
    im=Image.new('RGB',(pixels,pixels),(219,215,192));draw=ImageDraw.Draw(im)
    for _,color,ring in features:
        if max(q[0] for q in ring)<x or min(q[0] for q in ring)>x+span or max(q[1] for q in ring)<y or min(q[1] for q in ring)>y+span:continue
        draw.polygon([((px-x)*pixels/span,(py-y)*pixels/span) for px,py in ring],fill=color)
    im.save(a.output/(name+'.png'))
(a.output/'map.json').write_text(json.dumps({'regions':regions,'coordinateScale':256/300,'features':len(features)},indent=2))
print(a.output.resolve())
