import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('folio',Path(__file__).with_name('azure_folio.py'))
folio=importlib.util.module_from_spec(spec);spec.loader.exec_module(folio)
pictures=folio.pictures

# Never the owner's own pictures or cache: every test points both at a
# temporary folder (PicturesTests) or at nothing.
_none=tempfile.TemporaryDirectory()
pictures.FOLDER=Path(_none.name)/'Pictures/Folio';pictures.STORE=Path(_none.name)/'store';folio.CACHE=Path(_none.name)/'renders';folio.STATE=Path(_none.name)/'selection.json'

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

    def test_themes_and_custom_colors(self):
        self.assertEqual(folio.validate({})['theme'],'folio')
        choice=folio.validate({'theme':'lumen','accent':'custom','customAccent':'#D4FF00','ink':'custom','customInk':'#e8590c'})
        self.assertEqual(folio.pick(choice),'#d4ff00');self.assertEqual(folio.pick(choice,'folio'),'#e8590c')
        doc=folio.appearance(choice)
        self.assertEqual(doc['look']['theme'],'lumen')
        self.assertEqual(doc['inkColor'],folio.looks.derive('folio',choice['mode'],'#e8590c')[0])
        for art in doc['images']: self.assertTrue(Path(art['portrait']).is_file(),art['portrait'])
        # A named color keeps the custom one for later.
        self.assertEqual(folio.pick(folio.validate({'ink':'cobalt','customInk':'#e8590c'})),'cobalt')
        self.assertEqual(folio.validate({})['sky'],'orbit');self.assertEqual(folio.validate({'sky':'haze'})['sky'],'haze')
        for raw in [{'sky':'stars'},{'sky':'haze\n'},{'theme':'gnome'},{'accent':'#ff0000'},{'ink':'custom'},{'accent':'custom'},{'customInk':'#ff00ff\n'},{'customAccent':'red'},{'customInk':'$(id)'}]:
            with self.assertRaises(ValueError,msg=raw): folio.validate(raw)

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


SMALL={'desktop':(192,120),'portrait':(96,120)}
AZURE_LIGHT=folio.catalog(mine=False)['inks']['azure']['light']


