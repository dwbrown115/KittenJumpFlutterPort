from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, plistlib, re, shutil, subprocess

root = Path(__file__).resolve().parents[1]
artifacts = root / 'artifacts'
artifacts.mkdir(exist_ok=True)
apk_input = root / 'build/app/outputs/flutter-apk/app-release.apk'
mac_input = root / 'build/macos/Build/Products/Release/Kitten Jump Christmas.app'
assert apk_input.is_file() and mac_input.is_dir(), 'Build both release targets first.'
info = plistlib.loads((mac_input / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.silvercastledigital.kittenJumpChristmas'
assert info['CFBundleShortVersionString'] == '2.1.1'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(mac_input)], check=True)
apk = artifacts / 'KittenJump-Christmas-Android.apk'
shutil.copy2(apk_input, apk)
mac = artifacts / 'Kitten Jump Christmas.app'
if mac.exists():
    shutil.rmtree(mac)
subprocess.run(['ditto', str(mac_input), str(mac)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(mac)], check=True)
executable = mac / 'Contents/MacOS' / info['CFBundleExecutable']
architectures = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).strip().split()
assert set(architectures) == {'arm64', 'x86_64'}
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
manifest = {
    'built_at_utc': datetime.now(timezone.utc).isoformat(),
    'source_ipa_sha256': '99cf9a56cb75a3967215b3658272decce94515a20003d132907e456284a4a07a',
    'source_version': '2.1.1',
    'android': {
        'artifact': apk.name,
        'application_id': 'com.silvercastledigital.kitten_jump_christmas',
        'bytes': apk.stat().st_size,
        'sha256': sha(apk),
        'signing': 'Development signing key for local testing',
    },
    'macos': {
        'artifact': mac.name,
        'bundle_id': info['CFBundleIdentifier'],
        'version': info['CFBundleShortVersionString'],
        'executable': info['CFBundleExecutable'],
        'executable_sha256': sha(executable),
        'architectures': architectures,
        'signing': 'Local ad hoc signature, deep strict verification passed',
    },
    'preferences_namespace': 'kittenJumpChristmas',
    'source_dart_sha256': {
        str(path.relative_to(root)): sha(path)
        for path in sorted((root / 'lib').rglob('*.dart'))
    },
}
(artifacts / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
