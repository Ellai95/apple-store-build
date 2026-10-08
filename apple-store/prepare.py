#!/usr/bin/env python3
"""Apply the Apple Store 4.3 overlay to the pinned, tested Feather revision.
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
change('Makefile', '_build/Payload/Feather.app', '_build/Payload/AppleStore.app', 5)

# New app identity allows baseline Feather and Apple Store to coexist.
change('Feather.xcconfig','FEATHER_PROJECT_VERSION=2.9.0','FEATHER_PROJECT_VERSION=4.3')
change('Feather.xcconfig','FEATHER_PRODUCT_BUNDLE_IDENTIFIER=thewonderofyou.Feather','FEATHER_PRODUCT_BUNDLE_IDENTIFIER=ru.ipa95.applestore')
change('Feather.xcodeproj/project.pbxproj','INFOPLIST_KEY_CFBundleDisplayName = Feather;','INFOPLIST_KEY_CFBundleDisplayName = "Apple Store";',2)
# Generated Info.plist gets CFBundleName from PRODUCT_NAME.
# Preserve existing Swift/Core Data module and executable identities.
change('Feather.xcodeproj/project.pbxproj','PRODUCT_NAME = "$(TARGET_NAME)";',
       'PRODUCT_NAME = "Apple Store";\n\t\t\t\tPRODUCT_MODULE_NAME = Feather;\n\t\t\t\tEXECUTABLE_NAME = AppleStore;',2)
change('Feather.xcodeproj/project.pbxproj','path = Feather.app;','path = "Apple Store.app";')
change('Feather.xcodeproj/xcshareddata/xcschemes/Feather.xcscheme',
       'BuildableName = "Feather.app"','BuildableName = "Apple Store.app"',3)
change('Feather.xcodeproj/project.pbxproj','CURRENT_PROJECT_VERSION = 1;','CURRENT_PROJECT_VERSION = 430;',2)
change('Feather.xcodeproj/project.pbxproj','ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;','ASSETCATALOG_COMPILER_APPICON_NAME = AppleStoreIcon;',2)

# Restrict these settings to the app Release target, leaving signing dependencies alone.
p=source/'Feather.xcodeproj/project.pbxproj'; text=p.read_text()
a=text.index('3379C1CF2DA869A3004372DA /* Release */ = {')
b=text.index('\n\t\t};',a)
block=text[a:b]
assert 'STRIP_INSTALLED_PRODUCT' not in block
block=block.replace('STRIPFLAGS = "-rSTx";', 'STRIPFLAGS = "-rSTx";\n\t\t\t\tSTRIP_INSTALLED_PRODUCT = YES;\n\t\t\t\tSTRIP_STYLE = "non-global";\n\t\t\t\tSTRIP_SWIFT_SYMBOLS = YES;\n\t\t\t\tENABLE_TESTABILITY = NO;\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";')
p.write_text(text[:a]+block+text[b:])

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
# Set both common name keys: signing tools may read either one.
plist['CFBundleDisplayName'] = 'Apple Store'
plist['CFBundleName'] = 'Apple Store'
# Let actool populate the actual iPhone/iPad icon file names for this asset.
for key in ['CFBundleIcons','CFBundleIcons~ipad']:
    plist[key] = {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppleStoreIcon'}}
# Standalone PNG supports tools which cannot extract Assets.car.
plist['CFBundleIconFile'] = 'AppIcon.png'
for item in plist.get('CFBundleDocumentTypes', []):
    item['CFBundleTypeIconFile'] = 'AppleStoreDocument'
for item in plist.get('CFBundleURLTypes', []):
    item['CFBundleURLIconFile'] = 'AppleStoreDocument'
for item in plist.get('UTExportedTypeDeclarations', []):
    item['UTTypeIconFile'] = 'AppleStoreDocument'
plist.pop('AppleStoreSourceURL', None)
plist_path.write_bytes(plistlib.dumps(plist,sort_keys=False))

# Retire unused upstream promotional source links, preserving network code and licenses.
change('Feather/Views/Settings/SettingsView.swift',
       '"https://github.com/claration/Feather"', 'StoreVault.link("channel")')
p=source/'Feather/Views/Sources/SourcesAddView.swift'; text=p.read_text()
old='Open an [issue](https://github.com/claration/Feather/issues) on GitHub if you want your source to be featured.'
if old not in text: raise SystemExit('Unexpected upstream source-help text')
p.write_text(text.replace(old, 'Обратитесь в поддержку Apple IPA, чтобы предложить источник.'))
for p in (source/'Feather').rglob('*.xcstrings'):
    data=json.loads(p.read_text())
    entries=data.get('strings', {})
    remove=[key for key in entries if 'https://github.com/claration/Feather' in key]
    if remove:
        for key in remove: del entries[key]
        p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')

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

# Xcode 26's Icon Composer input overrides the older asset catalog. Removing
# only AppIcon.appiconset left this Feather icon active in the previous build.
shutil.rmtree(source/'Feather/Resources/AppIcon.icon')
shutil.rmtree(source/'Feather/Resources/Icons')
(source/'Feather/Resources/feather_extension.png').unlink()
# Do not swallow a local server startup failure and wait forever for installation.
change('Feather/Backend/Server/ServerInstaller.swift',
       'self._server = try? setupApp(port: port)', 'self._server = try setupApp(port: port)')

# Track full payload delivery and concurrent Range requests before cleanup.
change('Feather/Backend/Server/ServerInstaller.swift',
       'var packageUrl: URL?', 'let storeTransfers = StorePayloadTransfers()\n\tvar packageUrl: URL?')
change('Feather/Backend/Server/ServerInstaller.swift',
       'self._updateStatus(.sendingPayload)',
       'let attributes = try? FileManager.default.attributesOfItem(atPath: packageUrl.path)\n                let total = (attributes?[.size] as? NSNumber)?.int64Value ?? 0\n                if req.method == .HEAD {\n                    return Response(status: .ok, headers: ["Content-Length": String(total), "Content-Type": "application/octet-stream"])\n                }\n                // The installer URL is private to this operation. Force a body on retries;\n                // a 304 response does not transfer the archive or invoke stream completion.\n                req.headers.remove(name: .ifNoneMatch)\n                guard let bytes = StorePayloadTransfers.bytes(range: req.headers.first(name: .range), total: total, isGET: req.method == .GET) else { return Response(status: .badRequest) }\n                guard self.storeTransfers.begin() else { return Response(status: .gone) }\n                self._updateStatus(.sendingPayload)')
change('Feather/Backend/Server/ServerInstaller.swift',
       'self._updateStatus(.installing)',
       'if self.storeTransfers.finish(success: true, bytes: bytes, total: total) { self._updateStatus(.installing) }')
change('Feather/Backend/Server/ServerInstaller.swift',
       'self._updateStatus(.broken(error))',
       '_ = self.storeTransfers.finish(success: false, bytes: nil, total: total)\n\t\t\t\t\t\tself._updateStatus(.broken(error))')

# Remove old icon variants before overlaying the new production artwork.
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

change('Feather.xcodeproj/project.pbxproj',
       'INFOPLIST_KEY_UILaunchStoryboardName = "Launch Screen.storyboard";',
       'INFOPLIST_KEY_UILaunchStoryboardName = AppleStoreLaunch34;',2)
# New launch resource name for this release, using the clipped Glyph prepared by CI.
launch=source/'Feather/Resources/Launch Screen.storyboard'
launch.rename(source/'Feather/Resources/AppleStoreLaunch34.storyboard')
info=source/'Feather/Resources/Info.plist'
data=plistlib.loads(info.read_bytes());data['UILaunchStoryboardName']='AppleStoreLaunch34'
info.write_bytes(plistlib.dumps(data,sort_keys=False))

# Standalone provenance and complete GPL license travel with the app/source artifact.
(source/'APPLE_STORE_CHANGES.md').write_text((base/'CHANGES.md').read_text())
(report/'source-commit.txt').write_text(actual+'\n'+subprocess.check_output(['git','-C',str(source),'submodule','status','--recursive'],text=True))
(report/'customization.txt').write_text('Apple Store 4.3, build 430\n'+(base/'CHANGES.md').read_text())
print('Apple Store 4.3 applied. New AppleStoreIcon; display name Apple Store. Ready for Xcode build.')
