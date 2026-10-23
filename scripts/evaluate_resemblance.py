"""Fixed stock-only paired comparison. Reviews are explicitly agent judgments, not user accuracy."""
import argparse,json,hashlib
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps,ImageDraw
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'.local/TwinsServerIndex';OUT=ROOT/'.local/resemblance'
base=json.loads((BASE/'catalog.json').read_text())['assets']
def fixed_queries():
 return [a for species in ('dog','cat') for a in sorted((r for r in base if r['species']==species),key=lambda r:hashlib.sha256(('mefrion-eval-20261011:'+r['id']).encode()).hexdigest())[:12]]
def sheet(rows,path):
 out=Image.new('RGB',(1000,len(rows)*158),'white');d=ImageDraw.Draw(out)
 for y,row in enumerate(rows):
  for x,(asset,label) in enumerate(row):
   with Image.open(BASE/'images'/asset['file']) as im:thumb=ImageOps.contain(im.convert('RGB'),(136,126))
   out.paste(thumb,(x*142+(136-thumb.width)//2,y*158));d.text((x*142,y*158+128),label,fill='black');d.text((x*142,y*158+142),asset['id'],fill='black')
 out.save(path)
parser=argparse.ArgumentParser();parser.add_argument('--queries',action='store_true');args=parser.parse_args()
queries=fixed_queries()
if args.queries:
 (OUT/'evaluation-queries.json').write_text(json.dumps(queries,indent=2))
 for group in range(4):sheet([[(a,f'Q{group*6+i+1} {a["species"]}') for i,a in enumerate(queries[group*6:(group+1)*6])]],OUT/f'queries-{group+1}.jpg')
 raise SystemExit()
new=json.loads((OUT/'native-catalog.json').read_text())['assets'];lookup={r['id']:i for i,r in enumerate(new)};baseids={r['id']:i for i,r in enumerate(base)}
v=np.fromfile(BASE/'vectors.bin',dtype='<f4').reshape(-1,768);w=np.fromfile(OUT/'native-vectors.bin',dtype='<f4').reshape(-1,384);w=w/np.linalg.norm(w,axis=1,keepdims=True)
c=np.array([r['color'] for r in new],np.float32)
fp=np.array([[b=='1' for b in a['fingerprint']] for a in base]);means=np.array([a['mean'] for a in base]);species=np.array([a['species'] for a in base]);bi=np.array([baseids[r['id']] for r in new])
def choose(order,qi,diverse=False):
 chosen=[]
 for i in order:
  if i==qi or species[i]!=species[qi] or base[i]['id']=='pexels-1790445' or base[i]['credit']==base[qi]['credit']:continue
  if abs(means[i]-means[qi])<=4 and np.count_nonzero(fp[i]!=fp[qi])<=12:continue
  if np.linalg.norm(v[i]-v[qi])<=.08:continue
  if diverse and any(base[j]["credit"]==base[i]["credit"] for j in chosen):continue
  if any((abs(means[i]-means[j])<=4 and np.count_nonzero(fp[i]!=fp[j])<=12) or np.linalg.norm(v[i]-v[j])<=.08 for j in chosen):continue
  chosen.append(int(i))
  if len(chosen)==3:break
 return chosen
comparisons=[]
for q in queries:
 qi=baseids[q['id']]
 if q['id'] not in lookup:continue
 ni=lookup[q['id']]
 olddist=np.linalg.norm(v-v[qi],axis=1);old=choose([i for i in np.argsort(olddist) if olddist[i]<=1.1],qi)
 semantic=1-np.einsum('ij,j->i',w,w[ni]);color=1-np.einsum('ij,j->i',c,c[ni]);assert np.isfinite(semantic).all() and np.isfinite(color).all()
 score=semantic+.12*color
 pool=np.array([j for j in np.argsort(semantic) if new[j]['species']==q['species'] and semantic[j]<=.5 and new[j]['id']!='pexels-1790445'][:240]);order=pool[np.argsort(score[pool])];improved=choose(bi[order],qi,diverse=True)
 pure=choose(bi[pool],qi)
 comparisons.append({'query':q['id'],'species':q['species'],'legacy':[base[j]['id'] for j in old],'dino':[base[j]['id'] for j in pure],'dino_color':[base[j]['id'] for j in improved],'kind':new[ni]['kind']})
(OUT/'comparison.json').write_text(json.dumps(comparisons,indent=2))
for g in range(0,len(comparisons),4):
 rows=[]
 for n,r in enumerate(comparisons[g:g+4]):
  ids=[r['query']]+r['legacy']+r['dino_color'];rows.append([(base[baseids[id]],('QUERY' if i==0 else 'OLD' if i<4 else 'NEW')+f' {g+n+1}') for i,id in enumerate(ids)])
 sheet(rows,OUT/f'comparison-{g//4+1}.jpg')
print('Compared',len(comparisons),'queries, excluded self and near duplicates in both arms')
