#!/usr/bin/env python3
"""Build immutable blue-and-ivory art plates; UI palettes are built separately."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageOps
from render import atkinson, desktop_mask


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
    return {'desktop':desktop_mask(source, art, (3840,2400)),'portrait':atkinson(portrait)}


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
