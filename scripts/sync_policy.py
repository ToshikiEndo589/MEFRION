"""Keep provisional prototype settings centralized, separate from baseline limits."""
from pathlib import Path
import json
root=Path(__file__).resolve().parent.parent
c=json.loads((root/'config/prototype.json').read_text())
p=c['provisional'];b=c['baseline'];d=c['prototype']
fields={'pets':p['pets_per_account'],'albumBatch':p['album_batch'],'imageBytes':p['image_megabytes']*1024*1024,'petNameCharacters':d['pet_name_characters'],'cardTextCharacters':d['comparison_text_characters'],'thumbnailPixels':d['thumbnail_pixels'],'twinsMinimumPixels':d['twins_minimum_pixels'],'twinsCandidates':b['twins_candidates']}
s='// Generated from config/prototype.json. Provisional values require release approval.\nimport Foundation\n\nenum PrototypePolicy {\n'+''.join(f'    static let {k} = {v}\n' for k,v in fields.items())+f'    static let twinsMaximumDistance: Float = {d["twins_maximum_distance"]}\n    static let twinsDuplicateDistance: Float = {d["twins_duplicate_distance"]}\n}}\n'
(root/'ios/MEFRION/PrototypePolicy.swift').write_text(s)
print('Generated native prototype policy; unimplemented quotas are not enforced by this file.')
