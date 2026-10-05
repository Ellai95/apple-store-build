#!/usr/bin/env python3
"""Deterministic resource/integration checks; native type-check remains Xcode's job."""
from pathlib import Path
import json, plistlib, re, sys
from urllib.parse import urlparse, unquote
root=Path(sys.argv[1]);resources=root/'Feather/Resources';assets=resources/'Assets.xcassets'
doc=json.loads((resources/'AppleStoreCatalog.json').read_text()); apps=doc['apps']
assert doc['schemaVersion']==1 and doc['contacts']['whatsapp']=='https://wa.me/79667202220'
assert len(apps)==201 and len({a['id'] for a in apps})==201
assert sum(bool(a['ipaUrl']) for a in apps)==197
for app in apps:
    for key in ['id','name','category','subtitle','description','version','size','ipaUrl','kind','searchTerms','addedAt','updatedAt']:
        assert isinstance(app[key],str),(app['id'],key)
    for key in ['isMod','featured']: assert isinstance(app[key],bool)
    assert isinstance(app['modFeatures'],list)
    asset=assets/('store_'+app['id'].replace('-','_')+'.imageset')
    descriptor=json.loads((asset/'Contents.json').read_text())
    for image in descriptor['images']: assert (asset/image['filename']).is_file()
    if app['ipaUrl']:
        u=urlparse(app['ipaUrl']);assert u.scheme=='https' and u.netloc in {'pub-d11175355ab34b9299fb0a916702bce7.r2.dev','github.com'}
        assert unquote(u.path).lower().endswith('.ipa'),app['id']
    assert not re.search(r'kamohacks|@unlim|tg@|appassassin',app['name'],re.I)
    if app['kind']=='subscription': assert not app['ipaUrl'] and app['subscriptionPlans']
assert (resources/'AppleStoreLicense.txt').is_file()
icon=assets/'AppleStoreIcon.appiconset';data=json.loads((icon/'Contents.json').read_text())
assert data['images'][0]['size']=='1024x1024' and (icon/data['images'][0]['filename']).is_file()
assert not (resources/'AppIcon.icon').exists(), 'Old Icon Composer file overrides the new icon'
assert not (assets/'AppIcon.appiconset').exists()
assert not (resources/'Icons').exists()
assert not (resources/'feather_extension.png').exists()
assert (resources/'AppIcon.png').read_bytes() == (icon/'AppleStore.png').read_bytes()
assert {i.get('appearances',[{'value':'default'}])[0]['value'] for i in data['images']} == {'default','dark','tinted'}
assert {i['filename'] for i in data['images']} == {'AppleStore.png'}
project=(root/'Feather.xcodeproj/project.pbxproj').read_text()
assert project.count('INFOPLIST_KEY_CFBundleDisplayName = "Apple Store";')==2
assert project.count('ASSETCATALOG_COMPILER_APPICON_NAME = AppleStoreIcon;')==2
assert project.count('PRODUCT_NAME = "Apple Store";') == 2
assert project.count('PRODUCT_MODULE_NAME = Feather;') == 2
assert project.count('EXECUTABLE_NAME = Feather;') == 2
assert 'PRODUCT_NAME = "$(TARGET_NAME)";' not in project
assert 'path = "Apple Store.app";' in project
scheme = (root/'Feather.xcodeproj/xcshareddata/xcschemes/Feather.xcscheme').read_text()
assert scheme.count('BuildableName = "Apple Store.app"') == 3
assert project.count('CURRENT_PROJECT_VERSION = 306;')==2
assert 'FEATHER_PROJECT_VERSION=3.6' in (root/'Feather.xcconfig').read_text()
assert 'FEATHER_PRODUCT_BUNDLE_IDENTIFIER=ru.ipa95.applestore' in (root/'Feather.xcconfig').read_text()
plist=plistlib.loads((resources/'Info.plist').read_bytes())
assert plist['CFBundleURLTypes'][0]['CFBundleURLSchemes']==['appleipa']
assert plist['CFBundleName'] == plist['CFBundleDisplayName'] == 'Apple Store'
for key in ['CFBundleIcons','CFBundleIcons~ipad']:
    assert plist[key]['CFBundlePrimaryIcon']['CFBundleIconName'] == 'AppleStoreIcon'
    assert 'CFBundleAlternateIcons' not in plist[key]
assert plist['CFBundleIconFile'] == 'AppIcon.png'
assert (resources/'AppleStoreDocument.png').is_file()
entry=(root/'Feather/FeatherApp.swift').read_text()
assert 'StoreRootView()' in entry and 'VariedTabbarView()' not in entry
p1=json.loads((root/'Feather.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
p2=json.loads((root/'Feather.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
assert p1==p2 and len(p1['pins'])==28
pipeline=(root/'Feather/AppleStore/StorePipeline.swift').read_text()
assert 'uuid == %@' in pipeline and 'storeResultUUID' in pipeline
assert 'Task.checkCancellation()' in pipeline
downloader=(root/'Feather/AppleStore/StoreDownloader.swift').read_text()
assert 'response.statusCode' in downloader and 'session.downloadTask(with: url).resume()' in downloader
assert 'case .handedOff' in pipeline
assert '@AppStorage("AppleStore.darkTheme") private var dark = false' in (root/'Feather/AppleStore/StoreRootView.swift').read_text()
assert (resources/'AppleStoreNotices.txt').stat().st_size > 1000
print('PASS: catalog, URLs, resources, identity, dependency locks, root view and pipeline integration.')
print('Native compilation and on-device verification are required for the new UI/pipeline.')

assert project.count('INFOPLIST_KEY_UILaunchStoryboardName = AppleStoreLaunch34;') == 2
assert plist['UILaunchStoryboardName'] == 'AppleStoreLaunch34'
assert (resources/'AppleStoreLaunch34.storyboard').is_file()
settings=(root/'Feather/AppleStore/StoreSettingsView.swift').read_text()
licenses=settings.split('struct StoreLicensesView: View {',1)[1]
assert licenses.count('NavigationLink(')==2
assert 'Apple Store распространяется' not in licenses and 'Link("Feather' not in licenses
assert 'Наш канал в Телеграм' in settings and 'https://t.me/appipastore' not in settings
catalog_view=(root/'Feather/AppleStore/StoreCatalogView.swift').read_text()
assert 'requestBanner' not in catalog_view
assert 'StoreInstallationDefaults.apply()' in pipeline and 'cleanupJournal.recoverCompletedHandoffs()' in pipeline
server=(root/'Feather/Backend/Server/ServerInstaller.swift').read_text()
assert 'self._server = try setupApp(port: port)' in server
assert 'self._server = try? setupApp' not in server
print('PASS: install migration hook, server errors, launch wiring, channel and simplified licenses.')

assert 'StoreSettingsVisibility.advancedOptions' in settings and 'static let advancedOptions = false' in settings
assert 'static let sourceLink = false' in settings
assert '@AppStorage("AppleStore.autoCleanup") private var autoCleanup = true' in settings
assert 'struct StoreChangelogView: View' in settings and 'Версия 3.6' in settings
assert 'StoreInstallAppSnapshot(app)' in pipeline
assert 'storeTransfers.closeAfterCompleteTransfer()' in pipeline
assert 'StorePayloadTransfers.bytes' in server
assert 'storeTransfers.finish(success: false' in server
assert 'if !cleanupEnabled, options.post_deleteAppAfterSigned' in pipeline
assert (root/'Feather/AppleStore/StoreCleanup.swift').is_file()
print('PASS: cleanup wiring, old-option compatibility, archive retirement, metadata snapshot, changelog and settings visibility.')
