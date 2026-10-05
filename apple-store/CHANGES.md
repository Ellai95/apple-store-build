# Apple Store 3.6 (build 306), archive 14

- Default-on per-operation cleanup with a visible Settings toggle.
- Preserve library copies on errors before full HTTP handoff or IDevice success.
- Remove current operation's imported/signed copies after full HTTP delivery;
  retain the independent IPA and immutable manifest metadata for five-minute retries.
- Track full/ranged/concurrent payload reads under a lock; never retire active streams.
- Recover only recorded completed temporary archives on next cold launch.
- Remove the packaging working Payload after its independent archive is complete.
- Native, concise versioned changelog in About; retain 3.5 visibility switches.
- Add cleanup safety fixtures to macOS CI. Xcode/device validation still required.

# Apple Store 3.5 (build 305), archive 13

- Hide the installation/signing options card using a source visibility flag.
- Hide the source-code link in About using a separate source visibility flag.
- Retain all destinations, URL generation, underlying screens and stored options.
- Keep the 3.4 installation defaults, sizes, artwork, catalog and license files.

To show them again, set advancedOptions and/or sourceLink to true in
StoreSettingsView.swift and rebuild. No removal or recreation of screens is needed.

# Apple Store 3.4 (build 304), archive 12

- One-time migration selects Semi Local with localhost for fresh and existing users;
  subsequent explicit choices and the advanced IDevice method remain available.
- Report local installer initialization failures instead of swallowing them.
- Remove the home request banner; keep requests in Settings and empty search.
- Replace News with the main @appleipa095 channel.
- License landing page contains only GPL-3.0 and Components/authors; bundled notices,
  full license and corresponding-source entry in About remain available.
- Generate a rounded launch-only image from the unchanged original logo at build time.
- Read and cache R2 IPA sizes when opening a card; HEAD first, header-only GET fallback.
  Unknown/error responses are never shown as real IPA sizes. No whole IPA is downloaded.
- Keep the working 3.3 downloader and corrected local CI test runner.

The owner confirmed Semi Local + localhost works on the test iPhone. The 3.4 build
still needs GitHub compilation and device verification. R2 header requests from the
preparation environment returned 403, so no fabricated static file sizes are bundled.

# Apple Store 3.3 (build 303) — download repair candidate, archive 9

- Replace per-task async download delegation with an explicit resumed download task
  and a retained session delegate, following the upstream downloader approach.
- Serialize progress, completion, cancellation and watchdog state on one queue.
- Report no-data timeout after 45 seconds, stalled transfer after 90 seconds,
  HTTP/network errors and invalid IPA responses instead of an indefinite spinner.
- Move the temporary IPA before the download callback returns.
- Add CI tests for success, redirects, unknown size, HTTP 403, invalid data,
  first-byte timeout, cancellation before/during transfer and a subsequent retry.
- Retain the icon, bundle-name and progress UI fixes from 3.2.

The original device-specific root cause is not yet proven. Native compilation
and the transport tests run on macOS GitHub Actions; iPhone verification is required.

# Apple Store 3.2 — packaging correction (archive 8)

- Set PRODUCT_NAME to Apple Store in both configurations so generated CFBundleName is correct.
- Preserve module/executable identities and align product references.
- Save metadata before validation and capture stderr in the report.
- Keep version 3.2 / build 302, UI payload, icon and catalog unchanged.

# Apple Store 3.2 (build 302)

- Fix the missing install model in the bottom progress indicator shown on install.
- Pass the shared model explicitly to progress rings in the inset, catalog and sheet.
- Scope catalog/install environment objects around both the tabs and the bottom inset.
- Add a GitHub macOS SwiftUI render check of the actual indicator in 11 install states,
  deliberately without an injected environment object.
- Keep the 3.1 app icon/name fix, signing engine, certificates and catalog.

# Apple Store 3.1 (build 301)

- Replace the app icon with new blue/white artwork in all appearances.
- Remove the upstream Icon Composer asset which overrode our icon in Xcode 26.
- Remove old alternate Feather icons and replace the document icon.
- Fix both bundle name fields to Apple Store and export Apple Store.ipa.
- Add post-build IPA identity and icon checks.
- Keep catalog, signing flow, settings and license notices from 3.0.

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
