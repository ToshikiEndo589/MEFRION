"""Read-only OSV advisory check for declared and installed dependencies.
Only package names/versions are sent; credentials and source code are never sent.
"""
import argparse,json,re,subprocess,sys,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--report',default='SECURITY-DEPENDENCIES-20261023.json');args=parser.parse_args()
 packages=set()
 for file in ('requirements.txt','deploy/requirements-admin.txt','scripts/resemblance-requirements.txt'):
  for line in (ROOT/file).read_text().splitlines():
   match=re.fullmatch(r'([\w-]+)==([^\s]+)',line.strip())
   if match:packages.add(('PyPI',match[1].lower().replace('_','-'),match[2]))
 installed=json.loads(subprocess.check_output([sys.executable,'-m','pip','list','--format=json'],text=True))
 for row in installed:packages.add(('PyPI',row['name'].lower().replace('_','-'),row['version']))
 packages.update([('npm','@supabase/supabase-js','2.57.4'),('npm','@imagemagick/magick-wasm','0.0.45')])
 with urllib.request.urlopen('https://registry.npmjs.org/@supabase/supabase-js/2.57.4',timeout=25) as f:manifest=json.load(f)
 for name,version in manifest.get('dependencies',{}).items():
  if name.startswith('@supabase/') and re.fullmatch(r'\d+\.\d+\.\d+',version):packages.add(('npm',name,version))
 ordered=sorted(packages)
 request=urllib.request.Request('https://api.osv.dev/v1/querybatch',data=json.dumps({'queries':[{'package':{'ecosystem':e,'name':n},'version':v} for e,n,v in ordered]}).encode(),headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(request,timeout=45) as f:result=json.load(f)
 items=[{'ecosystem':p[0],'package':p[1],'version':p[2],'advisories':[v['id'] for v in r.get('vulns',[])]} for p,r in zip(ordered,result['results'])]
 report={'source':'OSV public advisory database','scope':'declared exact pins + installed Python environment + pinned Edge SDK direct dependencies','passed':all(not r['advisories'] for r in items),'items':items}
 target=ROOT/'docs/evidence'/Path(args.report).name;target.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'passed':report['passed'],'packages':len(items),'findings':[r for r in items if r['advisories']]}))
 return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
