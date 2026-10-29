import sys
from PIL import Image
from collections import Counter
def bg(im):
    im=im.convert('RGB');w,h=im.size
    px=[im.getpixel((x,0)) for x in range(0,w,8)]+[im.getpixel((x,h-1)) for x in range(0,w,8)]
    return Counter(px).most_common(1)[0][0]
def frame(src,out,W,H,pad=0.06):
    im=Image.open(src).convert('RGB');c=Image.new('RGB',(W,H),bg(im))
    s=min(W*(1-2*pad)/im.width,H*(1-2*pad)/im.height);r=im.resize((round(im.width*s),round(im.height*s)),Image.LANCZOS)
    c.paste(r,((W-r.width)//2,(H-r.height)//2));c.save(out,quality=95)
for i,f in enumerate(sys.argv[1:],1):
    frame(f,f'ig-4x5-{i}.jpg',1080,1350)
