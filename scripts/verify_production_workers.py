"""Production queue acceptance with an explicitly synthetic, non-login fixture.

No customer is selected. IDs are recorded before uploading; cleanup goes through
the normal withdrawal/deletion queues. Inspect status before requesting cleanup.
"""
import argparse
import io
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path
from uuid import uuid4

from PIL import Image
from production_admin import ROOT, LOCAL, connect

STATE = LOCAL / 'production-worker-fixture.json'


def claims(c, owner):
    c.run("select set_config('request.jwt.claims',:value,false)", value=json.dumps({'sub': owner, 'role': 'service_role', 'is_anonymous': False, 'iat': int(time.time())}))


def setup(c):
    if STATE.exists():
        raise RuntimeError('Existing fixture: inspect it instead of creating duplicates')
    state = {'owner': str(uuid4()), 'pet': str(uuid4()), 'photos': [str(uuid4()), str(uuid4())], 'job': str(uuid4()), 'post': str(uuid4()), 'phase': 'reserved'}
    STATE.write_text(json.dumps(state, indent=2)); STATE.chmod(0o600)
    c.run('begin')
    claims(c, state['owner'])
    c.run("insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,reauthentication_token,phone_change_token,raw_app_meta_data,raw_user_meta_data,banned_until) values(:id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',:email,now(),now(),now(),'','','','','','','','{\"provider\":\"email\",\"providers\":[\"email\"]}', '{\"deployment_fixture\":true}',now()+interval '100 years')", id=state['owner'], email='mefrion-deploy-'+state['owner']+'@example.invalid')
    c.run('insert into mefrion_private.managed_publishers(id) values(:id)', id=state['owner'])
    c.run("insert into mefrion_private.pets(id,owner_id,name,species) values(:pet,:owner,'サーバー動作確認','dog')", **{k: state[k] for k in ('pet', 'owner')})
    c.run("insert into mefrion_private.managed_pets(pet_id,publisher_id,external_key,source_note,rights_note,rights_until,rights_verified,updated_by) values(:pet,:owner,:key,'Own synthetic deployment fixture','Generated test pattern; no third party personal data',now()+interval '1 day',true,:owner)", pet=state['pet'], owner=state['owner'], key='deployment-'+state['pet'])
    for photo in state['photos']:
        c.run("insert into mefrion_private.photos(id,pet_id,provider_id,object_path,request_key) values(:photo,:pet,:owner,:path,:photo)", photo=photo, pet=state['pet'], owner=state['owner'], path=state['pet']+'/'+photo+'.jpg')
        c.run("insert into mefrion_private.managed_photo_rights(photo_id,holder,scope,evidence,checked_by,expires_at,allowed) values(:photo,'MEFRION','Synthetic infrastructure test','Generated solid-color pattern; no third party content',:owner,now()+interval '1 day',true)", photo=photo, owner=state['owner'])
    c.run('commit')
    token = (LOCAL / 'production-cloud-worker-token').read_text().strip()
    for i, photo in enumerate(state['photos']):
        # Include the largest image accepted by the current iPhone encoder.
        image = Image.new('RGB', (4000, 4000) if i == 0 else (900, 600), (210, 160, 120))
        exif = Image.Exif(); exif[270] = 'PRIVATE-MEFRION-METADATA'
        stream = io.BytesIO(); image.save(stream, 'JPEG', quality=90, exif=exif)
        path = state['pet']+'/'+photo+'.jpg'
        url = 'https://pbnimpqrthvznbwewtcf.supabase.co/functions/v1/asset-ingest?'+urllib.parse.urlencode({'bucket': 'family-originals', 'path': path})
        request = urllib.request.Request(url, data=stream.getvalue(), method='PUT', headers={'x-mefrion-worker': token, 'Content-Type': 'image/jpeg'})
        with urllib.request.urlopen(request, timeout=90) as response:
            assert json.load(response)['uploaded']
        c.run("update mefrion_private.photos set state='ready' where id=:photo", photo=photo)
    c.run('begin'); claims(c, state['owner'])
    c.run('insert into mefrion_private.public_profiles(pet_id,enabled) values(:pet,true)', pet=state['pet'])
    c.run("insert into mefrion_private.seed_jobs(id,pet_id,created_by,request_key,body,photos,state,approved_by,scheduled_at,post_id) values(:id,:pet,:owner,:id,'サーバー動作確認',:photos,'scheduled',:owner,now(),:post)", id=state['job'], pet=state['pet'], owner=state['owner'], photos=state['photos'], post=state['post'])
    c.run('commit')
    state['phase'] = 'scheduled'; STATE.write_text(json.dumps(state, indent=2))
    print(json.dumps({'synthetic_fixture': True, 'scheduled': True, 'photos': 2, 'largest_dimension': 4000}))


