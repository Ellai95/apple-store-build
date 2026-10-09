#!/usr/bin/env bash
set -euo pipefail
mkdir -p source/build-report
python3 customization/apple-store/tests/test-release-audit.py

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

# Prepare Apple Store 4.4
set -euo pipefail
if [ ! -f customization/apple-store/prepare.py ]; then
  echo 'Upload apple-store folder at repository ROOT, alongside README.md.' | tee source/build-report/prepare.log
  exit 1
fi
python3 customization/apple-store/prepare.py source 2>&1 | tee source/build-report/prepare.log
xcrun swift customization/apple-store/make-launch-icon.swift source/Feather/Resources/Assets.xcassets/StoreBrand.imageset/brand.png source/Feather/Resources/Assets.xcassets/Glyph.imageset/brand.png
python3 customization/apple-store/validate.py source 2>&1 | tee source/build-report/validation.log
xcrun swift customization/apple-store/pack-resources.swift source customization/apple-store
xcrun swiftc -swift-version 5 -D STORE_VAULT_TESTS -parse-as-library source/Feather/AppleStore/StoreVault.swift source/Feather/AppleStore/StoreCatalogData.swift customization/apple-store/tests/VaultSmoke.swift -o source/build-report/vault-smoke
source/build-report/vault-smoke source | tee source/build-report/vault-smoke.log
git -C customization rev-parse HEAD > source/build-report/customization-commit.txt
git -C source diff > source/build-report/source-changes.patch
xcrun swiftc -frontend -parse source/Feather/AppleStore/*.swift
xcrun swiftc -swift-version 5 -D STORE_VAULT_TESTS source/Feather/AppleStore/StoreVault.swift source/Feather/AppleStore/StoreCatalogData.swift customization/apple-store/tests/main.swift -o source/build-report/catalog-tests
source/build-report/catalog-tests source/build-report/plain-catalog.json source/Feather/Resources/StoreData.bin | tee source/build-report/catalog-tests.log

# Validate remote documents, deep links, release identity and archive integrity.
xcrun swiftc -swift-version 5 -parse-as-library source/Feather/AppleStore/StoreCatalogData.swift source/Feather/AppleStore/StoreRemoteData.swift source/Feather/AppleStore/StoreUpdateVerifier.swift customization/apple-store/tests/RemoteSmoke.swift -o source/build-report/remote-smoke
source/build-report/remote-smoke customization/Online/configuration.json customization/Online/release-4.4.json | tee source/build-report/remote-smoke.log

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
mv packages/Feather.ipa "packages/Apple Store.ipa"
shasum -a 256 "packages/Apple Store.ipa" > build-report/SHA256.txt
python3 ../customization/apple-store/release-info.py "packages/Apple Store.ipa" packages/release.json
)

# Prepare corresponding source (GPL)
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import zipfile
root=Path('source')
excluded={'.git','_build','packages','deps','build-report'}
with zipfile.ZipFile('Apple-Store-4.4-Source.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in root.rglob('*'):
        rel=p.relative_to(root)
        if p.is_file() and not any(part in excluded for part in rel.parts) and rel.name != 'cert.json':
            z.write(p,Path('Apple-Store-4.4-Source')/rel)
    for p in Path('customization/apple-store').rglob('*'):
        if p.is_file(): z.write(p,Path('BuildCustomization/apple-store')/p.relative_to('customization/apple-store'))
    for p in Path('customization/Online').rglob('*'):
        if p.is_file(): z.write(p,Path('BuildCustomization/Online')/p.relative_to('customization/Online'))
    workflow=Path('customization/apple-store-4.4.yml')
    if workflow.exists(): z.write(workflow,Path('BuildCustomization/apple-store-4.4.yml'))
PY

python3 customization/apple-store/package-licenses.py source Apple-Store-4.4-Licenses.zip
