"""Stage only reserved owner credentials and two owned illustrations in Simulator."""
import io,json,subprocess,sys
from uuid import uuid4
from PIL import Image
from p1_test_support import ROOT,DevelopmentClient
c=DevelopmentClient();c.login();photos=[]
for i in range(2):
 p=c.check('reserve',c.rpc('begin_photo',{'p_pet':c.pet,'p_request_key':str(uuid4()),'p_captured':'2020' if i==0 else None,'p_title':'P1 owned UI card'}));photos.append(p['id'])
 data=io.BytesIO();Image.new('RGB',(256,256),(140+i*60,150,130)).save(data,'JPEG');c.check('upload',c.call('/storage/v1/object/family-originals/'+p['path'],raw=data.getvalue(),role='owner'),(200,201));c.check('ready',c.rpc('finish_photo',{'p_photo':p['id']}));c.check('own-external-test-purpose',c.rpc('consent',{'p_photo':p['id'],'p_purpose':'external_share','p_allowed':True}))
owner=next(i for i in c.people if i['role']=='owner');container=subprocess.check_output(['xcrun','simctl','get_app_container',sys.argv[1],'dev.local.mefrion.prototype.uitests.xctrunner','data'],text=True).strip()
fixture={'anon_key':c.config['anon_key'],'email':owner['email'],'password':owner['password'],'pet_id':c.pet,'first':photos[0],'second':photos[1]}
from pathlib import Path
p=Path(container)/'Documents/p1-card-fixture.json';p.write_text(json.dumps(fixture));p.chmod(0o600)
p=ROOT/'.local/p1-card-ui-fixture.json';p.write_text(json.dumps({'photos':photos,'pet':c.pet}));p.chmod(0o600)
print('Two owned private UI illustrations staged; no values printed.')
