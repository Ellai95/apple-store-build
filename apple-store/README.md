# Apple Store 4.3 — package 26

Build 430 exercises self-update from installed 4.2 build 420. Native download,
signing, installer and identity verifier code is byte-identical to package 25.
Only version metadata, bundled changelog and publication profile change.

Upload apple-store and Online; replace the existing workflow with
apple-store-4.3.yml and run Actions. Publish the original IPA/release.json pair
using Online/Publish-Test-Update.cmd. Leave 4.2 installed for the test.

The canonical downloaded IPA is verified and then signed using the running
application's Bundle ID. Do not modify the original IPA before publication.
Device testing remains required. See START_HERE.txt. Corresponding source and
component licenses are emitted as a separate build artifact.
