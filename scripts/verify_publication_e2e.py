"""Real Auth/storage/derivatives, synthetic images only in approved test project.

Creates a temporary synthetic public projection and removes it at the end.
Does not publish the app, deploy a production service, or upload human photos.
"""
import io,json,subprocess,sys,urllib.request,urllib.error
from pathlib import Path
from uuid import uuid4
from PIL import Image
root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text())
assert public['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
identities=json.loads((root/'.local/supabase-test-identities.json').read_text())
pet=json.loads((root/'.local/supabase-test-sessions.json').read_text())['pet_id']
owner=None;photo=None;checks=[]
def call(path,body=None,token=None,raw=None):
    headers={'apikey':public['anon_key']}
    if token:headers['Authorization']='Bearer '+token
    if body is not None:raw=json.dumps(body).encode();headers['Content-Type']='application/json'
    elif raw is not None:headers['Content-Type']='image/jpeg'
    try:
        with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=raw,headers=headers),timeout=40) as response:
            data=response.read();return response.status,json.loads(data) if 'json' in response.headers.get('Content-Type','') else data,dict(response.headers)
    except urllib.error.HTTPError as error:return error.code,{},dict(error.headers)
def checked(label,result,statuses=(200,),predicate=lambda data,headers:True):
    status,data,headers=result;passed=status in statuses and predicate(data,headers);checks.append({'check':label,'passed':passed,'status':status})
    if not passed:raise RuntimeError(label+' failed')
    return data
def rpc(name,body,token=None):return call('/rest/v1/rpc/mefrion_'+name,body,token)
try:
    identity=next(i for i in identities if i['role']=='owner')
    owner=checked('synthetic-login',call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}))['access_token']
    photo=checked('reserve-original',rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4()),'p_title':'synthetic publication test'},owner))
    image=Image.new('RGB',(2400,1600),(238,190,170));exif=Image.Exif();exif[315]='Synthetic private metadata';exif[34853]={1:'N',2:(35,0,0),3:'E',4:(139,0,0)}
    stream=io.BytesIO();image.save(stream,format='JPEG',exif=exif,comment=b'synthetic private location');original=stream.getvalue()
    checked('upload-original',call('/storage/v1/object/family-originals/'+photo['path'],token=owner,raw=original),(200,201))
    checked('finish-original',rpc('finish_photo',{'p_photo':photo['id']},owner))
    checked('profile-explicit-required',rpc('set_public_profile',{'p_pet':pet,'p_enabled':True,'p_explicit':False},owner),(400,))
    checked('profile-explicit-enable',rpc('set_public_profile',{'p_pet':pet,'p_enabled':True,'p_explicit':True},owner))
    body={'p_pet':pet,'p_photos':[photo['id']],'p_body':'Synthetic development test only','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True}
    checked('provider-purpose-required',rpc('request_publication',body,owner),(403,))
    checked('provider-sns-purpose',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True},owner))
    checked('post-explicit-required',rpc('request_publication',{**body,'p_explicit':False},owner),(400,))
    checked('body-limit',rpc('request_publication',{**body,'p_body':'x'*501},owner),(400,))
    checked('duplicate-media-rejected',rpc('request_publication',{**body,'p_photos':[photo['id']]*5},owner),(400,))
    post=checked('queue-publication',rpc('request_publication',body,owner))['id']
    checked('same-request-retry',rpc('request_publication',body,owner),predicate=lambda data,h:data['id']==post)
    checked('pending-not-visible',rpc('public_feed',{}),predicate=lambda data,h:post not in [row['id'] for row in data])
    checked('owner-cannot-run-worker',rpc('publication_batch',{},owner),(403,))
    checked('anonymous-cannot-run-worker',rpc('publication_batch',{}),(401,403))
    completed=subprocess.run([sys.executable,str(root/'scripts/process_publication_outbox.py')],capture_output=True,text=True,check=True)
    worker=json.loads(completed.stdout)
    if worker['processed']!=1 or worker['failed']:raise RuntimeError('synthetic derivative worker failed')
    checks.append({'check':'actual-metadata-stripping-worker','passed':True})
    feed=checked('published-feed-safe-projection',rpc('public_feed',{}),predicate=lambda data,h:any(row['id']==post and not any(key in row for key in ('actor_id','source_id','object_path','provider_id')) for row in data))
    item=next(row for row in feed if row['id']==post);media=item['media'][0]
    gateway='/functions/v1/public-image?media='+media
    jpeg=checked('anonymous-derived-image',call(gateway),predicate=lambda data,h:isinstance(data,bytes) and h.get('Cache-Control')=='private, no-store, max-age=0')
    with Image.open(io.BytesIO(jpeg)) as clean:
        if clean.size!=(1200,800) or clean.getexif() or any(key in clean.info for key in ('comment','xmp','icc_profile')):raise RuntimeError('public derivative leaked metadata')
    checks.append({'check':'real-derived-dimensions-and-empty-private-metadata','passed':True})
    checked('invalid-token-not-treated-as-anonymous',call(gateway,token='not-a-real-token'),(401,))
    checked('original-id-not-accepted-as-public-media',call('/functions/v1/public-image?media='+photo['id']),(404,))
    checked('direct-derived-storage-denied',call('/storage/v1/object/public/public-derived/'+media+'.jpg'),(400,401,403,404))
    checked('signed-derived-url-denied',call('/storage/v1/object/sign/public-derived/'+media+'.jpg',{'expiresIn':3600},owner),(400,401,403,404))
    checked('withdraw-sns-purpose',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':False},owner))
    checked('withdrawn-feed-hidden',rpc('public_feed',{}),predicate=lambda data,h:post not in [row['id'] for row in data])
    checked('withdrawn-image-hidden-before-purge',call(gateway),(404,))
    checked('regrant-consent',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True},owner))
    checked('regrant-does-not-republish',rpc('public_feed',{}),predicate=lambda data,h:post not in [row['id'] for row in data])
    outcome={'passed':True,'scope':'real Auth / synthetic EXIF JPEG / public derivative / consent withdrawal','checks':checks}
except Exception as error:outcome={'passed':False,'failure':str(error),'checks':checks}
finally:
    if owner:
        checked('return-test-profile-to-private',rpc('set_public_profile',{'p_pet':pet,'p_enabled':False},owner))
        if photo:checked('delete-test-original',rpc('delete_photo',{'p_photo':photo['id']},owner))
    (root/'docs/evidence/supabase-publication-e2e.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2))
    print(json.dumps({'passed':outcome['passed'],'checks':len(checks),'failure':outcome.get('failure')}))
if not outcome['passed']:raise SystemExit(1)
