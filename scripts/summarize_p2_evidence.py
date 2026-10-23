"""Index actual P2 evidence without converting partial runs into release approval."""
import json
from pathlib import Path
root=Path(__file__).resolve().parent.parent
folder=root/'docs/evidence'
matrix=json.loads((folder/'p2-acceptance-matrix.json').read_text())
assert len(matrix['items'])==69 and len({row['id'] for row in matrix['items']})==69
missing=[row['evidence'] for row in matrix['items'] if row['evidence'] and not (folder/row['evidence']).is_file()]
assert not missing, 'Missing evidence references: '+repr(missing)
runs=[]
for path in sorted(folder.glob('p2-*-summary.json')):
 result=json.loads(path.read_text())
 runs.append({'evidence':path.name,**{key:result.get(key) for key in ('result','passedTests','failedTests','skippedTests','totalTestCount')}})
report={'scope':'local Simulator/development evidence only; repeated tests are not distinct coverage','p2_complete':False,'acceptance_scenarios':69,'end_to_end_verified':sum(row['overall']=='passed' for row in matrix['items']),'runs':runs,'external_gates':['real iPhone and VoiceOver/camera/Photos','formal authentication, email and APNs','permitted real-photo quality','HTTPS and continuous workers','backup restore and re-deletion','cloud load and actual costs','human trial and quality approval']}
(folder/'p2-run-index.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'p2_complete':False,'scenarios':69,'runs':len(runs),'missing_references':len(missing)}))
