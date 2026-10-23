"""Upload consented stock thumbnails/vectors to the existing Free development project.

Never accepts query images/family originals. Credentials remain in ignored config.
The import is additive and cannot reactivate withdrawn records.
"""
import argparse,concurrent.futures,http.client,json,struct,sys,time,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))

def validate(asset):
    import re
    if not re.fullmatch(r'pexels-[0-9]+',asset['id']) or asset['species'] not in ('dog','cat') or not asset['demoOnly'] or asset['file']!=asset['id']+'.jpg':raise ValueError('Invalid stock metadata')
    if not asset['source'].startswith('https://www.pexels.com/photo/') or not re.fullmatch('[01]{144}',asset['fingerprint']) or not 0<=asset['mean']<=255:raise ValueError('Invalid stock provenance/fingerprint')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--index',type=Path,default=ROOT/'.local/TwinsServerIndex');parser.add_argument('--byte-budget',type=int,default=450_000_000);args=parser.parse_args()
    config=json.loads((ROOT/'.local/supabase-server.json').read_text());assert config['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
    catalog=json.loads((args.index/'catalog.json').read_text());assert catalog['revision']==2 and catalog['elements']==768
    assets=catalog['assets'];vectors=(args.index/'vectors.bin').read_bytes();assert len(vectors)==len(assets)*768*4
    for a in assets:validate(a)
    total=sum((args.index/'images'/a['file']).stat().st_size for a in assets)
    assert total<=args.byte_budget,'Free development stock-byte budget exceeded'
    headers={'apikey':config['secret_key'],'Authorization':'Bearer '+config['secret_key']}
    def request(path,body=None,raw=None,extra=None,method=None):
        h=dict(headers);h.update(extra or {})
        if body is not None:raw=json.dumps(body,allow_nan=False).encode();h['Content-Type']='application/json'
        for attempt in range(3):
            try:
                with urllib.request.urlopen(urllib.request.Request(config['url']+path,data=raw,headers=h,method=method),timeout=60) as response:
                    b=response.read();return json.loads(b) if b else None
            except urllib.error.HTTPError as error:
                if error.code not in (429,500,502,503,504) or attempt==2:raise RuntimeError('Server HTTP '+str(error.code)) from None
            except (OSError,urllib.error.URLError,http.client.HTTPException):
                if attempt==2:raise RuntimeError('Import connection failed') from None
            time.sleep(2**attempt)
    existing=[]
    while True:
        page=request('/rest/v1/mefrion_reference_assets?select=id,active,withdrawn_at&order=id&limit=1000&offset='+str(len(existing)))
        existing.extend(page)
        if len(page)<1000:break
    published={a['id'] for a in existing if a['active'] or a['withdrawn_at'] is not None}
    selected=[(i,a) for i,a in enumerate(assets) if a['id'] not in published]
    staged=activated=failed=0
    for offset in range(0,len(selected),100):
        batch=selected[offset:offset+100];rows=[]
        for i,a in batch:
            values=struct.unpack_from('<768f',vectors,i*768*4)
            rows.append({'id':a['id'],'species':a['species'],'file':a['file'],'credit':a['credit'],'source':a['source'],'demo_only':True,'revision':2,'embedding':str(list(values)),'fingerprint':a['fingerprint'],'mean':a['mean']})
        request('/rest/v1/mefrion_reference_assets?on_conflict=id',body=rows,extra={'Prefer':'resolution=merge-duplicates,return=minimal'});staged+=len(rows)
        def upload(pair):
            _,a=pair;data=(args.index/'images'/a['file']).read_bytes()
            if len(data)>200000 or not data.startswith(b'\xff\xd8'):raise ValueError('Invalid thumbnail')
            request('/storage/v1/object/reference-thumbnails/'+a['file'],raw=data,extra={'Content-Type':'image/jpeg','x-upsert':'true'})
            return a['id']
        ready=[]
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            futures=[pool.submit(upload,pair) for pair in batch]
            for future in concurrent.futures.as_completed(futures):
                try:ready.append(future.result())
                except (OSError,RuntimeError,ValueError):failed+=1
        activated+=request('/rest/v1/rpc/mefrion_reference_activate',body={'p_ids':ready})
        print(json.dumps({'staged':staged,'activated':activated,'failed':failed}),flush=True)
    result={'indexed':len(assets),'existing_active_or_withdrawn':len(published),'newly_activated':activated,'failed':failed,'stock_thumbnail_bytes':total,'family_originals_read':False,'query_images_uploaded':False,'new_contract':False}
    (ROOT/'docs/evidence/server-reference-import.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result),flush=True)
    if failed:raise SystemExit(1)

if __name__=='__main__':main()
