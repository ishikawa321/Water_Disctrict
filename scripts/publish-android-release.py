"""Publish an already verified APK and checksum; never upload signing material."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'ishikawa321/Water_Disctrict'
API = f'https://api.github.com/repos/{REPOSITORY}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true', help='Create/upload/publish the release after local validation.')
    args = parser.parse_args()
    metadata = json.loads((ROOT / 'web/src/lib/android-release.json').read_text(encoding='utf-8'))
    artifact_dir = (ROOT / 'artifacts/android').resolve()
    apk = (artifact_dir / metadata['fileName']).resolve()
    if apk.parent != artifact_dir or apk.suffix != '.apk':
        raise RuntimeError('Release metadata must name an APK inside artifacts/android.')
    with apk.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != metadata['sha256'] or apk.stat().st_size != metadata['sizeBytes']:
        raise RuntimeError('APK differs from the verified release metadata. Revalidate the signed build first.')
    checksum = Path(str(apk) + '.sha256')
    if checksum.read_text().split()[0] != digest:
        raise RuntimeError('APK checksum file does not match.')
    tag = 'android-v' + metadata['version']
    expected_url = f'https://github.com/{REPOSITORY}/releases/download/{tag}/{apk.name}'
    if metadata['apkUrl'] != expected_url:
        raise RuntimeError('Download URL does not match this release.')
    source_paths = ['android', 'lib', 'assets', 'pubspec.yaml', 'pubspec.lock']
    status = subprocess.run(['git', 'status', '--porcelain', '--', *source_paths], cwd=ROOT, capture_output=True, text=True, check=True)
    if status.stdout.strip():
        raise RuntimeError('Commit the verified Android source before publishing its APK.')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    print(json.dumps({'tag': tag, 'sourceCommit': commit, 'file': apk.name, 'sha256': digest, 'publish': args.publish}))
    if not args.publish:
        return
    # Reuse the existing GitHub login through Git Credential Manager. Credentials
    # are captured in process memory, never printed, saved, or put in argv.
    environment = {**os.environ, 'GIT_TERMINAL_PROMPT': '0'}
    credential = subprocess.run(['git', 'credential', 'fill'], cwd=ROOT, input=f'protocol=https\nhost=github.com\npath={REPOSITORY}.git\n\n', text=True, capture_output=True, check=True, env=environment)
    values = dict(line.split('=', 1) for line in credential.stdout.splitlines() if '=' in line)
    token = values.get('password')
    if not token:
        raise RuntimeError('A GitHub login with release permission is required.')

    def request(url, method='GET', data=None, content_type='application/json'):
        payload = json.dumps(data).encode() if isinstance(data, dict) else data
        req = urllib.request.Request(url, data=payload, method=method, headers={
            'Authorization': 'Bearer ' + token,
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'WaterDistrict-Android-Release',
            'Content-Type': content_type,
        })
        # Only fixed GitHub API/upload endpoints receive the credential.
        if urllib.parse.urlparse(url).hostname not in {'api.github.com', 'uploads.github.com'}:
            raise RuntimeError('Refusing to send GitHub credentials to another host.')
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        with urllib.request.build_opener(NoRedirect).open(req, timeout=180) as response:
            return json.load(response)

    try:
        release = request(API + '/releases/tags/' + tag)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        body = (
            f'Android release {metadata["version"]} (build {metadata["buildNumber"]}).\n\n'
            f'- Signed universal APK for Android {metadata["minimumAndroid"]} or later.\n'
            f'- Application ID: `{metadata["applicationId"]}`.\n'
            '- Uses existing Supabase identities and account permissions; internet required.\n'
            '- Consumer, Admin and invited Staff mobile views. Staff can confirm payments and complete assigned repairs for Admin resolution.\n'
            '- Uses the existing public application ID and signing certificate; installs as an update to version 1.0.1.\n\n'
            f'APK SHA-256: `{digest}`\n\n'
            f'Release certificate SHA-256: `{metadata["certificateSha256"]}`\n\n'
            'Download the APK asset, open it on Android, and follow the installer. '
            'If asked, allow installation from the browser or Files app used for the download.\n\n'
            'Student-developed project showcase; this release is not an official district service launch.'
        )
        release = request(API + '/releases', 'POST', {'tag_name': tag, 'target_commitish': commit, 'name': f'Water District Connect for Android {metadata["version"]}', 'body': body, 'draft': True, 'prerelease': False})
    files = [apk, checksum]
    assets = {asset['name']: asset for asset in release.get('assets', [])}
    for file in files:
        with file.open('rb') as stream:
            expected_digest = 'sha256:' + hashlib.file_digest(stream, 'sha256').hexdigest()
        existing = assets.get(file.name)
        if existing:
            if existing.get('digest') != expected_digest:
                raise RuntimeError('An existing release asset differs. Release assets are immutable; use a new version.')
            continue
        if not release['draft']:
            raise RuntimeError('Published release is missing an asset. Do not alter an existing public release.')
        asset_url = f'https://uploads.github.com/repos/{REPOSITORY}/releases/{release["id"]}/assets?name={urllib.parse.quote(file.name)}'
        uploaded = request(asset_url, 'POST', file.read_bytes(), 'application/vnd.android.package-archive' if file.suffix == '.apk' else 'text/plain')
        if uploaded.get('state') != 'uploaded' or uploaded.get('digest') != expected_digest:
            raise RuntimeError('Uploaded asset did not match the local digest; release remains a draft.')
        print(json.dumps({'uploaded': file.name, 'size': uploaded['size'], 'digestVerified': True}))
    if release['draft']:
        release = request(API + f'/releases/{release["id"]}', 'PATCH', {'draft': False})
    print(json.dumps({'published': not release['draft'], 'releaseUrl': release['html_url'], 'apkUrl': expected_url}))


if __name__ == '__main__':
    try:
        main()
    except urllib.error.HTTPError as error:
        print(f'GitHub release request failed (HTTP {error.code}); any uploaded draft is preserved.', file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
