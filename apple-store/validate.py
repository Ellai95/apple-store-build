#!/usr/bin/env python3
"""Deterministic resource/integration checks; native type-check remains Xcode's job."""
from pathlib import Path
import json, plistlib, re, sys
from urllib.parse import urlparse, unquote
root=Path(sys.argv[1]);resources=root/'Feather/Resources';assets=resources/'Assets.xcassets'
apps=json.loads((resources/'AppleStoreCatalog.json').read_text())
assert len(apps)==80 and len({a['id'] for a in apps})==80
assert sum(bool(a['ipaUrl']) for a in apps)==76
for app in apps:
    for key in ['id','name','category','subtitle','description','version','size','ipaUrl','kind','searchTerms','addedAt','updatedAt']:
        assert isinstance(app[key],str),(app['id'],key)
    for key in ['isMod','featured']: assert isinstance(app[key],bool)
    assert isinstance(app['modFeatures'],list)
    asset=assets/('store_'+app['id'].replace('-','_')+'.imageset')
    descriptor=json.loads((asset/'Contents.json').read_text())
    for image in descriptor['images']: assert (asset/image['filename']).is_file()
    if app['ipaUrl']:
        u=urlparse(app['ipaUrl']);assert u.scheme=='https' and u.netloc=='pub-d11175355ab34b9299fb0a916702bce7.r2.dev'
        assert unquote(u.path).lower().endswith('.ipa'),app['id']
    assert not re.search(r'kamohacks|@unlim|tg@|appassassin',app['name'],re.I)
    if app['kind']=='subscription': assert not app['ipaUrl'] and app['subscriptionPlans']
assert (resources/'AppleStoreLicense.txt').is_file()
icon=assets/'AppIcon.appiconset';data=json.loads((icon/'Contents.json').read_text())
assert data['images'][0]['size']=='1024x1024' and (icon/data['images'][0]['filename']).is_file()
project=(root/'Feather.xcodeproj/project.pbxproj').read_text()
assert project.count('INFOPLIST_KEY_CFBundleDisplayName = "Apple Store";')==2
assert 'FEATHER_PROJECT_VERSION=2.0' in (root/'Feather.xcconfig').read_text()
assert 'FEATHER_PRODUCT_BUNDLE_IDENTIFIER=ru.ipa95.applestore' in (root/'Feather.xcconfig').read_text()
plist=plistlib.loads((resources/'Info.plist').read_bytes())
assert plist['CFBundleURLTypes'][0]['CFBundleURLSchemes']==['appleipa']
entry=(root/'Feather/FeatherApp.swift').read_text()
assert 'StoreRootView()' in entry and 'VariedTabbarView()' not in entry
p1=json.loads((root/'Feather.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
p2=json.loads((root/'Feather.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
assert p1==p2 and len(p1['pins'])==28
pipeline=(root/'Feather/AppleStore/StorePipeline.swift').read_text()
assert 'uuid == %@' in pipeline and 'storeResultUUID' in pipeline
assert 'http.statusCode' in pipeline and 'Task.checkCancellation()' in pipeline
assert 'case .handedOff' in pipeline
assert '@AppStorage("AppleStore.darkTheme") private var dark = false' in (root/'Feather/AppleStore/StoreRootView.swift').read_text()
print('PASS: catalog, URLs, resources, identity, dependency locks, root view and pipeline integration.')
print('Native compilation and on-device verification are required for the new UI/pipeline.')
