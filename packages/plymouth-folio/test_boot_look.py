"""Tests for the boot look: what may cross into the boot files, the archive,
and the initrd's check of it (boot-look-check.sh) against archives cut short
or damaged the way the kernel would unpack them.

Run by the plymouth-folio package's `tests` (BOOT_LOOK_ARGS holds the fixed
print arguments as JSON; BOOT_LOOK_CHECK is the initrd check script)."""
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

import boot_look
import build

LOOKS = build.load_module('looks', Path(__file__).with_name('looks.py'))
ARGS = json.loads(os.environ.get('BOOT_LOOK_ARGS', '[]'))
CHECK = os.environ.get('BOOT_LOOK_CHECK')


def doc(theme='lumen', mode='dark', pick='blue', **extra):
    return json.dumps({'theme': theme, 'mode': mode, 'look': {'theme': theme, 'mode': mode, 'pick': pick},
                       **extra}).encode()


def align(n):
    return n + (-n % 4)


def entries(blob):
    """Read a newc archive as the kernel does: (name, mode, data, complete)."""
    pos = 0
    while pos + 110 <= len(blob):
        header = blob[pos:pos + 110]
        if header[:6] != b'070701':
            raise ValueError('bad magic')
        f = [int(header[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
        mode, size, namesize = f[1], f[6], f[11]
        if pos + 110 + namesize > len(blob):
            return
        name = blob[pos + 110:pos + 110 + namesize - 1].decode()
        start = align(pos + 110 + namesize)
        data = blob[start:start + size]
        yield name, mode, data, len(data) == size
        if name == 'TRAILER!!!' or len(data) < size:
            return
        pos = align(start + size)


def unpack(blob, root):
    """What the kernel leaves in the initrd from `blob`: directories, files
    in order, and a cut-short last file as far as it got."""
    for name, mode, data, _ in entries(blob):
        if name == 'TRAILER!!!':
            break
        path = Path(root) / name
        if stat.S_ISDIR(mode):
            path.mkdir(exist_ok=True)
        else:
            path.write_bytes(data)


class Validation(unittest.TestCase):
    def ok(self, data):
        return boot_look.look_from(LOOKS, data)

    def bad(self, data):
        with self.assertRaises(boot_look.LookError):
            boot_look.look_from(LOOKS, data)

    def test_named_and_custom_colors(self):
        self.assertEqual(self.ok(doc('folio', 'dark', 'azure')), ('folio', 'dark', 'azure'))
        self.assertEqual(self.ok(doc('lumen', 'light', 'graphite')), ('lumen', 'light', 'graphite'))
        self.assertEqual(self.ok(doc('lumen', 'light', '#FF00Ff')), ('lumen', 'light', '#ff00ff'))
        self.assertEqual(self.ok(doc('folio', 'light', '#8a2be2')), ('folio', 'light', '#8a2be2'))

    def test_what_azure_folio_publishes(self):
        # appearance.json carries look = looks.resolve(theme, mode, pick).
        data = json.dumps({'theme': 'lumen', 'mode': 'dark', 'look': LOOKS.resolve('lumen', 'dark', '#12ab34'),
                           'images': [{'desktop': '/x.png'}], 'paper': '#101d33'}).encode()
        self.assertEqual(self.ok(data), ('lumen', 'dark', '#12ab34'))

    def test_bad_json(self):
        for data in (b'', b'{', b'{"look": }', b'\xff\xfe', b'null', b'[]', b'"lumen"', b'{"look": null}',
                     b'{"look": "lumen dark blue"}', b'{"look": {}}'):
            with self.subTest(data=data):
                self.bad(data)

    def test_no_look_yet(self):
        # A bridge older than Interstellar's looks writes no `look`: the
        # built-in look, as when nothing has been published.
        old = json.dumps({'collection': 'dore', 'mode': 'dark', 'ink': 'azure', 'art': 0, 'images': []}).encode()
        self.assertIsNone(self.ok(old))
        self.assertIsNone(self.ok(b'{}'))

    def test_unknown_theme_and_mode(self):
        for theme, mode in (('pond', 'dark'), ('Folio', 'dark'), ('', 'dark'), ('lumen', 'dim'),
                            ('lumen', 'Dark'), ('lumen', '')):
            with self.subTest(theme=theme, mode=mode):
                self.bad(doc(theme, mode, 'blue'))

    def test_colors_must_be_exact(self):
        for pick in ('#ff00ff\n', ' #ff00ff', '#ff00ff ', '#ff00f', '#ff00ffa', 'ff00ff', '#gg00ff',
                     '#ff00ff\x00', '#ff\n00ff', 'rgb(1,2,3)', '', 'azure', '../x', '#ＦＦ00ff'):
            with self.subTest(pick=pick):
                self.bad(doc('lumen', 'dark', pick))
        # A name belongs to its own theme only.
        self.bad(doc('folio', 'dark', 'blue'))
        self.bad(doc('lumen', 'dark', 'azure'))

    def test_types(self):
        for value in (True, 7, None, ['blue'], {'blue': 1}):
            with self.subTest(value=value):
                self.bad(json.dumps({'look': {'theme': 'lumen', 'mode': 'dark', 'pick': value}}).encode())
                self.bad(json.dumps({'look': {'theme': value, 'mode': 'dark', 'pick': 'blue'}}).encode())
                self.bad(json.dumps({'look': {'theme': 'lumen', 'mode': value, 'pick': 'blue'}}).encode())


class Input(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.path = self.dir / 'appearance.json'

    def read(self, owner=None):
        return boot_look.read_appearance(self.path, owner=os.getuid() if owner is None else owner)

    def test_missing_means_none(self):
        self.assertIsNone(self.read())

    def test_regular_file(self):
        self.path.write_bytes(doc())
        os.chmod(self.path, 0o644)
        self.assertEqual(self.read(), doc())

    def test_symlink_refused(self):
        target = self.dir / 'real.json'
        target.write_bytes(doc())
        self.path.symlink_to(target)
        with self.assertRaises(boot_look.LookError):
            self.read()

    def test_oversized_refused(self):
        self.path.write_bytes(b' ' * (boot_look.MAX_INPUT + 1))
        os.chmod(self.path, 0o644)
        with self.assertRaises(boot_look.LookError):
            self.read()
        self.path.write_bytes(doc() + b' ' * (boot_look.MAX_INPUT - len(doc())))
        self.assertEqual(len(self.read()), boot_look.MAX_INPUT)

    def test_directory_and_fifo_refused(self):
        self.path.mkdir()
        with self.assertRaises(boot_look.LookError):
            self.read()
        self.path.rmdir()
        os.mkfifo(self.path)
        with self.assertRaises(boot_look.LookError):
            self.read()  # and does not wait for a writer

    def test_owner_and_writers(self):
        self.path.write_bytes(doc())
        os.chmod(self.path, 0o644)
        with self.assertRaises(boot_look.LookError):
            self.read(owner=os.getuid() + 1)
        for mode in (0o664, 0o646):
            os.chmod(self.path, mode)
            with self.assertRaises(boot_look.LookError):
                self.read()


def theme_dir(root):
    d = Path(root) / boot_look.THEME
    d.mkdir()
    (d / f'{boot_look.THEME}.plymouth').write_text('[Plymouth Theme]\nModuleName=script\n')
    (d / f'{boot_look.THEME}.script').write_text('Window.SetBackgroundTopColor(0, 0, 0);\n')
    for i in range(3):
        (d / f'art-{i}.png').write_bytes(hashlib.sha256(bytes([i])).digest() * (200 + 37 * i))
    return d


class Archive(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.look = ('lumen', 'dark', '#12ab34')
        self.blob = boot_look.archive(theme_dir(self.tmp), self.look)

    def test_deterministic(self):
        self.assertEqual(self.blob, boot_look.archive(self.tmp / boot_look.THEME, self.look))

    def test_layout(self):
        names = [n for n, *_ in entries(self.blob)]
        self.assertEqual(names[:2], ['etc/interstellar', boot_look.STAGING])
        self.assertEqual(names[-3:], [f'{boot_look.STAGING}/MANIFEST', f'{boot_look.STAGING}/MANIFEST.sha256',
                                      'TRAILER!!!'])
        # Nothing outside its own directory, nothing NixOS's initrd has.
        for n in names[2:-1]:
            self.assertTrue(n.startswith(boot_look.STAGING + '/') and '/' not in n[len(boot_look.STAGING) + 1:], n)
        self.assertEqual(len(self.blob) % 4, 0)
        for name, mode, data, complete in entries(self.blob):
            self.assertTrue(complete)
            if name != 'TRAILER!!!':
                self.assertIn(stat.S_IMODE(mode), (0o644, 0o755))

    def test_manifest(self):
        files = {n.rsplit('/', 1)[-1]: d for n, m, d, _ in entries(self.blob) if stat.S_ISREG(m)}
        self.assertEqual(files['LOOK'], b'lumen dark #12ab34\n')
        lines = files['MANIFEST'].decode().splitlines()
        listed = {line.split('  ')[1]: line.split('  ')[0] for line in lines}
        self.assertEqual(set(listed), set(files) - {'MANIFEST', 'MANIFEST.sha256'})
        for name, digest in listed.items():
            self.assertEqual(hashlib.sha256(files[name]).hexdigest(), digest)
        self.assertEqual(files['MANIFEST.sha256'].decode(),
                         f'{hashlib.sha256(files["MANIFEST"]).hexdigest()}  MANIFEST\n')


@unittest.skipUnless(CHECK, 'BOOT_LOOK_CHECK not set')
class InitrdCheck(unittest.TestCase):
    """boot-look-check.sh against what the kernel leaves in the initrd."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.src = theme_dir(self.tmp)
        self.blob = boot_look.archive(self.src, ('folio', 'light', 'cobalt'))

    def check(self, blob):
        root = Path(tempfile.mkdtemp(dir=self.tmp))
        (root / 'etc').mkdir()
        if blob is not None:
            unpack(blob, root)
        themes = root / 'run/interstellar/themes'
        env = {**os.environ, 'INTERSTELLAR_STAGING': str(root / boot_look.STAGING), 'INTERSTELLAR_THEMES': str(themes)}
        proc = subprocess.run(['bash', '-e', CHECK], env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        live = themes / boot_look.THEME
        return proc.stdout, (live if live.exists() else None)

    def assertComplete(self, live):
        for p in self.src.iterdir():
            self.assertEqual((live / p.name).read_bytes(), p.read_bytes(), p.name)
        self.assertEqual((live / 'LOOK').read_text(), 'folio light cobalt\n')

    def test_valid_archive_is_shown(self):
        out, live = self.check(self.blob)
        self.assertIn('showing the look on the boot partition: folio light cobalt', out)
        self.assertComplete(live)
        self.assertEqual(sorted(p.name for p in live.parent.iterdir()), [boot_look.THEME])

    def test_no_archive_or_empty_archive(self):
        for blob in (None, b'', boot_look.newc([])):
            out, live = self.check(blob)
            self.assertIn('no look on the boot partition', out)
            self.assertIsNone(live)

    def test_cut_short_anywhere(self):
        # Whatever a cut leaves, Plymouth gets the whole look or none of it,
        # never a partial theme. Before the manifest's checksum is in, none;
        # once only the trailer is missing, all of it.
        whole = len(self.blob)
        trailer = whole - align(110 + len('TRAILER!!!') + 1)
        last = trailer - align(len(b'0' * 64 + b'  MANIFEST\n'))  # where the checksum's data starts
        cuts = set(range(0, whole, 61)) | set(range(last - 4, trailer + 4)) | {whole - 1}
        for cut in sorted(cuts):
            with self.subTest(cut=cut):
                out, live = self.check(self.blob[:cut])
                if live is not None:
                    self.assertComplete(live)
                else:
                    self.assertRegex(out, 'refusing|no look')
                if cut < last + 64:
                    self.assertIsNone(live, out)
                if cut >= trailer:
                    self.assertIsNotNone(live, out)

    def test_damaged_files_are_refused(self):
        names = [(n, i) for i, (n, m, d, _) in enumerate(entries(self.blob)) if stat.S_ISREG(m)]
        for name, _ in names:
            with self.subTest(name=name):
                files = []
                for n, m, d, _ in entries(self.blob):
                    if n == name:
                        d = d[:-1] + bytes([d[-1] ^ 0x20])
                    files.append((n, m, d))
                out, live = self.check(boot_look.newc(files[:-1]))
                self.assertIsNone(live, out)
                self.assertIn('refusing', out)

    def test_hostile_manifest_is_refused(self):
        def forged(listing):
            manifest = listing.encode()
            check = f'{hashlib.sha256(manifest).hexdigest()}  MANIFEST\n'.encode()
            s = boot_look.STAGING
            return boot_look.newc([('etc/interstellar', 0o40755, None), (s, 0o40755, None),
                                   (f'{s}/MANIFEST', 0o100644, manifest), (f'{s}/MANIFEST.sha256', 0o100644, check)])
        empty = hashlib.sha256(b'').hexdigest()
        for listing in (f'{empty}  ../../../../etc/passwd\n', f'{empty}  /etc/passwd\n', f'{empty}  MANIFEST\n',
                        f'{empty}  -rf\n', f'{empty}  a b\n', 'not a manifest\n', '',
                        f'{empty}  {boot_look.THEME}.plymouth\n'):
            with self.subTest(listing=listing):
                out, live = self.check(forged(listing))
                self.assertIsNone(live, out)

    def test_wrong_manifest_name_is_refused(self):
        files = [(n, m, d) for n, m, d, _ in entries(self.blob)][:-1]
        n, m, d = files[-1]
        files[-1] = (n, m, d.replace(b'  MANIFEST', b'  LOOK'))
        out, live = self.check(boot_look.newc(files))
        self.assertIsNone(live, out)


@unittest.skipUnless(ARGS and CHECK, 'BOOT_LOOK_ARGS not set')
class Publish(unittest.TestCase):
    """publish, rendering for real: missing, valid, unchanged and refused input."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.input = self.tmp / 'appearance.json'
        self.boot = self.tmp / 'esp/EFI/interstellar/look.cpio'
        self.boot.parent.mkdir(parents=True)
        self.state = self.tmp / 'state'
        self.runtime = self.tmp / 'run/interstellar/themes'

    def publish(self):
        boot_look.main(ARGS + ['publish', '--input', str(self.input), '--boot-file', str(self.boot),
                               '--state-dir', str(self.state), '--runtime-dir', str(self.runtime),
                               '--owner', str(os.getuid())])

    def test_publish(self):
        # No look published yet: an empty archive, the built-in look.
        self.publish()
        self.assertEqual(self.boot.read_bytes(), b'')
        self.assertFalse((self.runtime / boot_look.THEME).exists())

        # A look: an archive the initrd check accepts, and the copy in /run.
        self.input.write_bytes(doc('lumen', 'light', '#ff6a00'))
        os.chmod(self.input, 0o644)
        self.publish()
        blob = self.boot.read_bytes()
        files = {n.rsplit('/', 1)[-1]: d for n, m, d, _ in entries(blob) if stat.S_ISREG(m)}
        self.assertEqual(files['LOOK'], b'lumen light #ff6a00\n')
        self.assertIn(b'ImageDir=/run/interstellar/themes/interstellar-look\n', files['interstellar-look.plymouth'])
        self.assertIn(b'theme = "lumen";', files['interstellar-look.script'])
        self.assertIn('art-1920x1200.png', files)
        live = self.runtime / boot_look.THEME
        self.assertEqual((live / 'interstellar-look.script').read_bytes(), files['interstellar-look.script'])
        root = self.tmp / 'initrd'
        (root / 'etc').mkdir(parents=True)
        unpack(blob, root)
        env = {**os.environ, 'INTERSTELLAR_STAGING': str(root / boot_look.STAGING),
               'INTERSTELLAR_THEMES': str(root / 'run/themes')}
        proc = subprocess.run(['bash', '-e', CHECK], env=env, capture_output=True, text=True, check=True)
        self.assertIn('showing the look on the boot partition: lumen light #ff6a00', proc.stdout)

        # The same look again: nothing is rewritten.
        before = self.boot.stat()
        self.publish()
        after = self.boot.stat()
        self.assertEqual((before.st_ino, before.st_mtime_ns), (after.st_ino, after.st_mtime_ns))

        # A boot that did not load the look leaves no copy in /run: it comes
        # back, with the same archive.
        shutil.rmtree(live)
        self.publish()
        self.assertTrue((live / 'interstellar-look.script').exists())
        self.assertEqual(self.boot.read_bytes(), blob)

        # A refused file leaves the boot partition as it was.
        for bad in (b'{', doc('lumen', 'light', '#ff6a00\n'), doc('pond', 'dark', 'blue')):
            self.input.write_bytes(bad)
            with self.assertRaises(SystemExit) as e:
                self.publish()
            self.assertNotEqual(e.exception.code, 0)
            self.assertEqual(self.boot.read_bytes(), blob)

        # Back to no look: the empty archive again, and /run follows.
        self.input.unlink()
        self.publish()
        self.assertEqual(self.boot.read_bytes(), b'')
        self.assertFalse(live.exists())


if __name__ == '__main__':
    unittest.main()
