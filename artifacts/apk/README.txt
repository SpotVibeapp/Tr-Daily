APK artifacts for on-device testing of Tr-Daily.

- Tr-Daily-v0.1.0-arm64-v8a.apk      raw APK (64-bit phones — recommended)
- Tr-Daily-v0.1.0-arm64-v8a.apk.b64  base64 text copy of the arm64 APK,
                                     committed so it survives text-only
                                     workspace patches. Recover with:
                                       base64 -d Tr-Daily-v0.1.0-arm64-v8a.apk.b64 \
                                         > Tr-Daily-v0.1.0-arm64-v8a.apk
- Tr-Daily-v0.1.0-universal.apk      raw APK (all ABIs: arm64, 32-bit arm, x86_64)

These are also published as a GitHub Release (see the repo Releases page),
which is the easiest way to download them.
