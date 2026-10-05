#!/usr/bin/env python3
"""Build immutable blue-and-ivory plates and the six internal palette slots."""
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


def palette(ink, mode):
    light=mode=='light'
    p={'mode':mode,'background':'#f7f4e9' if light else '#101d33',
       'foreground':'#263a57' if light else '#e4e9f0','accent':ink,'blue':ink,
       'lighter_background':'#fbf9f2' if light else '#16253c',
       'dark_background':'#eaece7' if light else '#101b2c',
       'darker_background':'#e1e7ef' if light else '#0b1424',
       'dark_foreground':'#64728a' if light else '#9eb0ca',
       'bright_foreground':'#214c94' if light else '#f7f4e9',
       'muted':'#64728a' if light else '#9eb0ca',
       'selection':'#e1e7ef' if light else '#263e5e',
       'red':'#a44747' if light else '#e9a5a0',
       'green':'#367061' if light else '#a1caba',
       'yellow':'#82651e' if light else '#d9c28e',
       'orange':'#8e5e35' if light else '#dbb191',
       'cyan':'#356c82' if light else '#9fc8d8',
       'magenta':'#6d6089' if light else '#c5b5df'}
    return p


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
    for ink,colors in catalog['inks'].items():
        for mode,color in colors.items():
            dest=out/'themes'/f'folio-{ink}-{mode}';dest.mkdir(parents=True)
            (dest/'colors.toml').write_text(''.join(f'{k} = "{v}"\n' for k,v in palette(color,mode).items()))
    (out/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__': build(Path(sys.argv[1]),Path(sys.argv[2]))
