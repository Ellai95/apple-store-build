# Apple Store 3.0

Version 3.0 (build 300), bundle ID `ru.ipa95.applestore`.

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
`.github/workflows/apple-store-3.0.yml` additionally runs catalog unit tests,
checks the resulting IPA identity, and produces the corresponding source ZIP.
The catalog endpoint is in `StoreCatalog.swift`; the schema and validator are
in `StoreCatalogData.swift`. The catalog can be edited independently of IPA.

GPL-3.0 applies. Preserve original notices and distribute the corresponding
source alongside any distributed IPA. Do not rely on expiring Actions artifacts
as the only source distribution. No signing keys are needed to build.
