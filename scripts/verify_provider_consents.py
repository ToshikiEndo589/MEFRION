"""Synthetic former-provider consent management, approved Free project only."""
import io,json,urllib.request,urllib.error
from pathlib import Path
from uuid import uuid4
from PIL import Image
root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text())
assert public['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
identities=json.loads((root/'.local/supabase-test-identities.json').read_text())
pet=json.loads((root/'.local/supabase-test-sessions.json').read_text())['pet_id']
checks=[];photo=None;owner=None
def call(path,body=None,token=None,raw=None):
    headers={'apikey':public['anon_key']}
    if token:headers['Authorization']='Bearer '+token
    if body is not None:raw=json.dumps(body).encode();headers['Content-Type']='application/json'
    elif raw is not None:headers['Content-Type']='image/jpeg'
    try:
        with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=raw,headers=headers),timeout=30) as response:
            data=response.read();return response.status,json.loads(data) if 'json' in response.headers.get('Content-Type','') else data
    except urllib.error.HTTPError as error:return error.code,{}
def checked(label,result,statuses=(200,),predicate=lambda value:True):
    status,data=result;passed=status in statuses and predicate(data);checks.append({'check':label,'passed':passed,'status':status})
    if not passed:raise RuntimeError(label+' failed')
    return data
def rpc(name,body,token):return call('/rest/v1/rpc/mefrion_'+name,body,token)
try:
    sessions={}
    for identity in identities:
        sessions[identity['role']]=checked('login-'+identity['role'],call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}))['access_token']
    owner,family,outsider=(sessions[role] for role in ('owner','family','outsider'))
    invite=checked('invite',rpc('invite',{'p_pet':pet},owner))
    checked('family-accept',rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':True},family))
    photo=checked('family-reservation',rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4()),'p_title':'consent test'},family))
    stream=io.BytesIO();Image.new('RGB',(128,128),(240,200,180)).save(stream,format='JPEG')
    checked('upload',call('/storage/v1/object/family-originals/'+photo['path'],token=family,raw=stream.getvalue()),(200,201))
    checked('finish',rpc('finish_photo',{'p_photo':photo['id']},family))
    for purpose in ('sns','twins','external_share'):checked('grant-'+purpose,rpc('consent',{'p_photo':photo['id'],'p_purpose':purpose,'p_allowed':True},family))
    checked('owner-cannot-inspect-family-provider-list',rpc('provided_photos',{},owner),predicate=lambda rows:photo['id'] not in [row['id'] for row in rows])
    checked('third-party-cannot-inspect-provider-list',rpc('provided_photos',{},outsider),predicate=lambda rows:photo['id'] not in [row['id'] for row in rows])
    checked('anonymous-provider-list-denied',rpc('provided_photos',{},None),(401,403))
    member=next(identity['id'] for identity in identities if identity['role']=='family')
    checked('remove-family',rpc('remove_member',{'p_pet':pet,'p_user':member},owner))
    checked('removed-family-album-denied',rpc('album',{'p_pet':pet},family),(403,))
    checked('removed-family-original-denied',call('/functions/v1/private-image?photo='+photo['id'],token=family),(404,))
    fields={'id','captured','title','sns','twins','external_share'}
    checked('former-provider-list-only-safe-metadata',rpc('provided_photos',{},family),predicate=lambda rows:any(row['id']==photo['id'] and set(row)==fields and all(row[p] for p in ('sns','twins','external_share')) for row in rows))
    for purpose in ('sns','twins','external_share'):checked('withdraw-after-exit-'+purpose,rpc('consent',{'p_photo':photo['id'],'p_purpose':purpose,'p_allowed':False},family))
    checked('withdrawal-visible-in-list',rpc('provided_photos',{},family),predicate=lambda rows:any(row['id']==photo['id'] and not any(row[p] for p in ('sns','twins','external_share')) for row in rows))
    checked('regrant-after-exit-denied',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True},family),(403,))
    checked('former-provider-delete',rpc('delete_photo',{'p_photo':photo['id']},family))
    checked('deleted-photo-absent-from-provider-list',rpc('provided_photos',{},family),predicate=lambda rows:photo['id'] not in [row['id'] for row in rows])
    outcome={'passed':True,'scope':'former provider / safe consent metadata / synthetic image','checks':checks}
except Exception as error:outcome={'passed':False,'failure':str(error),'checks':checks}
finally:
    if photo and owner:call('/rest/v1/rpc/mefrion_delete_photo',{'p_photo':photo['id']},owner)
    (root/'docs/evidence/supabase-provider-e2e.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2))
    print(json.dumps({'passed':outcome['passed'],'checks':len(checks)}))
if not outcome['passed']:raise SystemExit(1)
