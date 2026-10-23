"""Owned in-memory loopback fixture measurements; no cloud mutation or content logs."""
import json,statistics,threading,time,urllib.request,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
from backend.server import make_server

def main():
 server=make_server(0);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 elapsed=[];sizes=[]
 try:
  base="http://127.0.0.1:"+str(server.server_port)
  for _ in range(5):urllib.request.urlopen(base+"/v1/demo/feed",timeout=5).close()
  for _ in range(100):
   start=time.perf_counter()
   with urllib.request.urlopen(base+"/v1/demo/feed",timeout=5) as response:
    data=response.read();assert response.status==200
    assert response.headers.get("Cache-Control")=="no-store"
   elapsed.append((time.perf_counter()-start)*1000);sizes.append(len(data))
 finally:server.shutdown();thread.join(timeout=5);server.store.db.close();server.server_close()
 values=sorted(elapsed)
 report={"scope":"100 sequential loopback requests, owned synthetic fixture feed, not cloud load or real-user latency","date":"2026-10-10","requests":len(elapsed),"median_ms":statistics.median(values),"p95_ms":values[94],"max_ms":max(values),"response_bytes":max(sizes),"body_logged":False,"cloud_cost_measured":False}
 output=Path(__file__).resolve().parent.parent/"docs/evidence/p2-loopback-performance.json";output.write_text(json.dumps(report,indent=2));print(json.dumps(report))
if __name__=="__main__":main()
