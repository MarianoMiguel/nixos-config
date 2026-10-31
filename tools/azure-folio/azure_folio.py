#!/usr/bin/env python3
"""Interstellar's look: a theme (Folio or Lumen), a mode and one color.

Folio's art: the shipped collections printed in its ink, and the owner's own
pictures (pictures.py: ~/Pictures/Folio, kept in the cache, never read by
root). The colors themselves come from looks.py, which apps, the shell and
the boot screen share."""
import argparse
import fcntl
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from render import render_cached
import looks
import pictures

DATA = Path(os.environ.get('AZURE_FOLIO_DATA', '@data@'))
STATE = Path.home()/'.local/state/nixos-config/azure-folio/selection.json'
CACHE = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home()/'.cache')))/'azure-folio/wallpapers'
MINE = pictures.ID


def catalog(mine=True):
    """The shipped catalog, and with mine your pictures as one more
    collection while there are any. Root's bridge reads the shipped one only."""
    cat=json.loads((DATA/'catalog.json').read_text())
    user=pictures.collection() if mine else None
    if user: cat['collections'].append(user)
    return cat


def collection_of(selection,cat):
    return next(c for c in cat['collections'] if c['id']==selection['collection'])


def data_of(collection):
    """Where a collection's sources and art live: the package, or your pictures' store."""
    return pictures.STORE if collection['id']==MINE else DATA


def validate(raw,cat=None):
    cat=cat or catalog(); result=dict(cat['defaults'])
    if not isinstance(raw,dict): raise ValueError('Selection must be an object')
    if raw.get('collection')==MINE and not any(c['id']==MINE for c in cat['collections']):
        raise ValueError(f'No pictures yet: add JPEG, PNG or WebP files to {pictures.FOLDER}')
    for key,choices in [('collection',[c['id'] for c in cat['collections']]),('mode',['light','dark']),('ink',list(cat['inks']))]:
        if key in raw and not (key=='ink' and raw[key]=='custom'):
            if raw[key] not in choices: raise ValueError('Unknown '+key)
            result[key]=raw[key]
    collection=next(c for c in cat['collections'] if c['id']==result['collection'])
    if 'art' in raw:
        if type(raw['art']) is not int or not 0<=raw['art']<len(collection['art']): raise ValueError('Unknown art')
        result['art']=raw['art']
    if 'randomLogin' in raw:
        if type(raw['randomLogin']) is not bool: raise ValueError('randomLogin must be boolean')
        result['randomLogin']=raw['randomLogin']
    # The theme, and each theme's color: a named one, or "custom" with the
    # #rrggbb it keeps (remembered while a named one is chosen).
    result.setdefault('theme','folio');result.setdefault('accent',looks.DEFAULT['lumen']);result.setdefault('sky',looks.SKIES[0])
    if 'sky' in raw:
        if raw['sky'] not in looks.SKIES: raise ValueError('Unknown sky')
        result['sky']=raw['sky']
    if 'theme' in raw:
        if raw['theme'] not in looks.THEMES: raise ValueError('Unknown theme')
        result['theme']=raw['theme']
    if raw.get('ink')=='custom': result['ink']='custom'
    if 'accent' in raw:
        if raw['accent']!='custom' and raw['accent'] not in looks.ACCENTS: raise ValueError('Unknown accent')
        result['accent']=raw['accent']
    for key in ['customInk','customAccent']:
        if key in raw:
            if not isinstance(raw[key],str) or not looks.HEX.fullmatch(raw[key]): raise ValueError('Unknown '+key)
            result[key]=raw[key].lower()
    if result['ink']=='custom' and 'customInk' not in result: raise ValueError('A custom ink needs its color')
    if result['accent']=='custom' and 'customAccent' not in result: raise ValueError('A custom accent needs its color')
    return result


def pick(selection,theme=None):
    """The active theme's color as looks.py takes it: a name or #rrggbb."""
    theme=theme or selection['theme']
    if theme=='folio': return selection['customInk'] if selection['ink']=='custom' else selection['ink']
    return selection['customAccent'] if selection['accent']=='custom' else selection['accent']


