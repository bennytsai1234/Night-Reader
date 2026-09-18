# Project Rules

## Project Overview

- This is the Flutter/Dart project `night_reader`.
- The app display name is `夜讀`.

## Language

- Use Traditional Chinese for user-facing communication and project-rule discussion.

## Maintenance Scope

- The project is in feature freeze. Prefer maintenance, bug fixes, compatibility work, performance tuning, refactoring, and improvements within existing capabilities.
- Do not add a new product-line feature unless the user explicitly expands the scope.

## Runtime Validation

- Use `flutter analyze` and relevant `flutter test` targets as the basic validation layer.
- For Android UI, reader interaction, scrolling, animation, lifecycle, storage, native-plugin, or runtime-performance changes, also run the affected flow with `flutter run` on an Android emulator or device.
- Match evidence to the problem: screenshots for visual state, ADB/logcat for runtime failures, and Flutter frame timing, DevTools Performance, or Perfetto for performance claims.
- Report what was verified, what remains unverified, and what is an evidence-based inference as separate statements.
- Local debug runs are part of development. Release APK builds and publishing remain the responsibility of `.github/workflows/android-release.yml`.

## Release Publishing

- Release publishing is handled by `.github/workflows/android-release.yml`.
- The workflow runs when a tag matching `v*` is pushed, and can also be started with `workflow_dispatch`.
- Standard release flow:

```bash
flutter pub get
flutter analyze
flutter test
git push origin HEAD
git tag vX.Y.Z
git push origin vX.Y.Z
```

- If version metadata changes are needed, update `pubspec.yaml` before tagging and commit that change first.
- Always push the release commit branch before creating or pushing the release tag. Do not tag unpublished local commits.
- After pushing the release tag, check GitHub Actions once and confirm the Android Release workflow has started building.
- Once the remote workflow is visibly building, it is acceptable to close the task without waiting for the build to finish.

## Documentation

- Human-facing project overview: `README.md`.
- Local setup, validation, and debugging: `DEVELOPMENT.md`.
- Visual and interaction system: `DESIGN.md`.
- Cross-module runtime and state ownership: `docs/architecture.md`.
- Code navigation map: `docs/night_reader_index.md`.
