"""Add a private activation resource to an unsigned IPA. Sign the result afterwards."""
import argparse
import json
import os
from pathlib import Path
import zipfile
from service import https


def personalize(source, bootstrap, destination):
    source, bootstrap, destination = map(Path,(source,bootstrap,destination))
    if destination.exists() or source.resolve() == destination.resolve():
        raise ValueError('Destination must be a new IPA')
    config = json.loads(bootstrap.read_text())
    https(config['endpoint'])
    if not 32 <= len(config['code']) <= 100 or not config['deviceID']:
        raise ValueError('Invalid private activation resource')
    with zipfile.ZipFile(source) as src:
        names = src.namelist()
        if any('..' in Path(name).parts or name.startswith('/') for name in names):
            raise ValueError('Unsafe IPA paths')
        apps = {name.split('/')[1] for name in names if name.startswith('Payload/') and len(name.split('/'))>2 and name.split('/')[1].endswith('.app')}
        if len(apps) != 1: raise ValueError('Expected exactly one root app')
        app = next(iter(apps)); target=f'Payload/{app}/StoreActivation.json'
        if any(name.startswith(f'Payload/{app}/_CodeSignature/') for name in names):
            raise ValueError('Use an unsigned IPA; personalizing invalidates any existing signature')
        if any(Path(name).suffix.lower() in ('.p12','.pfx') for name in names):
            raise ValueError('Do not embed signing private keys in an IPA')
        destination.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        try:
            with destination.open('xb') as output:
                os.chmod(destination,0o600)
                with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as dst:
                    for info in src.infolist():
                        if info.filename != target: dst.writestr(info,src.read(info))
                    dst.writestr(target,json.dumps(config).encode())
        except BaseException:
            destination.unlink(missing_ok=True)
            raise

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('unsigned_ipa'); parser.add_argument('bootstrap'); parser.add_argument('output_ipa')
    args=parser.parse_args()
    personalize(args.unsigned_ipa,args.bootstrap,args.output_ipa)
    print('Personalized unsigned IPA created. Sign before distribution.')
