#!/usr/bin/env python3
"""One desktop family: three art collections, two modes, three blue inks."""
import argparse
import fcntl
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

DATA = Path(os.environ.get('AZURE_FOLIO_DATA', '@data@'))
STATE = Path.home()/'.local/state/nixos-config/azure-folio/selection.json'


def catalog():
    return json.loads((DATA/'catalog.json').read_text())


def validate(raw):
    cat=catalog(); result=dict(cat['defaults'])
    if not isinstance(raw,dict): raise ValueError('Selection must be an object')
    for key,choices in [('collection',[c['id'] for c in cat['collections']]),('mode',['light','dark']),('ink',list(cat['inks']))]:
        if key in raw:
            if raw[key] not in choices: raise ValueError('Unknown '+key)
            result[key]=raw[key]
    collection=next(c for c in cat['collections'] if c['id']==result['collection'])
    if 'art' in raw:
        if type(raw['art']) is not int or not 0<=raw['art']<len(collection['art']): raise ValueError('Unknown art')
        result['art']=raw['art']
    if 'randomLogin' in raw:
        if type(raw['randomLogin']) is not bool: raise ValueError('randomLogin must be boolean')
        result['randomLogin']=raw['randomLogin']
    return result


def read_selection(path=STATE):
    if not path.exists(): return validate({})
    return validate(json.loads(path.read_text()))


def atomic_json(path,data,mode=0o644):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,name=tempfile.mkstemp(prefix='.'+path.name,dir=path.parent)
    try:
        with os.fdopen(fd,'w') as stream:
            json.dump(data,stream,ensure_ascii=False,indent=2);stream.write('\n')
        os.chmod(name,mode);os.replace(name,path)
    finally:
        if os.path.exists(name): os.unlink(name)


def appearance(selection):
    cat=catalog();collection=next(c for c in cat['collections'] if c['id']==selection['collection'])
    mode=selection['mode'];ink=selection['ink']
    prefix=f'{ink}-{mode}'
    images=[{'title':a['title'],'credit':a['credit'],'portrait':str(DATA/'art'/a['id']/f'{prefix}-portrait.png'),'desktop':str(DATA/'art'/a['id']/f'{prefix}-desktop.png')} for a in collection['art']]
    return {**selection,'collectionName':collection['name'],'paper':'#f7f4e9' if mode=='light' else '#101d33','inkColor':cat['inks'][ink][mode],'muted':'#64728a' if mode=='light' else '#9eb0ca','line':'#cbd1d7' if mode=='light' else '#384c69','images':images}


def ipc(*args,required=False):
    try:
        proc=subprocess.run(['dms','ipc','call',*map(str,args)],capture_output=True,text=True,timeout=15)
        good=proc.returncode==0 and not proc.stdout.startswith('ERROR:')
        if required and not good: raise RuntimeError(proc.stdout.strip() or proc.stderr.strip())
        return proc.stdout.strip() if good else None
    except (OSError,subprocess.TimeoutExpired):
        if required: raise
        return None


def set_wallpaper(path):
    result=subprocess.run(['mariano-set-wallpaper',path],capture_output=True,text=True,timeout=30)
    if result.returncode: raise RuntimeError(result.stdout+result.stderr)


def apply(selection, previous, force=False):
    palette_changed=force or any(selection[k]!=previous[k] for k in ['mode','ink'])
    if palette_changed:
        ink=selection['ink']; mode=selection['mode']; other='dark' if mode=='light' else 'light'
        subprocess.run(['themeport','set',f'folio-{ink}-{mode}','--pair',f'folio-{ink}-{other}','--no-restart'],check=True)
    doc=appearance(selection)
    # Live IPC owns DMS settings writes. The Home Manager activation separately
    # provides the same defaults before the shell has started.
    for key,value in {'fontFamily':'Inter','monoFontFamily':'IBM Plex Mono','lockScreenFontFamily':'Jacquard 24','lockScreenShowDate':'true','greeterFontFamily':'Inter','fontWeight':'400','fontScale':'1','niriLayoutRadiusOverride':'5','niriLayoutBorderSize':'1','niriLayoutGapsOverride':'12','dockTransparency':'1','cornerRadius':'5','widgetRadius':'5','popupTransparency':'1','terminalsAlwaysDark':'false'}.items():
        ipc('settings','set',key,value)
    selected=doc['images'][selection['art']]['desktop']
    if ipc('settings','get','currentThemeName') is not None:
        set_wallpaper(selected)
    else:
        session=Path.home()/'.local/state/nixos-config/dotfiles/dms/session.json'
        raw=json.loads(session.read_text()) if session.exists() else {}
        raw.update({'wallpaperPath':selected,'isLightMode':selection['mode']=='light'})
        if isinstance(raw.get('monitorWallpapers'),dict): raw['monitorWallpapers']={k:selected for k in raw['monitorWallpapers']}
        atomic_json(session.resolve(),raw,0o600)
    # Publish only after the wallpaper/theme apply succeeded. Greeter state is
    # reconstructed by a root-owned service, never copied as arbitrary paths.
    atomic_json(STATE,selection)
    atomic_json(STATE.with_name('appearance.json'),doc)
    print(f"Azure Folio · {doc['collectionName']} · {selection['mode']} · {selection['ink']}")


def publish(input_path,output):
    if input_path.exists():
        info=input_path.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid!=1000 or info.st_size>4096:
            raise ValueError('Refusing untrusted appearance selection')
    atomic_json(output,appearance(read_selection(input_path)))


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    sub.add_parser('status');sub.add_parser('catalog')
    s=sub.add_parser('set');s.add_argument('--collection',choices=['dore','summer','argentina']);s.add_argument('--mode',choices=['light','dark']);s.add_argument('--ink',choices=['azure','cobalt','slate']);s.add_argument('--art',type=int);s.add_argument('--force',action='store_true')
    sub.add_parser('next')
    sub.add_parser('restore')
    q=sub.add_parser('publish');q.add_argument('--input',type=Path,required=True);q.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    if args.command=='catalog': print(json.dumps(catalog(),ensure_ascii=False));return
    if args.command=='publish': publish(args.input,args.output);return
    if args.command=='status': print(json.dumps(appearance(read_selection()),ensure_ascii=False));return
    STATE.parent.mkdir(parents=True,exist_ok=True)
    with STATE.with_suffix('.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        previous=read_selection(); selection=dict(previous)
        if args.command=='set':
            for key in ['collection','mode','ink','art']:
                if getattr(args,key) is not None: selection[key]=getattr(args,key)
            if selection['collection']!=previous['collection']: selection['art']=0
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
