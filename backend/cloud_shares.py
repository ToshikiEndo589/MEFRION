"""No service key, original URLs or private family fields in shared projections."""
import html,json,math,os,re,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
UUID=re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',re.I)
BASE='https://pmrvzpuznwzuejbuhaqm.supabase.co'
def public_request(path,body=None):
 key=os.environ.get('MEFRION_PUBLIC_KEY')
 if key:
  if not key.startswith('sb_publishable_'):raise ValueError('publishable_key_required')
  config={'url':BASE,'anon_key':key}
 else:config=json.loads((ROOT/'.local/supabase-public.json').read_text())
 assert config['url']==BASE
 data=None if body is None else json.dumps(body).encode()
 request=urllib.request.Request(BASE+path,data=data,headers={'apikey':config['anon_key'],'Content-Type':'application/json'})
 with urllib.request.urlopen(request,timeout=20) as response:
  value=response.read(5*1024*1024+1)
  if len(value)>5*1024*1024:raise ValueError('bounded_public_response')
  return json.loads(value) if 'json' in response.headers.get('Content-Type','') else value

def projection(post):
 if not UUID.fullmatch(post):return None
 return public_request('/rest/v1/rpc/mefrion_shared_projection',{'p_post':post})

def image(post,media):
 if not UUID.fullmatch(media):return None
 before=projection(post)
 if not before or not any(v['id']==media for v in before['media']):return None
 value=public_request('/functions/v1/public-image?media='+media)
 after=projection(post)
 if not after or after!=before:return None
 return value

def page(post):
 value=projection(post)
 if not value:return 404, '<!doctype html><html lang="ja"><meta charset="utf-8"><title>MEFRION</title><link rel="stylesheet" href="/shared.css"><main><h1>この共有は終了しました</h1><p>公開が取り消されたか、写真・Petの公開設定が変更されています。</p><strong>MEFRION</strong></main></html>'
 esc=lambda s:html.escape(str(s),quote=True)
 pictures=[]
 layout=value.get('layout') or {}
 def bounded(field,default,low,high):
  try:number=float(layout.get(field,default))
  except (TypeError,ValueError):return default
  return max(low,min(high,number)) if math.isfinite(number) else default
 for index,m in enumerate(value['media']):
  prefix='first' if index==0 else 'second'
  zoom=bounded(prefix+'_zoom',1,1,3);x=bounded(prefix+'_x',0.5,0,1)*100;y=bounded(prefix+'_y',0.5,0,1)*100
  style=f'object-position:{x}% {y}%;transform:scale({zoom});transform-origin:{x}% {y}%'
  pictures.append('<figure><div class="photo"><img alt="公開を許可した写真" src="/cloud-shared/'+esc(post)+'/image/'+esc(m['id'])+'" style="'+style+'"></div><figcaption>'+esc(m['captured'] or '日付不明')+'</figcaption></figure>')
 pictures='<section class="pictures">'+''.join(pictures)+'</section>'

 # Canonical HTTPS URL and Universal Links remain disabled until approved domain.
 title='そっくりな子との出会い' if value['kind']=='twins' else 'あの頃と今'
 og='<meta property="og:title" content="MEFRION · 思い出カード"><meta property="og:description" content="'+esc(value['text'][:120])+'"><meta property="og:image" content="/cloud-shared/'+esc(post)+'/image/'+esc(value['media'][0]['id'])+'">'
 return 200,'<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MEFRION · 思い出カード</title>'+og+'<link rel="stylesheet" href="/shared.css"><main><p class="notice">無料検証環境の共有プレビュー</p><article><h1>'+esc(title)+'</h1><p>'+esc(value['name'])+'</p>'+( (' · '+esc(value['candidate_name'])) if value.get('candidate_name') else '')+pictures+'<p>'+esc(value['text'])+'</p><strong>MEFRION</strong></article><p>共有先に保存されたコピーは公開終了と連動しません。</p></main></html>'
