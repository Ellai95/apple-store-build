# Apple Store 2.0 (build 200)

Independent Apple IPA interface on Feather revision 7078b053c0af262809a48e4d3898d42b0d35fedf.

- New catalogue-first SwiftUI shell, detail cards, library, settings, certificate import.
- Light by default; persistent black theme, shared UIKit and SwiftUI appearance.
- 80 bundled catalogue cards, 76 existing HTTPS R2 IPA URLs, original cached app icons.
- Search aliases, categories, sort, available-only filter, subscription/contact links.
- Generated Apple Store icon (original ribbon A; red/blue/pearl palette).
- Sequential download, import, signing, packaging and system install request.
- Actual byte progress; explicit handler UUIDs; no "latest signed app" lookup.
- Download cancellation, HTTP errors, certificate presence/expiry checks, retry.
- Only one active signing/install operation. Catalogue remains browsable.
- Preserved Zsign, local installation server, optional IDevice installation, signing settings.
- Correct main-context database writes for import/sign/certificate registration.
- Own bundle ID ru.ipa95.applestore, own appleipa URL scheme. Baseline remains separate.
- Existing Telegram Mini App is not modified.

The native build must be compiled in GitHub Actions, then signed and tested on iPhone.
Tests of baseline Feather do not constitute testing of these new features.
The OTA payload-transfer state is deliberately not labelled "installed": iOS owns installation.
No background-completion guarantee: keep Apple Store open during download/signing.

## Licenses and source
Feather and this derivative are distributed under GPL-3.0 (see LICENSE).
Original copyright notices and licenses remain in source. Zsign/IDeviceKit and other
packages retain their own licenses. Build workflow uploads complete assembled source
(including checked-out submodules, excluding .git/builds/secrets) alongside the IPA.
Original app icons and catalogue metadata retain their respective owners' rights.

## Icon generation
Built-in image generation; original full-bleed square asset, no text or fruit logo.
Prompt: premium app-marketplace icon, sculptural ribbon A, pearl glass-metal surfaces,
red left and electric-blue right lighting on midnight navy, legible silhouette,
no rounded external frame. Only standard asset resizing for Xcode was applied.
