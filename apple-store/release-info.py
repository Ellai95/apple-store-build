#!/usr/bin/env python3
"""Generate a release descriptor from the actual, unsigned build artifact."""
import hashlib,json,plistlib,re,sys,zipfile
from pathlib import Path
p=Path(sys.argv[1]); out=Path(sys.argv[2])
with zipfile.ZipFile(p) as z:
 names=[n for n in z.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist',n)]
 assert len(names)==1,'Expected one main application'
 info=plistlib.loads(z.read(names[0]))
assert info['CFBundleIdentifier']=='ru.ipa95.applestore','Wrong app'
assert info.get('CFBundleDisplayName',info.get('CFBundleName'))=='Apple Store','Wrong name'
h=hashlib.sha256()
with p.open('rb') as f:
 for chunk in iter(lambda:f.read(1024*1024),b''): h.update(chunk)
value={'enabled':True,'version':info['CFBundleShortVersionString'],'build':int(info['CFBundleVersion']),'sha256':h.hexdigest(),'bundleID':info['CFBundleIdentifier'],'sizeBytes':p.stat().st_size,'minimumIOS':info.get('MinimumOSVersion','15.0')}
out.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
print('Release descriptor created:',out)
