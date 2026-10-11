"""Retain exact baseline sources, binary and prepared-map identities before launch."""
from pathlib import Path
import hashlib, json, subprocess, zipfile

root=Path(__file__).resolve().parents[1]
output=root/'.build';output.mkdir(exist_ok=True)
files=sorted((root/'Contents/mods/mod_studio/42.20.4/java').rglob('*.java'))
files+=sorted((root/'Contents/mods/mod_studio/common/media/lua').rglob('*.lua'))
files+=[root/'scenario.ps1',root/'scenario-profile.ps1']
hashes={}
with zipfile.ZipFile(output/'native-inputs.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for file in files:
        name=file.relative_to(root).as_posix();data=file.read_bytes()
        hashes[name]=hashlib.sha256(data).hexdigest();archive.writestr(name,data)
jar=root/'Contents/mods/mod_studio/42.20.4/media/java/client/ModStudio.jar'
data={'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
      'sourceFiles':hashes,'jarSha256':hashlib.sha256(jar.read_bytes()).hexdigest(),
      'mapFiles':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (output/'native-map').glob('*')},
      'runtimeInputs':json.loads((output/'game-packages.json').read_text(encoding='utf-8-sig'))}
(output/'native-inputs.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
print('Retained inputs:',data['commit'],data['jarSha256'],len(files),'source files')
