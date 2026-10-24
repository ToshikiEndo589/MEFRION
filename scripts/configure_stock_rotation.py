"""Configure only MEFRION's owner-authorized, existing Pexels stock catalogue.

No Pexels API call, credentials in arguments, fake engagement, or plan upgrade.
Requires the scoped local migration token and explicit --apply for live writes.
"""
import argparse,hashlib,json,sys,urllib.request
from pathlib import Path
from uuid import uuid4
from stock_pet_names import name_for
ROOT=Path(__file__).resolve().parents[1]
PROJECTS={'production':'pbnimpqrthvznbwewtcf','development':'pmrvzpuznwzuejbuhaqm'}
BREEDS={
 'dog':{'golden retriever':'ゴールデン・レトリーバー','labrador':'ラブラドール・レトリーバー','shiba inu':'柴犬','corgi':'ウェルシュ・コーギー','pomeranian':'ポメラニアン','chihuahua':'チワワ','poodle':'プードル','dachshund':'ダックスフンド','french bulldog':'フレンチ・ブルドッグ','beagle':'ビーグル','border collie':'ボーダー・コリー','german shepherd':'ジャーマン・シェパード','husky':'シベリアン・ハスキー','samoyed':'サモエド','shih tzu':'シー・ズー','dalmatian':'ダルメシアン','rottweiler':'ロットワイラー','maltese':'マルチーズ','schnauzer':'シュナウザー','bichon frise':'ビション・フリーゼ'},
 'cat':{'british shorthair':'ブリティッシュショートヘア','scottish fold':'スコティッシュフォールド','ragdoll':'ラグドール','maine coon':'メインクーン','persian':'ペルシャ','siamese':'シャム','russian blue':'ロシアンブルー','bengal':'ベンガル','sphynx':'スフィンクス','norwegian forest':'ノルウェージャンフォレストキャット','american shorthair':'アメリカンショートヘア','exotic shorthair':'エキゾチックショートヘア'},
}
def lit(v):return "'"+str(v).replace("'","''")+"'"
def query(project,sql):
 token=(ROOT/'.local/cloud-migration-token').read_text().strip()
 req=urllib.request.Request('https://api.supabase.com/v1/projects/'+PROJECTS[project]+'/database/query',data=json.dumps({'query':sql}).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=120) as f:return json.load(f)
def main():
 p=argparse.ArgumentParser();p.add_argument('project',choices=PROJECTS);p.add_argument('--apply',action='store_true');a=p.parse_args()
 permission=json.loads((ROOT/'.local/pexels-permission.json').read_text())
 if permission.get('operator_confirmed_explicit_permission') is not True:raise RuntimeError('Owner permission record required')
 assets=query(a.project,"select a.id,a.species,a.source from public.mefrion_reference_assets a where a.active and a.withdrawn_at is null and a.species in ('dog','cat') and a.source like 'https://www.pexels.com/photo/%' and exists(select 1 from storage.objects o where o.bucket_id='reference-thumbnails' and o.name=a.file) order by a.id")
 rows=[]
 for asset in assets:
  record_path=ROOT/'.local/pexels-pets/records'/(asset['id'].removeprefix('pexels-')+'.json')
  record=json.loads(record_path.read_text()) if record_path.exists() else {}
  alt=record.get('alt','').casefold() if record.get('source_page')==asset['source'] else ''
  matching=[v for k,v in BREEDS[asset['species']].items() if k in alt]
  ordinal=int(hashlib.sha256(asset['id'].encode()).hexdigest()[:8],16)
  rows.append({'id':asset['id'],'name':name_for(asset['species'],ordinal),'breed':matching[0] if len(set(matching))==1 else '',
   'evidence':asset['source']+' | https://www.pexels.com/license/ | owner-authorized stock feed and daily rotation 2026-10-24'})
 if len(rows)<1200:raise RuntimeError('Insufficient dog/cat stock catalogue')
 print(json.dumps({'project':a.project,'catalogue':len(rows),'target':1000,'daily':100,'apply':a.apply}))
 if not a.apply:return
 publisher=query(a.project,'select publisher from mefrion_private.stock_policy where singleton')[0]['publisher'] or str(uuid4())
 sql="begin;insert into auth.users(id,aud,role,email,banned_until,raw_app_meta_data,raw_user_meta_data) values("+lit(publisher)+",'authenticated','authenticated',"+lit('mefrion-stock-'+publisher+'@internal.invalid')+",'infinity','{\"providers\":[]}', '{\"managed_publisher\":true,\"stock_rotation\":true}') on conflict(id) do nothing;insert into mefrion_private.managed_publishers(id) values("+lit(publisher)+") on conflict(id) do nothing;"
 sql+="update mefrion_private.stock_policy set publisher="+lit(publisher)+" where singleton;commit;"
 query(a.project,sql)
 # Existing public Pexels metadata only, never user uploads or account content.
 for start in range(0,len(rows),1000):
  chunk=lit(json.dumps(rows[start:start+1000],ensure_ascii=False))
  sql="insert into mefrion_private.stock_catalog(asset_id,name,breed,rights_until,evidence) select item->>'id',item->>'name',item->>'breed',now()+interval '365 days',item->>'evidence' from jsonb_array_elements("+chunk+"::jsonb) item on conflict(asset_id) do nothing;"
  query(a.project,sql)
 sql="update mefrion_private.stock_policy set enabled=true,publisher="+lit(publisher)+",target=1000,daily=100,updated_at=now() where singleton;"
 query(a.project,sql)
 print(json.dumps({'project':a.project,'configured':True,'password_or_login_created':False}))
if __name__=='__main__':main()
