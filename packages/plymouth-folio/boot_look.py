#!/usr/bin/env python3
"""Interstellar's look on the boot partition: the disk-unlock screen follows the desktop.

The desktop's selection lives in the encrypted home. The greeter bridge
(modules/nixos/themeport.nix) publishes a root-owned, validated copy at
/var/lib/azure-folio/appearance.json. `publish` reads only that file and
keeps three values from it: the theme, the mode and one color, each checked
against the closed sets looks.py knows. It prints that look with build.py
into a private directory, packs it as a small initrd archive, and replaces
the file on the boot partition atomically. The boot loader loads that file
after NixOS's own initrd (modules/nixos/folio-boot.nix adds the entry line).

At boot, interstellar-boot-look-check in the initrd shows the archive's look
only if its manifest and every file in it check out. Otherwise Plymouth shows
the look built into the initrd. No published look means an empty file: the
built-in look.
"""
import argparse
import hashlib
import json
import os
import shutil
import stat
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build  # noqa: E402

THEME = 'interstellar-look'
STAGING = 'etc/interstellar/boot-look'   # in the initrd, beside nothing of NixOS's own
RUNTIME = '/run/interstellar/themes'     # where the check puts it, and Plymouth reads it
MAX_INPUT = 64 * 1024
FORMAT = 1


class LookError(ValueError):
    pass


# ------------------------------------------------------------------ the input

def validate(looks, look):
    """Exactly a theme, a mode and a color from the closed sets, or an error."""
    if not isinstance(look, dict):
        raise LookError('look must be an object')
    theme, mode, pick = look.get('theme'), look.get('mode'), look.get('pick')
    if type(theme) is not str or theme not in looks.THEMES:
        raise LookError('unknown theme')
    if type(mode) is not str or mode not in looks.MODES:
        raise LookError('unknown mode')
    if type(pick) is not str:
        raise LookError('unknown color')
    if pick in looks.NAMED[theme]:
        return theme, mode, pick
    # A custom color is exactly #rrggbb: no space, no newline, nothing else.
    if len(pick) == 7 and pick[0] == '#' and all(c in '0123456789abcdefABCDEF' for c in pick[1:]):
        return theme, mode, pick.lower()
    raise LookError('unknown color')


