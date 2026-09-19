from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import unquote, urlsplit
import json, base64, os
ROOT=Path(__file__).parent
PUBLIC=ROOT/'public'
GAME=Path(r'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\media')
ALLOWED=set(json.loads((ROOT/'allowed-textures.json').read_text()))
PORT=8769
class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs): super().__init__(*args,directory=str(PUBLIC),**kwargs)
    def log_message(self,*args): pass
    def json(self,value,status=200):
        data=json.dumps(value,ensure_ascii=False).encode()
        self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    def do_GET(self):
        path=unquote(urlsplit(self.path).path)
        if path.startswith('/game/'):
            rel=path[6:]
            if rel not in ALLOWED: self.send_error(404);return
            data=(GAME/rel).read_bytes()
            self.send_response(200);self.send_header('Content-Type','image/png');self.send_header('Cache-Control','max-age=86400');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data);return
        if path=='/api/project':
            p=ROOT/'composition.json'
            self.json(json.loads(p.read_text(encoding='utf-8')) if p.exists() else None);return
        super().do_GET()
    def do_POST(self):
        if self.headers.get('Origin') not in (None,f'http://127.0.0.1:{PORT}',f'http://localhost:{PORT}'):
            self.send_error(403);return
        length=int(self.headers.get('Content-Length',0))
        if not 0<length<20_000_000: self.send_error(413);return
        try:
            data=json.loads(self.rfile.read(length))
            if self.path=='/api/project':
                if data.get('version')!=1 or not isinstance(data.get('layers'),list): raise ValueError('Invalid project')
                p=ROOT/'composition.json';t=ROOT/'composition.tmp';t.write_text(json.dumps(data,ensure_ascii=False),encoding='utf-8');os.replace(t,p)
                self.json({'ok':True});return
            if self.path=='/api/export':
                size=int(data['size'])
                if size not in (64,256,512,1024,2048): raise ValueError('Invalid size')
                raw=base64.b64decode(data['png'].split(',',1)[1],validate=True)
                if raw[:8]!=b'\x89PNG\r\n\x1a\n': raise ValueError('Not PNG')
                if size in (256,512) and len(raw)>1024000: raise ValueError('PNG превышает лимит Workshop: 1 024 000 байт')
                folder=PUBLIC/'exports';folder.mkdir(exist_ok=True)
                name=f'dead-pockets-{size}.png';(folder/name).write_bytes(raw)
                self.json({'url':'/exports/'+name,'bytes':len(raw),'name':name});return
            self.send_error(404)
        except Exception as e: self.json({'error':str(e)},400)
if __name__=='__main__':
    print(f'Dead Pockets Studio: http://127.0.0.1:{PORT}',flush=True)
    ThreadingHTTPServer(('127.0.0.1',PORT),Handler).serve_forever()
