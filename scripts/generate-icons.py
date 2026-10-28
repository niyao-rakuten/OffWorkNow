#!/usr/bin/env python3
"""Generate all platform icon sizes from the hand-painted clock master (Pillow, tooling only)."""
from pathlib import Path
from PIL import Image
import json
root = Path(__file__).resolve().parent.parent / 'Resources/Assets.xcassets'
folder = root / 'AppIcon.appiconset'; folder.mkdir(parents=True, exist_ok=True)
source = root.parent / 'AppIcon/offwork-clock-original.png'
with Image.open(source) as original:
 image = original.convert('RGB').resize((1024, 1024), Image.Resampling.LANCZOS)
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
