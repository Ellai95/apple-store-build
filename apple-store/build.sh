#!/usr/bin/env bash
set -euo pipefail
mkdir -p source/build-report
python3 customization/apple-store/tests/test-release-audit.py
python3 - <<'ZIPCHECK'
import zipfile
from pathlib import Path
with zipfile.ZipFile('customization/apple-store/payload.zip') as z:
    assert z.testzip() is None
    names=z.namelist()
    assert all(n.startswith('overlay/') and '..' not in Path(n).parts for n in names)
    for file in ['StoreThemes.swift','StorePersonalizationData.swift','StoreDiagnosticsData.swift','StoreDiagnosticsView.swift','StoreInstalledData.swift','StoreInstalledApps.swift','StoreServicesView.swift']:
        assert 'overlay/Feather/AppleStore/'+file in names
print('PASS: complete overlay and 4.10 source files')
ZIPCHECK

# Select Xcode
set -euo pipefail
for candidate in /Applications/Xcode_26.3.app /Applications/Xcode_26.3.5.app; do
  if [ -d "$candidate/Contents/Developer" ]; then
    sudo xcode-select -s "$candidate/Contents/Developer"
    break
  fi
done
mkdir -p source/build-report
xcodebuild -version | tee source/build-report/xcode.txt
xcrun --sdk iphoneos --show-sdk-version
python3 - <<'PY'
import re, subprocess
text = subprocess.check_output(['xcodebuild', '-version'], text=True)
assert tuple(map(int, re.search(r'Xcode (\d+)\.(\d+)', text).groups())) >= (26, 3), 'Xcode 26.3+ required'
PY

# Prepare Apple Store 4.10
set -euo pipefail
if [ ! -f customization/apple-store/prepare.py ]; then
  echo 'Upload apple-store folder at repository ROOT, alongside README.md.' | tee source/build-report/prepare.log
  exit 1
fi
python3 customization/apple-store/prepare.py source 2>&1 | tee source/build-report/prepare.log

# Preview-only shared gallery geometry: portrait, landscape and narrow screens.
if [ -f source/Feather/AppleStore/StoreProductMediaLayout.swift ]; then
  xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreProductMediaLayout.swift customization/apple-store/tests/ProductLayoutSmoke.swift -o source/build-report/product-layout-smoke
  source/build-report/product-layout-smoke | tee source/build-report/product-layout-smoke.log
fi
if [ "${APPSTORE_PLUS_PREVIEW:-0}" = "1" ]; then
  python3 - <<'DISPLAY_RECOVERY'
from pathlib import Path
code=Path('source/Feather/AppleStore/StoreDisplayPreferences.swift').read_text()
a=code.index('enum StoreDisplayRecovery {'); b=code.index('\nstruct StorePlusBackground', a)
Path('source/build-report/DisplayRecoverySmoke.swift').write_text(Path('customization/apple-store/tests/DisplayRecoverySmoke.swift').read_text()+'\n'+code[a:b])
DISPLAY_RECOVERY
  xcrun swiftc -swift-version 5 -parse-as-library source/build-report/DisplayRecoverySmoke.swift -o source/build-report/display-recovery-smoke
  source/build-report/display-recovery-smoke | tee source/build-report/display-recovery-smoke.log
  python3 - <<'LICENSE_LEASE'
from pathlib import Path
code=Path('source/Feather/AppleStore/StoreActivation.swift').read_text()
a=code.index('struct StoreSubscription:'); b=code.index('\nprivate enum StorePlusKeychain',a)
Path('source/build-report/LicenseLeaseSmoke.swift').write_text(Path('customization/apple-store/tests/LicenseLeaseSmoke.swift').read_text()+'\n'+code[a:b])
LICENSE_LEASE
  xcrun swiftc -swift-version 5 -parse-as-library source/build-report/LicenseLeaseSmoke.swift -o source/build-report/license-lease-smoke
  source/build-report/license-lease-smoke | tee source/build-report/license-lease-smoke.log
