"""Generate native theme from shared tokens without external dependencies."""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parent.parent
t=json.loads((root/'design/tokens/tokens.json').read_text())
p=root/'ios/MEFRION/Theme.swift';s=p.read_text()
for key in ['background','accent','text','actionText','secondaryText']:
 c=t[key].lstrip('#'); rgb=[int(c[i:i+2],16)/255 for i in (0,2,4)]
 s=re.sub(rf'static let {key} = Color\([^\n]+\)',f'static let {key} = Color(red: {rgb[0]:.6f}, green: {rgb[1]:.6f}, blue: {rgb[2]:.6f})',s)
for key in ['spacing','radius']:s=re.sub(rf'static let {key}: CGFloat = \d+',f'static let {key}: CGFloat = {t[key]}',s)
p.write_text(s)
p=root/'web/style.css';s=p.read_text()
for key in ['background','accent','text']:s=re.sub(rf'--{key}:#[A-Fa-f0-9]+',f'--{key}:{t[key]}',s)
p.write_text(s)
print('Native and web color tokens synchronized.')
