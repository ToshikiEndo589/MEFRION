"""Bounded dispatcher for approved seed schedules in the approved dev project."""
import json,urllib.request
from pathlib import Path
root=Path(__file__).resolve().parent.parent
c=json.loads((root/'.local/supabase-server.json').read_text());assert c['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
h={'apikey':c['secret_key'],'Authorization':'Bearer '+c['secret_key'],'Content-Type':'application/json'}
with urllib.request.urlopen(urllib.request.Request(c['url']+'/rest/v1/rpc/mefrion_seed_dispatch',data=b'{}',headers=h),timeout=40) as r:count=json.load(r)
print(json.dumps({'scheduled_jobs_dispatched':count,'scope':'approved development project'}))
