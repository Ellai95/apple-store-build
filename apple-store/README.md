# Apple Store 3.7 customization

Run `.github/workflows/apple-store-3.7.yml` on the pinned macOS/Xcode runner.
`build.sh` prepares the pinned Feather source, runs resource/caching/installer
checks, builds the IPA, audits its package, and produces corresponding source
and separate licenses. Read `../START_HERE.txt` for the Windows upload steps.

The protected resource pack contains no account credentials. Its embedded key
can be recovered by reverse engineering. Public R2/GitHub download endpoints
remain public. Signing and installation code is unchanged from 3.6.

Original notices and GPL rights are preserved. Publish source and license
archives with equivalent access beside the IPA. The build artifacts expire;
move them to your persistent download location before distributing the IPA.

The generated SOURCE_RESOURCES.json and StoreVault.swift are included in the
source archive for modification/rebuilding. Unpack the source archive, use the
specified Xcode 26.3+ and dependencies, and run `make iphoneos` from its source
root for an unsigned/ad-hoc package. The BuildCustomization directory contains
all preparation and packing scripts used by the workflow.
