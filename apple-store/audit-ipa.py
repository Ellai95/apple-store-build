#!/usr/bin/env python3
"""A narrow release-package gate, not a claim of resistance to reverse engineering."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import plistlib
import re
import sys
import zipfile

def check(ipa, report):
    forbidden_names = {'AppleStoreCatalog.json', 'AppleStoreLicense.txt', 'AppleStoreNotices.txt',
                       'SOURCE_RESOURCES.json', 'resource-links.json', 'cert.json', '.env'}
    secret_patterns = [rb'\b[0-9]{8,12}:[A-Za-z0-9_-]{35}\b',
                       rb'\bghp_[A-Za-z0-9]{36}\b', rb'\bgithub_pat_[A-Za-z0-9_]{70,}\b',
                       rb'\bAKIA[A-Z0-9]{16}\b']
    clear_addresses = {'source-repository': 'https://github.com/Ellai95/apple-store-build',
                       'r2-host': 'pub-d11175355ab34b9299fb0a916702bce7.r2.dev'}
    findings = []
    with zipfile.ZipFile(ipa) as z:
        names = z.namelist()
        assert z.testzip() is None, 'IPA CRC failure'
        assert 'Payload/AppleStore.app/Info.plist' in names, 'Unexpected package folder'
        info = plistlib.loads(z.read('Payload/AppleStore.app/Info.plist'))
        assert info.get('CFBundleExecutable') == 'AppleStore'
        assert 'AppleStoreSourceURL' not in info
        assert 'Payload/AppleStore.app/AppleStore' in names
        assert len(z.read('Payload/AppleStore.app/StoreData.bin')) > 1000
        for item in z.infolist():
            name = PurePosixPath(item.filename)
            if item.is_dir(): continue
            if (name.name in forbidden_names or any(p in {'.git', 'build-report'} or p.endswith('.dSYM') for p in name.parts)
                or name.suffix.lower() in {'.swift', '.p12', '.pfx', '.mobileprovision'}):
                findings.append('Unexpected packaged file: ' + item.filename)
            data = z.read(item)
            # Keep the expected local TLS server.pem: it is supplied by Feather's
            # installation transport, not a customer's signing private key.
            if any(re.search(pattern, data) for pattern in secret_patterns):
                findings.append('Credential-like data in: ' + item.filename)
            for label, address in clear_addresses.items():
                if any(address.encode(encoding) in data for encoding in ['utf-8', 'utf-16-le']):
                    findings.append('Plaintext protected address (' + label + ') in: ' + item.filename)
        result = {'version': info.get('CFBundleShortVersionString'),
                  'sha256': hashlib.sha256(Path(ipa).read_bytes()).hexdigest(),
                  'checkedFiles': len(names), 'findings': sorted(set(findings)),
                  'scope': 'Package hygiene and selected plaintext markers; not a full security audit.'}
    Path(report).mkdir(parents=True, exist_ok=True)
    (Path(report)/'release-audit.json').write_text(json.dumps(result, indent=2)+'\n')
    if findings: raise SystemExit('\n'.join(sorted(set(findings))))
    print('PASS: release package, protected resources, selected URL markers and credential patterns.')

if __name__ == '__main__':
    check(sys.argv[1], sys.argv[2])
