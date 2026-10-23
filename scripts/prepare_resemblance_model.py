"""Reproducible local-only DINOv2 -> Core ML conversion. No user photographs."""
import json, hashlib
from pathlib import Path
import numpy as np
import torch
from transformers import AutoModel
from huggingface_hub import model_info, hf_hub_download
import coremltools as ct
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'.local/resemblance';OUT.mkdir(parents=True,exist_ok=True)
REPO='facebook/dinov2-small'
revision_file=OUT/'model-source.json'
revision='ed25f3a31f01632728cabb09d1542f84ab7b0056'
source={'repository':REPO,'revision':revision,'license':'Apache-2.0','input':'RGB 224x224, stretch subject crop, ImageNet mean/std','output':'L2-normalized CLS, 384 floats','algorithm':'dinov2-small-subject-v1'}
revision_file.write_text(json.dumps(source,indent=2)+'\n')
model=AutoModel.from_pretrained(REPO,revision=revision,trust_remote_code=False,use_safetensors=True,attn_implementation='eager').eval()
# Input is fixed at 224, so positional interpolation is computed exactly once.
# This avoids embedding an unsupported bicubic operator in Core ML.
import types
with torch.no_grad():
 fixed=model.embeddings.interpolate_pos_encoding(torch.zeros(1,257,384),224,224).detach()
model.embeddings.position_embeddings=torch.nn.Parameter(fixed,requires_grad=False)
model.embeddings.interpolate_pos_encoding=types.MethodType(lambda self,embeddings,height,width:self.position_embeddings,model.embeddings)
class Encoder(torch.nn.Module):
 def __init__(self,model):
  super().__init__();self.model=model
  self.register_buffer('mean',torch.tensor([.485,.456,.406]).view(1,3,1,1))
  self.register_buffer('std',torch.tensor([.229,.224,.225]).view(1,3,1,1))
 def forward(self,x):
  y=self.model(pixel_values=(x-self.mean)/self.std,return_dict=False)[0][:,0,:]
  return torch.nn.functional.normalize(y,dim=-1)
encoder=Encoder(model).eval()
x=torch.rand(1,3,224,224)
with torch.no_grad():
 traced=torch.jit.trace(encoder,x,strict=False)
traced.save(str(OUT/'dinov2-small.pt'))
converted=ct.convert(traced,inputs=[ct.ImageType(name='image',shape=x.shape,scale=1/255,color_layout=ct.colorlayout.RGB)],outputs=[ct.TensorType(name='embedding')],minimum_deployment_target=ct.target.iOS17,compute_precision=ct.precision.FLOAT16)
converted.short_description='MEFRION resemblance features: DINOv2 small, subject crop, normalized CLS.'
converted.author='Meta AI (DINOv2 weights); MEFRION conversion'
converted.license='Apache-2.0'
converted.user_defined_metadata['source_revision']=revision
converted.user_defined_metadata['algorithm']=source['algorithm']
converted.save(str(OUT/'PetResemblance.mlpackage'))
from PIL import Image
rgb=(x[0].permute(1,2,0).numpy()*255).astype('uint8');im=Image.fromarray(rgb)
with torch.no_grad():reference=encoder(torch.from_numpy(rgb.copy()).permute(2,0,1).float()[None]/255).numpy()[0]
actual=converted.predict({'image':im})['embedding'].reshape(-1)
cosine=float(np.dot(reference,actual)/(np.linalg.norm(reference)*np.linalg.norm(actual)))
source.update(conversion_cosine=cosine,torch_version=torch.__version__,coremltools_version=ct.__version__)
assert cosine>.999,'Core ML conversion drift'
revision_file.write_text(json.dumps(source,indent=2)+'\n')
print(json.dumps(source),flush=True)
