# Apple Store 4.0 — build 400

Overlay for pinned Feather revision 7078b053c0af262809a48e4d3898d42b0d35fedf.
Run prepare.py only on a clean checkout, then build.sh via the supplied macOS workflow.
Display name remains Apple Store, bundle ID ru.ipa95.applestore.

New remote configuration is shipped in the protected resources, cached after validation,
and refreshed from R2. See ../Online/README.md for editable fields and publication tools.
The self-update path is isolated from catalog and Library custom Bundle ID operations.
It verifies archive size, SHA-256, actual main-app ID/version/build/name before signing
and identity again after signing. Default clean signing options preserve update identity.
The existing installer transport handles system confirmation and payload delivery.

Linux-side integration and syntax checks do not replace Xcode compilation or iPhone testing.
GitHub CI validates remote documents and release integrity before compiling the app.
Publish matching source and license artifacts alongside each distributed IPA.
