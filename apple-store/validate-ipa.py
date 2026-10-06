#!/usr/bin/env python3
"""Check the actual built IPA, not only the uncompiled asset catalog.

Usage: python3 validate-ipa.py FILE.ipa SOURCE_DIRECTORY REPORT_DIRECTORY
Requires Python standard library only; writes icon previews to the build report.
"""
from pathlib import Path, PurePosixPath
import hashlib
import json
import plistlib
import struct
import sys
import zipfile


def check(ipa, source, report):
    report.mkdir(parents=True, exist_ok=True)
    expected_png = (source / 'Feather/Resources/AppIcon.png').read_bytes()
    with zipfile.ZipFile(ipa) as archive:
        names = set(archive.namelist())
        candidates = [n for n in names if n.startswith('Payload/')
                      and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        assert len(candidates) == 1, 'Expected exactly one main application'
        plist_name = candidates[0]
        bundle = plist_name.rsplit('/', 1)[0] + '/'
        info = plistlib.loads(archive.read(plist_name))
        expected = {
            'CFBundleDisplayName': 'Apple Store',
            'CFBundleName': 'Apple Store',
            'CFBundleIdentifier': 'ru.ipa95.applestore',
            'CFBundleShortVersionString': '3.8',
            'CFBundleVersion': '309',
            'CFBundleExecutable': 'AppleStore',
            'UILaunchStoryboardName': 'AppleStoreLaunch34',
        }
        # Keep actual metadata even when an assertion fails.
        (report / 'built-Info.plist').write_bytes(plistlib.dumps(info))
        actual = {key: info.get(key) for key in expected}
        actual['CFBundleExecutable'] = info.get('CFBundleExecutable')
        (report / 'app-identity-actual.json').write_text(json.dumps(actual, indent=2) + '\n')
        for key, value in expected.items():
            assert info.get(key) == value, f'{key}: {info.get(key)!r} != {value!r}'

        preview = archive.read(bundle + 'AppIcon.png')
        assert preview == expected_png, 'Installer preview is not the new artwork'
        assert preview[:8] == b'\x89PNG\r\n\x1a\n'
        assert struct.unpack('>II', preview[16:24]) == (1024, 1024)
        (report / 'Apple-Store-icon.png').write_bytes(preview)

        # These shipped with the previous app and caused the wrong icon.
        forbidden = {'Donor@2x.png', 'Donor@3x.png', 'V0@2x.png', 'V0@3x.png',
                     'V1@2x.png', 'V1@3x.png', 'V1Mac@2x.png', 'V1Mac@3x.png',
                     'V2Mac@2x.png', 'V2Mac@3x.png', 'Wing@2x.png', 'Wing@3x.png',
                     'feather_extension.png', 'feather.png', 'feather 5.png',
                     'feather_dark.png', 'feather_tint.png'}
        own_files = [n for n in names if n.startswith(bundle)
                     and not n.startswith(bundle + 'Frameworks/')]
        assert not any('AppIcon.icon' in PurePosixPath(n).parts for n in own_files)
        assert not any(PurePosixPath(n).name in forbidden for n in own_files), 'Old icon PNG still packaged'

        compiled = set()
        for key in ['CFBundleIcons', 'CFBundleIcons~ipad']:
            entry = info.get(key, {})
            primary = entry.get('CFBundlePrimaryIcon', {})
            assert primary.get('CFBundleIconName') == 'AppleStoreIcon', f'Wrong compiled icon: {key}'
            assert not entry.get('CFBundleAlternateIcons'), 'Old alternate icon still selectable'
            files = primary.get('CFBundleIconFiles', [])
            assert files, f'No compiled icon files for {key}'
            for stem in files:
                stem = Path(stem).stem
                matches = [n for n in names if n.startswith(bundle + stem)
                           and '/' not in n[len(bundle):] and n.endswith('.png')]
                assert matches, f'Compiled icon missing: {stem}'
                compiled.update(matches)
        for filename in sorted(compiled):
            data = archive.read(filename)
            assert data.startswith(b'\x89PNG\r\n\x1a\n'), filename
            (report / PurePosixPath(filename).name).write_bytes(data)
        result = {**expected, 'activeIcon': 'AppleStoreIcon',
                  'iconSHA256': hashlib.sha256(preview).hexdigest(),
                  'compiledIcons': sorted(compiled), 'oldIconResources': False}
        (report / 'app-identity.json').write_text(json.dumps(result, indent=2) + '\n')
        print('PASS: Apple Store name, version 3.8, new compiled icon and installer PNG; no old icon resources.')


if __name__ == '__main__':
    check(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
