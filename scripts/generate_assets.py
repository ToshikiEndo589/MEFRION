from pathlib import Path
from PIL import Image,ImageDraw
import json,shutil
for i in range(10):
 cat=i%2==1
 bg=['#F5D9BA','#E7DCCC','#D9DFD2','#EDD4CF'][i%4]
 im=Image.new('RGB',(640,640),bg);d=ImageDraw.Draw(im)
 # Self-authored, intentionally recognizable as illustration, not real photography.
 fur=['#B77B4D','#E8AD62','#F1EBDF','#777B80'][i%4]
 if cat:
  d.polygon([(150,300),(170,110),(295,230)],fill=fur)
  d.polygon([(350,230),(475,110),(490,310)],fill=fur)
 else:
  d.ellipse((65,155,245,480),fill=fur);d.ellipse((395,155,575,480),fill=fur)
 d.ellipse((145,175,495,525),fill=fur)
 d.ellipse((230,295,255,330),fill='#45312B');d.ellipse((380,295,405,330),fill='#45312B')
 d.ellipse((265,340,375,450),fill='#FFF4DE');d.ellipse((300,353,340,380),fill='#45312B')
 d.line((320,375,320,409),fill='#45312B',width=5)
 d.arc((280,375,322,425),0,120,fill='#45312B',width=4);d.arc((318,375,360,425),60,180,fill='#45312B',width=4)
 d.text((20,608),'MEFRION / DEVELOPMENT ILLUSTRATION',fill='#45312B')
 p=Path(f'ios/MEFRION/Assets.xcassets/pet-{i}.imageset');p.mkdir(parents=True,exist_ok=True)
 im.save(p/'demo.png'); (p/'Contents.json').write_text(json.dumps({'images':[{'filename':'demo.png','idiom':'universal'}],'info':{'version':1,'author':'xcode'}}))
 Path('web/assets').mkdir(parents=True,exist_ok=True);shutil.copy(p/'demo.png',f'web/assets/pet-{i}.png')
Path('ios/MEFRION/Assets.xcassets/Contents.json').write_text('{"info":{"version":1,"author":"xcode"}}')
Path('design/ASSET_RIGHTS.md').write_text('# テスト素材台帳\n全10枚はscripts/generate_assets.pyの独自描画。Web収集なし。実在写真ではない。用途は開発専用、demo_only。本番投入禁止。Twins品質評価には使用不可。\n')
