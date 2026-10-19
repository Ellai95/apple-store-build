"""Prepare our ad-hoc CI IPA for personalization and subsequent zsign."""
import argparse
import os
from pathlib import Path, PurePosixPath
import plistlib
import zipfile


def prepare_base(source, destination):
    source, destination = Path(source), Path(destination)
    if destination.exists() or source.resolve() == destination.resolve():
        raise ValueError('Destination must be a new file')
    with zipfile.ZipFile(source) as src:
        names = src.namelist()
        if len(set(names)) != len(names):
            raise ValueError('Duplicate archive paths')
        for name in names:
            parts = PurePosixPath(name).parts
            if '..' in parts or name.startswith('/') or '\\' in name:
                raise ValueError('Unsafe IPA path')
            if PurePosixPath(name).suffix.lower() in {'.p12', '.pfx'} or PurePosixPath(name).name == 'StoreActivation.json':
                raise ValueError('A private or personalized IPA cannot be the shared base')
        roots = [n for n in names if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        if len(roots) != 1 or plistlib.loads(src.read(roots[0])).get('CFBundleIdentifier') != 'ru.ipa95.applestore':
            raise ValueError('Expected our AppStore+ base')
        if src.testzip() is not None:
            raise ValueError('Corrupt IPA')
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            with destination.open('xb') as output:
                os.chmod(destination, 0o600)
                with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as dst:
                    for info in src.infolist():
                        parts = PurePosixPath(info.filename).parts
                        if '_CodeSignature' in parts or PurePosixPath(info.filename).name in {'CodeResources', 'embedded.mobileprovision'}:
                            continue
                        dst.writestr(info, src.read(info))
        except BaseException:
            destination.unlink(missing_ok=True)
            raise
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ci_ipa'); parser.add_argument('output_ipa')
    args = parser.parse_args()
    prepare_base(args.ci_ipa, args.output_ipa)
    print('Base prepared. Personalize, then sign before installation.')