def folio_ink(selection,mode):
    return looks.derive('folio',mode,pick(selection,'folio'))[0]


def settle(raw,cat):
    """A saved choice of your pictures that no longer resolves falls back:
    to the shipped default plate when there are none (they were removed, the
    cache was cleared, or the reader never sees them: root's bridge), to the
    last one when the chosen one is past the end."""
    if not isinstance(raw,dict) or raw.get('collection')!=MINE: return raw
    mine=next((c for c in cat['collections'] if c['id']==MINE),None)
    if mine is None: return {k:v for k,v in raw.items() if k not in ('collection','art')}
    if type(raw.get('art')) is int and raw['art']>=len(mine['art']): return {**raw,'art':len(mine['art'])-1}
    return raw


def read_selection(path=None,cat=None):
    path=path or STATE;cat=cat or catalog()
    if not path.exists(): return validate({},cat)
    return validate(settle(json.loads(path.read_text()),cat),cat)


def atomic_json(path,data,mode=0o644):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,name=tempfile.mkstemp(prefix='.'+path.name,dir=path.parent)
    try:
        with os.fdopen(fd,'w') as stream:
            json.dump(data,stream,ensure_ascii=False,indent=2);stream.write('\n')
        os.chmod(name,mode);os.replace(name,path)
    finally:
        if os.path.exists(name): os.unlink(name)


def prefix_of(selection,cat):
    # Pre-printed art exists for the named inks; a custom ink borrows azure's
    # (the shell and the boot screen print plates in any ink themselves).
    ink=selection['ink']
    return (ink if ink in cat['inks'] else 'azure'),selection['mode']


def appearance(selection,cat=None):
    cat=cat or catalog();collection=collection_of(selection,cat)
    mode=selection['mode']
    prefix='-'.join(prefix_of(selection,cat));art=data_of(collection)/'art'
    images=[{'title':a['title'],'credit':a['credit'],'portrait':str(art/a['id']/f'{prefix}-portrait.png'),'desktop':str(art/a['id']/f'{prefix}-desktop.png')} for a in collection['art']]
    return {**selection,'collectionName':collection['name'],'paper':'#f7f4e9' if mode=='light' else '#101d33','inkColor':folio_ink(selection,mode),'look':looks.resolve(selection['theme'],mode,pick(selection)),'muted':'#536177' if mode=='light' else '#9eb0ca','line':'#d9d0bf' if mode=='light' else '#384c69','images':images}


def ipc(*args,required=False):
    try:
        proc=subprocess.run(['dms','ipc','call',*map(str,args)],capture_output=True,text=True,timeout=15)
        good=proc.returncode==0 and not proc.stdout.startswith('ERROR:')
        if required and not good: raise RuntimeError(proc.stdout.strip() or proc.stderr.strip())
        return proc.stdout.strip() if good else None
    except (OSError,subprocess.TimeoutExpired):
        if required: raise
        return None


def display_targets(outputs):
    """Include disabled connectors so the laptop's render is ready to undock."""
    result = {}
    for name, output in outputs.items():
        modes = output.get('modes', [])
        index = output.get('current_mode')
        mode = modes[index] if type(index) is int and 0 <= index < len(modes) else next((m for m in modes if m.get('is_preferred')), None)
        if not mode: continue
        width, height = mode['width'], mode['height']
        transform = (output.get('logical') or {}).get('transform', 'Normal')
        if transform in ['90', '270', 'Flipped90', 'Flipped270']:
            width, height = height, width
        result[name] = (width, height)
    return result


def monitor_outputs():
    if not os.environ.get('NIRI_SOCKET'): return {}
    result = subprocess.run(['niri', 'msg', '-j', 'outputs'], capture_output=True, text=True, timeout=10, check=True)
    return json.loads(result.stdout)


