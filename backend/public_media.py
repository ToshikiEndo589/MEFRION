"""Local worker transformation. Never write metadata into public derivatives."""
import io,subprocess,tempfile,shutil
from pathlib import Path
from PIL import Image,ImageOps

def derivative(original):
    if len(original)>20*1024*1024:raise ValueError('Image too large')
    with Image.open(io.BytesIO(original)) as image:
        if image.width*image.height>50_000_000:raise ValueError('Image too large')
        clean=ImageOps.exif_transpose(image).convert('RGB');clean.thumbnail((1200,1200))
        clean.info.clear()
        stream=io.BytesIO();clean.save(stream,format='JPEG',quality=85,optimize=True)
        return stream.getvalue()

def video_derivative(original):
    """Strip container metadata, constrain playback to five minutes and 50MB."""
    if not 0<len(original)<=50*1024*1024 or original[4:8] != b'ftyp':
        raise ValueError('Invalid video')
    with tempfile.TemporaryDirectory(prefix='mefrion-video-') as folder:
        source=Path(folder)/'source.mov';output=Path(folder)/'clean.mp4'
        source.write_bytes(original)
        if shutil.which('avconvert'):
            for preset in ('Preset960x540','Preset640x480'):
                result=subprocess.run(['avconvert','--source',str(source),'--preset',preset,'--output',str(output),'--duration','300','--replace'],capture_output=True,timeout=420)
                if result.returncode==0 and output.exists() and output.stat().st_size<=49*1024*1024:
                    return output.read_bytes()
        elif shutil.which('ffmpeg'):
            result=subprocess.run(['ffmpeg','-v','error','-i',str(source),'-t','300','-map_metadata','-1','-vf','scale=960:540:force_original_aspect_ratio=decrease','-c:v','libx264','-b:v','850k','-c:a','aac','-b:a','96k','-movflags','+faststart','-y',str(output)],capture_output=True,timeout=420)
            if result.returncode==0 and output.exists() and output.stat().st_size<=49*1024*1024:
                return output.read_bytes()
        raise ValueError('Video transcode failed')
