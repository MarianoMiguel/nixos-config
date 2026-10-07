"""Render the original artwork at its destination size before applying ink."""
import hashlib
import json
import os
import tempfile
from array import array
from pathlib import Path

from PIL import Image, ImageFilter, ImageOps


def atkinson(image):
    w, h = image.size
    gray = array('f', image.getdata())
    output = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            i = y * w + x
            tone = 255 if gray[i] > 127.5 else 0
            output[i] = tone
            error = (gray[i] - tone) / 8
            if x + 1 < w: gray[i + 1] += error
            if x + 2 < w: gray[i + 2] += error
            if y + 1 < h:
                if x: gray[i + w - 1] += error
                gray[i + w] += error
                if x + 1 < w: gray[i + w + 1] += error
            if y + 2 < h: gray[i + 2 * w] += error
    return Image.frombytes('L', (w, h), bytes(output))


def crop_box(source_size, target_size, focus):
    sw, sh = source_size
    tw, th = target_size
    scale = min(sw / tw, sh / th)
    cw, ch = tw * scale, th * scale
    left = max(0, min(sw - cw, focus[0] * sw - cw / 2))
    top = max(0, min(sh - ch, focus[1] * sh - ch / 2))
    return (left, top, left + cw, top + ch)


def desktop_mask(source, art, size):
    with Image.open(source) as original:
        gray = ImageOps.grayscale(ImageOps.exif_transpose(original))
    if art['generated']:
        gray = ImageOps.autocontrast(gray, cutoff=.3)
    box = crop_box(gray.size, size, art.get('desktopFocus', [.5, .5]))
    gray = gray.resize(size, Image.Resampling.LANCZOS, box=box)
    gray = gray.filter(ImageFilter.UnsharpMask(radius=.7, percent=80, threshold=2))
    return atkinson(gray)


def save_atomic(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    os.close(fd)
    try:
        image.save(temporary, format='PNG', optimize=True)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def render_cached(data, cache, art, size, ink, paper):
    if any(type(n) is not int or not 1 <= n <= 16384 for n in size) or size[0] * size[1] > 40_000_000:
        raise ValueError('Unsupported display dimensions')
    source = data / 'sources' / art['file']
    # Recipe/content hashes invalidate stale renders without tying the cache to
    # unrelated palette, UI or NixOS generation changes.
    recipe = json.dumps([art, size], sort_keys=True).encode()
    key = hashlib.sha256(Path(__file__).read_bytes() + source.read_bytes() + recipe).hexdigest()[:20]
    directory = cache / f"{art['id']}-{size[0]}x{size[1]}-{key}"
    target = directory / f'{ink.removeprefix("#")}-{paper.removeprefix("#")}.png'
    if target.is_file(): return target
    mask_path = directory / 'mask.png'
    if not mask_path.is_file():
        save_atomic(desktop_mask(source, art, size).convert('1'), mask_path)
    with Image.open(mask_path) as mask:
        colored = ImageOps.colorize(mask.convert('L'), ink, paper)
        save_atomic(colored, target)
    return target
