import json,sys
from pathlib import Path
import numpy as np
directory=Path(sys.argv[1]);data=json.loads((directory/'scene-prepared.json').read_text())
frames=np.load(directory/'native-physical.npy');offset=0
for item in data['items']:
    n=len(item['positions']);faces=np.array(item['faces']);p=frames[0,offset:offset+n];q=frames[-1,offset:offset+n]
    def area(p):return np.linalg.norm(np.cross(p[faces[:,1]]-p[faces[:,0]],p[faces[:,2]]-p[faces[:,0]]),axis=1)/2
    ratio=area(q)/area(p)
    print(json.dumps({'item':item['index'],'triangles':len(faces),'areaRatioP01':float(np.quantile(ratio,.01)),
      'collapsedBelow10Percent':int((ratio<.1).sum()),'collapsedBelow1Percent':int((ratio<.01).sum()),'medianAreaRatio':float(np.median(ratio))}))
    offset+=n
