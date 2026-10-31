"""Interstellar's looks: every pick reads, and the shell agrees with apps.

Run: python3 tools/azure-folio/test_looks.py (the shell check needs node:
nix shell nixpkgs#nodejs -c python3 tools/azure-folio/test_looks.py).
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import looks

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
SHELL_LOOKS = REPO / 'dotfiles/quickshell/folio/Common/Looks.js'

# Hues all round the wheel at several lightnesses and chromas, plus grays and
# the corners of the cube, where gamut and contrast fight hardest.
PICKS = sorted({looks.lch(L, C, h) for h in range(0, 360, 20) for L in (0.35, 0.6, 0.85) for C in (0.05, 0.2)}
               | {'#000000', '#ffffff', '#808080', '#ffff00', '#00ffff', '#ff00ff', '#00ff00', '#0000ff', '#ff0000'})


def cases():
    for theme in looks.THEMES:
        for mode in looks.MODES:
            for pick in list(looks.NAMED[theme]) + PICKS:
                yield theme, mode, pick


class LookTests(unittest.TestCase):
    def test_folio_inks_are_the_catalog_inks(self):
        catalog = json.loads((REPO / 'assets/azure-folio/catalog.json').read_text())
        self.assertEqual({k: (v['light'], v['dark']) for k, v in catalog['inks'].items()}, looks.INKS)

    def test_named_inks_are_kept_exactly(self):
        for name, (light, dark) in looks.INKS.items():
            self.assertEqual(looks.derive('folio', 'light', name)[0], light)
            self.assertEqual(looks.derive('folio', 'dark', name)[0], dark)

    def test_every_pick_reads(self):
        for theme, mode, pick in cases():
            accent, on = looks.derive(theme, mode, pick)
            bg = looks.BACKGROUND[theme][mode]
            where = f'{theme} {mode} {pick} -> {accent}'
            if theme == 'folio':
                if pick not in looks.INKS:
                    self.assertGreaterEqual(looks.contrast(accent, bg), 7 if mode == 'light' else 9, where)
                self.assertEqual(on, bg)
            else:
                self.assertGreaterEqual(looks.contrast(accent, bg), 3, where)
                self.assertGreaterEqual(looks.contrast(on, accent), 4.5, where)

    def test_hue_is_kept(self):
        for theme, mode, pick in cases():
            L, C, h = looks.oklch(pick if pick.startswith('#') else looks.NAMED[theme][pick][0] if theme == 'folio' else looks.ACCENTS[pick])
            accent = looks.derive(theme, mode, pick)[0]
            L1, C1, h1 = looks.oklch(accent)
            if C > 0.04 and C1 > 0.04 and not (theme == 'folio' and pick in looks.INKS):
                self.assertLess(min(abs(h - h1), 360 - abs(h - h1)), 12, f'{theme} {mode} {pick} -> {accent}')

    def test_untrusted_picks_are_refused(self):
        for pick in ('#12345', '12345g', 'azure; id', '../x', '#ff00ff\n', '', 'blue'):
            if looks.valid_pick('folio', pick):
                self.fail(pick)
        self.assertTrue(looks.valid_pick('lumen', 'blue'))
        with self.assertRaises(ValueError):
            looks.derive('folio', 'light', '$(id)')

    def test_themeport_palettes(self):
        with tempfile.TemporaryDirectory() as d:
            looks.write_themeport('lumen', 'dark', '#d4ff00', d)
            for mode in looks.MODES:
                text = (Path(d) / f'interstellar-lumen-{mode}/colors.toml').read_text()
                self.assertIn(f'mode = "{mode}"', text)
                self.assertIn(f'accent = "{looks.derive("lumen", mode, "#d4ff00")[0]}"', text)
                self.assertIn(f'background = "{looks.BACKGROUND["lumen"][mode]}"', text)

    @unittest.skipUnless(shutil.which('node'), 'node is not installed')
    def test_shell_agrees(self):
        all_cases = list(cases())
        script = SHELL_LOOKS.read_text().replace('.pragma library', '', 1)
        runner = script + '\nconst cases = JSON.parse(require("fs").readFileSync(0, "utf8"));\n' \
            'process.stdout.write(JSON.stringify(cases.map(([t, m, p]) => derive(t, m, p))));\n'
        result = subprocess.run(['node', '-e', runner], input=json.dumps(all_cases), capture_output=True, text=True, check=True)
        for (theme, mode, pick), got in zip(all_cases, json.loads(result.stdout)):
            self.assertEqual(tuple(got), looks.derive(theme, mode, pick), f'{theme} {mode} {pick}')


if __name__ == '__main__':
    unittest.main()
