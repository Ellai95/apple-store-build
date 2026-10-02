# Apple Store 3.0 — changes to Feather

Base: claration/Feather, 7078b053c0af262809a48e4d3898d42b0d35fedf.
Customization: Maga Magomadov / Apple IPA, 2026-10-02.
License: GNU GPL-3.0; original notices and licenses remain included.

3.0 adds a schema-validated HTTPS catalog with a bundled fallback and an atomic
last-known-good disk snapshot. Catalog metadata, media URLs and contact links
can change without replacing the app binary. Bad or older remote snapshots
are rejected. Images use the existing Nuke memory/disk cache.

There are 201 initial cards: 80 existing cards and 121 additions. The existing
76 IPA URLs, versions, subscription plans and mod features are retained.
External data were matched explicitly; full merge/source records accompany
the owner package. IPA files were not copied or re-signed during preparation.
New IPA downloads link to the selected public GitHub Releases repository.

App pages show screenshots, ratings, descriptions, version and known file size.
Unknown sizes and ratings are omitted. Existing mod capabilities are preserved.
Requests check the current catalog before offering Telegram/WhatsApp drafts.
About contains brief product/owner details, with separate working source and
license entries. Third-party licenses and copyright notices are bundled.

The pinned dependency repair, file handlers and install pipeline from 2.0 remain.
Only a pre-download minimum-iOS check has been added to the install pipeline.
URL scheme: appleipa. Bundle ID: ru.ipa95.applestore. Version: 3.0, build: 300.
Source URL is stamped to the customization commit during GitHub Actions builds.

No client certificate or password is uploaded to the catalog host. Requests to
messengers are opened as drafts; the user sends the message themselves.

Validation: resource/schema/URL checks and Swift syntax checks in preparation;
Foundation catalog tests and native Xcode compilation run in GitHub Actions.
Device testing of this new release remains required.
