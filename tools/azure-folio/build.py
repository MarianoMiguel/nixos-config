#!/usr/bin/env python3
"""Build immutable blue-and-ivory art plates; UI palettes are built separately."""
import json
import sys
from array import array
from pathlib import Path
from PIL import Image, ImageOps


def atkinson(image):
    w, h = image.size
    gray = array('f', image.getdata())
    output = bytearray(w*h)
    for y in range(h):
        for x in range(w):
            i = y*w+x
            tone = 255 if gray[i] > 127.5 else 0
            output[i] = tone
            error = (gray[i]-tone)/8
            if x+1 < w: gray[i+1] += error
            if x+2 < w: gray[i+2] += error
            if y+1 < h:
                if x: gray[i+w-1] += error
                gray[i+w] += error
                if x+1 < w: gray[i+w+1] += error
            if y+2 < h: gray[i+2*w] += error
    return Image.frombytes('L', (w,h), bytes(output))


def masks(source, art):
    image = Image.open(source).convert('RGB')
    # The originals remain untouched. Only the generated blue source requires
    # normalization before applying this family's exact two-color ink palette.
    image = ImageOps.grayscale(image)
    if art['generated']:
        image = ImageOps.autocontrast(image, cutoff=.3)
    portrait = ImageOps.fit(image, (700,875), centering=(.72 if art['generated'] else .5,.5))
    # Desktop art fills the entire monitor. Login/lock use the separate
    # portrait asset in their split page; never bake that split into wallpaper.
    desktop = ImageOps.fit(image, (1400,875), centering=(.5,.5))
    return {'desktop':atkinson(desktop),'portrait':atkinson(portrait)}


def build(src, out):
    catalog=json.loads((src/'catalog.json').read_text())
    (out/'art').mkdir(parents=True)
    for collection in catalog['collections']:
        for art in collection['art']:
            dest=out/'art'/art['id'];dest.mkdir()
            rendered=masks(src/'sources'/art['file'],art)
            for ink, colors in catalog['inks'].items():
                for mode,color in colors.items():
                    paper='#f7f4e9' if mode=='light' else '#101d33'
                    for layout, mask in rendered.items():
                        size=(3840,2400) if layout=='desktop' else (1920,2400)
                        image=ImageOps.colorize(mask,color,paper).resize(size,Image.Resampling.NEAREST)
                        image.save(dest/f'{ink}-{mode}-{layout}.png',optimize=True)
            print('Printed',art['id'],flush=True)
    (out/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__': build(Path(sys.argv[1]),Path(sys.argv[2]))
