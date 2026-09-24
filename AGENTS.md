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
- Android 實機與模擬器驗證（包含 UI、手勢互動、滾動、動畫、lifecycle、原生外掛或執行效能等實機行為）為使用者的任務。Agent 不得主動要求、提及或承擔實機驗證，亦無需在回報中將實機驗證列為待辦或未驗證要求。
- Report what was verified, what remains unverified, and what is an evidence-based inference as separate statements, scoped strictly to Agent-deliverable validation (static analysis and automated contract tests).
- Local debug runs are part of development. Release APK builds and publishing remain the responsibility of `.github/workflows/android-release.yml`.

## Release Publishing

- Release publishing is handled by `.github/workflows/android-release.yml`.
- The workflow runs when a tag matching `v*` is pushed, and can also be started with `workflow_dispatch`.
- Standard release flow:

```bash
flutter pub get
flutter analyze
# Run only the contract/invariant tests relevant to the release changes.
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
