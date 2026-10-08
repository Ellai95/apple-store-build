# Apple Store 4.2 — package 25

Build 420 separates the canonical downloaded release identity from the local
installation identity. The downloaded archive must match the published hash,
size, canonical bundle ID, name and version. The signer sets the current
Bundle.main.bundleIdentifier; the signed plist and library record must both
match it before iOS installation begins.

Existing catalog/Library flows retain their behavior. Run the macOS workflow
and RemoteSmoke tests before device testing. See START_HERE.txt for the one-time
migration from 4.0 and the subsequent update test.

The workflow emits corresponding source and component licenses separately.
