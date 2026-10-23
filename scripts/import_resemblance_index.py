"""Add versioned descriptors to existing stock references; never changes active/withdrawn flags."""
import json,struct,time,urllib.request,urllib.error,http.client
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];INDEX=ROOT/'.local/resemblance'
def main():
 config=json.loads((ROOT/'.local/supabase-server.json').read_text());assert config['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
 catalog=json.loads((INDEX/'native-catalog.json').read_text());assert catalog['algorithm']=='dinov2-small-subject-v1' and catalog['elements']==384
 rows=catalog['assets'];raw=(INDEX/'native-vectors.bin').read_bytes();assert len(raw)==len(rows)*384*4
 headers={'apikey':config['secret_key'],'Authorization':'Bearer '+config['secret_key'],'Content-Type':'application/json','Prefer':'resolution=merge-duplicates,return=minimal'}
 for offset in range(0,len(rows),100):
  payload=[]
  for i,a in enumerate(rows[offset:offset+100],offset):
   vector=struct.unpack_from('<384f',raw,i*384*4)
   assert len(a['color'])==64 and a['kind'] in ('head','animal')
   payload.append({'id':a['id'],'species':a['species'],'algorithm':catalog['algorithm'],'embedding':str(list(vector)),'color':str(a['color']),'crop_kind':a['kind']})
  data=json.dumps(payload,allow_nan=False).encode()
  for attempt in range(4):
   try:
    req=urllib.request.Request(config['url']+'/rest/v1/mefrion_reference_resemblance?on_conflict=id',data=data,headers=headers)
    with urllib.request.urlopen(req,timeout=60) as response:assert response.status in (200,201,204)
    break
   except urllib.error.HTTPError as e:
    if e.code not in (429,500,502,503,504) or attempt==3:raise RuntimeError('Import HTTP '+str(e.code)) from None
   except (OSError,http.client.HTTPException):
    if attempt==3:raise RuntimeError('Import connection failure') from None
   time.sleep(2**attempt)
  print('imported',min(offset+100,len(rows)),flush=True)
 (ROOT/'docs/evidence/resemblance-import.json').write_text(json.dumps({'algorithm':catalog['algorithm'],'descriptors':len(rows),'vector_bytes':len(raw),'active_flags_changed':False,'original_photos_uploaded':False},indent=2)+'\n')
if __name__=='__main__':main()
