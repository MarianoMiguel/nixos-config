import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('folio',Path(__file__).with_name('azure_folio.py'))
folio=importlib.util.module_from_spec(spec);spec.loader.exec_module(folio)

class AppearanceTests(unittest.TestCase):
    def test_all_choices_resolve_to_shipped_artwork(self):
        cat=folio.catalog()
        self.assertEqual([x['id'] for x in cat['collections']],['dore','summer','argentina','ronin'])
        for collection in cat['collections']:
            for mode in ['light','dark']:
                for ink in ['azure','cobalt','slate']:
                    choice=folio.validate({'collection':collection['id'],'mode':mode,'ink':ink})
                    doc=folio.appearance(choice)
                    self.assertEqual(len(doc['images']),2)
                    for art in doc['images']:
                        for key in ['portrait','desktop']:
                            self.assertTrue(Path(art[key]).is_file(),art[key])
                            self.assertTrue(Path(art[key]).is_relative_to(folio.DATA))

    def test_untrusted_state_cannot_inject_paths_or_commands(self):
        for raw in [{'collection':'../../tmp'},{'mode':'light; id'},{'ink':'#ff0000'},{'art':-1},{'art':True},{'art':999},{'randomLogin':'false'}]:
            with self.assertRaises(ValueError): folio.validate(raw)
        clean=folio.validate({'path':'/etc/shadow','command':'id','images':[{'portrait':'/etc/shadow'}]})
        self.assertNotIn('path',clean);self.assertNotIn('images',clean)

    def test_publisher_reconstructs_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'selection.json';output=Path(directory)/'public.json'
            source.write_text(json.dumps({'collection':'argentina','mode':'dark','ink':'slate','images':['/tmp/untrusted']}))
            folio.publish(source,output)
            doc=json.loads(output.read_text())
            self.assertEqual(doc['collectionName'],'Argentina')
            self.assertTrue(all('/art/argentina-' in item['portrait'] for item in doc['images']))
            self.assertNotIn('/tmp/untrusted',output.read_text())

    def test_publisher_rejects_symlinks_and_oversized_requests(self):
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'target';target.write_text('{}')
            link=Path(directory)/'link';link.symlink_to(target)
            with self.assertRaises(ValueError):folio.publish(link,Path(directory)/'out')
            target.write_text(' '*4097)
            with self.assertRaises(ValueError):folio.publish(target,Path(directory)/'out')

    def test_missing_selection_publishes_daylight_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'public.json'
            folio.publish(Path(directory)/'missing',output)
            doc=json.loads(output.read_text())
            self.assertEqual((doc['collection'],doc['mode'],doc['ink']),('dore','light','azure'))
            self.assertTrue(doc['randomLogin'])

if __name__=='__main__':unittest.main()
