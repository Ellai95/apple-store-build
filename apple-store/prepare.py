#!/usr/bin/env python3
"""Apply the Apple Store 3.0 overlay to the pinned, tested Feather revision.
No signing certificates or secrets are required. Run: python3 prepare.py SOURCE.
"""
from pathlib import Path
import json, plistlib, shutil, subprocess, sys, tempfile, zipfile, os

base = Path(__file__).resolve().parent
source = Path(sys.argv[1]).resolve()
expected = '7078b053c0af262809a48e4d3898d42b0d35fedf'
actual = subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
if actual != expected: raise SystemExit('Unexpected Feather revision; refusing to patch.')
report = source/'build-report'; report.mkdir(exist_ok=True)

def change(relative, old, new, count=1):
    path=source/relative; text=path.read_text()
    if text.count(old) != count: raise SystemExit(f'Unexpected source in {relative}: {old[:75]!r}')
    path.write_text(text.replace(old,new))

# Keep the dependency repair already built and tested on the owner's iPhone.
p1=source/'Feather.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
p2=source/'Feather.xcworkspace/xcshareddata/swiftpm/Package.resolved'
project=json.loads(p1.read_text()); workspace=json.loads(p2.read_text())
obsolete={'apikit','heliumlogger','licenseplist','loggerapi','swift-argument-parser','swift-html-entities','xcodeedit','yams'}
if {p['identity'] for p in project['pins']} - {p['identity'] for p in workspace['pins']} != obsolete:
    raise SystemExit('Unexpected dependency graph')
project['pins']=[p for p in project['pins'] if p['identity'] not in obsolete]
project.pop('originHash',None)
for p in [p1,p2]: p.write_text(json.dumps(project,indent=2)+'\n')
(report/'pins-input.json').write_text(p1.read_text())
change('Makefile','-project Feather.xcodeproj','-workspace Feather.xcworkspace')

# New app identity allows baseline Feather and Apple Store to coexist.
change('Feather.xcconfig','FEATHER_PROJECT_VERSION=2.9.0','FEATHER_PROJECT_VERSION=3.0')
change('Feather.xcconfig','FEATHER_PRODUCT_BUNDLE_IDENTIFIER=thewonderofyou.Feather','FEATHER_PRODUCT_BUNDLE_IDENTIFIER=ru.ipa95.applestore')
change('Feather.xcodeproj/project.pbxproj','INFOPLIST_KEY_CFBundleDisplayName = Feather;','INFOPLIST_KEY_CFBundleDisplayName = "Apple Store";',2)
change('Feather.xcodeproj/project.pbxproj','CURRENT_PROJECT_VERSION = 1;','CURRENT_PROJECT_VERSION = 300;',2)

# Keep the app delegate, heartbeat and file import entry points. Replace its root UI.
app=source/'Feather/FeatherApp.swift'; text=app.read_text()
start=text.index('\t\t\tVStack {')
end=text.index('\n\t\t\t.onReceive',start)
text=text[:start]+'''\t\t\tStoreRootView()
\t\t\t\t.environment(\\.managedObjectContext, storage.context)
\t\t\t\t.onOpenURL(perform: _handleURL)'''+text[end:]
start=text.index('\n\t\t\t// dear god help me')
end=text.index('\n\t\t}\n\t}',start)
text=text[:start]+text[end:]
text=text.replace('url.scheme == "feather"','url.scheme == "appleipa"')
app.write_text(text)
plist_path=source/'Feather/Resources/Info.plist'; plist=plistlib.loads(plist_path.read_bytes())
for item in plist['CFBundleURLTypes']:
    item['CFBundleURLSchemes']=['appleipa']; item['CFBundleURLName']='ru.ipa95.applestore'
for key in ['CFBundleIcons','CFBundleIcons~ipad']:
    if key in plist: plist[key].pop('CFBundleAlternateIcons',None)
commit = os.environ.get('GITHUB_SHA', '')
if len(commit) == 40 and all(c in '0123456789abcdef' for c in commit):
    plist['AppleStoreSourceURL'] = 'https://github.com/Ellai95/apple-store-build/tree/' + commit
plist_path.write_bytes(plistlib.dumps(plist,sort_keys=False))

