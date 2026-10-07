# Apple Store 3.8 — Fix 20

Build customization for the pinned Feather revision. See `../START_HERE.txt`.
Run in the GitHub Actions macOS workspace:

```sh
bash customization/apple-store/build.sh
```

The Library editor passes a per-operation ID to the existing signer. It reads
local Info.plist or optional catalog bundleIdentifier without downloading IPA.
Missing metadata allows manual input. Catalog metadata is not authenticated IPA
identity. Download/import happens only after Install through the existing pipeline.
No application-identifier profile allowlist is applied by this custom flow; actual
signing and iOS validation remain unchanged. Syntax and self-replacement checks remain.
Unchanged input is accepted for updates. Original local items and global preferences
are preserved. Ordinary catalog installs continue to pass a nil override.

CI checks catalog backward compatibility, metadata persistence, ID syntax, downloader,
installation defaults and cleanup, then builds and audits the IPA. Local static
checks do not replace Xcode compilation or iPhone tests.
Source and notices remain in the existing separate publication artifacts.

Progress presentation is hidden on handedOff/completed; manual dismissal only changes
UI state. Server lifetime and cleanup grace are preserved. New operations/retries
restore presentation, and errors reveal the banner. Applies to both catalog and library.