def read_appearance(path, owner=0):
    """The appearance file's raw bytes, or None when there is none yet.

    Refuses anything but a small regular file owned by `owner` and not
    writable by anyone else; never follows a symlink."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    except OSError as e:
        raise LookError(f'cannot open {path}: {e.strerror}') from None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise LookError('not a regular file')
        if info.st_uid != owner or info.st_mode & 0o022:
            raise LookError('not owned and written by root alone')
        if info.st_size > MAX_INPUT:
            raise LookError('too large')
        data = b''
        while len(data) <= MAX_INPUT:
            chunk = os.read(fd, MAX_INPUT + 1 - len(data))
            if not chunk:
                break
            data += chunk
    finally:
        os.close(fd)
    if len(data) > MAX_INPUT:
        raise LookError('too large')
    return data


def look_from(looks, data):
    """(theme, mode, pick) from the appearance document, or None when it
    carries no look: written by a bridge older than Interstellar's looks,
    which means the built-in look, as when nothing is published."""
    try:
        doc = json.loads(data.decode('utf-8'))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise LookError('not JSON') from None
    if not isinstance(doc, dict):
        raise LookError('not an object')
    if 'look' not in doc:
        return None
    return validate(looks, doc['look'])


# ------------------------------------------------------------------ the archive

def newc(entries):
    """A deterministic newc cpio: fixed inodes, owners and times."""
    out = bytearray()

    def pad(n):
        out.extend(b'\0' * (-n % 4))

    for ino, (name, mode, data) in enumerate(entries + [('TRAILER!!!', 0, b'')], start=1):
        body = data or b''
        raw = name.encode() + b'\0'
        fields = [ino if name != 'TRAILER!!!' else 0, mode, 0, 0,
                  2 if stat.S_ISDIR(mode) else 1, 0, len(body), 0, 0, 0, 0, len(raw), 0]
        header = b'070701' + b''.join(b'%08x' % v for v in fields)
        out += header + raw
        pad(len(header) + len(raw))
        out += body
        pad(len(body))
    return bytes(out)


def archive(theme_dir, look):
    """The look's files under STAGING, then its manifest, then the manifest's
    own checksum, last: an archive cut short anywhere lacks it."""
    files = {p.name: p.read_bytes() for p in sorted(Path(theme_dir).iterdir()) if p.is_file()}
    files['LOOK'] = (' '.join(look) + '\n').encode()
    names = sorted(files)
    manifest = ''.join(f'{hashlib.sha256(files[n]).hexdigest()}  {n}\n' for n in names).encode()
    check = f'{hashlib.sha256(manifest).hexdigest()}  MANIFEST\n'.encode()
    entries = [('etc/interstellar', stat.S_IFDIR | 0o755, None), (STAGING, stat.S_IFDIR | 0o755, None)]
    entries += [(f'{STAGING}/{n}', stat.S_IFREG | 0o644, files[n]) for n in names]
    entries += [(f'{STAGING}/MANIFEST', stat.S_IFREG | 0o644, manifest),
                (f'{STAGING}/MANIFEST.sha256', stat.S_IFREG | 0o644, check)]
    return newc(entries)


def render(args, look, out):
    looks = build.load_module('looks', args.looks)
    theme, mode, pick = look
    build.build(looks=looks, render=build.load_module('render', args.render), assets=args.assets,
                template=args.script.read_text(), out=out, name=args.name, theme=theme, mode=mode,
                pick=pick, art_id=args.art, sizes=build.parse_sizes(args.size),
                bold_font=args.bold_font, theme_name=THEME,
                install_dir=f'{RUNTIME}/{THEME}')


# ------------------------------------------------------------------ writing

def fsync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_atomic(path, data):
    """Replace `path` so a crash leaves the old file or the new one, never
    neither: a missing file would stop the boot loader at that entry."""
    path = Path(path)
    fd, tmp = tempfile.mkstemp(prefix=f'.{path.name}.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
        fsync_dir(path.parent)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def install_runtime(theme_dir, runtime):
    """Refresh the copy in /run that Plymouth uses for the shutdown page."""
    root = Path(runtime)
    root.mkdir(parents=True, exist_ok=True)
    new, old, live = root / f'.{THEME}.new', root / f'.{THEME}.old', root / THEME
    for d in (new, old):
        shutil.rmtree(d, ignore_errors=True)
    if theme_dir is not None:
        shutil.copytree(theme_dir, new)
    if live.exists():
        live.rename(old)
    if theme_dir is not None:
        new.rename(live)
    shutil.rmtree(old, ignore_errors=True)


def sha256_file(path):
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except FileNotFoundError:
        return None


def publish(args):
    looks = build.load_module('looks', args.looks)
    state = Path(args.state_dir) / 'published.json'
    # What prints the look: this code and everything fixed at build time
    # (a new system, another plate or name prints it again).
    tool = [str(Path(__file__).resolve())] + [str(v) for v in (
        args.assets, args.render, args.looks, args.script, args.bold_font, args.name, args.art)] + list(args.size)
    for _ in range(3):
        data = read_appearance(args.input, owner=args.owner)
        found = None if data is None else look_from(looks, data)
        look = None if found is None else list(found)
        try:
            stamp = json.loads(state.read_text())
        except (FileNotFoundError, ValueError):
            stamp = {}
        current = sha256_file(args.boot_file)
        # The copy in /run goes missing when the boot did not load the look
        # (an older generation): the shutdown page needs it back.
        runtime_ok = not args.runtime_dir or (look is None) == (not (Path(args.runtime_dir) / THEME).exists())
        if (stamp.get('format') == FORMAT and stamp.get('tool') == tool and stamp.get('look') == look
                and current is not None and stamp.get('sha256') == current and runtime_ok):
            print(f'Interstellar boot look: {" ".join(look) if look else "built-in"}, already on the boot partition')
            return
        with tempfile.TemporaryDirectory() as tmp:
            if look is None:
                blob, theme_dir = b'', None
            else:
                theme_dir = Path(tmp) / THEME
                render(args, look, theme_dir)
                blob = archive(theme_dir, look)
            write_atomic(args.boot_file, blob)
            if args.runtime_dir:
                install_runtime(theme_dir, args.runtime_dir)
        Path(args.state_dir).mkdir(parents=True, exist_ok=True)
        write_atomic(state, json.dumps({'format': FORMAT, 'tool': tool, 'look': look,
                                        'sha256': hashlib.sha256(blob).hexdigest()}).encode())
        print(f'Interstellar boot look: {" ".join(look) if look else "built-in"} '
              f'({len(blob)} bytes) written to {args.boot_file}')
        # The owner may have changed the look while it printed: once more.
        if read_appearance(args.input, owner=args.owner) == data:
            return
    print('Interstellar boot look: the look kept changing; the next change publishes it')


def overlay(args):
    looks = build.load_module('looks', args.looks)
    look = validate(looks, {'theme': args.theme, 'mode': args.mode, 'pick': args.pick})
    with tempfile.TemporaryDirectory() as tmp:
        theme_dir = Path(tmp) / THEME
        render(args, look, theme_dir)
        Path(args.out).write_bytes(archive(theme_dir, look))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for flag in ('--assets', '--render', '--looks', '--script', '--bold-font'):
        p.add_argument(flag, type=Path, required=True)
    p.add_argument('--name', required=True)
    p.add_argument('--art', required=True)
    p.add_argument('--size', action='append', required=True)
    sub = p.add_subparsers(dest='command', required=True)
    q = sub.add_parser('publish', help="write the published look to the boot partition")
    q.add_argument('--input', type=Path, required=True)
    q.add_argument('--boot-file', type=Path, required=True)
    q.add_argument('--state-dir', type=Path, required=True)
    q.add_argument('--runtime-dir', type=Path)
    q.add_argument('--owner', type=int, default=0, help=argparse.SUPPRESS)
    o = sub.add_parser('overlay', help='print one look as a boot archive (for tests)')
    o.add_argument('--theme', required=True)
    o.add_argument('--mode', required=True)
    o.add_argument('--pick', required=True)
    o.add_argument('--out', type=Path, required=True)
    args = p.parse_args(argv)
    try:
        (publish if args.command == 'publish' else overlay)(args)
    except LookError as e:
        sys.exit(f'Interstellar boot look: refusing {getattr(args, "input", "the look")}: {e}; '
                 'the boot partition keeps its last look')


if __name__ == '__main__':
    main()