# A failed Zsign result must never be moved into the signed library.
change('Feather/Utilities/Handlers/SigningHandler.swift',
       '\t\ttry await self.move()\n\t\ttry await self.addToDatabase()\n\t\t\n\t\tif let error = handler.hadError {\n\t\t\tthrow error\n\t\t}',
       '\t\tif let error = handler.hadError { throw error }\n\t\ttry await self.move()\n\t\ttry await self.addToDatabase()')

# Explicit job identities remove a race with manual imports / other signed apps.
for name in ['AppFileHandler','SigningHandler']:
    change(f'Feather/Utilities/Handlers/{name}.swift',
           '\tprivate let _uuid = UUID().uuidString',
           '\tprivate let _uuid = UUID().uuidString\n\tvar storeResultUUID: String { _uuid }')

# Core Data viewContext writes must run on its main executor and finish before
# returning the UUID to the next pipeline stage.
p=source/'Feather/Utilities/Handlers/AppFileHandler.swift';s=p.read_text()
a=s.index('\t\tlet bundle = Bundle(url: appUrl)',s.index('func addToDatabase'))
b=s.index('\n\t}\n\t\n\tprivate func _directory',a)
block=s[a:b]
s=s[:a]+'\t\tawait MainActor.run {\n'+''.join('\t'+line+'\n' for line in block.splitlines())+'\t\t}\n'+s[b:]
p.write_text(s)
p=source/'Feather/Utilities/Handlers/SigningHandler.swift';s=p.read_text()
a=s.index('\t\tawait withCheckedContinuation',s.index('func addToDatabase'))
b=s.index('\n\t}\n\t\n\tprivate func _directory',a)
s=s[:a]+'''\t\tawait MainActor.run {
\t\t\tlet bundle = Bundle(url: appUrl)
\t\t\tStorage.shared.addSigned(
\t\t\t\tuuid: _uuid, source: _app.source,
\t\t\t\tcertificate: _options.signingOption != .default ? nil : appCertificate,
\t\t\t\tappName: bundle?.name, appIdentifier: bundle?.bundleIdentifier,
\t\t\t\tappVersion: bundle?.version, appIcon: bundle?.iconFileName
\t\t\t) { _ in }
\t\t\tStorage.shared.copySourceMetadata(from: _app.uuid, to: _uuid, kind: .signed)
\t\t}
'''+s[b:]
p.write_text(s)
p=source/'Feather/Utilities/Handlers/CertificateFileHandler.swift';s=p.read_text()
a=s.index('\t\tStorage.shared.addCertificate(',s.index('func addToDatabase'))
b=s.index('\n\t}\n\t\n\tprivate func _directory',a)
block=s[a:b]
s=s[:a]+'\t\tawait MainActor.run {\n'+''.join('\t'+line+'\n' for line in block.splitlines())+'\t\t}\n'+s[b:]
p.write_text(s)

# Remove old icon variants before overlaying a single new production icon.
for name in ['AppIcon.appiconset','Glyph.imageset']:
    shutil.rmtree(source/'Feather/Resources/Assets.xcassets'/name)
with tempfile.TemporaryDirectory(prefix='apple-store-overlay-') as directory:
    with zipfile.ZipFile(base/'payload.zip') as archive:
        destination=Path(directory).resolve()
        for item in archive.infolist():
            if not (destination/item.filename).resolve().is_relative_to(destination):
                raise SystemExit('Invalid overlay path')
        archive.extractall(destination)
    shutil.copytree(destination/'overlay',source,dirs_exist_ok=True)
# Launch-screen emblem uses a square aspect ratio.
p=source/'Feather/Resources/Launch Screen.storyboard';s=p.read_text().replace('multiplier="31:21"','multiplier="1:1"').replace('constant="155"','constant="105"');p.write_text(s)

# Standalone provenance and complete GPL license travel with the app/source artifact.
(source/'APPLE_STORE_CHANGES.md').write_text((base/'CHANGES.md').read_text())
(report/'source-commit.txt').write_text(actual+'\n'+subprocess.check_output(['git','-C',str(source),'submodule','status','--recursive'],text=True))
(report/'customization.txt').write_text('Apple Store 3.0, build 300\n'+(base/'CHANGES.md').read_text())
print('Apple Store 3.0 applied. 201 catalog entries; 197 IPA links. Ready for Xcode build.')
