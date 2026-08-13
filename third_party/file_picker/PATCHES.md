# Night Reader `file_picker` patches

## Provenance and license

- Upstream package: `file_picker` 11.0.3
- Archive: <https://pub.dev/api/archives/file_picker-11.0.3.tar.gz>
- SHA-256: `29cc1fdb20613876cc7afc529738c1c0f11a9ca159b010edad0c566ac330847e`
- License: MIT; the upstream `LICENSE` file is retained unchanged.
- Local version: `11.0.3+nightreader.1`

The imported files are an exact subset of the upstream archive before the
patches below are applied.

## Local patches

### Win32 6 compatibility

- Changed the `win32` constraint from `^5.9.0` to `^6.4.0`.
- Ported only the Windows directory-picker COM calls to the public Win32 6 API
  (`CoInitializeEx`, typed COM arenas, typed shell-item creation, and HRESULT
  cancellation handling).
- Kept the 11.0.3 public Dart API and the existing open-file, save-file, file
  filter, display-name, and path behavior.
- Upstream tracking: <https://github.com/miguelpruivo/flutter_file_picker/issues/1980>.
  The compatibility implementation is based on upstream 12.0.0-beta.7.

### Android Gradle Plugin 9 compatibility

- Set `compileSdk` to 37 and made the existing namespace unconditional.
- Replaced the removed `lintOptions` block with the current `lint` DSL.
- Removed the package's embedded AGP 8.5 and Kotlin Gradle Plugin 1.8
  classpaths. The Android library plugin is supplied by Night Reader's root
  AGP 9 toolchain.
- Uses AGP 9 built-in Kotlin exclusively and pins its compiler JVM target to 17
  through `kotlin.compilerOptions`; the legacy Kotlin Android plugin is never
  applied.
- Kept the existing minimum SDK, namespace, and Android runtime dependencies.
- This controlled fork intentionally supports only Night Reader's confirmed
  Flutter 3.47 / AGP 9 toolchain; it is not an AGP 8 compatibility package.
- Upstream tracking: <https://github.com/miguelpruivo/flutter_file_picker/issues/1942>.

## Removal condition

Remove this fork when a stable upstream `file_picker` release simultaneously
supports Win32 6, AGP 9 with built-in Kotlin, compile SDK 37, and Night Reader's
current Flutter/Dart baseline without changing the 11.0.3 selection semantics.
