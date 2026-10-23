import io,unittest
from PIL import Image
from backend.public_media import derivative

class PublicMediaTests(unittest.TestCase):
    def test_metadata_is_stripped_and_orientation_is_normalized(self):
        original=Image.new('RGB',(300,100),(230,150,130))
        exif=Image.Exif();exif[274]=6;exif[315]='Private synthetic provider';exif[306]='2020:01:01 10:10:10'
        exif[34853]={1:'N',2:(35,0,0),3:'E',4:(139,0,0)}
        data=io.BytesIO();original.save(data,format='JPEG',exif=exif,comment=b'private location')
        with Image.open(io.BytesIO(data.getvalue())) as source:self.assertTrue(source.getexif())
        clean=derivative(data.getvalue())
        with Image.open(io.BytesIO(clean)) as image:
            self.assertEqual(image.size,(100,300));self.assertEqual(dict(image.getexif()),{})
            self.assertNotIn('comment',image.info);self.assertNotIn('xmp',image.info);self.assertNotIn('icc_profile',image.info)
        self.assertNotIn(b'Private synthetic provider',clean);self.assertNotIn(b'private location',clean)

    def test_public_size_bound_and_invalid_images(self):
        source=io.BytesIO();Image.new('RGB',(2400,1600)).save(source,format='PNG')
        with Image.open(io.BytesIO(derivative(source.getvalue()))) as image:self.assertEqual(image.size,(1200,800));self.assertEqual(image.format,'JPEG')
        with self.assertRaises((OSError,ValueError)):derivative(b'not an image')
        with self.assertRaises(ValueError):derivative(b'x'*(20*1024*1024+1))
