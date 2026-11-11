#!/usr/bin/env python3
"""Private runner entry point. Builds an isolated checkout, never the working repository."""
import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys

SOURCE = 'https://github.com/samuelesegrini/PoliVerse.git'


def run(args, cwd=None, log=None):
    if log:
        print('Running ' + args[0] + '; log: ' + str(log), flush=True)
        with log.open('w') as output:
            result = subprocess.run(args, cwd=cwd, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            print('\n'.join(log.read_text(errors='replace').splitlines()[-65:]), flush=True)
            raise RuntimeError(f'{args[0]} failed ({result.returncode}). Full log: {log}')
        return ''
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def summary(text):
    print(text, flush=True)
    if path := os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(path, 'a') as output:
            output.write(text + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', default='main', help='Branch in the fixed PoliVerse repository')
    parser.add_argument('--platform', choices=['device', 'simulator', 'mac'], default='device')
    parser.add_argument('--configuration', choices=['Debug', 'Release'], default='Debug')
    parser.add_argument('--install', action='store_true')
    parser.add_argument('--test', action='store_true')
    parser.add_argument('--automatic', action='store_true', help='Skip a commit already attempted')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_./-]*', args.ref) or '..' in args.ref:
        parser.error('Invalid branch name')
    if args.automatic and args.ref != 'main':
        parser.error('Automatic builds only accept main')
    if args.install and args.platform == 'mac':
        parser.error('Install is supported for iPhone and simulator builds')

    base = Path.home() / 'Library/Application Support/PoliVerseBuilds'
    base.mkdir(parents=True, exist_ok=True)
    with (base / 'build.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another local build is already running')
        build(args, base)


def simulator():
    devices = json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))['devices']
    # A dedicated simulator keeps CI from terminating the simulator someone is using in Xcode.
    for runtime, entries in devices.items():
        if 'iOS-27' in runtime:
            for device in entries:
                if device['name'] == 'PoliVerse CI':
                    return device['udid']
    runtimes = json.loads(run(['xcrun', 'simctl', 'list', 'runtimes', '--json']))['runtimes']
    runtime = next((r['identifier'] for r in reversed(runtimes)
                    if r.get('isAvailable') and 'iOS-27' in r['identifier']), None)
    if not runtime:
        raise RuntimeError('Install an iOS 27 simulator runtime in Xcode')
    return run(['xcrun', 'simctl', 'create', 'PoliVerse CI',
                'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro', runtime])


def prepare_simulator(identifier):
    devices = json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))['devices']
    device = next(d for entries in devices.values() for d in entries if d['udid'] == identifier)
    if device['state'] == 'Shutdown':
        run(['xcrun', 'simctl', 'boot', identifier])
    try:
        # A fresh runtime can take longer than Xcode's 60-second launch timeout.
        subprocess.run(['xcrun', 'simctl', 'bootstatus', identifier, '-b'],
                       check=True, timeout=300)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError('Simulator did not become ready within five minutes') from error


def build(args, base):
    source = base / 'source'
    if not source.exists():
        run(['git', 'clone', '--depth=1', '--single-branch', '--branch', args.ref,
             '--no-checkout', SOURCE, str(source)])
    if run(['git', 'remote', 'get-url', 'origin'], cwd=source) != SOURCE:
        raise RuntimeError('Unexpected origin in the managed build checkout')
    run(['git', 'fetch', '--depth=1', '--no-tags', 'origin', 'refs/heads/' + args.ref], cwd=source)
    commit = run(['git', 'rev-parse', 'FETCH_HEAD'], cwd=source)
    state = base / ('attempted-' + args.platform + '-' + args.configuration + '.json')
    identity = {'commit': commit, 'tests': args.test, 'install': args.install}
    if args.automatic and state.exists() and json.loads(state.read_text()) == identity:
        summary('No new commit on main. Last attempt: `' + commit[:7] + '`. Use Run workflow to retry.')
        return
    state.write_text(json.dumps(identity))
    run(['git', 'checkout', '--detach', '--force', commit], cwd=source)
    logs = base / 'logs' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    logs.mkdir(parents=True)
    summary(f'Building [{commit[:7]}](https://github.com/samuelesegrini/PoliVerse/commit/{commit}) · '
            f'{args.platform} · {args.configuration}')
    derived = base / 'DerivedData'
    common = ['xcodebuild', '-project', 'PoliVerse.xcodeproj', '-scheme', 'PoliVerse',
              '-configuration', args.configuration, '-derivedDataPath', str(derived),
              'CURRENT_PROJECT_VERSION=' + datetime.datetime.now().strftime('%Y%m%d%H%M'),
              'POLIVERSE_BUILD_COMMIT=' + commit, 'POLIVERSE_BUILD_CHANNEL=local']
    sim = simulator() if args.test or args.platform == 'simulator' else None
    if sim is not None:
        prepare_simulator(sim)
    if args.test:
        run(common + ['test', '-destination', 'platform=iOS Simulator,id=' + sim,
                      'CODE_SIGNING_ALLOWED=NO'], cwd=source, log=logs / 'tests.log')
        summary('Unit tests passed.')
    if args.platform == 'device':
        device = os.environ.get('POLIVERSE_DEVICE_ID', '')
        if args.install and not re.fullmatch(r'[A-Fa-f0-9-]{20,40}', device):
            raise RuntimeError('Set POLIVERSE_DEVICE_ID to the paired iPhone UDID')
        destination = 'id=' + device if args.install else 'generic/platform=iOS'
        suffix = '-iphoneos'
        signing = ['-allowProvisioningUpdates']
    elif args.platform == 'simulator':
        destination, suffix, signing = 'platform=iOS Simulator,id=' + sim, '-iphonesimulator', ['CODE_SIGNING_ALLOWED=NO']
    else:
        destination, suffix, signing = 'platform=macOS', '', ['CODE_SIGNING_ALLOWED=NO']
    run(common + ['build', '-destination', destination] + signing, cwd=source, log=logs / 'build.log')
    app = derived / 'Build/Products' / (args.configuration + suffix) / 'PoliVerse.app'
    if not app.is_dir():
        raise RuntimeError('Build succeeded but the expected app bundle is missing')
    summary('Build succeeded. App on Mac: `' + str(app) + '`')
    if args.install:
        if args.platform == 'device':
            run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', device, str(app)],
                log=logs / 'install.log')
        else:
            run(['xcrun', 'simctl', 'install', sim, str(app)])
        summary('Installed successfully. Open PoliVerse on the device.')
    (base / 'last-success.json').write_text(json.dumps(identity))
    summary('Finished. Full logs stay on the Mac: `' + str(logs) + '`.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        summary('Build failed: ' + str(error))
        sys.exit(1)
