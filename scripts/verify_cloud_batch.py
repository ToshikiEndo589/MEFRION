"""Thirty synthetic images only, in the explicitly approved test project.

Exercise a lost-upload-response retry before finish_photo. Never log keys,
tokens, provider identities, paths, or server response bodies.
"""
import io,json,urllib.request,urllib.error
from pathlib import Path
from uuid import uuid4
from PIL import Image

root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text())
assert public['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
identity=next(x for x in json.loads((root/'.local/supabase-test-identities.json').read_text()) if x['role']=='owner')
pet=json.loads((root/'.local/supabase-test-sessions.json').read_text())['pet_id']
token=None;checks=[];photos=[]
def call(path,body=None,raw=None):
    headers={'apikey':public['anon_key']}
    if token:headers['Authorization']='Bearer '+token
    if body is not None:raw=json.dumps(body).encode();headers['Content-Type']='application/json'
    elif raw is not None:headers['Content-Type']='image/jpeg'
    request=urllib.request.Request(public['url']+path,data=raw,headers=headers)
    try:
        with urllib.request.urlopen(request,timeout=30) as response:
            data=response.read();return response.status,json.loads(data) if 'json' in response.headers.get('Content-Type','') else data
    except urllib.error.HTTPError as error:
        try:data=json.loads(error.read())
        except ValueError:data={}
        return error.code,data
def checked(label,result,statuses=(200,),predicate=lambda value:True):
    status,data=result;passed=status in statuses and predicate(data)
    checks.append({'check':label,'passed':passed,'status':status})
    if not passed:raise RuntimeError(label+' failed')
    return data
def rpc(name,body):return call('/rest/v1/rpc/mefrion_'+name,body)
try:
    token=checked('synthetic-owner-login',call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}))['access_token']
    stream=io.BytesIO();Image.new('RGB',(128,128),(220,180,170)).save(stream,format='JPEG');jpeg=stream.getvalue()
    for index in range(30):
        body={'p_pet':pet,'p_request_key':str(uuid4()),'p_captured':'2020','p_title':''}
        photo=checked('reserve-'+str(index+1),rpc('begin_photo',body));photos.append(photo['id'])
        path='/storage/v1/object/family-originals/'+photo['path']
        checked('upload-'+str(index+1),call(path,raw=jpeg),(200,201))
        if index==0:
            retry=checked('same-reservation-after-lost-response',rpc('begin_photo',body),predicate=lambda value:value['id']==photo['id'] and value['state']=='pending')
            duplicate=call(path,raw=jpeg)
            checked('existing-object-retry-response',duplicate,(400,409),lambda value:value.get('error')=='Duplicate' or value.get('statusCode') in ('409',409))
            duplicate_status=duplicate[0]
        checked('finish-'+str(index+1),rpc('finish_photo',{'p_photo':photo['id']}))
        if index==0:checked('completed-reservation-retry',rpc('begin_photo',body),predicate=lambda value:value['id']==photo['id'] and value['state']=='ready')
    checked('all-thirty-present',rpc('album',{'p_pet':pet}),predicate=lambda value:set(photos).issubset({row['id'] for row in value}))
    outcome={'passed':True,'scope':'30 synthetic JPEGs / real Auth / same UUID retry','duplicate_upload_http_status':duplicate_status,'checks':checks}
except Exception as error:
    outcome={'passed':False,'failure':str(error),'checks':checks}
finally:
    for photo in photos:
        checked('delete-synthetic-photo',rpc('delete_photo',{'p_photo':photo}))
    (root/'docs/evidence/supabase-batch-e2e.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2))
    print(json.dumps({'passed':outcome['passed'],'checks':len(checks),'duplicate_upload_http_status':outcome.get('duplicate_upload_http_status')}))
if not outcome['passed']:raise SystemExit(1)