def ensure_prints(selection, cat=None):
    """Your pictures are printed for DMS when chosen, not ahead of time: the
    chosen one in the selection's ink and mode (shipped plates come printed)."""
    cat = cat or catalog()
    collection = collection_of(selection, cat)
    if collection['id'] != MINE: return
    ink, mode = prefix_of(selection, cat)
    pictures.prints(collection['art'][selection['art']]['id'], ink, mode, cat['inks'][ink][mode])


def render_wallpapers(selection, outputs):
    cat = catalog()
    collection = collection_of(selection, cat)
    art = collection['art'][selection['art']]
    if collection['id'] == MINE:
        # A renamed picture keeps its renders: only what shapes the crop counts.
        art = {k: art[k] for k in ('id', 'file', 'generated', 'desktopFocus')}
    ink = folio_ink(selection, selection['mode'])
    paper = '#f7f4e9' if selection['mode'] == 'light' else '#101d33'
    return {name: str(render_cached(data_of(collection), CACHE, art, size, ink, paper))
            for name, size in display_targets(outputs).items()}


def set_wallpaper(selection):
    ensure_prints(selection)
    selected = appearance(selection)['images'][selection['art']]['desktop']
    wallpapers = render_wallpapers(selection, monitor_outputs())
    result = ipc('folioWallpaper', 'apply', selected, json.dumps(wallpapers), required=True)
    if not result.startswith('SUCCESS:'):
        raise RuntimeError('DMS Folio wallpaper integration is not ready: ' + result)
    return wallpapers


def refresh_wallpapers(selection):
    # Hotplug must not replace a personal wallpaper chosen outside Folio.
    current = ipc('folioWallpaper', 'get')
    selected = appearance(selection)['images'][selection['art']]['desktop']
    if not current or Path(current).resolve() != Path(selected).resolve(): return
    set_wallpaper(selection)


def apply(selection, previous, force=False):
    palette_changed=force or any(selection.get(k)!=previous.get(k) for k in ['theme','mode','ink','customInk','accent','customAccent'])
    if palette_changed:
        # Apps get the palette looks.py derives for this theme, mode and color.
        subprocess.run(['themeport','look',selection['theme'],selection['mode'],pick(selection),'--no-restart'],check=True)
    doc=appearance(selection)
    # Live IPC owns DMS settings writes. The Home Manager activation separately
    # provides the same defaults before the shell has started. Corners, gaps and
    # transparency are not Folio's: they belong to the workshop's looks.
    for key,value in {'fontFamily':'Inter','monoFontFamily':'IBM Plex Mono','lockScreenFontFamily':'Jacquard 24','lockScreenShowDate':'true','greeterFontFamily':'Inter','fontWeight':'400','fontScale':'1','terminalsAlwaysDark':'false'}.items():
        ipc('settings','set',key,value)
    selected=doc['images'][selection['art']]['desktop']
    if selection['theme']=='folio': ensure_prints(selection)
    # Lumen's wallpaper is drawn by the shell; DMS keeps the last plate.
    if selection['theme']!='folio': pass
    elif ipc('settings','get','currentThemeName') is not None:
        set_wallpaper(selection)
    else:
        session=Path.home()/'.local/state/nixos-config/dotfiles/dms/session.json'
        raw=json.loads(session.read_text()) if session.exists() else {}
        raw.update({'wallpaperPath':selected,'isLightMode':selection['mode']=='light','perMonitorWallpaper':False,'monitorWallpapers':{}})
        if isinstance(raw.get('monitorWallpapers'),dict): raw['monitorWallpapers']={k:selected for k in raw['monitorWallpapers']}
        atomic_json(session.resolve(),raw,0o600)
    # Publish only after the wallpaper/theme apply succeeded. Greeter state is
    # reconstructed by a root-owned service, never copied as arbitrary paths.
    atomic_json(STATE,selection)
    atomic_json(STATE.with_name('appearance.json'),doc)
    print(f"Interstellar · {selection['theme']} · {selection['mode']} · {pick(selection)}")


