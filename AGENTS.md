# Project Rules

## Project Overview

- This is the Flutter/Dart project `night_reader`.
- The app display name is `墨頁`.
- The product is a novel reader inspired by Legado.

## Language

- Use Traditional Chinese for user-facing communication and project-rule discussion.

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
