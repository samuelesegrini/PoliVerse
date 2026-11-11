#!/usr/bin/env python3
"""One-time provisioning of a private control repository and Mac login-session runner."""
import hashlib
import json
import plistlib
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request


def run(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def main():
    base = Path.home() / 'Library/Application Support/PoliVerseBuilds'
    control, runner = base / 'control', base / 'runner'
    template = Path(__file__).resolve().parent
    login = json.loads(run(['gh', 'api', 'user']))['login']
    repo = login + '/PoliVerse-builds'
    base.mkdir(parents=True, exist_ok=True)
    if not control.exists():
        control.mkdir()
        shutil.copyfile(template / 'build.py', control / 'build.py')
        shutil.copyfile(template / 'README.md', control / 'README.md')
        shutil.copytree(template / '.github', control / '.github')
        (control / '.gitignore').write_text('__pycache__/\n.DS_Store\n')
        run(['git', 'init', '-b', 'main'], cwd=control)
        run(['git', 'add', '.'], cwd=control)
        run(['git', 'commit', '-m', 'Add private PoliVerse Mac build workflow'], cwd=control)
        run(['gh', 'repo', 'create', repo, '--private', '--source', str(control),
             '--remote', 'origin', '--push', '--description', 'Private phone-to-Mac build control for PoliVerse'])
    visibility = json.loads(run(['gh', 'repo', 'view', repo, '--json', 'visibility']))['visibility']
    if visibility != 'PRIVATE':
        raise RuntimeError('The build-control repository must be private')
    if not (runner / '.runner').exists():
        runner.mkdir(exist_ok=True)
        release = json.loads(run(['gh', 'api', 'repos/actions/runner/releases/latest']))
        asset = next(a for a in release['assets'] if a['name'].startswith('actions-runner-osx-arm64-'))
        digest = asset.get('digest', '')
        if not digest.startswith('sha256:'):
            raise RuntimeError('Runner release has no SHA-256 digest')
        archive = base / asset['name']
        print('Downloading and verifying GitHub runner…', flush=True)
        urllib.request.urlretrieve(asset['browser_download_url'], archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != digest.split(':')[1]:
            raise RuntimeError('Runner checksum mismatch')
        with tarfile.open(archive) as tar:
            tar.extractall(runner, filter='data')
        archive.unlink()
        token = json.loads(run(['gh', 'api', '--method', 'POST',
                               f'repos/{repo}/actions/runners/registration-token']))['token']
        # Capture output so the registration secret is never printed.
        result = subprocess.run(['./config.sh', '--unattended', '--url', 'https://github.com/' + repo,
                                 '--token', token, '--name', 'PoliVerse-Mac',
                                 '--labels', 'poliverse-builds', '--work',
                                 str(Path.home() / '.local/share/poliverse-builds/work')],
                                cwd=runner, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if result.returncode:
            raise RuntimeError('Runner registration failed; inspect GitHub runner diagnostics on the Mac')
    service = runner / '.service'
    if not service.exists():
        run(['./svc.sh', 'install'], cwd=runner)
    # The default runner template creates a new security session, which cannot
    # use this logged-in user's signing key (actions/runner#3407).
    subprocess.run(['./svc.sh', 'stop'], cwd=runner, capture_output=True)
    plist = Path(service.read_text().strip())
    settings = plistlib.loads(plist.read_bytes())
    settings['SessionCreate'] = False
    plist.write_bytes(plistlib.dumps(settings))
    print(run(['./svc.sh', 'start'], cwd=runner))
    print('Ready: https://github.com/' + repo + '/actions', flush=True)


if __name__ == '__main__':
    main()
