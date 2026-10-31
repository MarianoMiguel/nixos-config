"""Your pictures: Folio plates from the pictures the owner keeps in ~/Pictures/Folio.

Any JPEG, PNG or WebP directly in that folder becomes a plate of one more
collection, "Your pictures" (id "mine"), printed exactly as the shipped plates
are: build.masks and render.desktop_mask crop and dither it, build.print_plate
prints the light azure render the shell's Plate re-prints in any ink, and
render.render_cached crops each display for DMS. The pictures stay on this
computer: never in the repository, never in the Nix store. `azure-folio
pictures` reads the folder and keeps what it prints in a store in the cache,
$XDG_CACHE_HOME/azure-folio/pictures, keyed by content (renaming a picture
costs nothing; the folder alone decides what is there):

  catalog.json                        the collection, and the files not used
  sources/<id>.png                    the picture in gray, re-encoded
  art/<id>/mask-<layout>.png          its 1-bit masks (desktop, portrait)
  art/<id>/azure-light-<layout>.png   the plates the shell prints from
  art/<id>/<ink>-<mode>-<layout>.png  DMS's copy, printed when it is chosen

A picture may have a sidecar beside it, named like it with .json in place of
(or after) its extension, `2pac.json` or `2pac.jpg.json`:

  {"focus": [0.72, 0.4], "title": "All eyez on me"}

focus is the point every crop keeps in view (x and y from 0 to 1, from the
top left; 0.5, 0.5 without one): the desktop, each display, and the
lock's and screensaver's split. title replaces the file's name (at most 80
characters). Both are optional; nothing else may be in it. A sidecar that
does not check out is not used, and the catalog says why.

The folder is untrusted input. Only regular files directly in it are read,
never through a link, each opened without following one and read whole up
to MAX_BYTES; Pillow decodes it only as JPEG, PNG or WebP, and only after its
header says it fits MAX_PIXELS (Pillow's decompression-bomb guard stays on, at
that limit). Everything written is re-encoded by Pillow, never copied.

Root never reads any of this: the greeter's bridge (`azure-folio publish`)
and the boot screen see only the selection, and a choice of your pictures
reaches them as the shipped default plate.
"""
import contextlib
import errno
import fcntl
import hashlib
import io
import json
import math
import os
import re
import shutil
import stat
import tempfile
import time
import unicodedata
import warnings
from pathlib import Path

from PIL import Image, ImageOps

import build
import render

ID = 'mine'
NAME = 'Your pictures'
DESCRIPTION = 'Your own, printed in your ink'
CREDIT = 'Your picture'
SUFFIXES = {'.jpg', '.jpeg', '.png', '.webp'}
FORMATS = ('JPEG', 'PNG', 'WEBP')
MAX_BYTES = 48 * 1024 * 1024
MAX_PIXELS = 50_000_000
MIN_SIDE = 32
MAX_PICTURES = 200
SIDECAR_BYTES = 4096
TITLE_LENGTH = 80
CENTRE = [.5, .5]
# A file this recent may still be arriving (a copy in progress): it waits for
# the next scan, which the shell runs a moment later.
SETTLE_SECONDS = 2
# Bump when the way a picture becomes gray changes: every picture is printed again.
VERSION = b'your-pictures-1'
# The render every shell plate starts from (Plate.qml re-prints it in any ink).
SHELL = ('azure', 'light')
LAYOUTS = tuple(build.SIZES)

ART_ID = re.compile(r'mine-[0-9a-f]{16}')
SOURCE = re.compile(r'(mine-[0-9a-f]{16})\.png')
RENDER = re.compile(r'(mine-[0-9a-f]{16})-\d+x\d+-[0-9a-f]{20}')

_cache = Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache')
FOLDER = Path(os.environ.get('AZURE_FOLIO_PICTURES') or Path.home() / 'Pictures/Folio')
STORE = Path(os.environ.get('AZURE_FOLIO_PICTURES_STORE') or _cache / 'azure-folio/pictures')


class Unreadable(ValueError):
    """A file in the folder that cannot be used; the message says why."""


def point(value):
    """[x, y], each a finite number from 0 to 1, or None."""
    if isinstance(value, list) and len(value) == 2 and all(type(v) in (int, float) and math.isfinite(v) and 0 <= v <= 1 for v in value):
        return [float(v) for v in value]
    return None


# ------------------------------------------------------------------ the store

