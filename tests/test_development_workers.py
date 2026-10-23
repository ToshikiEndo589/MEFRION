"""Failure-window tests: no network, only owned synthetic image bytes."""
import io,json,runpy,unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image
ROOT=Path(__file__).resolve().parent.parent
class Response:
 def __init__(self,data,mime='application/json'):self.data=data;self.headers={'Content-Type':mime}
 def __enter__(self):return self
 def __exit__(self,*args):return False
 def read(self):return self.data

class DevelopmentWorkerTests(unittest.TestCase):
 def run_worker(self,name,transport):
  captured={};original=Path.read_text
  def read(path,*args,**kwargs):
   if path.name=='supabase-server.json':return json.dumps({'url':'https://pmrvzpuznwzuejbuhaqm.supabase.co','secret_key':'TEST-NOT-A-CREDENTIAL'})
   return original(path,*args,**kwargs)
  def write(path,content,*args,**kwargs):captured.update(json.loads(content));return len(content)
  with patch.object(Path,'read_text',read),patch.object(Path,'write_text',write),patch('urllib.request.urlopen',transport),patch('builtins.print'):
   try:runpy.run_path(str(ROOT/'scripts'/(name+'.py')),run_name='__main__')
   except SystemExit as result:self.assertEqual(result.code,1)
  return captured
 def publication(self,scenario):
  buffer=io.BytesIO();Image.new('RGB',(8,8),(200,100,80)).save(buffer,format='JPEG')
  objects=set();calls={'finish':0,'delete':0}
  def transport(request,**kwargs):
   path=request.full_url.split('.supabase.co',1)[1]
   if path.endswith('publication_batch'):data=[{'id':'synthetic-post','media':[{'source_path':'synthetic/source.jpg','path':'synthetic-derived.jpg'}]}]
   elif path.startswith('/storage/v1/object/authenticated/'):return Response(buffer.getvalue(),'image/jpeg')
   elif path=='/storage/v1/object/public-derived/synthetic-derived.jpg':
    objects.add('synthetic-derived.jpg');data={}
    if scenario=='lost-upload':raise OSError('Synthetic lost response after upload')
   elif path.endswith('publication_finish'):
    calls['finish']+=1
    if scenario=='unknown-finish' or (scenario=='lost-finish' and calls['finish']==1):raise OSError('Synthetic lost finish response')
    data=scenario!='withdrawn'
   elif path=='/storage/v1/object/public-derived' and request.get_method()=='DELETE':
    calls['delete']+=1;objects.difference_update(json.loads(request.data)['prefixes']);data=[]
   else:raise AssertionError('Unexpected request')
   return Response(json.dumps(data).encode())
  report=self.run_worker('process_publication_outbox',transport);return report,objects,calls
 def test_withdrawal_during_processing_removes_late_derivative(self):
  report,objects,calls=self.publication('withdrawn');self.assertEqual(report['stopped'],1);self.assertFalse(objects);self.assertEqual(calls['delete'],1)
 def test_lost_upload_response_does_not_leave_a_late_blob(self):
  report,objects,calls=self.publication('lost-upload');self.assertEqual(report['failed'],1);self.assertFalse(objects)
 def test_lost_finish_response_preserves_committed_publication(self):
  report,objects,calls=self.publication('lost-finish');self.assertEqual(calls['finish'],2);self.assertIn('synthetic-derived.jpg',objects);self.assertEqual(calls['delete'],0)
 def test_ambiguous_finish_is_reported_and_never_blindly_deleted(self):
  report,objects,calls=self.publication('unknown-finish');self.assertEqual(report['failed'],1);self.assertIn('synthetic-derived.jpg',objects);self.assertEqual(calls['delete'],0)
 def test_delete_ack_requires_verified_storage_absence(self):
  acknowledgments=[]
  def transport(request,**kwargs):
   path=request.full_url.split('.supabase.co',1)[1]
   if path.endswith('deletion_batch'):data=[{'id':'synthetic-job','path':'synthetic.jpg','bucket':'public-derived'}]
   elif path=='/storage/v1/object/public-derived':data=[]
   elif path=='/storage/v1/object/list/public-derived':data=[{'name':'synthetic.jpg'}]
   elif path.endswith('deletion_ack'):acknowledgments.append(True);data=True
   else:raise AssertionError('Unexpected request')
   return Response(json.dumps(data).encode())
  report=self.run_worker('process_deletion_outbox',transport);self.assertEqual(report['failed'],1);self.assertFalse(acknowledgments)
