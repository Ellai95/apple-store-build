# Apple Store 3.6

Version 3.6 (build 306), bundle ID `ru.ipa95.applestore`.

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
`.github/workflows/apple-store-3.6.yml` additionally runs catalog unit tests,
checks the resulting IPA identity, and produces the corresponding source ZIP.
The catalog endpoint is in `StoreCatalog.swift`; the schema and validator are
in `StoreCatalogData.swift`. The catalog can be edited independently of IPA.

GPL-3.0 applies. Preserve original notices and distribute the corresponding
source alongside any distributed IPA. Do not rely on expiring Actions artifacts
as the only source distribution. No signing keys are needed to build.

The public display name and bundle name are always `Apple Store`. The workflow
exports `Apple Store.ipa`; version 3.6 is metadata, not part of the app name.
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

## Automatic cleanup (3.6)

Enabled by default; Settings → Автоочистка IPA. The setting is captured at the
start of an operation. Unrelated library items, Files originals and certificates
are never removed. On a complete local HTTP payload handoff, only the imported
and signed library copies for that operation are removed. Independent manifest
metadata and the packaged IPA remain available for retries for five minutes
after the latest transfer. Active streams block retirement. Completed temporary
archives are recorded for cleanup on the next cold launch if iOS suspends or
kills the app before its timer runs. IDevice cleanup happens after its awaited
installation call returns successfully. Errors before handoff preserve copies.

HTTP handoff is not proof of installation; the UI still reports that iOS controls
completion. With auto-cleanup disabled, library copies remain unless the owner's
pre-existing advanced delete-after-sign option is explicitly enabled. Packaging
working copies and the initial temporary download are always temporary.

About → История обновлений is a native versioned list with short customer-facing
notes. Add the next version's Section in StoreChangelogView for future releases.

New CI coverage: preferences, interrupted downloads, retry, Range coverage/gaps,
concurrent transfers, deletion gate, restart recovery and path confinement.
Run on-device checks before distributing this new build.