def publish(input_path,output):
    if input_path.exists():
        info=input_path.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid!=1000 or info.st_size>4096:
            raise ValueError('Refusing untrusted appearance selection')
    # Root never reads your pictures: the shipped catalog only, so a choice
    # of them reaches the greeter and the boot screen as the shipped default
    # plate (settle), with the owner's theme, mode and color.
    cat=catalog(mine=False)
    atomic_json(output,appearance(read_selection(input_path,cat),cat))


def scan_pictures(create=False,wait=True):
    """Print what is new in your pictures' folder, forget what is gone."""
    return pictures.scan(catalog(mine=False)['inks'][pictures.SHELL[0]][pictures.SHELL[1]], renders=CACHE, create=create, wait=wait)


def stored_collection():
    try: return json.loads(STATE.read_text()).get('collection')
    except (OSError, ValueError, AttributeError): return None


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    sub.add_parser('status');sub.add_parser('catalog')
    s=sub.add_parser('set');s.add_argument('--collection',choices=[c['id'] for c in catalog(mine=False)['collections']]+[MINE]);s.add_argument('--mode',choices=['light','dark']);s.add_argument('--theme',choices=looks.THEMES);s.add_argument('--sky',choices=looks.SKIES);s.add_argument('--ink',help='azure, cobalt, slate, custom or #rrggbb');s.add_argument('--accent',help="one of Lumen's colors, custom or #rrggbb");s.add_argument('--art',type=int);s.add_argument('--force',action='store_true')
    sub.add_parser('next')
    sub.add_parser('restore')
    sub.add_parser('refresh-wallpapers', help='Refresh per-display crops after a display change')
    q=sub.add_parser('publish');q.add_argument('--input',type=Path,required=True);q.add_argument('--output',type=Path,required=True)
    y=sub.add_parser('pictures',help=f'Print the pictures in {pictures.FOLDER} as plates of "{pictures.NAME}"');y.add_argument('--create',action='store_true',help='make the folder first')
    args=p.parse_args()
    if args.command=='catalog': print(json.dumps(catalog(),ensure_ascii=False));return
    if args.command=='publish': publish(args.input,args.output);return
    if args.command=='pictures':
        doc=scan_pictures(args.create)
        print(json.dumps({k:doc[k] for k in ['folder','present','pending','arriving','skipped']}|{'pictures':len(doc['collection']['art'])},ensure_ascii=False));return
    # Your pictures are read again before they are chosen or cycled, so DMS
    # (which does not watch the folder as Folio's shell does) sees new ones;
    # not while a scan is already printing (the shell's): its plates do.
    if args.command in ('set','next','restore') and MINE in (getattr(args,'collection',None),stored_collection()): scan_pictures(wait=False)
    if args.command=='status': print(json.dumps(appearance(read_selection()),ensure_ascii=False));return
    STATE.parent.mkdir(parents=True,exist_ok=True)
    with STATE.with_suffix('.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        previous=read_selection(); selection=dict(previous)
        if args.command=='refresh-wallpapers': refresh_wallpapers(selection);return
        if args.command=='set':
            for key in ['collection','mode','art','theme','sky']:
                if getattr(args,key) is not None: selection[key]=getattr(args,key)
            # A #rrggbb becomes the theme's custom color; validate() checks it.
            for key,custom in [('ink','customInk'),('accent','customAccent')]:
                value=getattr(args,key)
                if value is None: continue
                if value.startswith('#'): selection[key]='custom';selection[custom]=value
                else: selection[key]=value
            if selection['collection']!=previous['collection'] and args.art is None: selection['art']=0
        if args.command=='next':
            count=len(appearance(selection)['images']);selection['art']=(selection['art']+1)%count
        force=args.command=='restore' or getattr(args,'force',False)
        selection=validate(selection)
        if not force and selection==previous and STATE.exists(): return
        apply(selection,previous,force)

if __name__=='__main__':
    try: main()
    except (ValueError,OSError,RuntimeError,subprocess.SubprocessError) as exc:
        print(f'Azure Folio: {exc}',file=sys.stderr);sys.exit(1)