def read_catalog(store=None):
    """The store's catalog document, or {} when there is none or it is damaged."""
    try:
        fd = os.open((store or STORE) / 'catalog.json', os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError:
        return {}
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > 4 * 1024 * 1024:
            return {}
        try:
            doc = json.loads(stream.read())
        except ValueError:
            return {}
    return doc if isinstance(doc, dict) else {}


def _entries(doc):
    """The catalog's plates, each rebuilt from checked fields only."""
    c = doc.get('collection')
    art = c.get('art') if isinstance(c, dict) else None
    out = []
    for a in art if isinstance(art, list) else []:
        if not isinstance(a, dict) or type(a.get('id')) is not str or not ART_ID.fullmatch(a['id']):
            continue
        if type(a.get('title')) is not str or len(a['title']) > 200 or any(x['id'] == a['id'] for x in out):
            continue
        focus = point(a.get('desktopFocus')) or CENTRE
        entry = {'id': a['id'], 'title': a['title'], 'file': a['id'] + '.png', 'credit': CREDIT,
                 'desktopFocus': focus, 'plateFocus': point(a.get('plateFocus')) or focus, 'generated': False}
        if type(a.get('name')) is str: entry['name'] = a['name']
        if isinstance(a.get('sig'), list): entry['sig'] = a['sig']
        out.append(entry)
    return out


def collection(store=None):
    """Your pictures as a catalog collection, or None while there are none."""
    art = [{k: v for k, v in a.items() if k not in ('name', 'sig')} for a in _entries(read_catalog(store))]
    return {'id': ID, 'name': NAME, 'description': DESCRIPTION, 'user': True, 'art': art} if art else None


def art_dir(ident, store=None):
    if not ART_ID.fullmatch(ident): raise ValueError('Unknown picture')
    return (store or STORE) / 'art' / ident


def complete(ident, store=None):
    store = store or STORE
    folder = art_dir(ident, store)
    names = [f'mask-{l}.png' for l in LAYOUTS] + [f'{SHELL[0]}-{SHELL[1]}-{l}.png' for l in LAYOUTS]
    return (store / 'sources' / f'{ident}.png').is_file() and all((folder / n).is_file() for n in names)


def save(image, path):
    """An atomic PNG save. Not optimized, unlike the shipped plates: that
    takes seconds per plate for a few percent, on the owner's machine."""
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    os.close(fd)
    try:
        image.save(temporary, format='PNG')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def prints(ident, ink, mode, color, store=None):
    """The plate printed in one of the catalog's inks, for DMS: made once, from its masks."""
    folder = art_dir(ident, store)
    for layout in LAYOUTS:
        target = folder / f'{ink}-{mode}-{layout}.png'
        if target.is_file(): continue
        with Image.open(folder / f'mask-{layout}.png') as mask:
            save(build.print_plate(mask.convert('L'), color, build.PAPER[mode], layout), target)


def plate_focus(ident, focus, store):
    """The focus as a point of the desktop plate (the shell's Plate centres
    that): where the picture's focus lands once it is cropped to 16:10."""
    with Image.open(store / 'sources' / f'{ident}.png') as source:
        size = source.size
    left, top, right, bottom = render.crop_box(size, build.SIZES['desktop'], focus)
    return [round(min(1, max(0, (focus[0] * size[0] - left) / (right - left))), 4),
            round(min(1, max(0, (focus[1] * size[1] - top) / (bottom - top))), 4)]


# ------------------------------------------------------------------ one file

def shown(name):
    """A file name as text: valid UTF-8, no control characters."""
    text = os.fsencode(name).decode('utf-8', 'replace')
    return ''.join(c for c in text if not unicodedata.category(c).startswith('C'))[:200]


def title(name):
    """The plate's title: the file's name without its extension, underscores as spaces."""
    text = ' '.join(Path(shown(name)).stem.replace('_', ' ').split())
    return text[:TITLE_LENGTH].strip() or 'Untitled'


def read_file(dirfd, name, limit=None):
    """The bytes of a regular file in the folder, never through a link."""
    limit = limit or MAX_BYTES
    too_large = f'larger than {limit >> 20} MB' if limit >= 1 << 20 else f'larger than {limit} bytes'
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK, dir_fd=dirfd)
    except OSError as exc:
        raise Unreadable('a link: copy the file itself into the folder' if exc.errno == errno.ELOOP else 'could not be opened') from None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode): raise Unreadable('not a regular file')
        if info.st_size > limit: raise Unreadable(too_large)
        chunks, total = [], 0
        while True:
            chunk = os.read(fd, min(1 << 20, limit + 1 - total))
            if not chunk: break
            chunks.append(chunk); total += len(chunk)
            if total > limit: raise Unreadable(too_large)
    finally:
        os.close(fd)
    return b''.join(chunks)


