"""Contract/static checks. This does not compile Swift or validate iPhone UX."""
import json
import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

root=Path(__file__).resolve().parent.parent
ids={'AUTH','PET','ALB','FAM','MEM','TW','HOME','SEED','POST','SOC','SEARCH','NTF','WEB','SAFE','OPS','MET','REL'}
json.loads((root/'config/prototype.json').read_text())
assert len(list((root/'docs/spec').glob('page-*.txt')))==29
text=(root/'docs/product/TASKS.md').read_text()
for i in ids: assert re.search(r'\| '+i+r'(?:-|\s)',text),i
for n in range(1,7): assert 'SEED-0'+str(n) in text
acceptance=(root/'docs/product/ACCEPTANCE.md').read_text()
assert len(re.findall(r'^\| T-\d\d \|',acceptance,re.M))==69
for n in range(1,70): assert f'| T-{n:02} |' in acceptance
for p in (root/'ios/MEFRION/Assets.xcassets').rglob('*.json'): json.loads(p.read_text())
ET.parse(root/'ios/MEFRION.xcodeproj/xcshareddata/xcschemes/MEFRION.xcscheme')
project=(root/'ios/MEFRION.xcodeproj/project.pbxproj').read_text()
for p in (root/'ios/MEFRION').glob('*.swift'): assert p.name in project
device_families=re.findall(r'TARGETED_DEVICE_FAMILY\s*=\s*"?([^";]+)"?;',project)
assert device_families and all(value.strip()=="1" for value in device_families),device_families
assert not (root/'.env').exists()
print('Repository contracts OK: 29 pages, all feature families, SEED-01..06, 69 pending E2E scenarios, assets, iPhone project references. Swift build is not covered.')