class PicturesTests(unittest.TestCase):
    """Your pictures: a folder of the owner's, printed into a store in the cache."""
    def setUp(self):
        from PIL import Image, ImageDraw
        self.Image=Image
        self.tmp=tempfile.TemporaryDirectory();root=Path(self.tmp.name)
        self.folder=root/'Pictures/Folio';self.folder.mkdir(parents=True)
        self.store=root/'cache/azure-folio/pictures';self.renders=root/'cache/azure-folio/wallpapers'
        self.state=root/'state/selection.json'
        for p in [patch.object(pictures,'FOLDER',self.folder),patch.object(pictures,'STORE',self.store),
                  patch.object(folio,'CACHE',self.renders),patch.object(folio,'STATE',self.state),
                  patch.object(pictures,'SETTLE_SECONDS',0),patch.dict(pictures.build.SIZES,SMALL)]:
            p.start();self.addCleanup(p.stop)
        self.addCleanup(self.tmp.cleanup)

    def picture(self,name,size=(320,200),shade=0):
        image=self.Image.linear_gradient('L').resize(size).convert('RGB')
        self.Image.Image.paste(image,(shade,shade,shade),(size[0]//3,size[1]//3,size[0]//2,size[1]//2))
        image.save(self.folder/name);return self.folder/name

    def scan(self):
        return folio.scan_pictures()

    def reasons(self,doc):
        return {s['name']:s['reason'] for s in doc['skipped']}

    def test_folder_becomes_a_collection_and_a_selection(self):
        self.picture('first_light.png');self.picture('second.jpg',(200,320),90)
        (self.folder/'second.json').write_text(json.dumps({'focus':[0.72,0.4],'title':'All eyez'}))
        doc=self.scan()
        art=doc['collection']['art']
        self.assertEqual([a['title'] for a in art],['first light','All eyez'])
        self.assertEqual(art[1]['desktopFocus'],[0.72,0.4])
        mine=folio.collection_of({'collection':'mine'},folio.catalog())
        self.assertEqual((mine['name'],mine['art'][0]['credit']),('Your pictures','Your picture'))
        # The shell's plates: the light azure render, two colors, at plate size.
        for a in art:
            for layout,size in SMALL.items():
                with self.Image.open(self.store/'art'/a['id']/f'azure-light-{layout}.png') as plate:
                    self.assertEqual(plate.size,size)
                    self.assertEqual({c for _,c in plate.convert('RGB').getcolors()},{(33,76,148),(247,244,233)})
        # Chosen, as `azure-folio set --collection mine --art 1` chooses it.
        choice=folio.validate({'collection':'mine','art':1,'mode':'dark','ink':'slate'})
        with self.assertRaises(ValueError): folio.validate({'collection':'mine','art':2})
        doc=folio.appearance(choice)
        self.assertEqual(doc['collectionName'],'Your pictures')
        self.assertTrue(all(Path(i['desktop']).is_relative_to(self.store) for i in doc['images']))
        folio.ensure_prints(choice)
        self.assertTrue(Path(doc['images'][1]['desktop']).is_file());self.assertTrue(Path(doc['images'][1]['portrait']).is_file())
        # DMS's per-display renders crop the gray source, as for shipped plates.
        outputs={'eDP-1':{'current_mode':0,'modes':[{'width':160,'height':100}]}}
        rendered=Path(folio.render_wallpapers(choice,outputs)['eDP-1'])
        self.assertTrue(rendered.is_relative_to(self.renders))
        with self.Image.open(rendered) as image:
            self.assertEqual(image.size,(160,100))
            self.assertEqual(len(image.convert('RGB').getcolors()),2)

    def test_cli_sets_a_picture(self):
        self.picture('a.png');self.picture('b.png',shade=200)
        self.scan()
        with patch.object(folio,'apply') as apply, patch('sys.argv',['azure-folio','set','--collection','mine','--art','1']):
            folio.main()
        selection=apply.call_args.args[0]
        self.assertEqual((selection['collection'],selection['art']),('mine',1))
        with patch('sys.argv',['azure-folio','set','--collection','mine','--art','2']), self.assertRaises(ValueError):
            folio.main()

    def test_untrusted_files_are_refused(self):
        outside=Path(self.tmp.name)/'outside.png'
        self.Image.new('RGB',(64,64)).save(outside)
        (self.folder/'link.png').symlink_to(outside)
        (self.folder/'notes.jpg').write_text('not a picture')
        self.Image.new('RGB',(64,64)).save(self.folder/'moving.png',format='GIF')
        self.Image.new('1',(8000,8000)).save(self.folder/'bomb.png')      # 64 MP, a few kB
        self.Image.new('RGB',(8,8)).save(self.folder/'tiny.png')
        (self.folder/'later.psd').write_bytes(b'8BPS')
        (self.folder/'.hidden.png').write_bytes(outside.read_bytes())
        (self.folder/'sub').mkdir();self.Image.new('RGB',(64,64)).save(self.folder/'sub/deep.png')
        self.picture('ok.png')
        written=[];write=pictures._write
        with patch.object(pictures,'_write',side_effect=lambda s,d,p:(written.append(d['pending']),write(s,d,p))[1]):
            doc=self.scan()
        reasons=self.reasons(doc)
        self.assertEqual([a['name'] for a in doc['collection']['art']],['ok.png'])
        # Refused at once (headers only): never counted as printing.
        self.assertEqual(written,[1,0])
        self.assertIn('link',reasons['link.png'])
        self.assertIn('not a JPEG, PNG or WebP',reasons['notes.jpg'])
        self.assertIn('not a JPEG, PNG or WebP',reasons['moving.png'])
        self.assertIn('not a JPEG, PNG or WebP',reasons['later.psd'])
        self.assertEqual(reasons['bomb.png'],'too many pixels')
        self.assertEqual(reasons['tiny.png'],'too small')
        self.assertNotIn('.hidden.png',reasons);self.assertNotIn('sub',reasons)
        # Nothing of the link's target was printed or copied.
        self.assertEqual(len(list((self.store/'sources').iterdir())),1)
        # Larger than the limit: never read whole.
        self.picture('big.png',(640,480),30)
        with patch.object(pictures,'MAX_BYTES',(self.folder/'big.png').stat().st_size-1):
            self.assertIn('larger than',self.reasons(self.scan())['big.png'])

    def test_sidecars_are_checked_strictly(self):
        for name,body in [('a','{"focus": [1.2, 0.5]}'),('b','{"focus": [0.5, NaN]}'),('c','{"title": "x", "path": "/etc"}'),
                          ('d','{"title": "'+'x'*81+'"}'),('e','{"focus": [true, 0.5]}'),('f','[0.5, 0.5]'),('g','{"title": "ok\\u0007"}')]:
            self.picture(name+'.png',shade=ord(name));(self.folder/(name+'.json')).write_text(body)
        self.picture('h.png',shade=9)
        (Path(self.tmp.name)/'h.json').write_text('{"focus": [0.1, 0.1]}');(self.folder/'h.png.json').symlink_to(Path(self.tmp.name)/'h.json')
        (self.folder/'nobody.json').write_text('{}')
        doc=self.scan();reasons=self.reasons(doc)
        for name in 'abcdefg': self.assertTrue(reasons[name+'.json'].startswith('not used'),name)
        self.assertIn('link',reasons['h.png.json'])
        self.assertIn('without its picture',reasons['nobody.json'])
        # Each picture is still used, centred and titled by its name.
        art=doc['collection']['art']
        self.assertEqual(len(art),8)
        self.assertTrue(all(a['desktopFocus']==[.5,.5] for a in art))
        self.assertEqual(sorted(a['title'] for a in art),list('abcdefgh'))

    def test_store_follows_the_folder(self):
        self.picture('b.png');doc=self.scan();first=doc['collection']['art'][0]['id']
        choice=folio.validate({'collection':'mine','art':0})
        folio.render_wallpapers(choice,{'eDP-1':{'current_mode':0,'modes':[{'width':64,'height':40}]}})
        # A rename prints nothing again; a new picture never moves the first.
        os.rename(self.folder/'b.png',self.folder/'renamed.png');self.picture('a.png',shade=128)
        with patch.object(pictures,'print_picture',wraps=pictures.print_picture) as printed:
            doc=self.scan()
        self.assertEqual(printed.call_count,1)
        self.assertEqual([(a['id'],a['title']) for a in doc['collection']['art']][0],(first,'renamed'))
        self.assertEqual(doc['collection']['art'][1]['title'],'a')
        # A new focus is a new print, in the same place.
        (self.folder/'renamed.json').write_text('{"focus": [0.2, 0.3]}')
        doc=self.scan();self.assertNotEqual(doc['collection']['art'][0]['id'],first);self.assertEqual(doc['collection']['art'][0]['title'],'renamed')
        # Gone from the folder: gone from the store and from DMS's renders.
        for f in self.folder.iterdir(): f.unlink()
        doc=self.scan()
        self.assertEqual(doc['collection']['art'],[])
        self.assertEqual(list((self.store/'art').iterdir()),[]);self.assertEqual(list((self.store/'sources').iterdir()),[])
        self.assertFalse(any(p.name.startswith('mine-') for p in self.renders.iterdir()))
        self.assertIsNone(pictures.collection())

    def test_a_choice_of_missing_pictures_falls_back(self):
        self.picture('only.png');self.scan()
        self.state.parent.mkdir(parents=True)
        self.state.write_text(json.dumps({'collection':'mine','art':3,'mode':'dark'}))
        selection=folio.read_selection()
        self.assertEqual((selection['collection'],selection['art']),('mine',0))
        (self.folder/'only.png').unlink();self.scan()
        selection=folio.read_selection()
        self.assertEqual((selection['collection'],selection['art'],selection['mode']),('dore',0,'dark'))
        with self.assertRaises(ValueError): folio.validate({'collection':'mine'})

    def test_greeter_and_boot_never_read_pictures(self):
        self.picture('one.png');self.picture('two.png',shade=50);self.scan()
        self.state.parent.mkdir(parents=True)
        for theme in ['folio','lumen']:
            self.state.write_text(json.dumps({'collection':'mine','art':1,'mode':'dark','ink':'slate','theme':theme,'accent':'green'}))
            output=Path(self.tmp.name)/'public.json'
            # Root's bridge: the shipped catalog only, never the folder or the store.
            with patch.object(pictures,'collection',side_effect=AssertionError('read the store')), \
                 patch.object(pictures,'read_catalog',side_effect=AssertionError('read the store')), \
                 patch.object(pictures,'scan',side_effect=AssertionError('read the folder')):
                folio.publish(self.state,output)
            doc=json.loads(output.read_text())
            # The shipped default plate, with the owner's theme, mode and color
            # (all the boot screen keeps: packages/plymouth-folio/boot_look.py).
            self.assertEqual((doc['collection'],doc['art'],doc['collectionName']),('dore',0,'Doré'))
            self.assertEqual((doc['look']['theme'],doc['look']['mode']),(theme,'dark'))
            self.assertEqual(doc['look']['pick'],'slate' if theme=='folio' else 'green')
            self.assertTrue(all(Path(i[k]).is_relative_to(folio.DATA) and Path(i[k]).is_file() for i in doc['images'] for k in ['portrait','desktop']))
            self.assertNotIn(str(self.store),output.read_text());self.assertNotIn(str(self.folder),output.read_text())


class PictureFormatTests(unittest.TestCase):
    def test_plates_match_the_shipped_format(self):
        """At full size: the plates Plate.qml reads, as the shipped ones are."""
        from PIL import Image
        with tempfile.TemporaryDirectory() as root:
            store=Path(root)/'store';store.mkdir()
            buffer=Path(root)/'p.jpg';Image.linear_gradient('L').resize((900,600)).save(buffer)
            pictures.print_picture('mine-0123456789abcdef',buffer.read_bytes(),[.5,.5],AZURE_LIGHT,store)
            shipped=folio.DATA/'art'/folio.catalog(mine=False)['collections'][0]['art'][0]['id']
            for layout in ['desktop','portrait']:
                with Image.open(store/'art/mine-0123456789abcdef'/f'azure-light-{layout}.png') as mine, Image.open(shipped/f'azure-light-{layout}.png') as ref:
                    self.assertEqual((mine.size,mine.mode),(ref.size,ref.mode))
                    self.assertEqual({c for _,c in mine.getcolors()},{c for _,c in ref.convert(mine.mode).getcolors()})

if __name__=='__main__':unittest.main()