def parse_sidecar(data):
    """A sidecar's focus and title, each checked, or Unreadable saying what is wrong."""
    def constant(name): raise ValueError(name)
    try:
        doc = json.loads(data.decode('utf-8'), parse_constant=constant)
    except ValueError:
        raise Unreadable('not used: not JSON') from None
    if not isinstance(doc, dict):
        raise Unreadable('not used: not a JSON object')
    if set(doc) - {'focus', 'title'}:
        raise Unreadable('not used: only "focus" and "title" may be in it')
    out = {}
    if 'focus' in doc:
        out['focus'] = point(doc['focus'])
        if out['focus'] is None: raise Unreadable('not used: "focus" must be [x, y], each from 0 to 1')
    if 'title' in doc:
        t = doc['title']
        if type(t) is not str or not t.strip() or len(t) > TITLE_LENGTH or any(unicodedata.category(c).startswith('C') for c in t):
            raise Unreadable(f'not used: "title" must be text, at most {TITLE_LENGTH} characters')
        out['title'] = ' '.join(t.split())
    return out


@contextlib.contextmanager
def opened(data):
    """The picture with only its header read, if it is a JPEG, PNG or WebP
    within the limits; Unreadable otherwise. Nothing is decoded before this."""
    Image.MAX_IMAGE_PIXELS = MAX_PIXELS   # Pillow's own guard, at our limit
    with warnings.catch_warnings():
        warnings.simplefilter('error', Image.DecompressionBombWarning)
        try:
            image = Image.open(io.BytesIO(data), formats=FORMATS)
        except (Image.DecompressionBombError, Image.DecompressionBombWarning):
            raise Unreadable('too many pixels') from None
        except Exception:
            raise Unreadable('not a JPEG, PNG or WebP picture') from None
        with image:
            w, h = image.size
            if w * h > MAX_PIXELS: raise Unreadable('too many pixels')
            if min(w, h) < MIN_SIDE: raise Unreadable('too small')
            yield image


def normalize(data):
    """The picture as 8-bit gray on white paper, no larger than the largest
    plate needs (it still covers the 3840 x 2400 desktop plate), or Unreadable."""
    cover = build.SIZES['desktop']
    with opened(data) as image:
        w, h = image.size
        try:
            if image.format == 'JPEG':
                # Decode gray, and no larger than the plate needs (libjpeg scales by 1/2, 1/4, 1/8).
                turned = image.getexif().get(0x0112) in (5, 6, 7, 8)
                cw, ch = (h, w) if turned else (w, h)
                s = max(cover[0] / cw, cover[1] / ch)
                image.draft('L', (math.ceil(w * s), math.ceil(h * s)) if s < 1 else None)
            image.load()
            picture = ImageOps.exif_transpose(image)
            if picture.mode in ('RGBA', 'LA', 'PA', 'RGBa', 'La') or 'transparency' in picture.info:
                # Transparent parts are paper.
                picture = picture.convert('RGBA')
                paper = Image.new('RGBA', picture.size, (255, 255, 255, 255))
                paper.alpha_composite(picture)
                picture = paper
            if picture.mode.startswith('I'):
                picture = picture.convert('I').point(lambda v: v / 257).convert('L')
            gray = ImageOps.grayscale(picture.convert('RGB'))
        except Exception:
            raise Unreadable('damaged: it could not be read') from None
    # A photo's tones spread over the whole range, as the shipped generated plates' are.
    gray = ImageOps.autocontrast(gray, cutoff=.3)
    s = max(cover[0] / gray.width, cover[1] / gray.height)
    if s < 1:
        gray = gray.resize((max(1, round(gray.width * s)), max(1, round(gray.height * s))), Image.Resampling.LANCZOS)
    return gray


