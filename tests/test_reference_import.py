import copy,unittest
from scripts.import_reference_index import validate

class ReferenceImportTests(unittest.TestCase):
 def setUp(self):
  self.asset={'id':'pexels-123','file':'pexels-123.jpg','species':'dog','demoOnly':True,'source':'https://www.pexels.com/photo/dog-123/','fingerprint':'01'*72,'mean':128}
 def test_only_verified_stock_shape_accepted(self):validate(self.asset)
 def test_invalid_species_identity_or_fingerprint_refused(self):
  for field,value in [('species','bird'),('id','family-photo'),('file','../secret.jpg'),('demoOnly',False),('source','https://www.pexels.com.evil.test/photo/123'),('fingerprint','01'),('mean',float('nan'))]:
   asset=copy.deepcopy(self.asset);asset[field]=value
   with self.assertRaises(ValueError):validate(asset)
