#!/usr/bin/env python3
"""Run the existing Mod Studio NoSave scenario protocol in an isolated macOS app.

Development bundles are supplied explicitly; this launcher never replaces installed mods.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time
import uuid


def link(destination, source):
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.symlink_to(source.resolve(), target_is_directory=source.is_dir())


def stage(profile, root, bundle, common=None):
    versions = sorted(p for p in root.iterdir() if p.is_dir() and (p / 'mod.info').is_file())
    if len(versions) != 1:
        raise ValueError(f'Expected one explicit version directory: {root}')
    version = versions[0]
    metadata = dict(line.split('=', 1) for line in (version / 'mod.info').read_text().splitlines() if '=' in line)
    destination = profile / 'mods' / metadata['id']
    for child in root.iterdir():
        if child.name != version.name:
            link(destination / child.name, common if child.name == 'common' and common else child)
    target = destination / version.name
    jar = Path(metadata['javaJarFile'])
    for child in version.rglob('*'):
        relative = child.relative_to(version)
        if relative.parts[0] == 'java' or child.is_dir() or relative == jar:
            continue
        link(target / relative, child)
    (target / jar).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(bundle, target / jar)
    return metadata['id']


def execute(args, artifact):
    definition = json.loads(args.scenario.read_text())
    if definition.get('manual') or definition.get('persistence') or definition.get('multiplayer'):
        raise ValueError('This launcher currently supports disposable automatic single-player scenarios only')
    game = args.game_app.resolve() / 'Contents'
    profile = artifact / 'profile'
    profile.mkdir()
    if args.common_cache:
        if not args.common_cache.is_dir():
            raise ValueError('Prepared common cache is missing')
        link(profile / 'PZ3D/fast-track', args.common_cache)
    mods = ['ZombieBuddy', stage(profile, Path(__file__).resolve().parent / 'Contents/mods/mod_studio', args.studio_jar)]
    common_assets = {name: Path(path).resolve() for name, path in args.common_assets}
    for root, bundle in args.mod:
        root = Path(root).resolve()
        mods.append(stage(profile, root, Path(bundle).resolve(), common_assets.get(root.name)))
    buddy_mod = Path.home() / 'Library/Application Support/Steam/steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy'
    link(profile / 'mods/ZombieBuddy', buddy_mod)
    (profile / 'mods/default.txt').write_text('VERSION = 1,\nmods\n{\n' + ''.join(f' mod = {name},\n' for name in mods) + '}\nmaps\n{\n}\n')
    (profile / 'mods/reset-mods-42_00.txt').touch()
    # Explicit display options make captures comparable and avoid fullscreen focus changes.
    options = 'version=8\nwidth=1280\nheight=720\nfullScreen=false\nborderless=false\nvsync=true\nfocusloss=false\nshowSurvivalGuide=false\n'
    source_options = Path.home() / 'Zomboid/options.ini'
    if source_options.is_file():
        # Carry the user's existing acceptance; never invent acceptance of a new version.
        options += ''.join(line + '\n' for line in source_options.read_text().splitlines()
                           if line.startswith('termsOfServiceVersion='))
    (profile / 'options.ini').write_text(options)
    scenario = artifact / 'scenario.json'
    shutil.copy2(args.scenario, scenario)
    app = artifact / 'Mod Studio Scenario.app'
    contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    for child in (game / 'Java').iterdir():
        link(contents / 'Java' / child.name, args.buddy if child.name == 'ZombieBuddy.jar' else child)
    for name in ['PlugIns', 'Resources']:
        link(contents / name, game / name)
    for name in ['JavaAppLauncher', 'libsteam_api.dylib']:
        shutil.copy2(game / 'MacOS' / name, contents / 'MacOS' / name)
    info = plistlib.loads((game / 'Info.plist').read_bytes())
    info.update(CFBundleIdentifier='com.pavelvoronin.modstudio.scenario', CFBundleName='Mod Studio Scenario',
                CFBundleDisplayName='Mod Studio Scenario', WorkingDirectory=str(game / 'Java'))
    info['JVMOptions'] = ['-Djava.awt.headless=true', '--enable-native-access=ALL-UNNAMED',
        '--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED', '-XstartOnFirstThread',
        '-Dzomboid.steam=0', '-Ddebug=true', '-Xmx4096m', '-XX:+UseZGC',
        f'-Dmodstudio.scenario={scenario}', f'-Dmodstudio.scenario.output={artifact}',
        '-Dpz3d.macCoreDiagnostics=true',
        f'-javaagent:{args.buddy}=verbosity=1,policy=allow-all,config_dir={artifact / "buddy-config"}']
    info['JVMOptions'] += [f'-javaagent:{path.resolve()}' for path in args.agent]
    if args.trace_mod:
        info['JVMOptions'].append('-Dpz3d.macCoreTraceMod=true')
    info['JVMArguments'] = [f'-cachedir={profile}', '-nosteam', '-debug', '-windowed']
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    record = dict(schema=1, status='prepared', scenario=definition['id'], artifact=str(artifact),
                  mods=mods, agents=[str(p.resolve()) for p in args.agent],
                  commonCache=str(args.common_cache.resolve()) if args.common_cache else None,
                  studioSha256=hashlib.sha256(args.studio_jar.read_bytes()).hexdigest())
    launch_file = artifact / 'launch.json'
    launch_file.write_text(json.dumps(record, indent=2))
    lock = Path.home() / 'Zomboid/ModStudio/game-session.lock'
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open('a+') as lease:
        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        commands = subprocess.check_output(['ps', '-axo', 'command='], text=True).splitlines()
        if any('/Contents/MacOS/JavaAppLauncher' in command or 'zombie.gameStates.MainScreenState' in command for command in commands):
            raise RuntimeError('A game is already running')
        process = None
        try:
            with (artifact / 'console.log').open('w') as log:
                process = subprocess.Popen([str(contents / 'MacOS/JavaAppLauncher')], stdout=log, stderr=subprocess.STDOUT)
                lease.seek(0); lease.truncate()
                json.dump(dict(owner='modstudio-macos', pid=process.pid, wrapperPid=os.getpid(), artifact=str(artifact)), lease)
                lease.flush()
                record.update(status='running', pid=process.pid, started=time.time())
                launch_file.write_text(json.dumps(record, indent=2))
                print(json.dumps(record), flush=True)
                code = process.wait(timeout=args.timeout)
                result_file = artifact / 'scenario-result.json'
                result = json.loads(result_file.read_text()) if result_file.is_file() else {}
                if code != 0 or result.get('status') != 'complete':
                    raise RuntimeError(f'Game exit={code}, result={result}')
                record.update(status='complete', exitCode=code)
        except BaseException as error:
            record.update(status='failed', error=str(error))
            raise
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
            record['finished'] = time.time()
            launch_file.write_text(json.dumps(record, indent=2))
            lease.seek(0); lease.truncate()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('scenario', type=Path)
    parser.add_argument('--studio-jar', type=Path, required=True)
    parser.add_argument('--buddy', type=Path, required=True)
    parser.add_argument('--agent', type=Path, action='append', default=[])
    parser.add_argument('--trace-mod', action='store_true', help='Enable per-call GL diagnostics in the supplied Core development agent')
    parser.add_argument('--mod', nargs=2, action='append', default=[], metavar=('ROOT', 'JAR'))
    parser.add_argument('--common-assets', nargs=2, action='append', default=[], metavar=('MOD', 'DIRECTORY'), help='Use a stable common-resource snapshot for a mod')
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--common-cache', type=Path, help='Reuse a validated prepared fast-track cache, as with scenario.ps1 -ReuseCommonCache')
    parser.add_argument('--game-app', type=Path, default=Path.home() / 'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app')
    parser.add_argument('--artifacts', type=Path, default=Path.home() / 'Zomboid/ModStudio/scenarios')
    args = parser.parse_args()
    artifact = args.artifacts / (datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8])
    artifact.mkdir(parents=True)
    print(f'Artifact: {artifact}', flush=True)
    execute(args, artifact.resolve())


if __name__ == '__main__':
    main()