def print_picture(ident, data, focus, ink, store):
    """Print one picture into the store: its gray source, masks and the shell's plates."""
    gray = normalize(data)
    (store / 'sources').mkdir(exist_ok=True)
    source = store / 'sources' / f'{ident}.png'
    save(gray, source)
    rendered = build.masks(source, {'id': ident, 'file': source.name, 'generated': False,
                                    'desktopFocus': focus, 'portraitFocus': focus})
    (store / 'art').mkdir(exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f'.{ident}-', dir=store / 'art'))
    try:
        for layout, mask in rendered.items():
            mask.convert('1', dither=Image.Dither.NONE).save(temporary / f'mask-{layout}.png', optimize=True)
            build.print_plate(mask, ink, build.PAPER[SHELL[1]], layout).save(temporary / f'{SHELL[0]}-{SHELL[1]}-{layout}.png')
        target = art_dir(ident, store)
        if target.is_dir() and not target.is_symlink(): shutil.rmtree(target)
        os.rename(temporary, target)
    finally:
        if temporary.exists(): shutil.rmtree(temporary)


def recipe():
    """What a picture's id depends on besides its bytes and focus: this version and the renderer's code."""
    return hashlib.sha256(VERSION + Path(render.__file__).read_bytes() + Path(build.__file__).read_bytes()).digest()


def ident_of(salt, focus, data):
    return 'mine-' + hashlib.sha256(salt + json.dumps(focus).encode() + data).hexdigest()[:16]


# ------------------------------------------------------------------ the folder

def _remove(entry):
    if entry.is_dir(follow_symlinks=False): shutil.rmtree(entry.path)
    else: os.unlink(entry.path)


def collect(store, renders, keep):
    """Forget the pictures no longer in the folder: their prints and DMS's renders of them."""
    for sub, pattern in (('art', ART_ID), ('sources', SOURCE)):
        if not (store / sub).is_dir(): continue
        with os.scandir(store / sub) as entries:
            for e in entries:
                m = pattern.fullmatch(e.name)
                # Leftovers of an interrupted print start with a dot.
                if (m and m.group(m.lastindex or 0) not in keep) or e.name.startswith('.mine-'):
                    _remove(e)
    if renders and renders.is_dir():
        with os.scandir(renders) as entries:
            for e in entries:
                m = RENDER.fullmatch(e.name)
                if m and m.group(1) not in keep: _remove(e)


def _write(store, doc, previous):
    if doc != previous:
        fd, name = tempfile.mkstemp(prefix='.catalog.json', dir=store)
        try:
            with os.fdopen(fd, 'w') as stream:
                json.dump(doc, stream, ensure_ascii=False, indent=1); stream.write('\n')
            os.replace(name, store / 'catalog.json')
        finally:
            if os.path.exists(name): os.unlink(name)
    return doc


