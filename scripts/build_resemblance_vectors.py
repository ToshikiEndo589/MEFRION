"""Offline experiment index. Uses only already acquired stock photos."""
import json,time
from pathlib import Path
import numpy as np
from PIL import Image
import torch
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'.local/resemblance';BASE=ROOT/'.local/TwinsServerIndex'
rows=json.loads((BASE/'catalog.json').read_text())['assets']
device='mps' if torch.backends.mps.is_available() else 'cpu'
torch.set_num_threads(2)
model=torch.jit.load(str(OUT/'dinov2-small.pt'),map_location='cpu').to(device).eval()
selected=[r for r in rows if (OUT/'crops'/(r['id']+'.json')).exists()]
vectors=np.lib.format.open_memmap(OUT/'vectors.npy',mode='w+',dtype=np.float32,shape=(len(selected),384))
start=time.time();batch_size=16
for offset in range(0,len(selected),batch_size):
 batch=selected[offset:offset+batch_size]
 images=[]
 for row in batch:
  with Image.open(OUT/'crops'/(row['id']+'.png')) as im:
   images.append(np.asarray(im.convert('RGB').resize((224,224),Image.Resampling.BILINEAR)).copy())
 x=torch.from_numpy(np.stack(images)).permute(0,3,1,2).to(device=device,dtype=torch.float32)/255
 with torch.no_grad():values=model(x).cpu().numpy()
 assert values.shape==(len(batch),384) and np.isfinite(values).all()
 vectors[offset:offset+len(batch)]=values
 if offset%320==0:print(json.dumps({'processed':offset+len(batch),'total':len(selected),'seconds':round(time.time()-start,1),'device':device}),flush=True)
vectors.flush()
for row in selected:
 meta=json.loads((OUT/'crops'/(row['id']+'.json')).read_text());row.update(kind=meta['kind'],color=meta['color'])
(OUT/'catalog.json').write_text(json.dumps({'algorithm':'dinov2-small-subject-v1','elements':384,'assets':selected},ensure_ascii=False))
print('COMPLETE',len(selected),round(time.time()-start,1),flush=True)
