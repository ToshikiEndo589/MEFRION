"""Disposable, in-memory loopback server for Simulator interaction tests."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
from backend.server import make_server
server=make_server(8766)
print('MEFRION disposable UI fixtures: 127.0.0.1:8766',flush=True)
try: server.serve_forever()
finally: server.shutdown();server.store.db.close();server.server_close()
