"""Public-only share origin. No administration, sessions, originals or demo routes.

Use behind the selected HTTPS gateway. Host/domain selection remains pending.
Only the development public projection and derived-image API are contacted.
"""
import argparse,urllib.error
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlsplit
from backend import cloud_shares

CSS=(cloud_shares.ROOT/'web/shared.css').read_bytes()
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def send(self,status,data,kind):
  self.send_response(status);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store, max-age=0');self.send_header('X-Content-Type-Options','nosniff');self.send_header('Referrer-Policy','no-referrer');self.send_header('Content-Security-Policy',"default-src 'none'; img-src 'self'; style-src 'self' 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");self.end_headers();self.wfile.write(data)
 def do_GET(self):
  path=urlsplit(self.path).path;parts=path.strip('/').split('/')
  try:
   if path=='/shared.css':return self.send(200,CSS,'text/css; charset=utf-8')
   if len(parts)==2 and parts[0]=='cloud-shared' and cloud_shares.UUID.fullmatch(parts[1]):
    status,page=cloud_shares.page(parts[1]);return self.send(status,page.encode(),'text/html; charset=utf-8')
   if len(parts)==4 and parts[0]=='cloud-shared' and parts[2]=='image' and cloud_shares.UUID.fullmatch(parts[1]) and cloud_shares.UUID.fullmatch(parts[3]):
    image=cloud_shares.image(parts[1],parts[3]);return self.send(200 if image else 404,image or b'Ended','image/jpeg' if image else 'text/plain')
   self.send(404,b'Not found','text/plain')
  except (OSError,ValueError,KeyError,urllib.error.URLError):self.send(503,'共有状態を確認できません。再試行してください。'.encode(),'text/plain; charset=utf-8')
 def do_POST(self):self.send(405,b'Method not allowed','text/plain')
 do_PUT=do_DELETE=do_PATCH=do_OPTIONS=do_POST

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=9792);args=parser.parse_args();ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
