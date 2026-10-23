"""Copy only the approved development publishable configuration into the app."""
import json
from pathlib import Path
root=Path(__file__).resolve().parent.parent
config=json.loads((root/'.local/supabase-public.json').read_text())
assert config['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
assert config['anon_key'].startswith('sb_publishable_')
(root/'ios/MEFRION/DevelopmentPublicConfiguration.json').write_text(json.dumps({k:config[k] for k in ('url','anon_key')}))
print('Development publishable client configuration prepared; server credentials excluded.')
