import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image
import azure_folio as folio
import render


class DisplayRenderingTests(unittest.TestCase):
    def test_current_mode_and_undocked_preferred_mode(self):
        outputs = {
            'DP-1': {'current_mode': 0, 'modes': [{'width': 3440, 'height': 1440}]},
            'eDP-1': {'current_mode': None, 'logical': None,
                      'modes': [{'width': 1920, 'height': 1200, 'is_preferred': True}]},
            'absent': {'modes': []},
        }
        self.assertEqual(folio.display_targets(outputs), {'DP-1': (3440, 1440), 'eDP-1': (1920, 1200)})
        outputs.pop('DP-1')
        self.assertEqual(folio.display_targets(outputs), {'eDP-1': (1920, 1200)})

    def test_rotation_uses_physical_pixels_not_scaled_logical_size(self):
        outputs = {'DP-2': {'current_mode': 0, 'modes': [{'width': 3840, 'height': 2160}],
                             'logical': {'width': 1080, 'height': 1920, 'transform': '90', 'scale': 2}}}
        self.assertEqual(folio.display_targets(outputs), {'DP-2': (2160, 3840)})

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

    def test_personal_wallpaper_survives_display_change(self):
        selection = folio.validate({})
        with patch.object(folio, 'ipc', return_value='/tmp/personal.png'), patch.object(folio, 'set_wallpaper') as apply:
            folio.refresh_wallpapers(selection)
            apply.assert_not_called()

    def test_one_transaction_publishes_same_art_to_all_displays(self):
        selection = folio.validate({'collection': 'summer', 'ink': 'slate'})
        outputs = {'DP-1': {'current_mode': 0, 'modes': [{'width': 3440, 'height': 1440}]},
                   'eDP-1': {'modes': [{'width': 1920, 'height': 1200, 'is_preferred': True}]}}
        def cached(data, cache, art, size, ink, paper):
            self.assertEqual((art['id'], ink, paper), ('summer-riviera', '#35556e', '#f7f4e9'))
            return Path('/tmp') / f'{art["id"]}-{size[0]}x{size[1]}.png'
        with patch.object(folio, 'monitor_outputs', return_value=outputs), patch.object(folio, 'render_cached', side_effect=cached), patch.object(folio, 'ipc', return_value='SUCCESS: updated') as ipc:
            folio.set_wallpaper(selection)
            args = ipc.call_args.args
            self.assertEqual(args[:2], ('folioWallpaper', 'apply'))
            self.assertEqual(json.loads(args[3]), {'DP-1': '/tmp/summer-riviera-3440x1440.png', 'eDP-1': '/tmp/summer-riviera-1920x1200.png'})
            self.assertEqual(ipc.call_count, 1)


if __name__ == '__main__': unittest.main()
