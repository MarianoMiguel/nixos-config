#!/usr/bin/env python3
"""Build immutable blue-and-ivory art plates; UI palettes are built separately."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageOps
from render import atkinson, crop_box, desktop_mask

# A plate's printed size per layout, and the paper under each mode.
SIZES = {'desktop': (3840, 2400), 'portrait': (1920, 2400)}
PAPER = {'light': '#f7f4e9', 'dark': '#101d33'}
PORTRAIT = (700, 875)


def masks(source, art):
    image = Image.open(source).convert('RGB')
    # The originals remain untouched. Only the generated blue source requires
    # normalization before applying this family's exact two-color ink palette.
    image = ImageOps.grayscale(image)
    if art['generated']:
        image = ImageOps.autocontrast(image, cutoff=.3)
    if 'portraitFocus' in art:
        # Centred on a point where the picture allows, as crop_box crops the desktop.
        left, top, right, bottom = crop_box(image.size, PORTRAIT, art['portraitFocus'])
        centering = tuple(edge / (full - span) if full - span > .5 else .5
                          for edge, full, span in ((left, image.width, right - left), (top, image.height, bottom - top)))
    else:
        centering = (.72 if art['generated'] else .5, .5)
    portrait = ImageOps.fit(image, PORTRAIT, centering=centering)
    # Desktop art fills the entire monitor. Login/lock use the separate
    # portrait asset in their split page; never bake that split into wallpaper.
    return {'desktop':desktop_mask(source, art, SIZES['desktop']),'portrait':atkinson(portrait)}


def print_plate(mask, color, paper, layout):
    """A mask printed in one ink on one paper, at the layout's plate size."""
    return ImageOps.colorize(mask,color,paper).resize(SIZES[layout],Image.Resampling.NEAREST)


def build(src, out):
    catalog=json.loads((src/'catalog.json').read_text())
    (out/'art').mkdir(parents=True)
    for collection in catalog['collections']:
        for art in collection['art']:
            dest=out/'art'/art['id'];dest.mkdir()
            rendered=masks(src/'sources'/art['file'],art)
            for ink, colors in catalog['inks'].items():
                for mode,color in colors.items():
                    for layout, mask in rendered.items():
                        print_plate(mask,color,PAPER[mode],layout).save(dest/f'{ink}-{mode}-{layout}.png',optimize=True)
            print('Printed',art['id'],flush=True)
    (out/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__': build(Path(sys.argv[1]),Path(sys.argv[2]))