def scan(ink, folder=None, store=None, renders=None, create=False, wait=True):
    """Bring the store in line with the folder; returns the catalog document.

    ink: the light azure every shell plate prints in (the catalog's).
    renders: DMS's per-display render cache, cleaned of removed pictures.
    wait: False returns the catalog as it is while another scan runs."""
    folder, store = folder or FOLDER, store or STORE
    if create: folder.mkdir(parents=True, exist_ok=True)
    store.mkdir(parents=True, exist_ok=True)
    os.chmod(store, 0o700)   # copies of personal pictures
    with open(store / '.lock', 'w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | (0 if wait else fcntl.LOCK_NB))
        except BlockingIOError:
            return read_catalog(store)
        return _scan(ink, folder, store, renders)


def _scan(ink, folder, store, renders):
    previous = read_catalog(store)
    old = _entries(previous)
    by_name = {a['name']: a for a in old if 'name' in a}
    salt = recipe()
    found, skipped = [], []
    arriving = 0
    now = time.time()
    # Written in the last moments: perhaps still being written. (A time in
    # the future, a camera's wrong clock, is not that.)
    def recent(info): return 0 <= now - info.st_mtime < SETTLE_SECONDS
    present = folder.is_dir()
    dirfd = os.open(folder, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC) if present else None
    try:
        entries = []
        if dirfd is not None:
            with os.scandir(dirfd) as it:
                entries = sorted(it, key=lambda e: (shown(e.name).casefold(), e.name))
        files = {e.name: e for e in entries}
        sidecars_used = set()

        def sidecar(e):
            """(name, {focus, title}) of the picture's sidecar, or (None, {})."""
            for candidate in (e.name + '.json', Path(e.name).stem + '.json'):
                s = files.get(candidate)
                if s is None: continue
                sidecars_used.add(candidate)
                try:
                    if recent(s.stat(follow_symlinks=False)): return candidate, None
                    return candidate, parse_sidecar(read_file(dirfd, candidate, SIDECAR_BYTES))
                except FileNotFoundError:
                    return None, {}
                except Unreadable as exc:
                    skipped.append({'name': shown(candidate), 'reason': str(exc) if str(exc).startswith('not used') else 'not used: ' + str(exc)})
                    return candidate, {}
            return None, {}

        for e in entries:
            if e.name.startswith('.') or e.name.lower().endswith('.json'): continue
            name = shown(e.name)
            if e.is_symlink():
                skipped.append({'name': name, 'reason': 'a link: copy the picture itself into the folder'}); continue
            if not e.is_file(follow_symlinks=False): continue
            if Path(e.name).suffix.lower() not in SUFFIXES:
                skipped.append({'name': name, 'reason': 'not a JPEG, PNG or WebP picture'}); continue
            if len(found) >= MAX_PICTURES:
                skipped.append({'name': name, 'reason': f'more than {MAX_PICTURES} pictures'}); continue
            try: info = e.stat(follow_symlinks=False)
            except FileNotFoundError: continue          # gone since the folder was listed
            sig = [info.st_size, info.st_mtime_ns, info.st_ino]
            known = by_name.get(name)
            kept = bool(known) and complete(known['id'], store)
            _, extra = sidecar(e)
            plate = {'name': name, 'file': e.name, 'slot': known['id'] if known else None, 'print': False}
            if extra is None or recent(info):
                # Still arriving: it keeps its old plate (and old signature,
                # so the next scan reads it again) or waits for that scan.
                arriving += 1
                if kept: found.append({**plate, 'id': known['id'], 'sig': known.get('sig'), 'title': known['title'],
                                       'focus': known['desktopFocus'], 'plateFocus': known['plateFocus']})
                continue
            focus = extra.get('focus') or CENTRE
            plate.update(title=extra.get('title') or title(e.name), focus=focus)
            if kept and known.get('sig') == sig and known['desktopFocus'] == focus:
                found.append({**plate, 'id': known['id'], 'sig': sig, 'plateFocus': known['plateFocus']}); continue
            try:
                data = read_file(dirfd, e.name)
                with opened(data): pass      # refused now, not when its turn to print comes
                ident = ident_of(salt, focus, data)
            except Unreadable as exc:
                skipped.append({'name': name, 'reason': str(exc)}); continue
            twin = next((f for f in found if f['id'] == ident), None)
            if twin:
                skipped.append({'name': name, 'reason': 'the same picture as ' + twin['name']}); continue
            ready = complete(ident, store)
            found.append({**plate, 'id': ident, 'sig': sig, 'print': not ready,
                          'plateFocus': plate_focus(ident, focus, store) if ready else None})
        for n in files:
            if n.lower().endswith('.json') and not n.startswith('.') and n not in sidecars_used:
                skipped.append({'name': shown(n), 'reason': 'a sidecar without its picture: name it like the picture, with .json'})
        # Keep the plates in the order they arrived, so a new picture never
        # moves the chosen one; a replaced file keeps its place. New ones
        # follow by name.
        order = {a['id']: i for i, a in enumerate(old)}
        found.sort(key=lambda f: order.get(f['slot'] or f['id'], len(order)))

        def document():
            ready = [f for f in found if not f['print']]
            return {'version': 1, 'folder': str(folder), 'present': present,
                    'pending': len(found) - len(ready), 'arriving': arriving,
                    'collection': {'id': ID, 'name': NAME, 'description': DESCRIPTION, 'art': [
                        {'id': f['id'], 'title': f['title'], 'name': f['name'], 'file': f['id'] + '.png',
                         'credit': CREDIT, 'desktopFocus': f['focus'], 'plateFocus': f['plateFocus'],
                         'generated': False, 'sig': f['sig']}
                        for f in ready]},
                    'skipped': skipped}

        collect(store, renders, {f['id'] for f in found})
        doc = _write(store, document(), previous)
        # One picture at a time, read again (only one is ever held in
        # memory); each appears as soon as it is printed.
        for f in [f for f in found if f['print']]:
            try:
                data = read_file(dirfd, f['file'])
                if ident_of(salt, f['focus'], data) != f['id']:
                    found.remove(f); arriving += 1     # changed since: the next scan takes it
                else:
                    print_picture(f['id'], data, f['focus'], ink, store)
                    f.update(print=False, plateFocus=plate_focus(f['id'], f['focus'], store))
            except Unreadable as exc:
                found.remove(f)
                skipped.append({'name': f['name'], 'reason': str(exc)})
            doc = _write(store, document(), doc)
        return doc
    finally:
        if dirfd is not None: os.close(dirfd)
