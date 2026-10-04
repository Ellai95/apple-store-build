# Apple Store 3.3

Version 3.3 (build 303), bundle ID `ru.ipa95.applestore`.

The application is assembled from the exact Feather revision
`7078b053c0af262809a48e4d3898d42b0d35fedf` and this directory.
The complete added Swift sources, resources and icons are in `payload.zip`
under `overlay/` (ordinary ZIP, no obfuscation). `prepare.py` contains every
change made to the upstream source. `CHANGES.md` describes those changes.

```sh
git clone --recurse-submodules https://github.com/claration/Feather.git source
git -C source checkout 7078b053c0af262809a48e4d3898d42b0d35fedf
git -C source submodule update --init --recursive
python3 apple-store/prepare.py source
python3 apple-store/validate.py source
cd source
make iphoneos
```

Build on macOS with Xcode 26.3 or newer. The workflow in
`.github/workflows/apple-store-3.3.yml` additionally runs catalog unit tests,
checks the resulting IPA identity, and produces the corresponding source ZIP.
The catalog endpoint is in `StoreCatalog.swift`; the schema and validator are
in `StoreCatalogData.swift`. The catalog can be edited independently of IPA.

GPL-3.0 applies. Preserve original notices and distribute the corresponding
source alongside any distributed IPA. Do not rely on expiring Actions artifacts
as the only source distribution. No signing keys are needed to build.

The public display name and bundle name are always `Apple Store`. The workflow
exports `Apple Store.ipa`; version 3.3 is metadata, not part of the app name.
The legacy Feather Icon Composer file and alternate PNGs are removed.
`AppleStoreIcon` is the single active icon asset in every appearance.
`validate-ipa.py` checks the actual compiled icon metadata and preview PNG.

Version 3.2 fixes a missing `StorePipeline` environment object in the root inset.
The indicator takes an explicit observed model now. The workflow additionally
renders its real SwiftUI source on macOS without environment injection before
building the IPA. This targeted check is not an end-to-end iPhone installation test.

Version 3.3 replaces the catalog downloader and adds the DownloadSmoke transport
checks with a local HTTP fixture. No signing keys or real IPA downloads are used
by these tests. Their execution requires the macOS workflow.
