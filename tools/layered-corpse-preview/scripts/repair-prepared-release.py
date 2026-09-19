"""Revalidate an existing remesh without running MeshLab a second time."""
import sys,json
from pathlib import Path
from importlib import import_module
sys.path.insert(0,str(Path(__file__).parent))
path=Path(sys.argv[sys.argv.index('--')+1]);data=json.loads(path.read_text())
report=import_module('cloth-release-clearance').ensure_release_clearance(data['items'])
data['report']['postRemeshLayerRepairs']=report
path.write_text(json.dumps(data,separators=(',',':')))
print(json.dumps(report),flush=True)
