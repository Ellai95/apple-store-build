# Apple Store 3.8

Build customization for the pinned Feather revision. See `../START_HERE.txt`.
Run from a GitHub Actions macOS workspace containing `source` and `customization`:

```sh
bash customization/apple-store/build.sh
```

The new Library action supplies a per-operation Bundle ID to the existing signer.
The catalog install entry passes nil and retains its existing behavior. No global
signing preferences are saved by this action. Imported local originals are retained.
Catalog sources are downloaded only when selected through the new flow.

CI checks ID validation/profile matching, existing download, progress, installation
and cleanup behavior, compiles the app, and audits the produced IPA. Local static
validation is not a substitute for Xcode compilation and device testing.

Source and third-party notices are emitted by the existing source/license packaging steps.
