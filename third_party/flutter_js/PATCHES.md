# Night Reader controlled fork

This directory is a controlled fork of [`flutter_js` 0.8.7](https://pub.dev/packages/flutter_js/versions/0.8.7), originally published from [`abner/flutter_js`](https://github.com/abner/flutter_js).

- Upstream package version: `0.8.7`
- Local package version: `0.8.7+nightreader.1`
- Upstream package archive SHA-256: `046428059ac7bef71e305dc35fc24be933b684684a43e83eab7ebd0dc407ad85`
- License: MIT; the upstream [`LICENSE`](LICENSE) is retained unchanged.

## Patch `nightreader.1`

The Android build configuration is migrated for AGP 9 built-in Kotlin and its public DSL:

- Remove the plugin-local AGP 7.3.1 and Kotlin Gradle Plugin 1.7.20 buildscript classpaths.
- Stop applying `kotlin-android`; AGP 9 supplies built-in Kotlin support.
- Remove the explicit legacy Kotlin standard-library dependency supplied by KGP.
- Set `compileSdk` to 37 while retaining `minSdk` 21, namespace, instrumentation runner, and all four ABI filters.
- Register Kotlin sources through `AndroidSourceSet.kotlin` and JNI libraries through the public source-directory API.
- Preserve Java and Kotlin JVM 1.8 bytecode targets through `compileOptions` and `kotlin.compilerOptions`.
- Replace the deprecated `lintOptions` block with the `lint` DSL while retaining the `InvalidPackage` suppression.

The Android migration is build-configuration-only. The Dart API, Java/Kotlin plugin runtime, JavaScript assets, native libraries, and iOS/Linux/macOS/Windows runtime sources are intentionally unchanged from the vendored upstream content, except for the compatibility edit below.

The QuickJS UTF-8 helper also replaces the deprecated Dart FFI
`Pointer.elementAt` calls with the equivalent `Pointer + offset` operator for
Dart 3.13 compatibility. The byte offsets, NUL terminator, UTF-8 decoding, and
public API remain unchanged.

## Reason and tracking

The published 0.8.7 Android script applies the legacy Kotlin Android plugin and pins AGP/KGP versions that are incompatible with AGP 9 built-in Kotlin. No upstream issue or pull request has been submitted for this local patch. The wider Flutter plugin migration is tracked by [flutter/flutter#181383](https://github.com/flutter/flutter/issues/181383).

## Patch `nightreader.2`: Android only

- Removed the iOS, macOS, Linux and Windows implementations, the JavaScriptCore
  runtime, the legacy `QuickJsRuntime` and method-channel `FlutterJs` engines,
  and the QuickJS sync-server bridge. `getJavascriptRuntime()` always returns
  `QuickJsRuntime2`, which loads `libfastdev_quickjs_runtime.so` on Android.
- The Android plugin class is now an empty `FlutterPlugin` whose only job is to
  link the `fastdev-jsruntimes-quickjs` library; its unused `JSEngine`, method
  channel and template stub were removed, as was the unused `CMakeLists.txt`.
- The prebuilt desktop QuickJS bridge libraries moved to
  `test/fixtures/quickjs/` and are used only by the test suite.
- `pubspec.yaml` declares Android only and drops `sync_http`.
- Dart sources follow Night Reader's `flutter_lints` and `dart format` rules;
  the FFI bindings keep the QuickJS C API names.

## Maintenance

Night Reader maintains this package in-tree and no longer tracks upstream.
