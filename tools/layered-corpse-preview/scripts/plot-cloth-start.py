import json,sys
from PIL import Image,ImageDraw
d=json.load(open(sys.argv[1]));x=d['positions'];b=d['body']
image=Image.new('RGB',(1200,700),'white');draw=ImageDraw.Draw(image)
for column,i in enumerate([0,2]):
    def point(v):return (column*600+300+v[i]*530,650-v[1]*600)
    for v in b:
        px,py=point(v);draw.ellipse((px-1,py-1,px+1,py+1),fill='#cccccc')
    for rank,(a,z) in enumerate(d['ranges']):
        color=['blue','orange','red','green'][rank%4]
        for v in x[a:z]:
            px,py=point(v);draw.ellipse((px-1,py-1,px+1,py+1),fill=color)
image.save(sys.argv[2])
