import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image
import azure_folio as folio
import render

# Never the owner's own pictures: an empty store.
_none = tempfile.TemporaryDirectory()
folio.pictures.STORE = Path(_none.name) / 'store'


class DisplayRenderingTests(unittest.TestCase):
    def test_ultrawide_crop_preserves_focus_and_stays_inside_master(self):
        box = render.crop_box((1038, 1280), (3440, 1440), [.5, .66])
        self.assertAlmostEqual((box[2] - box[0]) / (box[3] - box[1]), 3440 / 1440)
        self.assertLess(box[1], 1280 * .66)
        self.assertGreater(box[3], 1280 * .66)
        self.assertGreaterEqual(box[0], 0)
        self.assertLessEqual(box[3], 1280)
        self.assertEqual(render.crop_box((1600, 1000), (1920, 1200), [.5, .6]), (0, 0, 1600, 1000))

    def test_native_size_exact_colors_and_palette_reuses_dither(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory); (data / 'sources').mkdir()
            Image.linear_gradient('L').resize((80, 60)).save(data / 'sources/test.png')
            art = {'id': 'test', 'file': 'test.png', 'generated': False, 'desktopFocus': [.5, .5]}
            cache = data / 'cache'
            path = render.render_cached(data, cache, art, (120, 50), '#35556e', '#f7f4e9')
            with Image.open(path) as image:
                self.assertEqual(image.size, (120, 50))
                self.assertEqual(set(image.getdata()), {(53, 85, 110), (247, 244, 233)})
            with patch.object(render, 'desktop_mask', side_effect=AssertionError('Mask must be reused')):
                self.assertEqual(render.render_cached(data, cache, art, (120, 50), '#35556e', '#f7f4e9'), path)
                dark = render.render_cached(data, cache, art, (120, 50), '#adc3d2', '#101d33')
                self.assertTrue(dark.is_file())
                self.assertNotEqual(dark, path)

    def test_folio_sets_the_plate_as_the_gnome_wallpaper(self):
        selection = folio.validate({'collection': 'summer', 'ink': 'slate'})
        with patch.object(folio.subprocess, 'run') as run:
            selected = folio.set_wallpaper(selection)
        self.assertEqual(run.call_args.args[0], ['mariano-set-wallpaper', selected])
        self.assertTrue(selected.endswith('summer-riviera/slate-light-desktop.png'))


if __name__ == '__main__': unittest.main()
