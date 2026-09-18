# Night Reader patches for `flutter_tts`

## Source

- Package: [`flutter_tts` 4.2.5](https://pub.dev/packages/flutter_tts/versions/4.2.5)
- Archive: `https://pub.dev/api/archives/flutter_tts-4.2.5.tar.gz`
- Archive SHA-256: `ce5eb209b40e95f2f4a1397116c87ab2fcdff32257d04ed7a764e75894c03775`
- Upstream repository: <https://github.com/dlutton/flutter_tts>
- Vendored version: `4.2.5+nightreader.1`
- License: MIT; the upstream [`LICENSE`](LICENSE) is retained unchanged.

## Local patch

- `android/build.gradle` applies only `com.android.library`, relying on AGP 9's
  built-in Kotlin support instead of applying `kotlin-android`.
- The Android DSL uses `compileSdk = 37`, `minSdk = 24`, the public `lint {}`
  block, and `kotlin.compilerOptions` with JVM 11.
- The plugin-local AGP/KGP buildscript and explicit Kotlin standard-library
  dependency were removed; the consuming Android build supplies AGP and its
  built-in Kotlin toolchain.
- `pubspec.yaml` adds Night Reader build metadata so dependency reports identify
  the patched package.
- Dart and native runtime sources are unchanged from the published archive.

## Reason and tracking

The published 4.2.5 Android script applies `kotlin-android` and uses the legacy
`android.kotlinOptions` and `lintOptions` DSLs. Those declarations are not
compatible with AGP 9's default built-in Kotlin and new public DSL.

- Migration guide: <https://developer.android.com/build/migrate-to-built-in-kotlin>
- Related Flutter tooling issue: <https://github.com/flutter/flutter/issues/189133>
- Upstream `flutter_tts` issue/PR: none filed for this package-specific patch as
  of 2026-08-13.

## Removal condition

Remove this fork and return to the hosted package after `flutter_tts` publishes
an AGP 9 built-in-Kotlin-compatible release that preserves the 4.2.5 runtime API
and passes Night Reader's Android build, analyzer, and complete regression suite.
