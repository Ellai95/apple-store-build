# Apple Store 4.1 — package 22

Test release, build 410. The installation, certificate, downloader and Bundle ID
implementation is unchanged from the user-tested 4.0 package. Only version
metadata, bundled release notes and the offline publication tools changed.

Upload apple-store and Online at the root of apple-store-build. Replace the
existing workflow contents with apple-store-4.1.yml. Run Actions on main.
On Windows, run Online/Publish-Test-Update.cmd with the original IPA produced
by that build and its adjacent release.json. See START_HERE.txt for full steps.

Publication preserves the current R2 configuration, adds the 4.1 announcement
for builds 400–409, uploads the immutable versioned IPA first, then publishes
configuration.json. No publication was performed from this workspace.

Xcode and device verification remain necessary. Keep the installed 4.0 on the
test device; the purpose of 4.1 is to exercise that existing update flow.

The pinned base and dependency notices are preserved. The workflow emits the
corresponding source and licenses in a separate artifact alongside the IPA.
