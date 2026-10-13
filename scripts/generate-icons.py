#!/usr/bin/env python3
"""Generate original cat-and-clock app icons from drawing primitives (Pillow, tooling only)."""
from pathlib import Path
from PIL import Image, ImageDraw
import json
root = Path(__file__).resolve().parent.parent / 'Resources/Assets.xcassets'
folder = root / 'AppIcon.appiconset'; folder.mkdir(parents=True, exist_ok=True)
image = Image.new('RGB',(1024,1024),(40,151,155)); d = ImageDraw.Draw(image)
d.ellipse((160,720,860,870),fill=(32,130,139))
d.polygon([(238,395),(256,153),(446,344)],fill=(251,181,92))
d.polygon([(580,344),(770,153),(788,395)],fill=(251,181,92))
d.polygon([(287,327),(293,219),(382,326)],fill=(243,131,128))
d.polygon([(642,327),(732,219),(738,327)],fill=(243,131,128))
d.ellipse((208,270,816,718),fill=(255,191,111))
d.ellipse((306,518,718,754),fill=(255,224,180))
d.ellipse((359,419,395,478),fill=(58,53,59));d.ellipse((629,419,665,478),fill=(58,53,59))
d.ellipse((332,493,420,523),fill=(244,148,131));d.ellipse((604,493,692,523),fill=(244,148,131))
d.polygon([(483,502),(541,502),(512,530)],fill=(58,53,59))
d.arc((458,502,566,582),0,180,fill=(58,53,59),width=12)
for y in [498,536]:
 d.line([(120,y-14),(297,y)],fill=(255,230,199),width=12);d.line([(727,y),(904,y-14)],fill=(255,230,199),width=12)
d.ellipse((603,616,895,908),fill=(255,255,247));d.ellipse((626,639,872,885),outline=(40,151,155),width=14)
d.line([(749,676),(749,762),(800,794)],fill=(58,53,59),width=16);d.ellipse((735,748,763,776),fill=(58,53,59))
entries=[]
for size in [16,32,128,256,512]:
 for scale in [1,2]:
  pixels=size*scale;filename=f'mac-{size}@{scale}x.png';image.resize((pixels,pixels),Image.Resampling.LANCZOS).save(folder/filename)
  entries.append({'idiom':'mac','size':f'{size}x{size}','scale':f'{scale}x','filename':filename})
for idiom,sizes,scales in [('iphone',[20,29,40,60],[2,3]),('ipad',[20,29,40,76],[1,2]),('ipad',[83.5],[2])]:
 for size in sizes:
  for scale in scales:
   filename=f'{idiom}-{size}@{scale}x.png';image.resize((int(size*scale),int(size*scale)),Image.Resampling.LANCZOS).save(folder/filename)
   entries.append({'idiom':idiom,'size':f'{size}x{size}','scale':f'{scale}x','filename':filename})
image.save(folder/'store-1024.png');entries.append({'idiom':'ios-marketing','size':'1024x1024','scale':'1x','filename':'store-1024.png'})
(folder/'Contents.json').write_text(json.dumps({'images':entries,'info':{'author':'xcode','version':1}},indent=2))
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