def status(c):
    state = json.loads(STATE.read_text())
    value = {'posts': c.run('select state from mefrion_private.public_posts where id=:post', post=state['post']),
             'jobs': c.run('select kind,state,attempts,error_code from mefrion_private.cloud_jobs where entity_id=:post order by object_path', post=state['post']),
             'objects': c.run("select bucket_id,count(*) from storage.objects where name like :prefix or name in(select object_path from mefrion_private.public_media where post_id=:post) group by bucket_id", prefix=state['pet']+'/%', post=state['post']),
             'health': c.run('select name,runs,failures from mefrion_private.cloud_worker_health')}
    print(json.dumps(value, default=str))


def video(c):
    state = json.loads(STATE.read_text())
    assert c.run("select raw_user_meta_data->>'deployment_fixture' from auth.users where id=:owner", owner=state['owner']) == [['true']]
    if state.get('video_photo'): raise RuntimeError('Video fixture already exists')
    photo = str(uuid4()); path = state['pet']+'/'+photo+'.mp4'; preview = state['pet']+'/'+photo+'-preview.jpg'
    c.run("insert into mefrion_private.photos(id,pet_id,provider_id,object_path,request_key,media_kind,duration_seconds,preview_path) values(:photo,:pet,:owner,:path,:photo,'video',2,:preview)", photo=photo, pet=state['pet'], owner=state['owner'], path=path, preview=preview)
    state['video_photo'] = photo; state['photos'].append(photo); STATE.write_text(json.dumps(state, indent=2))
    token = (LOCAL/'production-cloud-worker-token').read_text().strip()
    source = (LOCAL/'cloud-video-fixture.mp4').read_bytes()
    # Exercise close to the maximum iPhone export size without using any person's
    # video. A large MP4 free box is valid and has no effect on the two-second clip.
    import struct
    padding = 48*1024*1024-len(source)
    source += struct.pack('>I4s', padding, b'free') + bytes(padding-8)
    poster = io.BytesIO(); Image.new('RGB', (320,240), (180,150,120)).save(poster, 'JPEG')
    for name, data, mime in [(path, source, 'video/mp4'), (preview, poster.getvalue(), 'image/jpeg')]:
        url = 'https://pbnimpqrthvznbwewtcf.supabase.co/functions/v1/asset-ingest?'+urllib.parse.urlencode({'bucket':'family-originals','path':name})
        request = urllib.request.Request(url, data=data, method='PUT', headers={'x-mefrion-worker':token,'Content-Type':mime})
        with urllib.request.urlopen(request, timeout=120) as response: assert json.load(response)['uploaded']
    c.run('begin'); claims(c,state['owner'])
    c.run("update mefrion_private.photos set state='ready' where id=:photo",photo=photo)
    c.run("insert into mefrion_private.consents(photo_id,purpose,allowed) values(:photo,'sns',true)",photo=photo)
    result = c.run("select public.mefrion_request_publication(:pet,:photos,'動画のサーバー動作確認','post',:key,true)",pet=state['pet'],photos=[photo],key=str(uuid4()))[0][0]
    c.run('commit');state['video_post']=result['id'];STATE.write_text(json.dumps(state,indent=2))
    print(json.dumps({'video_scheduled': True, 'bytes': len(source), 'synthetic_only': True}))


def withdraw(c):
    state = json.loads(STATE.read_text())
    assert c.run("select raw_user_meta_data->>'deployment_fixture' from auth.users where id=:owner", owner=state['owner']) == [['true']]
    c.run('begin'); claims(c, state['owner'])
    c.run('select public.mefrion_stop_publication(:post)', post=state['post'])
    for photo in state['photos']:
        c.run('select public.mefrion_delete_photo(:photo)', photo=photo)
    c.run('commit')
    state['phase'] = 'withdrawn'; STATE.write_text(json.dumps(state, indent=2))
    print(json.dumps({'withdrawn': True, 'cleanup': 'cloud queue only'}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['setup', 'status', 'video', 'withdraw']); args = parser.parse_args()
    connection = connect()
    try:
        {'setup': setup, 'status': status, 'video': video, 'withdraw': withdraw}[args.action](connection)
    finally:
        connection.close()
