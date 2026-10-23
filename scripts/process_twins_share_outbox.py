"""Manual derivative worker; approved synthetic development project only.

Decode/re-encode JPEG, normalize orientation, strip metadata, resize to 1200px.
Original URLs and service keys are never returned to an iPhone or public feed.
"""
import json,urllib.request,sys
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(root))
from backend.public_media import derivative
config=json.loads((root/'.local/supabase-server.json').read_text())
assert config['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
headers={'apikey':config['secret_key'],'Authorization':'Bearer '+config['secret_key']}
def request(path,body=None,raw=None,method=None):
    current=dict(headers)
    if body is not None:raw=json.dumps(body).encode();current['Content-Type']='application/json'
    elif raw is not None:current['Content-Type']='image/jpeg';current['x-upsert']='true'
    with urllib.request.urlopen(urllib.request.Request(config['url']+path,data=raw,headers=current,method=method),timeout=40) as response:
        data=response.read();return json.loads(data) if 'json' in response.headers.get('Content-Type','') else data
jobs=request('/rest/v1/rpc/mefrion_twins_share_batch',{})
processed=failed=stopped=0
for job in jobs:
    completed=False;uploaded=[];finish_attempted=False;uncertain=False
    try:
        for media in job['media']:
            original=request('/storage/v1/object/authenticated/family-originals/'+media['source_path'])
            uploaded.append(media['path']);request('/storage/v1/object/public-derived/'+media['path'],raw=derivative(original))
        finish_attempted=True
        if request('/rest/v1/rpc/mefrion_twins_share_ready',{'p_id':job['id']}):processed+=1;completed=True
        else:stopped+=1
    except (OSError,ValueError,Image.DecompressionBombError):
        failed+=1
        if finish_attempted:
            # A lost response may have committed publication. Its idempotent
            # finish RPC resolves that before any derivative is removed.
            try:completed=bool(request('/rest/v1/rpc/mefrion_twins_share_ready',{'p_id':job['id']}))
            except (OSError,ValueError):uncertain=True
    finally:
        # Withdrawal can race with image processing after the ordinary deletion
        # worker has already run. Remove this worker's late writes on failure.
        if not completed and not uncertain and uploaded:
            try:request('/storage/v1/object/public-derived',{'prefixes':uploaded},method='DELETE')
            except (OSError,ValueError):failed+=1
result={'scope':'synthetic development only','processed':processed,'stopped':stopped,'failed':failed,'automatic_worker':False,'metadata_stripped':True,'max_dimension':1200}
(root/'docs/evidence/supabase-twins-share-worker.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if failed:raise SystemExit(1)