fi
xcrun swift customization/apple-store/make-launch-icon.swift source/Feather/Resources/Assets.xcassets/StoreBrand.imageset/brand.png source/Feather/Resources/Assets.xcassets/Glyph.imageset/brand.png
python3 customization/apple-store/validate.py source 2>&1 | tee source/build-report/validation.log
xcrun swift customization/apple-store/pack-resources.swift source customization/apple-store
xcrun swiftc -swift-version 5 -D STORE_VAULT_TESTS -parse-as-library source/Feather/AppleStore/StoreVault.swift source/Feather/AppleStore/StoreCatalogData.swift customization/apple-store/tests/VaultSmoke.swift -o source/build-report/vault-smoke
source/build-report/vault-smoke source | tee source/build-report/vault-smoke.log
git -C customization rev-parse HEAD > source/build-report/customization-commit.txt
git -C source diff > source/build-report/source-changes.patch
xcrun swiftc -frontend -parse source/Feather/AppleStore/*.swift
test_defines=(-D APPSTORE_BASE)
if [[ -f source/Feather/AppleStore/StoreActivation.swift ]]; then test_defines=(-D APPSTORE_PLUS); fi
xcrun swiftc -swift-version 5 "${test_defines[@]}" -parse-as-library source/Feather/AppleStore/StoreInstalledData.swift customization/apple-store/tests/InstalledSmoke.swift -o source/build-report/installed-smoke
source/build-report/installed-smoke | tee source/build-report/installed-smoke.log
if [[ -f source/Feather/AppleStore/StoreActivation.swift ]]; then
python3 - <<'INSTALLED_FIXTURE'
from pathlib import Path
code=Path('source/Feather/AppleStore/StoreInstalledApps.swift').read_text()
a=code.index('@MainActor final class StoreInstalledApps');b=code.index('\nprivate enum StoreSystemApps')
Path('source/build-report/InstalledRegistryActual.swift').write_text(Path('customization/apple-store/tests/InstalledRegistrySmoke.swift').read_text()+'\n'+code[a:b])
INSTALLED_FIXTURE
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreInstalledData.swift source/build-report/InstalledRegistryActual.swift -o source/build-report/installed-registry-smoke
source/build-report/installed-registry-smoke | tee source/build-report/installed-registry-smoke.log
fi
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreCatalogData.swift source/Feather/AppleStore/StoreRemoteData.swift source/Feather/AppleStore/StoreAdvertisingData.swift source/Feather/AppleStore/StorePersonalizationData.swift source/Feather/AppleStore/StoreProExtrasData.swift customization/apple-store/tests/ServicesSmoke.swift -o source/build-report/services-smoke
source/build-report/services-smoke customization/Online/configuration.json | tee source/build-report/services-smoke.log
xcrun swiftc -swift-version 5 -D STORE_VAULT_TESTS source/Feather/AppleStore/StoreVault.swift source/Feather/AppleStore/StoreCatalogData.swift customization/apple-store/tests/main.swift -o source/build-report/catalog-tests
source/build-report/catalog-tests source/build-report/plain-catalog.json source/Feather/Resources/StoreData.bin | tee source/build-report/catalog-tests.log
if [ -f source/Feather/AppleStore/StoreActivation.swift ]; then
  xcrun swiftc -swift-version 5 -D STORE_VAULT_TESTS -parse-as-library source/Feather/AppleStore/StoreVault.swift source/Feather/AppleStore/StoreCatalogData.swift customization/apple-store/tests/CatalogMergeSmoke.swift -o source/build-report/catalog-merge-smoke
  source/build-report/catalog-merge-smoke source/build-report/plain-catalog.json | tee source/build-report/catalog-merge-smoke.log
fi

# Validate remote documents, deep links, release identity and archive integrity.
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreCatalogData.swift source/Feather/AppleStore/StoreRemoteData.swift source/Feather/AppleStore/StoreAdvertisingData.swift source/Feather/AppleStore/StorePersonalizationData.swift source/Feather/AppleStore/StoreProExtrasData.swift source/Feather/AppleStore/StoreUpdateVerifier.swift customization/apple-store/tests/RemoteSmoke.swift -o source/build-report/remote-smoke
source/build-report/remote-smoke customization/Online/configuration.json customization/Online/release-4.10.json | tee source/build-report/remote-smoke.log

# Validate advertising scheduling, schema and per-installation exemptions.
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreCatalogData.swift source/Feather/AppleStore/StoreRemoteData.swift source/Feather/AppleStore/StoreAdvertisingData.swift source/Feather/AppleStore/StorePersonalizationData.swift source/Feather/AppleStore/StoreProExtrasData.swift customization/apple-store/tests/AdvertisingSmoke.swift -o source/build-report/advertising-smoke
source/build-report/advertising-smoke customization/Online/configuration.json customization/Online/Advertising.json | tee source/build-report/advertising-smoke.log

# Exact shipping theme/Pro decoder and privacy-safe diagnostics.
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreCatalogData.swift source/Feather/AppleStore/StoreRemoteData.swift source/Feather/AppleStore/StoreAdvertisingData.swift source/Feather/AppleStore/StorePersonalizationData.swift source/Feather/AppleStore/StoreProExtrasData.swift customization/apple-store/tests/PersonalizationSmoke.swift -o source/build-report/personalization-smoke
source/build-report/personalization-smoke customization/Online/configuration.json | tee source/build-report/personalization-smoke.log
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreDiagnosticsData.swift customization/apple-store/tests/DiagnosticsSmoke.swift -o source/build-report/diagnostics-smoke
source/build-report/diagnostics-smoke | tee source/build-report/diagnostics-smoke.log

# Manual checkout cannot grant access; early audiences and the five-slot limit are validated.
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreCatalogData.swift source/Feather/AppleStore/StoreRemoteData.swift source/Feather/AppleStore/StoreAdvertisingData.swift source/Feather/AppleStore/StorePersonalizationData.swift source/Feather/AppleStore/StoreProExtrasData.swift source/Feather/AppleStore/StoreProPurchaseData.swift customization/apple-store/tests/ProCheckoutSmoke.swift -o source/build-report/pro-checkout-smoke
source/build-report/pro-checkout-smoke customization/Online/configuration.json customization/Online/Personalization.json | tee source/build-report/pro-checkout-smoke.log

# Exercise the exact queue coordinator with deterministic transport/installer fixtures.
python3 - <<'QUEUE'
from pathlib import Path
code=Path('source/Feather/AppleStore/StoreProDownloads.swift').read_text()
start=code.index('@MainActor final class StoreProDownloads')
end=code.index('\nstruct StoreProQueueView:',start)
Path('source/build-report/ProQueueActual.swift').write_text(Path('customization/apple-store/tests/ProQueueSmoke.swift').read_text()+'\n'+code[start:end])
QUEUE
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreCatalogData.swift source/Feather/AppleStore/StoreRemoteData.swift source/Feather/AppleStore/StoreAdvertisingData.swift source/Feather/AppleStore/StorePersonalizationData.swift source/Feather/AppleStore/StoreProExtrasData.swift source/Feather/AppleStore/StoreDiagnosticsData.swift source/build-report/ProQueueActual.swift -o source/build-report/pro-queue-smoke
source/build-report/pro-queue-smoke | tee source/build-report/pro-queue-smoke.log

# Verify banner close persistence and isolation from modal presentation history.
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreNewsDismissals.swift customization/apple-store/tests/NewsDismissalSmoke.swift -o source/build-report/news-dismissal-smoke
source/build-report/news-dismissal-smoke | tee source/build-report/news-dismissal-smoke.log

# Check install progress UI without environment injection
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
code = Path('source/Feather/AppleStore/StoreRootView.swift').read_text()
start = code.index('struct StoreProgressRing: View {')
end = code.index('\nstruct StoreProgressSheet:', start)
test = Path('customization/apple-store/tests/ProgressSmoke.swift').read_text()
Path('source/build-report/ProgressSmoke.swift').write_text(test + '\n' + code[start:end])
PY
xcrun swiftc -swift-version 5 -parse-as-library source/build-report/ProgressSmoke.swift -o source/build-report/progress-smoke
source/build-report/progress-smoke source/build-report | tee source/build-report/progress-smoke.log

# Check IPA downloader with local HTTP fixtures
set -euo pipefail
mkdir -p source/build-report
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreDownloader.swift customization/apple-store/tests/DownloadSmoke.swift -o source/build-report/download-smoke
python3 -u customization/apple-store/tests/download-server.py source/build-report/download-smoke 2>&1 | tee source/build-report/download-smoke.log

# Check installation defaults and file sizes
set -euo pipefail
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreInstallationDefaults.swift customization/apple-store/tests/InstallDefaultsSmoke.swift -o source/build-report/defaults-smoke
source/build-report/defaults-smoke | tee source/build-report/defaults-smoke.log
if [[ -f source/Feather/AppleStore/StoreActivation.swift ]]; then
  xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreInstallationDefaults.swift source/Feather/AppleStore/StoreCleanup.swift customization/apple-store/tests/InstallLinksSmoke.swift -o source/build-report/install-links-smoke
  source/build-report/install-links-smoke | tee source/build-report/install-links-smoke.log
fi
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreVault.swift source/Feather/AppleStore/StoreCatalogData.swift source/Feather/AppleStore/StoreFileSizes.swift customization/apple-store/tests/FileSizeSmoke.swift -o source/build-report/file-size-smoke
source/build-report/file-size-smoke | tee source/build-report/file-size-smoke.log

# Check isolated Bundle ID validation before signing/building.
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreBundleID.swift customization/apple-store/tests/BundleIDSmoke.swift -o source/build-report/bundle-id-smoke
source/build-report/bundle-id-smoke | tee source/build-report/bundle-id-smoke.log

# Check automatic cleanup safety
set -euo pipefail
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreCleanup.swift customization/apple-store/tests/CleanupSmoke.swift -o source/build-report/cleanup-smoke
source/build-report/cleanup-smoke | tee source/build-report/cleanup-smoke.log

# Build iPhone IPA
(
cd source
set -euo pipefail
make iphoneos 2>&1 | tee build-report/build.log
test -s packages/Feather.ipa
unzip -t packages/Feather.ipa
python3 ../customization/apple-store/validate-ipa.py packages/Feather.ipa . build-report 2>&1 | tee build-report/ipa-validation.log
python3 ../customization/apple-store/audit-ipa.py packages/Feather.ipa build-report
ipa_name="Apple Store.ipa"
if [ "${APPSTORE_PLUS_PREVIEW:-0}" = "1" ]; then ipa_name="AppStore+.ipa"; fi
mv packages/Feather.ipa "packages/$ipa_name"
shasum -a 256 "packages/$ipa_name" > build-report/SHA256.txt
python3 ../customization/apple-store/release-info.py "packages/$ipa_name" packages/release.json
)

# Prepare corresponding source (GPL)
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import zipfile
root=Path('source')
excluded={'.git','_build','packages','deps','build-report'}
with zipfile.ZipFile('Apple-Store-4.10-Source.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in root.rglob('*'):
        rel=p.relative_to(root)
        if p.is_file() and not any(part in excluded for part in rel.parts) and rel.name != 'cert.json':
            z.write(p,Path('Apple-Store-4.10-Source')/rel)
    for p in Path('customization/apple-store').rglob('*'):
        if p.is_file(): z.write(p,Path('BuildCustomization/apple-store')/p.relative_to('customization/apple-store'))
    for p in Path('customization/Online').rglob('*'):
        if p.is_file(): z.write(p,Path('BuildCustomization/Online')/p.relative_to('customization/Online'))
    workflow=Path('customization/apple-store-4.10.yml')
    if workflow.exists(): z.write(workflow,Path('BuildCustomization/apple-store-4.10.yml'))
PY

python3 customization/apple-store/package-licenses.py source Apple-Store-4.10-Licenses.zip
